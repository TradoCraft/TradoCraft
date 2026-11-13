// Runs the Playwright suite with friendly defaults, no environment syntax needed:
//   node run.mjs watch [playwright args]   Firefox, visible window fitted to the screen, every action slowed (150 ms)
//   node run.mjs ui [playwright args]      Firefox in Playwright UI mode (scaled live view, timeline)
// The same E2E_* variables as playwright.config.ts override the defaults. Extra arguments go to
// `playwright test`, its exit code is returned. Checks the ports and prerequisites first.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';

const require = createRequire(import.meta.url);
const { missingPrerequisites, portProblem, staleBuildWarning } = require('./lib.cjs');

const [mode, ...rest] = process.argv.slice(2);
const modes = {
  watch: { E2E_BROWSER: 'firefox', E2E_HEADED: '1', E2E_SLOWMO: '150' },
  ui: { E2E_BROWSER: 'firefox' },
};
if (!modes[mode]) {
  console.error(`usage: node run.mjs <${Object.keys(modes).join('|')}> [playwright test arguments]`);
  process.exit(2);
}
for (const [k, v] of Object.entries(modes[mode])) if (process.env[k] === undefined) process.env[k] = v;
const args = [...(mode === 'ui' ? ['--ui'] : []), ...rest];

if (!process.env.E2E_SKIP_PREFLIGHT && !args.includes('--list')) {
  const problems = [
    ...(await Promise.all([
      portProblem(Number(process.env.E2E_API_PORT ?? 18080), 'API', 'E2E_API_PORT'),
      portProblem(Number(process.env.E2E_WEB_PORT ?? 18088), 'web', 'E2E_WEB_PORT'),
    ])),
    ...missingPrerequisites(),
  ].filter(Boolean);
  if (problems.length) {
    for (const p of problems) console.error(`e2e: ${p}`);
    console.error('e2e: (set E2E_SKIP_PREFLIGHT=1 to skip these checks)');
    process.exit(1);
  }
  // Only a warning: the run can still be fine, but a stale build is the usual cause of "step not found".
  const stale = staleBuildWarning();
  if (stale) console.warn(`e2e: WARNING ${stale}`);
}

const child = spawn(process.execPath, [require.resolve('@playwright/test/cli'), 'test', ...args], { stdio: 'inherit' });
// Ctrl-C reaches the whole foreground group, so Playwright shuts its servers down itself; just
// pass termination signals on and wait for it.
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
child.on('exit', (code, signal) => process.exit(code ?? (signal ? 128 + ({ SIGINT: 2, SIGTERM: 15 }[signal] ?? 1) : 1)));
