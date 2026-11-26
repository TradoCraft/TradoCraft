import { expect, test } from '@playwright/test';
import {
  attachErrorCollector, openModule, queuedReplies, receiveMail, signInAsAdmin, unique,
} from './support';

// Gate: users with permission create and edit reusable reply templates with subject and body translations.
// In Helpdesk an agent finds an answer, inserts it into a ticket reply in the ticket's language, reviews the
// rendered placeholders and edits the draft before sending. The reply reaches the tutorial outbox.

test('Standard Answers: write a template, use it in a ticket reply, edit and send', async ({ page, request }) => {
  const errors = attachErrorCollector(page);
  const tag = Date.now().toString(36);
  const customer = { name: 'Jonas Peeters', address: `jonas.${tag}@example.test` };
  const subject = unique('Vraag over levering');
  const code = `E2E-${tag}`.toUpperCase();
  const name = unique('Delivery follow-up');
  const extra = unique('Please call us if anything is unclear');

  const inbound = await receiveMail(request, customer, subject, 'Wanneer komt mijn bestelling aan? Alvast bedankt voor uw antwoord.');

  await signInAsAdmin(page);

  await test.step('create a template with an English subject and body', async () => {
    await openModule(page, 'nav-answers', /\/app\/helpdesk\/answers$/);
    await expect(page.locator('[data-target="answers-page"]')).toBeVisible();
    await page.locator('[data-target="answers-new"]').click();
    await page.locator('[data-target="answers-code"]').fill(code);
    await page.locator('[data-target="answers-name"]').fill(name);
    await page.locator('[data-target="answers-keywords"]').fill('delivery, arrive');
    await page.locator('[data-target="answers-lang-en"]').click();
    await page.locator('[data-target="answers-subject-en"]').fill('Re: {{ticket.subject}}');
    await page.locator('[data-target="answers-body-en"]').fill('Dear {{contact.name}}, about ticket ');
    await page.locator('[data-target="answers-placeholder-ticket.number"]').click();
    await page.locator('[data-target="answers-save"]').click();
    await expect(page.locator('[data-target="answers-list"]')).toContainText(name);
  });

  await test.step('edit the template: add a Dutch text', async () => {
    await page.locator('[data-target="answers-search"]').fill(code);
    await page.locator('[data-target^="answers-edit-"]').first().click();
    await page.locator('[data-target="answers-lang-nl"]').click();
    await page.locator('[data-target="answers-subject-nl"]').fill('Re: {{ticket.subject}}');
    await page.locator('[data-target="answers-body-nl"]').fill('Beste {{contact.name}}, over ticket {{ticket.number}}.');
    await page.locator('[data-target="answers-save"]').click();
    await expect(page.locator('[data-target^="answers-lang-badge-"][data-target$="-nl"]').first()).toHaveClass(/tc-badge-primary/);
  });

  await test.step('insert it into a ticket reply, review and edit the draft', async () => {
    await openModule(page, 'nav-helpdesk', /\/app\/helpdesk$/);
    await page.locator('[data-target="helpdesk-status-filter"]').selectOption('');
    await page.locator('[data-target="helpdesk-search"]').fill(subject);
    await page.locator(`[data-target="ticket-row-${inbound.ticket_number}"]`).click();
    await page.locator('[data-target="helpdesk-answer-search"]').fill(code);
    const picker = page.locator('[data-target="helpdesk-prepared-answers"]');
    const value = await picker.locator('option', { hasText: name }).first().getAttribute('value');
    await picker.selectOption(value!);
    const body = page.locator('[data-target="ticket-reply-body"]');
    // The ticket is Dutch, so the Dutch text is used; placeholders are filled in for this ticket and customer.
    await expect(body).toHaveValue(new RegExp(`Beste ${customer.name}.*${inbound.ticket_number}`));
    await expect(body).not.toHaveValue(/\{\{/);
    await expect(page.locator('[data-target="helpdesk-answer-notice"]')).toBeVisible();
    await expect(page.locator('[data-target="ticket-reply-subject"]')).toHaveValue(new RegExp(subject));
    await body.fill(`${await body.inputValue()} ${extra}`);
  });

  await test.step('send it and find it in the outbox', async () => {
    await page.locator('[data-target="ticket-send"]').click();
    await expect(page.locator('[data-target="ticket-articles"]')).toContainText(extra);
    await expect.poll(() => queuedReplies(customer.address, extra)).toBe(1);
  });

  errors.assertClean();
});
