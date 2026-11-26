import { expect, test } from '@playwright/test';
import {
  attachErrorCollector, createTeam, openModule, PNG_1X1, queuedReplies, receiveMail, reloadAndReturn,
  signInAsAdmin, sql, unique,
} from './support';

// Gate: a staff user can find and open tickets, create a ticket, assign it to a team or owner, add an
// internal note, send a customer reply with an attachment, and change or reopen its status. The reply
// reaches the local outbox and the ticket history and attachment are still there after a reload.

test('Helpdesk: find, create, assign, note, reply with attachment, close and reopen, reload', async ({
  page,
  request,
}) => {
  const errors = attachErrorCollector(page);
  const tag = Date.now().toString(36);
  const customer = { name: 'Priya Natarajan', address: `priya.${tag}@example.test` };
  const subject = unique('Pump humming');
  const created = unique('Counter display dark');
  const note = unique('Checked the maintenance log');
  const reply = unique('We will send a technician');
  const team = unique('Support team');

  await createTeam(request, team);
  const inbound = await receiveMail(request, customer, subject, 'The pump hums loudly since this morning.');
  const row = (number: string) => page.locator(`[data-target="ticket-row-${number}"]`);
  const search = async (text: string) => {
    await page.locator('[data-target="helpdesk-status-filter"]').selectOption('');
    await page.locator('[data-target="helpdesk-search"]').fill(text);
  };

  await signInAsAdmin(page);
  await openModule(page, 'nav-helpdesk', /\/app\/helpdesk$/);
  await expect(page.locator('[data-target="helpdesk-page"]')).toBeVisible();

  await test.step('find and open a ticket that arrived by e-mail', async () => {
    await search(subject);
    await expect(row(inbound.ticket_number)).toBeVisible();
    await row(inbound.ticket_number).click();
    await expect(page.locator('[data-target="ticket-articles"]')).toContainText('The pump hums loudly');
  });

  await test.step('assign the ticket to a team and an owner', async () => {
    await page.locator('[data-target="ticket-assign-team"]').selectOption({ label: team });
    await page.locator('[data-target="ticket-assign-owner"]').selectOption({ label: 'Admin User' });
    await page.locator('[data-target="ticket-assign-save"]').click();
    await expect(page.locator('[data-target="ticket-team-badge"]')).toContainText(team);
    await expect(page.locator('[data-target="ticket-owner-badge"]')).toContainText('Admin User');
  });

  await test.step('add an internal note', async () => {
    await page.locator('[data-target="ticket-note-body"]').fill(note);
    await page.locator('[data-target="ticket-note-submit"]').click();
    await expect(page.locator('[data-target="ticket-articles"]')).toContainText(note);
  });

  await test.step('send a customer reply with an attachment', async () => {
    await page.locator('[data-target="ticket-reply-body"]').fill(reply);
    await page.locator('[data-target="ticket-reply-attach"]').setInputFiles({
      name: 'pump-photo.png',
      mimeType: 'image/png',
      buffer: PNG_1X1,
    });
    await expect(page.locator('[data-target="ticket-reply-attachments"]')).toContainText('pump-photo.png');
    await page.locator('[data-target="ticket-send"]').click();
    await expect(page.locator('[data-target="ticket-articles"]')).toContainText(reply);
    await expect(
      page.locator('[data-target="ticket-attachment-download"][data-filename="pump-photo.png"]'),
    ).toBeVisible();
  });

  await test.step('the reply reaches the local outbox', async () => {
    await expect.poll(() => queuedReplies(customer.address, reply)).toBe(1);
  });

  await test.step('close the ticket and reopen it', async () => {
    const status = async () => sql(`select status from helpdesk.tickets where id = '${inbound.ticket_id}'`)[0];
    await page.locator('[data-target="ticket-quick-status"]').selectOption('closed');
    await page.locator('[data-target="ticket-apply-status"]').click();
    await expect.poll(status).toBe('closed');
    await page.locator('[data-target="ticket-quick-status"]').selectOption('open');
    await page.locator('[data-target="ticket-apply-status"]').click();
    await expect.poll(status).toBe('open');
  });

  await test.step('create a ticket from the form', async () => {
    await page.locator('[data-target="helpdesk-create"]').click();
    await page.locator('[data-target="new-ticket-subject"]').fill(created);
    await page.locator('[data-target="new-ticket-body"]').fill('Reported by phone.');
    await page.locator('[data-target="new-ticket-submit"]').click();
    await search(created);
    await expect(page.locator('[data-target="helpdesk-table"]')).toContainText(created);
  });

  await test.step('history and attachment are still there after a reload', async () => {
    await reloadAndReturn(page, 'nav-helpdesk', /\/app\/helpdesk$/);
    await search(subject);
    await row(inbound.ticket_number).click();
    const articles = page.locator('[data-target="ticket-articles"]');
    await expect(articles).toContainText(note);
    await expect(articles).toContainText(reply);
    await expect(
      page.locator('[data-target="ticket-attachment-download"][data-filename="pump-photo.png"]'),
    ).toBeVisible();
  });

  errors.assertClean();
});
