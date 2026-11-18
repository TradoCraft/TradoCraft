import { APIRequestContext, expect, Page, test } from '@playwright/test';
import { API_PORT } from '../playwright.config';
import { boot, choose, field, railTo, searchPick, typeInto } from './flutter';

// The helpdesk, end to end: a customer's e-mail arrives (the API's `POST /helpdesk/inbound`, the call the mail
// importer makes, ADR 0013), and an agent works the ticket through the UI. Each step is one area of the module.

const api = `http://127.0.0.1:${API_PORT}/api/v1`;
const customer = { name: 'Priya Natarajan', address: 'priya.natarajan@example.test' };
let seq = 0;
const asAdmin = { 'x-dev-user': 'admin@example.com' };

/** A plain-text RFC 5322 message with CRLF line endings. */
function rfc822(o: { subject: string; body: string; messageId: string; inReplyTo?: string }): string {
  return [
    `Message-ID: <${o.messageId}>`,
    ...(o.inReplyTo ? [`In-Reply-To: <${o.inReplyTo}>`, `References: <${o.inReplyTo}>`] : []),
    `From: ${customer.name} <${customer.address}>`,
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

type Inbound = { ticket_id: string; ticket_number: string; new_ticket: boolean; duplicate: boolean; messageId: string };

/** Delivers a customer e-mail to the helpdesk, as the mail importer does. */
async function receiveMail(
  request: APIRequestContext,
  subject: string,
  body: string,
  inReplyTo?: string,
): Promise<Inbound> {
  const messageId = `e2e-${Date.now()}-${seq++}@example.test`;
  const res = await request.post(`${api}/helpdesk/inbound`, {
    headers: { 'content-type': 'message/rfc822', ...asAdmin },
    data: rfc822({ subject, body, messageId, inReplyTo }),
  });
  expect(res.ok(), await res.text()).toBeTruthy();
  return { ...(await res.json()), messageId };
}

/** Opens the helpdesk list with every ticket (the new ones are unassigned) and opens the one named `title`. */
async function openTicket(page: Page, title: string | RegExp) {
  await railTo(page, 'Helpdesk');
  // The list is the module's front page; once a record is open, its "Overview" tab leads back to it.
  const overview = page.getByRole('button', { name: 'Overview', exact: true });
  if (await overview.isVisible()) await overview.click();
  await page.getByRole('button', { name: 'All', exact: true }).click();
  await page.getByRole('button', { name: title }).first().click();
}

test('a customer writes in and the helpdesk handles the ticket', async ({ page, request }) => {
  await boot(page);
  // A tutorial environment offers its guided tour on first sign-in; this test works on its own.
  await page.getByRole('button', { name: 'Not now' }).click();
  let first: Inbound;

  await test.step('an e-mail becomes a new ticket', async () => {
    first = await receiveMail(
      request,
      'Gearbox makes a grinding noise',
      'Hello, since last week the gearbox of our cart grinds when it starts. Can you help?',
    );
    expect(first.new_ticket).toBe(true);
    expect(first.duplicate).toBe(false);
    await openTicket(page, /grinding noise/);
    await expect(page.getByText('Gearbox makes a grinding noise').first()).toBeVisible();
    await expect(page.getByText(/grinds when it starts/).first()).toBeVisible();
  });

  await test.step('the agent replies to the customer using a prepared answer', async () => {
    await page.getByRole('button', { name: 'Reply to customer' }).click();
    await page.getByRole('button', { name: 'Insert prepared answer' }).click();
    await page.getByRole('button', { name: /Delivery time/ }).first().click();
    await field(page, 'Message').click();
    await expect(field(page, 'Message')).not.toHaveValue('');
    await typeInto(field(page, 'Message'), 'Hello Priya, we are looking into it. Which gearbox model do you have?');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(page.getByText('Reply queued for sending').first()).toBeVisible();
    await expect(page.getByText(/Which gearbox model/).first()).toBeVisible();
  });

  await test.step('an internal note stays inside', async () => {
    await page.getByRole('button', { name: 'Internal note' }).click();
    await typeInto(field(page, 'Internal note'), 'Probably the worn pinion again, check the stock.');
    await page.getByRole('button', { name: 'Add note', exact: true }).click();
    await expect(page.getByText('Note added').first()).toBeVisible();
    await expect(page.getByText(/worn pinion/).first()).toBeVisible();
  });

  await test.step('the customer answers: the mail joins the same ticket', async () => {
    const again = await receiveMail(request, 'Re: Gearbox makes a grinding noise', 'It is the GX-200.', first.messageId);
    expect(again.new_ticket).toBe(false);
    expect(again.ticket_number).toBe(first.ticket_number);
    // Reopen the ticket: the in-process mail import publishes no live event (ADR 0073).
    await page.getByRole('button', { name: 'Close tab' }).first().click();
    await openTicket(page, /grinding noise/);
    await expect(page.getByText('It is the GX-200.').first()).toBeVisible();
    // Importing the same message again is recognised.
    const res = await request.post(`${api}/helpdesk/inbound`, {
      headers: { 'content-type': 'message/rfc822', ...asAdmin },
      data: rfc822({
        subject: 'Re: Gearbox makes a grinding noise',
        body: 'It is the GX-200.',
        messageId: again.messageId,
        inReplyTo: first.messageId,
      }),
    });
    expect((await res.json()).duplicate).toBe(true);
  });

  await test.step('status and priority are saved with the ticket', async () => {
    await choose(page, /^Priority/, 'high');
    await choose(page, /^Status(?! afterwards)/, 'waiting for colleague');
    await page.getByRole('button', { name: 'Save changes' }).click();
    await expect(async () => {
      const t = await (await request.get(`${api}/tickets/${first.ticket_id}`, { headers: asAdmin })).json();
      expect(t.ticket.priority).toBe('high');
      expect(t.ticket.status).toBe('pending_internal');
    }).toPass();
  });

  await test.step('tags, checklist and watching', async () => {
    await typeInto(field(page, 'Add tag'), 'gearbox');
    await page.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(page.getByRole('checkbox', { name: 'gearbox' })).toBeVisible();
    await typeInto(field(page, 'Add checklist item'), 'Check pinion stock');
    await page.getByRole('button', { name: 'Add checklist item' }).click();
    await expect(page.getByText('Check pinion stock').first()).toBeVisible();
    // Tick the checklist item.
    await page.getByRole('checkbox').last().click();
    await expect(page.getByText('1/1').first()).toBeVisible();
    // Replying made the agent a watcher already; stop and start again.
    await page.getByRole('button', { name: 'Stop watching' }).click();
    await page.getByRole('button', { name: 'Watch', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Stop watching' })).toBeVisible();
  });

  await test.step('time tracking', async () => {
    await page.getByRole('button', { name: 'Log time' }).click();
    await typeInto(field(page, 'Minutes'), '25');
    await typeInto(field(page, 'Note'), 'Inspected gearbox');
    await page.getByRole('checkbox', { name: 'Billable' }).click();
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(page.getByText(/25 min/).first()).toBeVisible();
    await expect(page.getByText(/Total 25 min, billable 25 min/).first()).toBeVisible();
  });

  await test.step('log a phone call on the ticket', async () => {
    await page.getByRole('button', { name: 'Log call' }).click();
    await typeInto(field(page, 'Duration (minutes)'), '10');
    await typeInto(field(page, 'What was discussed'), 'Confirmed GX-200 serial number with Priya.');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(page.getByText('Call logged').first()).toBeVisible();
    await expect(page.getByText(/Confirmed GX-200 serial number/).first()).toBeVisible();
  });

  await test.step('escalate and hand over', async () => {
    await page.getByRole('button', { name: 'Escalate', exact: true }).click();
    await choose(page, /^Escalate to/, /Support Agent/);
    await typeInto(field(page, 'Reason (required)'), 'Needs specialist gearbox review.');
    await page.getByRole('button', { name: 'Escalate', exact: true }).last().click();
    await expect(page.getByText('Ticket escalated').first()).toBeVisible();
    await expect(page.getByText('Escalated').first()).toBeVisible();

    await page.getByRole('button', { name: 'Hand over', exact: true }).click();
    await choose(page, /^New owner/, /Support Agent/);
    await typeInto(field(page, 'Comment for the new owner (optional)'), 'Please check GX-200 tolerances.');
    await page.getByRole('button', { name: 'Hand over', exact: true }).last().click();
    await expect(page.getByText('Ticket handed over').first()).toBeVisible();
  });

  await test.step('linked tickets and bundle mass update', async () => {
    const second = await receiveMail(
      request,
      'Spare pinion kit for GX-200',
      'Can you also quote a spare pinion kit?',
    );
    expect(second.new_ticket).toBe(true);

    await page.getByRole('button', { name: 'Add link…' }).click();
    await choose(page, /Relation|Add the other|Join the bundle|Related/, 'Add the other ticket to this bundle');
    await typeInto(field(page, 'Search tickets'), second.ticket_number);
    await page.getByRole('button', { name: new RegExp(second.ticket_number) }).first().click();
    await page.getByRole('button', { name: 'Link', exact: true }).click();
    await expect(page.getByText(new RegExp(second.ticket_number)).first()).toBeVisible();

    await page.getByRole('button', { name: 'Update bundle…' }).click();
    await page.getByRole('button', { name: 'Internal note', exact: true }).last().click();
    await typeInto(field(page, 'Internal note').last(), 'Bundle check: GX-200 parts ordered.');
    await page.getByRole('button', { name: 'Preview', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Apply to 1 ticket' })).toBeVisible();
    await page.getByRole('button', { name: 'Apply to 1 ticket' }).click();
    await expect(page.getByRole('button', { name: 'Close', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Close', exact: true }).click();
  });

  await test.step('link a customer and create a sales lead from the ticket', async () => {
    await searchPick(page, 'Customer', 'Alpha', /Alpha Installaties/);
    await page.getByRole('button', { name: 'Save changes' }).click();
    await page.getByRole('button', { name: 'Create lead' }).click();
    await typeInto(field(page, 'Expected value (optional)'), '1500');
    await page.getByRole('button', { name: 'OK', exact: true }).click();
    await expect(page.getByText('Lead created').first()).toBeVisible();
  });

  await test.step('prepared answers, reports and settings screens open', async () => {
    await page.getByRole('button', { name: 'Overview', exact: true }).click();
    await page.getByRole('button', { name: 'Prepared answers' }).click();
    await expect(page.getByRole('button', { name: 'New answer' })).toBeVisible();
    await page.getByRole('button', { name: 'Back' }).click();

    await page.getByRole('button', { name: 'Reports' }).click();
    await expect(page.getByRole('button', { name: 'Scheduled mails' })).toBeVisible();
    await page.getByRole('button', { name: 'Back' }).click();

    await page.getByRole('button', { name: 'Helpdesk settings' }).click();
    await expect(page.getByRole('button', { name: 'Automation rules' })).toBeVisible();
  });
});
