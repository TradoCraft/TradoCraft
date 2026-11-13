import { defineConfig } from '@playwright/test';
import path from 'node:path';

// The whole stack runs locally: PostgreSQL (must be running), the API binary in a "tutorial"
// environment on a throw-away database, and a static server for the Flutter web build.
//   cargo build -p tradocraft-api
//   (cd app && flutter build web --release --no-web-resources-cdn)
//   cd e2e && npm ci && npx playwright test
const root = path.resolve(__dirname, '..');
export const API_PORT = Number(process.env.E2E_API_PORT ?? 18080);
export const WEB_PORT = Number(process.env.E2E_WEB_PORT ?? 18088);
export const DB_NAME = process.env.E2E_DB_NAME ?? 'tradocraft_e2e';
const pgBase = process.env.E2E_PG_URL ?? 'postgresql://tradocraft:tradocraft@localhost';

export default defineConfig({
  testDir: './tests',
  timeout: 20 * 60_000,
  expect: { timeout: 15_000 },
  workers: 1,
  fullyParallel: false,
  reporter: [['list']],
  use: {
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
        E2E_API_BIN: process.env.E2E_API_BIN ?? path.join(root, 'target/debug/tradocraft-api'),
        E2E_DB_NAME: DB_NAME,
        DATABASE_URL: `${pgBase}/${DB_NAME}`,
        AUTH_MODE: 'dev',
        SEED_DEV_DATA: 'true',
        APP_ENV_KIND: 'tutorial',
        APP_ENV_NAME: 'tutorial',
        BIND_ADDR: `127.0.0.1:${API_PORT}`,
        RUST_LOG: 'warn',
        ...(process.env.MAIL_FILES_DIR ? {} : { MAIL_TRANSPORT: 'files' }),
      },
    },
    {
      command: `node static-server.mjs ${path.join(root, 'app/build/web')} ${WEB_PORT}`,
      url: `http://127.0.0.1:${WEB_PORT}/`,
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
});
