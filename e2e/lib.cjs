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

// ---- Fit-to-screen mode (headed Firefox) --------------------------------------------------------
// The tests assume a 1400x1700 CSS-pixel viewport (the navigation rail only exposes the items that
// are on screen). A real window cannot be that tall on a laptop screen, and the part below the
// screen is not really there (clicks near the bottom are lost). So the page is scaled down with
// layout.css.devPixelsPerPx: the viewport stays 1400x1700 CSS pixels while the window shrinks.
const CSS_VIEWPORT = { width: 1400, height: 1700 };
/** Height of Firefox's own title bar, tab strip and toolbar at scale 1, in CSS px (measured: 48 device px at 0.55). */
const FIREFOX_CHROME_CSS = 88;
const FALLBACK_SCREEN = { width: 1920, height: 1080 };

/** The geometry of the primary (else the first) connected output in `xrandr --current` output. */
function parseXrandr(text) {
  let first;
  for (const line of String(text ?? '').split(/\r?\n/)) {
    const m = line.match(/^(\S+)\s+connected(\s+primary)?\s+(\d+)x(\d+)\+\d+\+\d+/);
    if (!m) continue;
    const size = { width: Number(m[3]), height: Number(m[4]) };
    if (m[2]) return size;
    first ??= size;
  }
  return first;
}

/** The first desktop's work area (without panels) from `xprop -root _NET_WORKAREA`. */
function parseWorkArea(text) {
  const m = String(text ?? '').match(/_NET_WORKAREA\(CARDINAL\)\s*=\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)/);
  return m ? { width: Number(m[3]), height: Number(m[4]) } : undefined;
}

/** "1920x1080" (also "1920X1080"); throws on anything else. */
function parseWindowSpec(spec) {
  const m = String(spec).trim().match(/^(\d{3,5})\s*[xX]\s*(\d{3,5})$/);
  if (!m) throw new Error(`E2E_WINDOW must look like 1920x1080, got "${spec}"`);
  return { width: Number(m[1]), height: Number(m[2]) };
}

function run(cmd, args, timeout = 5000) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout, windowsHide: true });
  } catch {
    return '';
  }
}

/**
 * Best-effort screen size without new dependencies: { width, height, workArea, source, note? }.
 * `workArea` is true when the size excludes panels (then a small margin is enough).
 * E2E_WINDOW=<W>x<H> overrides everything. Wayland/unknown platforms fall back to 1920x1080 with a note.
 */
function detectScreen(env = process.env, platform = process.platform, exec = run) {
  if (env.E2E_WINDOW) return { ...parseWindowSpec(env.E2E_WINDOW), workArea: false, source: 'E2E_WINDOW' };
  if (platform === 'win32') {
    const out = exec(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; $a = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; "$($a.Width)x$($a.Height)"',
      ],
      15000,
    );
    const m = out.match(/(\d{3,5})x(\d{3,5})/);
    if (m) return { width: Number(m[1]), height: Number(m[2]), workArea: true, source: 'powershell WorkingArea' };
  } else if (platform === 'linux' && env.DISPLAY) {
    const screen = parseXrandr(exec('xrandr', ['--current']));
    if (screen) {
      // Use the work area only when it belongs to this one screen (several monitors give their union).
      const work = parseWorkArea(exec('xprop', ['-root', '_NET_WORKAREA']));
      if (work && work.width <= screen.width && work.height <= screen.height) {
        return { ...work, workArea: true, source: 'xrandr + _NET_WORKAREA' };
      }
      return { ...screen, workArea: false, source: 'xrandr' };
    }
  }
  const why = platform === 'linux' && !env.DISPLAY ? 'no X display (Wayland?)' : 'screen size not detectable here';
  return {
    ...FALLBACK_SCREEN,
    workArea: false,
    source: 'fallback',
    note: `${why}; assuming ${FALLBACK_SCREEN.width}x${FALLBACK_SCREEN.height}. Set E2E_WINDOW=<W>x<H> if that is wrong.`,
  };
}

/**
 * The scale and window for a screen: the largest scale (at most 1, at least 0.3, two decimals) at which
 * a window showing 1400x1700 CSS px plus Firefox's chrome fits the screen minus a margin.
 * E2E_SCALE (0.3-1) forces the scale.
 */
function fitPlan(screen, env = process.env) {
  const mx = screen.workArea ? 20 : 40;
  const my = screen.workArea ? 20 : 120;
  const availW = screen.width - mx;
  const availH = screen.height - my;
  let scale;
  if (env.E2E_SCALE !== undefined && env.E2E_SCALE !== '') {
    scale = Number(env.E2E_SCALE);
    if (!Number.isFinite(scale) || scale < 0.3 || scale > 1) throw new Error(`E2E_SCALE must be a number from 0.3 to 1, got "${env.E2E_SCALE}"`);
  } else {
    const raw = Math.min(availW / CSS_VIEWPORT.width, availH / (CSS_VIEWPORT.height + FIREFOX_CHROME_CSS), 1);
    scale = Math.max(0.3, Math.floor(raw * 100) / 100);
  }
  const window = {
    width: Math.round(CSS_VIEWPORT.width * scale),
    height: Math.round((CSS_VIEWPORT.height + FIREFOX_CHROME_CSS) * scale),
  };
  return { scale, css: { ...CSS_VIEWPORT }, window, screen, fits: window.width <= availW && window.height <= availH };
}

/** Whether fit mode applies: headed Firefox, unless E2E_FIT=0. */
function fitWanted(env = process.env) {
  const headed = ['1', 'true'].includes((env.E2E_HEADED ?? '').toLowerCase());
  return headed && (env.E2E_BROWSER ?? 'chromium') === 'firefox' && !['0', 'false', 'off'].includes((env.E2E_FIT ?? '').toLowerCase());
}

/**
 * Runs `factory()` under a deadline. Resolves { timedOut: false, value } when it finishes in time, rejects
 * when it rejects in time, and resolves { timedOut: true } once `ms` have passed (the work is abandoned:
 * a rejection that arrives later is swallowed). The timer is always cleared.
 */
function withDeadline(factory, ms) {
  return new Promise((resolve, reject) => {
    let done = false;
    const timer = setTimeout(() => {
      done = true;
      resolve({ timedOut: true });
    }, ms);
    let work;
    try {
      work = Promise.resolve(factory());
    } catch (e) {
      work = Promise.reject(e);
    }
    work.then(
      (value) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve({ timedOut: false, value });
      },
      (err) => {
        if (done) return; // late rejection of abandoned work
        done = true;
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

/** Warning for a web build older than the newest commit that touched app/lib, or undefined. */
function staleBuildWarning() {
  const built = path.join(root, 'app/build/web/main.dart.js');
  if (!fs.existsSync(built)) return undefined;
  const commit = Number(run('git', ['-C', root, 'log', '-1', '--format=%ct', '--', 'app/lib']).trim());
  if (!commit) return undefined;
  const builtAt = fs.statSync(built).mtimeMs / 1000;
  if (builtAt >= commit) return undefined;
  const fmt = (t) => new Date(t * 1000).toLocaleString();
  return (
    `The web build (app/build/web, ${fmt(builtAt)}) is older than the newest commit touching app/lib (${fmt(commit)}).\n` +
    '  The test reads the tutorial texts from the CURRENT app_en.arb, so a stale build can fail with "step not found".\n' +
    '  Rebuild:  (cd app && flutter build web --release --no-web-resources-cdn)'
  );
}

module.exports = {
  root,
  apiBin,
  splitPgUrl,
  envPg,
  guardDbName,
  portProblem,
  missingPrerequisites,
  CSS_VIEWPORT,
  FIREFOX_CHROME_CSS,
  parseXrandr,
  parseWorkArea,
  parseWindowSpec,
  detectScreen,
  fitPlan,
  fitWanted,
  staleBuildWarning,
  withDeadline,
};
