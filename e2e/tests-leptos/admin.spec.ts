import { expect, Page, test } from '@playwright/test';
import { api, asAdmin, attachErrorCollector, openModule, signInAsAdmin, unique } from './support';

// Administration in the Leptos web UI, against the real API and the dev seed: users (create and edit),
// VAT rates, a company module switch, a CSV import (dry run with per-row errors, saved mapping, clean
// check, apply) and the audit trail filter. The tests share one database, so they run in order and
// each restores what it changes that others could notice (the module switch).

test.describe.configure({ mode: 'serial' });

const tag = Date.now().toString(36);
const mappingName = `E2E mapping ${tag}`;

async function openSection(page: Page, key: string): Promise<void> {
  await openModule(page, 'nav-admin', /\/app\/admin$/);
  await page.locator(`[data-target="admin-section-${key}"]`).click();
  await expect(page).toHaveURL(new RegExp(`/app/admin/${key}$`));
}

test('Admin users: create a user, then edit roles, modules and status', async ({ page, request }) => {
  const errors = attachErrorCollector(page);
  const email = `e2e.${tag}@example.test`;
  const name = unique('Erik Example');
  const renamed = `${name} (moved)`;
  const row = () => page.locator('[data-target^="admin-user-row-"]').filter({ hasText: email });

  await signInAsAdmin(page);

  await test.step('the admin page opens on Users and marks the navigation', async () => {
    await openModule(page, 'nav-admin', /\/app\/admin$/);
    await expect(page.locator('[data-target="admin-users"]')).toBeVisible();
    await expect(page.locator('[data-target="nav-admin"]')).toHaveClass(/active/);
    await page.locator('[data-target="admin-section-users"]').click();
    await expect(page).toHaveURL(/\/app\/admin\/users$/);
    await expect(page.locator('[data-target="nav-admin"]')).toHaveClass(/active/);
  });

  await test.step('create a user with one role and a module switched off', async () => {
    await page.locator('[data-target="admin-users-new"]').click();
    const save = page.locator('[data-target="admin-user-save"]');
    await expect(save).toBeDisabled();
    await page.getByLabel('E-mail').fill(email);
    await page.getByLabel('Name', { exact: true }).fill(name);
    await page.locator('[data-target="admin-user-role-sales"]').check();
    await page.locator('[data-target="admin-user-module-kb"]').uncheck();
    await expect(save).toBeEnabled();
    await save.click();
    await expect(page.locator('[data-target="admin-users-notice"]')).toHaveText('User added');
    await expect(row()).toContainText('Sales');
    await expect(row()).toContainText('Knowledge base');
    await expect(row()).toContainText('Not signed in yet');
  });

  await test.step('edit the name, add a role and deactivate', async () => {
    await page.locator('[data-target="admin-users-search"]').fill(email);
    await row().getByRole('button', { name: `Edit ${name}` }).click();
    await expect(page.locator('[data-target="admin-user-email-text"]')).toHaveText(email);
    await page.getByLabel('Name', { exact: true }).fill(renamed);
    await page.locator('[data-target="admin-user-role-support"]').check();
    await page.locator('[data-target="admin-user-active"]').uncheck();
    await page.locator('[data-target="admin-user-save"]').click();
    await expect(page.locator('[data-target="admin-users-notice"]')).toHaveText('Saved');
    await expect(row()).toContainText(renamed);
    await expect(row()).toContainText('inactive');
    await page.locator('[data-target="admin-users-filter"]').selectOption('active');
    await expect(row()).toHaveCount(0);
    await page.locator('[data-target="admin-users-filter"]').selectOption('inactive');
    await expect(row()).toHaveCount(1);
  });

  await test.step('the API has the changes', async () => {
    const res = await request.get(`${api}/admin/users`, { headers: asAdmin });
    expect(res.ok()).toBeTruthy();
    const user = (await res.json()).find((u: { email: string }) => u.email === email);
    expect(user).toMatchObject({
      display_name: renamed,
      roles: ['sales', 'support'],
      disabled_modules: ['kb'],
      active: false,
    });
  });

  errors.assertClean();
});

test('Admin VAT rates: add, edit and delete a rule', async ({ page }) => {
  const errors = attachErrorCollector(page);
  const notes = unique('E2E rule');
  const item = () => page.locator('[data-target^="admin-vat-rate-"]').filter({ hasText: notes });

  await signInAsAdmin(page);
  await openSection(page, 'vat');

  await test.step('validation is shown before anything is sent', async () => {
    await page.locator('[data-target="admin-vat-add"]').click();
    await page.locator('[data-target="admin-vat-country"]').fill('L');
    await page.locator('[data-target="admin-vat-save"]').click();
    await expect(page.locator('[data-target="admin-vat-editor-error"]')).toContainText('two letters');
  });

  await test.step('add an intermediate rate for Iceland', async () => {
    await page.locator('[data-target="admin-vat-country"]').fill('is');
    await page.locator('[data-target="admin-vat-category"]').selectOption('intermediate');
    await page.locator('[data-target="admin-vat-rate"]').fill('8');
    await page.locator('[data-target="admin-vat-start"]').fill('2031-01-01');
    await page.locator('[data-target="admin-vat-close-previous"]').uncheck();
    await page.locator('[data-target="admin-vat-notes"]').fill(notes);
    await page.locator('[data-target="admin-vat-save"]').click();
    await expect(page.locator('[data-target="admin-vat-notice"]')).toHaveText('Saved');
    await page.locator('[data-target="admin-vat-filter"]').selectOption('IS');
    await expect(item()).toContainText('IS · Intermediate · 8 %');
    await expect(item()).toContainText('2031-01-01 – Ongoing');
  });

  await test.step('edit the rate', async () => {
    await item().getByRole('button', { name: /^Edit / }).click();
    await page.locator('[data-target="admin-vat-rate"]').fill('7.5');
    await page.locator('[data-target="admin-vat-end"]').fill('2031-12-31');
    await page.locator('[data-target="admin-vat-save"]').click();
    await expect(item()).toContainText('IS · Intermediate · 7.5 %');
    await expect(item()).toContainText('2031-01-01 – 2031-12-31');
  });

  await test.step('delete it after confirmation', async () => {
    await item().getByRole('button', { name: /^Delete / }).click();
    await item().locator('[data-target^="admin-vat-delete-confirm-"]').click();
    await expect(item()).toHaveCount(0);
  });

  errors.assertClean();
});

test('Admin modules: switch a module off for the company and back on', async ({ page, request }) => {
  const errors = attachErrorCollector(page);
  const modules = async () =>
    (await (await request.get(`${api}/admin/modules`, { headers: asAdmin })).json()) as {
      code: string;
      requires: string[];
      enabled: boolean;
    }[];
  // A module nothing else needs, so switching it off moves nothing else along.
  const all = await modules();
  const leaf = all.find((m) => m.enabled && !all.some((o) => o.requires.includes(m.code)))!;
  expect(leaf).toBeTruthy();
  const enabled = async () => (await modules()).find((m) => m.code === leaf.code)!.enabled;
  const toggle = page.locator(`[data-target="admin-module-${leaf.code}"]`);
  const state = page.locator(`[data-target="admin-module-state-${leaf.code}"]`);
  const save = page.locator('[data-target="admin-modules-save"]');

  await signInAsAdmin(page);
  await openSection(page, 'modules');

  await test.step('switch it off and save', async () => {
    await expect(save).toBeDisabled();
    await toggle.uncheck();
    await expect(state).toHaveText('Off');
    await save.click();
    await expect(page.locator('[data-target="admin-modules-notice"]')).toHaveText('Modules saved');
    await expect.poll(enabled).toBe(false);
  });

  await test.step('switch it on again', async () => {
    await toggle.check();
    await expect(state).toHaveText('On');
    await save.click();
    await expect.poll(enabled).toBe(true);
    await expect(save).toBeDisabled();
  });

  errors.assertClean();
});

test('Admin import: dry run with row errors, map columns, save the mapping, check and apply', async ({
  page,
  request,
}) => {
  const errors = attachErrorCollector(page);
  const zones = await (await request.get(`${api}/price-zones`, { headers: asAdmin })).json();
  const zone: string = zones[0].code;
  const code1 = `E2E-${tag}-1`.toUpperCase();
  const code2 = `E2E-${tag}-2`.toUpperCase();
  // Column names that differ from the fields, so the columns must be mapped.
  const csv = (secondName: string) =>
    Buffer.from(
      `Klantnr;Naam;Prijszone;Stad\n${code1};Import Een ${tag};${zone};Gent\n${code2};${secondName};${zone};Brugge\n`,
      'utf8',
    );
  const steps = (n: number) => page.locator(`[data-target="admin-import-step-${n}"]`);

  await signInAsAdmin(page);
  await openSection(page, 'import');

  await test.step('upload a file and choose the entity', async () => {
    await page.locator('[data-target="admin-import-file"]').setInputFiles({
      name: 'customers-e2e.csv',
      mimeType: 'text/csv',
      buffer: csv(''),
    });
    await expect(page.locator('[data-target="admin-import-file-info"]')).toContainText('customers-e2e.csv');
    await page.locator('[data-target="admin-import-entity"]').selectOption('customers');
    await expect(page.locator('[data-target="admin-import-row-count"]')).toContainText('2 data rows');
    await expect(page.locator('[data-target="admin-import-preview"]')).toContainText(code2);
  });

  await test.step('map the columns: the key column is required', async () => {
    await expect(page.locator('[data-target="admin-import-key-missing"]')).toBeVisible();
    // The check step opens only once the mapping can be sent.
    await expect(page.locator('[data-target="admin-import-run-check"]')).toHaveCount(0);
    await page.locator('[data-target="admin-import-field-0"]').selectOption('code');
    await page.locator('[data-target="admin-import-field-1"]').selectOption('name');
    await page.locator('[data-target="admin-import-field-2"]').selectOption('price_zone_code');
    await page.locator('[data-target="admin-import-field-3"]').selectOption('city');
    await expect(page.locator('[data-target="admin-import-key-missing"]')).toHaveCount(0);
  });

  await test.step('save the mapping', async () => {
    await page.locator('[data-target="admin-import-save-mapping"]').click();
    await page.locator('[data-target="admin-import-mapping-name"]').fill(mappingName);
    await page.locator('[data-target="admin-import-mapping-name-ok"]').click();
    await expect(page.locator('[data-target="admin-import-notice"]')).toHaveText(`Mapping ${mappingName} saved`);
  });

  await test.step('the dry run reports the row without a name', async () => {
    await page.locator('[data-target="admin-import-run-check"]').click();
    const errorsBox = page.locator('[data-target="admin-import-check-errors"]');
    await expect(errorsBox).toContainText('1 problem found');
    await expect(errorsBox.locator('[data-target="admin-import-check-error-row"]')).toContainText('Row 3');
    await expect(page.locator('[data-target="admin-import-apply"]')).toBeDisabled();
  });

  await test.step('a corrected file takes the saved mapping and checks clean', async () => {
    await page.locator('[data-target="admin-import-file"]').setInputFiles({
      name: 'customers-e2e-fixed.csv',
      mimeType: 'text/csv',
      buffer: csv(`Import Twee ${tag}`),
    });
    await expect(page.locator('[data-target="admin-import-proposal"]')).toHaveText(
      `Columns taken from the saved mapping ${mappingName}.`,
    );
    await page.locator('[data-target="admin-import-run-check"]').click();
    await expect(page.locator('[data-target="admin-import-check-done"]')).toContainText('No problems found');
    await expect(page.locator('[data-target="admin-import-check-count-created"]')).toHaveText('2');
    await expect(steps(4)).toContainText('Done');
  });

  await test.step('apply after confirmation', async () => {
    await page.locator('[data-target="admin-import-apply"]').click();
    await expect(page.locator('[data-target="admin-import-apply-confirm-box"]')).toContainText(
      '2 will be created and 0 updated',
    );
    await page.locator('[data-target="admin-import-apply-confirm"]').click();
    await expect(page.locator('[data-target="admin-import-apply-done"]')).toHaveText('Import complete');
    await expect(page.locator('[data-target="admin-import-apply-count-created"]')).toHaveText('2');
    const res = await request.get(`${api}/customers?q=${encodeURIComponent(code2)}`, { headers: asAdmin });
    const found = (await res.json()).items.map((c: { code: string; name: string }) => [c.code, c.name]);
    expect(found).toContainEqual([code2, `Import Twee ${tag}`]);
  });

  await test.step('the history lists the runs', async () => {
    await page.locator('[data-target="admin-import-view-history"]').click();
    const job = page.locator('[data-target^="admin-import-job-"]').filter({ hasText: 'customers-e2e-fixed.csv' });
    await expect(job.filter({ hasText: 'Imported' })).toContainText('2 created, 0 updated, 0 unchanged');
    await expect(job.filter({ hasText: 'Check only' })).toContainText('2 to create');
  });

  errors.assertClean();
});

test('Admin audit trail: filter by record type and action', async ({ page }) => {
  const errors = attachErrorCollector(page);
  const events = page.locator('[data-target^="admin-audit-event-"]');

  await signInAsAdmin(page);
  await openSection(page, 'audit');
  await expect(events.first()).toBeVisible();

  await test.step('record type and action narrow the list', async () => {
    await page.locator('[data-target="admin-audit-entity"]').selectOption('import_mapping');
    await page.locator('[data-target="admin-audit-action"]').fill('created');
    await page.locator('[data-target="admin-audit-apply"]').click();
    const mine = events.filter({ hasText: mappingName });
    await expect(mine).toHaveCount(1);
    await expect(mine.locator('[data-target="admin-audit-event-action"]')).toHaveText('created');
    for (const entity of await events.locator('[data-target="admin-audit-event-entity"]').allTextContents()) {
      expect(entity).toContain('import_mapping');
    }
  });

  await test.step('a period without events shows nothing', async () => {
    await page.locator('[data-target="admin-audit-to"]').fill('2020-01-01');
    await expect(page.locator('[data-target="admin-audit-empty"]')).toBeVisible();
    await page.locator('[data-target="admin-audit-clear-dates"]').click();
    await expect(events.filter({ hasText: mappingName })).toHaveCount(1);
  });

  errors.assertClean();
});
