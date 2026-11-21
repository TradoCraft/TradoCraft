import { expect, Page, test } from '@playwright/test';
import { boot, field, railTo, typeInto } from './flutter';
import { API_PORT } from '../playwright.config';

function pdf(label: string) {
  const stream = `BT /F1 18 Tf 50 100 Td (${label}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let contents = '%PDF-1.4\n';
  const offsets = objects.map((object, index) => {
    const offset = contents.length;
    contents += `${index + 1} 0 obj\n${object}\nendobj\n`;
    return offset;
  });
  const start = contents.length;
  contents += 'xref\n0 6\n0000000000 65535 f \n';
  for (const offset of offsets) contents += `${String(offset).padStart(10, '0')} 00000 n \n`;
  return Buffer.from(contents + `trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`);
}

async function openLibrary(page: Page, user: string) {
  await boot(page, user);
  const intro = page.getByRole('button', { name: 'Not now' });
  if (await intro.isVisible()) await intro.click();
  await railTo(page, 'Knowledge base');
  await page.getByRole('button', { name: 'Documents', exact: true }).click();
}

async function upload(page: Page, name: string, buffer: Buffer) {
  const chooser = page.waitForEvent('filechooser');
  const upload = page.waitForResponse(
    r => r.request().method() === 'PUT' && r.url().includes('/kb/documents/') && r.url().includes('/draft/'),
  );
  await page.getByRole('button', { name: 'Upload PDF', exact: true }).click();
  await (await chooser).setFiles({ name, mimeType: 'application/pdf', buffer });
  expect((await upload).status()).toBe(204);
  await expect(page.getByRole('button', { name: 'Upload PDF', exact: true })).toBeEnabled();
}

test('publish translated PDFs and keep the original revision', async ({ page, browser }) => {
  const title = 'Motor clearance memo';
  const oldPdf = pdf('First French revision');
  const newPdf = pdf('Second French revision');
  await openLibrary(page, 'admin');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await typeInto(field(page, 'Document title'), title);
  await typeInto(field(page, 'Keywords (comma separated)'), 'maintenance');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText(title, { exact: true })).toBeVisible();

  await page.getByRole('button', { name: /English/ }).click();
  await page.getByRole('menuitem', { name: /Nederlands/ }).click();
  await upload(page, 'memo-nl.pdf', pdf('Dutch revision'));
  await page.getByRole('button', { name: /Nederlands/ }).click();
  await page.getByRole('menuitem', { name: /Français/ }).click();
  await upload(page, 'memo-fr.pdf', oldPdf);
  const publish = page.getByRole('button', { name: 'Publish revision' });
  await publish.click();
  await expect(publish).toBeDisabled();
  await upload(page, 'memo-fr-updated.pdf', newPdf);
  await publish.click();
  await expect(publish).toBeDisabled();

  const reader = await browser.newPage({ viewport: { width: 1400, height: 1700 } });
  try {
    await openLibrary(reader, 'sales');
    await typeInto(reader.getByLabel('Search', { exact: true }), 'maintenance');
    await reader.keyboard.press('Enter');
    await reader.getByRole('button', { name: new RegExp(title) }).click();
    await expect(reader.getByRole('button', { name: 'Preview PDF', exact: true })).toHaveCount(4);
    // Revisions are newest first. Within each revision French appears before Dutch.
    for (const [revision, index, bytes] of [
      [2, 0, newPdf],
      [1, 2, oldPdf],
    ] as const) {
      const response = reader.waitForResponse(r => r.url().endsWith(`/revisions/${revision}/fr`));
      await reader.getByRole('button', { name: 'Preview PDF', exact: true }).nth(index).click();
      expect(await (await response).body()).toEqual(bytes);
      await reader.getByRole('button', { name: 'Close', exact: true }).click();
    }
  } finally {
    await reader.close();
  }
});

test('attach the ticket language and explicitly choose a fallback PDF', async ({ page, request }) => {
  const api = `http://127.0.0.1:${API_PORT}/api/v1`;
  const staff = { 'x-dev-user': 'admin@example.com' };
  const french = pdf('French service notice');
  const dutch = pdf('Dutch service notice');
  for (const fixture of [
    { title: 'Service notice multilingual', variants: [['fr', 'notice-fr.pdf', french], ['nl', 'notice-nl.pdf', dutch]] },
    { title: 'Service notice Dutch only', variants: [['nl', 'reference-nl.pdf', dutch]] },
  ] as const) {
    const created = await request.post(`${api}/kb/documents`, {
      headers: staff,
      data: { title: fixture.title, kind: 'technical_memo', keywords: ['service bulletin'] },
    });
    await expect(created).toBeOK();
    const doc = await created.json();
    for (const [language, filename, bytes] of fixture.variants) {
      const upload = await request.put(`${api}/kb/documents/${doc.id}/draft/${language}`, {
        headers: { ...staff, 'content-type': 'application/pdf' },
        params: { filename },
        data: bytes,
      });
      await expect(upload).toBeOK();
    }
    await expect(await request.post(`${api}/kb/documents/${doc.id}/publish`, { headers: staff })).toBeOK();
  }

  const subject = 'Library PDF requested';
  const ticket = await request.post(`${api}/tickets`, {
    headers: staff,
    data: { subject, language: 'fr', contact_name: 'Claire', contact_email: 'claire@example.test', body: 'Documentation requested.' },
  });
  await expect(ticket).toBeOK();
  const { id } = (await ticket.json()).ticket;
  await boot(page);
  await page.getByRole('button', { name: 'Not now' }).click();
  await railTo(page, 'Helpdesk');
  await page.getByRole('button', { name: 'All', exact: true }).click();
  await page.getByRole('button', { name: new RegExp(subject) }).click();
  await page.getByRole('button', { name: 'Reply to customer' }).click();
  const attach = page.getByRole('button', { name: 'Attach from Documents' });

  await attach.click();
  const picker = page.getByRole('alertdialog');
  const search = picker.getByRole('textbox', { name: 'Search', exact: true });
  await typeInto(search, 'service bulletin');
  const searchResponse = page.waitForResponse(r => r.url().includes('/kb/documents?q='));
  await picker.getByRole('button', { name: 'Search', exact: true }).click();
  expect((await searchResponse).ok()).toBe(true);
  await picker.getByRole('button', { name: 'Service notice multilingual' }).click();
  await picker.getByRole('button', { name: /Français.*notice-fr.pdf/s }).click();

  await attach.click();
  await picker.getByRole('button', { name: 'Service notice Dutch only' }).click();
  await expect(picker.getByText('No PDF in the ticket language. Choose an available language.')).toBeVisible();
  await picker.getByRole('button', { name: /Nederlands.*reference-nl.pdf/s }).click();

  await typeInto(field(page, 'Message'), 'Voici la note technique.');
  const sent = page.waitForResponse(r => r.url().endsWith(`/tickets/${id}/replies`));
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  expect((await sent).ok()).toBe(true);
  const saved = await request.get(`${api}/tickets/${id}`, { headers: staff });
  await expect(saved).toBeOK();
  const article = (await saved.json()).articles.find((a: { kind: string }) => a.kind === 'email_out');
  expect(article.attachments.map((attachment: { filename: string }) => attachment.filename).sort())
    .toEqual(['notice-fr.pdf', 'reference-nl.pdf']);
  const frenchFile = article.attachments.find((a: { filename: string }) => a.filename === 'notice-fr.pdf');
  const response = await request.get(`${api}/tickets/${id}/attachments/${frenchFile.id}`, { headers: staff });
  await expect(response).toBeOK();
  expect(await response.body()).toEqual(french);
});
