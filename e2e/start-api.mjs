// Starts the API on a fresh database. Playwright starts web servers before global setup, so the
// database is recreated here: the tutorial creates records and the seed only runs on an empty one.
import { execFileSync, spawn } from 'node:child_process';

const { E2E_API_BIN, DATABASE_URL, E2E_DB_NAME } = process.env;
const admin = DATABASE_URL.replace(/\/[^/]+$/, '/postgres');
const psql = (sql) => execFileSync('psql', [admin, '-v', 'ON_ERROR_STOP=1', '-q', '-c', sql], { stdio: 'inherit' });
psql(`drop database if exists ${E2E_DB_NAME} with (force)`);
psql(`create database ${E2E_DB_NAME}`);
const child = spawn(E2E_API_BIN, { stdio: 'inherit' });
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => child.kill(sig));
child.on('exit', (code) => process.exit(code ?? 0));
