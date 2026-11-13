// Shared by playwright.config.ts, start-api.mjs and run.mjs: the PostgreSQL login taken from the
// repository .env, and the pre-flight checks. The .env is never sourced, only one key is parsed,
// and its value is never printed.
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');

/** The repository .env; in a git worktree (which has no .env of its own) the main checkout's. */
function envFile() {
  const own = path.join(root, '.env');
  if (fs.existsSync(own)) return own;
  try {
    const link = fs.readFileSync(path.join(root, '.git'), 'utf8').match(/^gitdir:\s*(.+)$/m);
    if (link) {
      const main = path.join(path.dirname(path.dirname(path.dirname(link[1].trim()))), '.env');
      if (fs.existsSync(main)) return main;
    }
  } catch {
    // .git is a directory: a normal checkout without .env
  }
  return undefined;
}

/** The raw DATABASE_URL value of the .env, or undefined. Parses that one key only. */
function readDatabaseUrl() {
  const file = envFile();
  if (!file) return undefined;
  let found;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*(?:export\s+)?DATABASE_URL\s*=\s*(.*)$/);
    if (!m) continue;
    let v = m[1].trim();
    const q = v[0];
    if (q === '"' || q === "'") {
      const end = v.indexOf(q, 1);
      v = end > 0 ? v.slice(1, end) : v.slice(1);
    } else {
      v = v.replace(/\s+#.*$/, '');
    }
    found = v.trim() || undefined; // the last assignment wins, as when sourced
  }
  return found;
}

/** Splits a PostgreSQL URL into its server part (scheme://user:pass@host:port) and database name. */
function splitPgUrl(url) {
  const m = url && url.match(/^([a-z][a-z0-9+.-]*:\/\/[^/?#]*)(?:\/([^?#]*))?(?:\?([^#]*))?/i);
  if (!m) return undefined;
  const decode = (v) => {
    try {
      return decodeURIComponent(v);
    } catch {
      return v; // keep it raw
    }
  };
  // The path names the database; else a libpq-style ?dbname=... does.
  let db = m[2] ? decode(m[2]) : undefined;
  if (!db && m[3]) {
    for (const pair of m[3].split('&')) {
      const eq = pair.indexOf('=');
      if (eq > 0 && pair.slice(0, eq) === 'dbname' && eq < pair.length - 1) db = decode(pair.slice(eq + 1));
    }
  }
  return { server: m[1], db };
}

/** Server part of the .env DATABASE_URL and the database it names (both may be undefined). */
function envPg() {
  return splitPgUrl(readDatabaseUrl()) ?? { server: undefined, db: undefined };
}

/** Throws when dbName is the developer's real database (the one named in the .env). */
function guardDbName(dbName) {
  const real = envPg().db;
  if (real && dbName === real) {
    throw new Error(
      `E2E_DB_NAME "${dbName}" is the database named in DATABASE_URL of the repository .env. ` +
        'The e2e run drops and recreates its database, so choose another name, e.g. E2E_DB_NAME=tradocraft_e2e.',
    );
  }
}

function portFree(port) {
  return new Promise((resolve) => {
    const s = net.createServer();
    s.once('error', () => resolve(false));
    s.listen(port, '127.0.0.1', () => s.close(() => resolve(true)));
  });
}

/** Best effort: what listens on a port. Never kills anything. */
function listener(port) {
  const run = (cmd, args) => {
    try {
      return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 3000 });
    } catch {
      return '';
    }
  };
  if (process.platform === 'win32') {
    const line = run('netstat', ['-ano', '-p', 'tcp']).split(/\r?\n/).find((l) => l.includes('LISTENING') && l.includes(`:${port} `));
    return line ? `netstat: ${line.trim().replace(/\s+/g, ' ')}` : undefined;
  }
  const ss = run('ss', ['-ltnpH', `sport = :${port}`]).trim();
  if (ss) return ss.replace(/\s+/g, ' ');
  const lsof = run('lsof', ['-nP', `-iTCP:${port}`, '-sTCP:LISTEN']).trim().split('\n').slice(1).join('; ');
  return lsof ? lsof.replace(/\s+/g, ' ') : undefined;
}

/** Returns a multi-line message when the port is taken, otherwise undefined. */
async function portProblem(port, name, envVar) {
  if (await portFree(port)) return undefined;
  const who = listener(port);
  return (
    `The ${name} port ${port} is already in use${who ? ` (${who})` : ''}.\n` +
    `  Stop that process, or pick other ports and a separate database, for example:\n` +
    `  E2E_API_PORT=18180 E2E_WEB_PORT=18188 E2E_DB_NAME=tradocraft_e2e_alt  (this one: ${envVar})`
  );
}

function onPath(bin) {
  const names = process.platform === 'win32' ? [`${bin}.exe`, `${bin}.cmd`, bin] : [bin];
  return (process.env.PATH ?? '').split(path.delimiter).filter(Boolean).some((d) => names.some((n) => fs.existsSync(path.join(d, n))));
}

/** The default API binary (E2E_API_BIN overrides it). */
function apiBin() {
  const exe = process.platform === 'win32' ? 'tradocraft-api.exe' : 'tradocraft-api';
  return process.env.E2E_API_BIN ?? path.join(root, 'target', 'debug', exe);
}

/** One actionable line per missing prerequisite. */
function missingPrerequisites() {
  const out = [];
  const api = apiBin();
  if (!fs.existsSync(api)) out.push(`API binary not found (${api}): run  cargo build -p tradocraft-api  (or set E2E_API_BIN)`);
  if (!fs.existsSync(path.join(root, 'app/build/web/index.html'))) {
    out.push('Flutter web build not found (app/build/web): run  (cd app && flutter build web --release --no-web-resources-cdn)');
  }
  const typst = process.env.TYPST_BIN;
  if (typst ? !fs.existsSync(typst) : !onPath('typst')) {
    out.push(
      `Typst not found${typst ? ` (TYPST_BIN=${typst})` : ' on PATH'}: install it from https://github.com/typst/typst/releases or set TYPST_BIN (the order confirmation PDF needs it)`,
    );
  }
  return out;
}

module.exports = { root, apiBin, splitPgUrl, envPg, guardDbName, portProblem, missingPrerequisites };
