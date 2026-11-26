import { defineConfig } from '@playwright/test';
import path from 'node:path';

const { apiBin, envPg, guardDbName } = require('./lib.cjs');
const root = path.resolve(__dirname, '..');

export const API_PORT = Number(process.env.E2E_API_PORT ?? 18080);
export const DB_NAME = process.env.E2E_DB_NAME ?? 'tradocraft_e2e';
const pgBase = (process.env.E2E_PG_URL ?? envPg().server ?? 'postgresql://tradocraft:tradocraft@localhost').replace(/\/+$/, '');
export const DATABASE_URL = `${pgBase}/${DB_NAME}`;

const externalBaseUrl = process.env.E2E_BASE_URL?.trim().replace(/\/+$/, '');
if (!externalBaseUrl) {
  guardDbName(DB_NAME);
}

const browser = process.env.E2E_BROWSER ?? 'chromium';
if (browser !== 'chromium' && browser !== 'firefox') {
  throw new Error(`E2E_BROWSER must be "chromium" or "firefox", got "${browser}"`);
}
const slowMo = Number(process.env.E2E_SLOWMO ?? 0);
if (!Number.isFinite(slowMo) || slowMo < 0) {
  throw new Error(`E2E_SLOWMO must be a number of milliseconds, got "${process.env.E2E_SLOWMO}"`);
}
const headed = ['1', 'true'].includes((process.env.E2E_HEADED ?? '').toLowerCase());

export default defineConfig({
  testDir: './tests-leptos',
  timeout: 120_000,
  expect: { timeout: 15_000 },
  workers: 1,
  fullyParallel: false,
  reporter: [['list']],
  use: {
    browserName: browser,
    headless: !headed,
    launchOptions: { slowMo, ...(process.env.E2E_CHROMIUM_PATH ? { executablePath: process.env.E2E_CHROMIUM_PATH } : {}) },
    baseURL: externalBaseUrl || `http://127.0.0.1:${API_PORT}`,
    viewport: { width: 1400, height: 1000 },
    screenshot: 'only-on-failure',
    trace: 'off',
    actionTimeout: 15_000,
  },
  webServer: externalBaseUrl
    ? undefined
    : [
        {
          command: 'node start-api.mjs',
          url: `http://127.0.0.1:${API_PORT}/api/v1/meta/environment`,
          reuseExistingServer: false,
          timeout: 120_000,
          env: {
            E2E_API_BIN: apiBin(),
            E2E_DB_NAME: DB_NAME,
            DATABASE_URL,
            AUTH_MODE: 'dev',
            SEED_DEV_DATA: 'true',
            APP_ENV_KIND: 'tutorial',
            APP_ENV_NAME: 'tutorial',
            BIND_ADDR: `127.0.0.1:${API_PORT}`,
            TEMPLATE_DIR: path.join(root, 'templates'),
            WEB_UI_DIR: path.join(root, 'crates/web-ui/dist'),
            RUST_LOG: 'warn',
            ...(process.env.MAIL_FILES_DIR ? {} : { MAIL_TRANSPORT: 'files' }),
          },
        },
      ],
});
