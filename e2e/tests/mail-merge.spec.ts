import { expect, test } from '@playwright/test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import path from 'node:path';
import { API_PORT, DATABASE_URL } from '../playwright.config';
import { boot, choose, field, railTo, typeInto } from './flutter';

test('save a localized mailing draft and review its audience', async ({ page, request }) => {
  const api = `http://127.0.0.1:${API_PORT}/api/v1`;
  const headers = { 'x-dev-user': 'admin@example.com' };
  const created = await request.post(`${api}/kb/documents`, {
    headers,
    data: { title: 'Mail preview technical memo', kind: 'technical_memo' },
  });
  await expect(created).toBeOK();
  const doc = await created.json();
  await expect(await request.put(`${api}/kb/documents/${doc.id}/draft/de`, {
    headers: { ...headers, 'content-type': 'application/pdf' },
    params: { filename: 'notice-de.pdf' },
    data: Buffer.from('%PDF-1.7 preview specimen'),
  })).toBeOK();
  await expect(await request.post(`${api}/kb/documents/${doc.id}/publish`, { headers })).toBeOK();
  for (const [code, name, language, email] of [
    ['MERGE-DE', 'Mail Preview German', 'de', 'preview@example.test'],
    ['MERGE-NL', 'Mail Preview Dutch', 'nl', null],
  ]) {
    await expect(await request.post(`${api}/customers`, {
      headers,
      data: { code, name, language, email, price_zone_id: '00000000-0000-7000-8000-000000000201' },
    })).toBeOK();
  }

  await boot(page);
  await page.getByRole('button', { name: 'Not now' }).click();
  await railTo(page, 'Customers');
  await page.getByRole('button', { name: 'Mail merge', exact: true }).click();
  await choose(page, /^Documents/, 'Mail preview technical memo');
  await choose(page, /^Language/, 'Deutsch');
  await typeInto(field(page, 'Subject'), 'Hinweis für {{customer.name}}');
  await typeInto(field(page, 'Message'), 'Guten Tag, hier ist unsere Mitteilung.');
  const save = page.waitForResponse(r => r.request().method() === 'PUT' && r.url().endsWith('/customers/mail-merge'));
  await page.getByRole('button', { name: 'Save and preview', exact: true }).click();
  expect((await save).ok()).toBe(true);
  await expect(page.getByText('Audience preview', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: /Mail Preview German/ }).click();
  await expect(page.getByRole('group', { name: 'Hinweis für Mail Preview German', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'notice-de.pdf', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: /Mail Preview Dutch.*Missing email address.*Missing subject/s })).toBeVisible();

  const saved = await request.get(`${api}/customers/mail-merge`, { headers });
  await expect(saved).toBeOK();
  const result = await saved.json();
  expect(result.draft.document_id).toBe(doc.id);
  expect(result.audience.find((row: { email?: string }) => row.email === 'preview@example.test')).toMatchObject({
    subject: 'Hinweis für Mail Preview German',
    body: 'Guten Tag, hier ist unsere Mitteilung.',
    pdf: 'notice-de.pdf',
    issues: [],
  });
});

test('confirm one mailing twice and retain the original localized PDFs', async ({ page, request }, testInfo) => {
  test.setTimeout(180_000);
  const api = `http://127.0.0.1:${API_PORT}/api/v1`;
  const headers = { 'x-dev-user': 'admin@example.com' };
  const setup = await request.post(`${api}/kb/documents`, {
    headers, data: { title: 'Queue technical memo', kind: 'technical_memo' },
  });
  await expect(setup).toBeOK();
  const document = await setup.json();
  const original = '%PDF-1.7 Original queue French';
  const files = { fr: original, nl: '%PDF-1.7 Original queue Dutch' };
  async function upload(lang: string, name: string, content: string) {
    await expect(await request.put(`${api}/kb/documents/${document.id}/draft/${lang}`, {
      headers: { ...headers, 'content-type': 'application/pdf' },
      params: { filename: name },
      data: Buffer.from(content),
    })).toBeOK();
  }
  for (const [lang, content] of Object.entries(files)) {
    await upload(lang, `queue-${lang}.pdf`, content);
  }
  await expect(await request.post(`${api}/kb/documents/${document.id}/publish`, { headers })).toBeOK();
  for (const [code, name, language, email] of [
    ['QUEUE-FR', 'Queue French', 'fr', 'queue-fr@example.test'],
    ['QUEUE-NL', 'Queue Dutch', 'nl', 'queue-nl@example.test'],
    ['QUEUE-DE', 'Queue Excluded', 'de', 'queue-excluded@example.test'],
  ]) {
    await expect(await request.post(`${api}/customers`, {
      headers,
      data: { code, name, language, email, price_zone_id: '00000000-0000-7000-8000-000000000201' },
    })).toBeOK();
  }

  await boot(page);
  await page.getByRole('button', { name: 'Not now' }).click();
  await railTo(page, 'Customers');
  await page.getByRole('button', { name: 'Mail merge', exact: true }).click();
  await choose(page, /^Documents/, 'Queue technical memo');
  for (const [language, subject, greeting] of [
    ['Français', 'Notice FR', 'Bonjour'],
    ['Nederlands', 'Notice NL', 'Beste'],
  ]) {
    await choose(page, /^Language/, language);
    await typeInto(field(page, 'Subject'), subject);
    await typeInto(field(page, 'Message'), `${greeting} {{contact.name}}`);
  }
  const saving = page.waitForResponse(r => r.request().method() === 'PUT' && r.url().endsWith('/customers/mail-merge'));
  await page.getByRole('button', { name: 'Save and preview', exact: true }).click();
  const saved = await saving;
  expect(saved.ok()).toBe(true);
  const { approval_id: approval } = await saved.json();
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.getByRole('button', { name: 'Confirm mailing', exact: true }).click();
    const queued = page.waitForResponse(r => r.url().endsWith(`/${approval}/confirm`));
    await page.getByRole('button', { name: 'Queue mailing', exact: true }).click();
    expect((await queued).status()).toBe(204);
  }

  await upload('fr', 'queue-fr-new.pdf', '%PDF-1.7 Replaced queue French');
  await expect(await request.post(`${api}/kb/documents/${document.id}/publish`, { headers })).toBeOK();

  const dir = testInfo.outputPath('outbox');
  const workerPath = process.env.E2E_WORKER_BIN ?? path.join(
    path.dirname(process.env.E2E_API_BIN ?? path.resolve('../target/debug/tradocraft-api')),
    process.platform === 'win32' ? 'tradocraft-worker.exe' : 'tradocraft-worker',
  );
  const worker = spawn(workerPath, {
    env: {
      ...process.env,
      DATABASE_URL,
      APP_ENV_KIND: 'tutorial',
      ALLOW_INBOUND_MAIL_IN_NON_LIVE: '0',
      MAIL_TRANSPORT: 'files',
      MAIL_FILES_DIR: dir,
      POLL_SECONDS: '1',
    },
    stdio: ['ignore', 'ignore', 'inherit'],
  });
  let launchError: Error | undefined;
  worker.on('error', error => launchError = error);
  try {
    await expect.poll(async () => {
      if (launchError) throw launchError;
      const response = await request.get(`${api}/customers/mail-merge/history`, { headers });
      await expect(response).toBeOK();
      const rows = (await response.json()).filter((row: { mailing_id: string }) => row.mailing_id === approval);
      return rows.filter((row: { delivery: string }) => row.delivery === 'sent').length;
    }, { timeout: 30_000 }).toBe(2);
    const messages = (await fs.readdir(dir)).filter(name => name.endsWith('.eml'));
    const content = await Promise.all(messages.map(name => fs.readFile(path.join(dir, name), 'utf8')));
    const relevant = content.filter(mail => /^Subject: Notice (FR|NL)\r?$/m.test(mail));
    expect(relevant).toHaveLength(2);
    for (const [lang, greeting, recipient] of [
      ['fr', 'Bonjour Queue French', 'queue-fr@example.test'],
      ['nl', 'Beste Queue Dutch', 'queue-nl@example.test'],
    ] as const) {
      const mail = relevant.find(m => m.includes(recipient));
      expect(mail).toBeDefined();
      expect(mail).toContain(`Subject: Notice ${lang.toUpperCase()}`);
      expect(mail).toContain(greeting);
      expect(mail).toContain(`queue-${lang}.pdf`);
      expect(mail!.includes(files[lang]) || mail!.includes(Buffer.from(files[lang]).toString('base64'))).toBe(true);
    }
    expect(content.some(mail => mail.includes('queue-excluded@example.test'))).toBe(false);
    await page.getByRole('button', { name: 'Refresh status', exact: true }).click();
    await expect(page.getByRole('button', { name: 'queue-fr.pdf', exact: true })).toBeVisible();
    const download = page.waitForResponse(r => r.url().endsWith(`/kb/documents/${document.id}/revisions/1/fr`));
    await page.getByRole('button', { name: 'queue-fr.pdf', exact: true }).click();
    expect((await (await download).body()).toString()).toBe(original);
  } finally {
    if (worker.pid && worker.exitCode == null) {
      const exited = once(worker, 'exit');
      worker.kill();
      await exited;
    }
  }
});
