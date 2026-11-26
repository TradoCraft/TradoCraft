import { execFileSync } from 'node:child_process';
import { APIRequestContext, expect, Page } from '@playwright/test';
import { API_PORT, DATABASE_URL } from '../playwright.leptos.config';

// Shared helpers of the Leptos release-gate specs (Helpdesk, To-do, Knowledge Base, Standard Answers).

export const api = `http://127.0.0.1:${API_PORT}/api/v1`;
export const asAdmin = { 'x-dev-user': 'admin@example.com' };
export const ADMIN_USER_ID = '00000000-0000-7000-8000-000000000101';

/** Unique text per run, so specs never match each other's records. */
export const unique = (prefix: string): string => `${prefix} ${Date.now().toString(36)}`;

export interface ErrorCollector {
  assertClean: () => void;
}

/** Fails the test on uncaught page errors and console errors (favicon misses are ignored). */
export function attachErrorCollector(page: Page): ErrorCollector {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    const url = msg.location()?.url ?? '';
    if (url.endsWith('/favicon.ico') || msg.text().includes('favicon.ico')) return;
    consoleErrors.push(url ? `${msg.text()} (${url})` : msg.text());
  });
  page.on('pageerror', (err) => pageErrors.push(err.message || String(err)));
  return {
    assertClean: () => {
      // One assertion, so a failure shows the panic message (console) next to the page error.
      expect(
        { pageErrors, consoleErrors },
        `Uncaught page errors: ${pageErrors.join('; ')}\nConsole errors: ${consoleErrors.join('; ')}`,
      ).toEqual({ pageErrors: [], consoleErrors: [] });
    },
  };
}

export async function signInAsAdmin(page: Page): Promise<void> {
  await page.goto('/app/login');
  await expect(page.locator('[data-target="login-form"]')).toBeVisible();
  await page.locator('[data-target="login-dev-user"]').fill('admin@example.com');
  await page.locator('[data-target="login-submit"]').click();
  await expect(page.locator('[data-target="active-user"]')).toBeVisible();
}

/** Opens a module from the sidebar. */
export async function openModule(page: Page, nav: string, url: RegExp): Promise<void> {
  await page.locator(`[data-target="module-nav"] [data-target="${nav}"]`).click();
  await expect(page).toHaveURL(url);
}

/**
 * Reloads the page. The app keeps its session in memory only, so after the reload sign in again and
 * return to the module through the navigation (a full page load would drop the session once more).
 */
export async function reloadAndReturn(page: Page, nav: string, url: RegExp): Promise<void> {
  await page.reload();
  await expect(page.locator('.tc-shell')).toBeVisible();
  await signInAsAdmin(page);
  await openModule(page, nav, url);
}

/** Runs a SQL query against the e2e database and returns the rows as text (psql -At). */
export function sql(query: string): string[] {
  const out = execFileSync('psql', [DATABASE_URL, '-v', 'ON_ERROR_STOP=1', '-At', '-c', query], {
    encoding: 'utf8',
  });
  return out.split('\n').filter((line) => line.length > 0);
}

/**
 * Replies queued for the customer: the ticket articles of kind `email_out` still waiting for the worker,
 * which writes them to .eml files in the tutorial environment (MAIL_TRANSPORT=files).
 */
export function queuedReplies(address: string, text: string): number {
  const literal = (value: string) => `'${value.replace(/'/g, "''")}'`;
  return Number(
    sql(
      `select count(*) from helpdesk.articles where kind = 'email_out' and delivery = 'queued' ` +
        `and to_addresses @> array[${literal(address)}] and body like ${literal(`%${text}%`)}`,
    )[0],
  );
}

/** A plain-text RFC 5322 message with CRLF line endings. */
function rfc822(o: { from: { name: string; address: string }; subject: string; body: string; messageId: string }) {
  return [
    `Message-ID: <${o.messageId}>`,
    `From: ${o.from.name} <${o.from.address}>`,
    'To: support@example.test',
    `Subject: ${o.subject}`,
    `Date: ${new Date().toUTCString()}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    '',
    o.body,
    '',
  ].join('\r\n');
}

export interface Inbound {
  ticket_id: string;
  ticket_number: string;
}

/** Delivers a customer e-mail to the helpdesk, as the mail importer does (`POST /helpdesk/inbound`). */
export async function receiveMail(
  request: APIRequestContext,
  from: { name: string; address: string },
  subject: string,
  body: string,
): Promise<Inbound> {
  const messageId = `e2e-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`;
  const res = await request.post(`${api}/helpdesk/inbound`, {
    headers: { 'content-type': 'message/rfc822', ...asAdmin },
    data: rfc822({ from, subject, body, messageId }),
  });
  expect(res.ok(), await res.text()).toBeTruthy();
  return res.json();
}

/** Creates a helpdesk team with the admin user as its only member. */
export async function createTeam(request: APIRequestContext, name: string): Promise<void> {
  const res = await request.post(`${api}/helpdesk/teams`, {
    headers: asAdmin,
    data: { name, members: [{ user_id: ADMIN_USER_ID, is_lead: true }] },
  });
  expect(res.ok(), await res.text()).toBeTruthy();
}

/** A 1x1 transparent PNG, accepted as a ticket attachment. */
export const PNG_1X1 = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);
