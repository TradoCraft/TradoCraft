import { defineConfig } from '@playwright/test';
import path from 'node:path';

// The whole stack runs locally: PostgreSQL (must be running), the API binary in a "tutorial"
// environment on a throw-away database, and a static server for the Flutter web build.
//   cargo build -p tradocraft-api
//   (cd app && flutter build web --release --no-web-resources-cdn)
//   cd e2e && npm ci && npx playwright test      (headless Chromium, as CI does)
//   npm run test:watch | npm run test:ui          (Firefox, visible; see README.md)
// Environment: E2E_BROWSER=firefox|chromium, E2E_HEADED=1, E2E_SLOWMO=<ms>, E2E_PG_URL, E2E_API_PORT,
// E2E_WEB_PORT, E2E_DB_NAME, E2E_API_BIN.
const { apiBin, envPg, guardDbName } = require('./lib.cjs');
const root = path.resolve(__dirname, '..');
export const API_PORT = Number(process.env.E2E_API_PORT ?? 18080);
export const WEB_PORT = Number(process.env.E2E_WEB_PORT ?? 18088);
export const DB_NAME = process.env.E2E_DB_NAME ?? 'tradocraft_e2e';
guardDbName(DB_NAME);
// Login: E2E_PG_URL, else the server part of DATABASE_URL in the repository .env, else the CI default.
const pgBase = (process.env.E2E_PG_URL ?? envPg().server ?? 'postgresql://tradocraft:tradocraft@localhost').replace(/\/+$/, '');

const browser = process.env.E2E_BROWSER ?? 'chromium';
if (browser !== 'chromium' && browser !== 'firefox') {
  throw new Error(`E2E_BROWSER must be "chromium" or "firefox", got "${browser}"`);
}
const slowMo = Number(process.env.E2E_SLOWMO ?? 0);
if (!Number.isFinite(slowMo) || slowMo < 0) throw new Error(`E2E_SLOWMO must be a number of milliseconds, got "${process.env.E2E_SLOWMO}"`);
const headed = ['1', 'true'].includes((process.env.E2E_HEADED ?? '').toLowerCase());

export default defineConfig({
  testDir: './tests',
  timeout: 20 * 60_000,
  expect: { timeout: 15_000 },
  workers: 1,
  fullyParallel: false,
  reporter: [['list']],
  use: {
    browserName: browser,
    headless: !headed,
    launchOptions: { slowMo },
    baseURL: `http://127.0.0.1:${WEB_PORT}`,
    viewport: { width: 1400, height: 1700 },
    screenshot: 'only-on-failure',
    trace: 'off',
    actionTimeout: 20_000,
  },
  webServer: [
    {
      command: 'node start-api.mjs',
      url: `http://127.0.0.1:${API_PORT}/api/v1/meta/environment`,
      reuseExistingServer: false,
      timeout: 120_000,
      env: {
        E2E_API_BIN: apiBin(),
        E2E_DB_NAME: DB_NAME,
        DATABASE_URL: `${pgBase}/${DB_NAME}`,
        AUTH_MODE: 'dev',
        SEED_DEV_DATA: 'true',
        APP_ENV_KIND: 'tutorial',
        APP_ENV_NAME: 'tutorial',
        BIND_ADDR: `127.0.0.1:${API_PORT}`,
        // The API reads its Typst templates relative to its working directory, which here is e2e/.
        TEMPLATE_DIR: path.join(root, 'templates'),
        RUST_LOG: 'warn',
        ...(process.env.MAIL_FILES_DIR ? {} : { MAIL_TRANSPORT: 'files' }),
      },
    },
    {
      command: `node static-server.mjs ${JSON.stringify(path.join(root, 'app/build/web'))} ${WEB_PORT}`,
      url: `http://127.0.0.1:${WEB_PORT}/`,
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
});
