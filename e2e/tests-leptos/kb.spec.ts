import { expect, Page, test } from '@playwright/test';
import { attachErrorCollector, openModule, signInAsAdmin, unique } from './support';

// Gate: staff search and read articles by category and language. Users with edit permission create, edit and
// publish an article with the intended visibility. A public article is discoverable in the public reader;
// drafts and staff-only articles stay out of public results.

test('Knowledge Base: create, edit and publish articles; only public ones reach the public reader', async ({
  page,
}) => {
  const errors = attachErrorCollector(page);
  const token = unique('kbgate').replace(/\s+/g, '');
  const pub = `Reset the pump ${token}`;
  const staffOnly = `Internal pump tuning ${token}`;
  const draft = `Pump warranty terms ${token}`;
  const draftRenamed = `${draft} (updated)`;

  const staffRow = (title: string) =>
    page.locator('[data-target^="kb-staff-row-"]').filter({ hasText: title });
  const publicRows = () => page.locator('[data-target^="kb-article-row-"]');

  /** Writes an article in the staff editor; `publish` saves and publishes in one go. */
  async function writeArticle(p: Page, title: string, body: string, visibility: string, publish: boolean) {
    await p.locator('[data-target="kb-staff-new"]').click();
    await expect(p.locator('[data-target="kb-staff-editor"]')).toBeVisible();
    await p.locator('[data-target="kb-staff-editor-title-en"]').fill(title);
    await p.locator('[data-target="kb-staff-editor-body-en"]').fill(body);
    await p.locator('[data-target="kb-staff-editor-visibility"]').selectOption(visibility);
    await p.locator(publish ? '[data-target="kb-staff-editor-publish"]' : '[data-target="kb-staff-editor-save"]').click();
    await expect(p.locator('[data-target="kb-staff-editor"]')).toHaveCount(0);
    await expect(p.locator('[data-target="kb-staff-article-title"]')).toContainText(title);
  }

  await signInAsAdmin(page);
  await openModule(page, 'nav-kb', /\/app\/kb$/);
  await page.locator('[data-target="kb-tab-staff"]').click();
  await expect(page.locator('[data-target="kb-staff-page"]')).toBeVisible();

  await test.step('create a public article and publish it', async () => {
    await writeArticle(page, pub, 'Hold the reset button for five seconds.', 'public', true);
    await expect(page.locator('[data-target="kb-staff-article-status"]')).toHaveText('Published');
    await expect(page.locator('[data-target="kb-staff-article-visibility"]')).toHaveText('Public');
  });

  await test.step('create a staff-only article (published) and a public draft', async () => {
    await writeArticle(page, staffOnly, 'Only for the service team.', 'internal', true);
    await expect(page.locator('[data-target="kb-staff-article-visibility"]')).toHaveText('Staff only');
    await writeArticle(page, draft, 'Warranty runs for two years.', 'public', false);
    await expect(page.locator('[data-target="kb-staff-article-status"]')).toHaveText('Draft');
  });

  await test.step('staff search finds articles of every status', async () => {
    await page.locator('[data-target="kb-staff-search"]').fill(token);
    await expect(staffRow(pub)).toBeVisible();
    await expect(staffRow(staffOnly)).toBeVisible();
    await expect(staffRow(draft)).toBeVisible();
    await page.locator('[data-target="kb-staff-status-filter"]').selectOption('draft');
    await expect(staffRow(draft)).toBeVisible();
    await expect(staffRow(pub)).toHaveCount(0);
    await page.locator('[data-target="kb-staff-status-filter"]').selectOption('');
  });

  await test.step('read an article in another language', async () => {
    await staffRow(pub).click();
    await page.locator('[data-target="kb-staff-edit"]').click();
    await page.locator('[data-target="kb-staff-editor-lang-nl"]').click();
    await page.locator('[data-target="kb-staff-editor-title-nl"]').fill(`Pomp resetten ${token}`);
    await page.locator('[data-target="kb-staff-editor-body-nl"]').fill('Houd de resetknop vijf seconden ingedrukt.');
    await page.locator('[data-target="kb-staff-editor-save"]').click();
    await page.locator('[data-target="kb-staff-article-lang-nl"]').click();
    await expect(page.locator('[data-target="kb-staff-article-body"]')).toContainText('resetknop');
    await page.locator('[data-target="kb-staff-article-lang-en"]').click();
    await expect(page.locator('[data-target="kb-staff-article-body"]')).toContainText('reset button');
  });

  await test.step('public reader shows the public article only', async () => {
    await page.locator('[data-target="kb-tab-public"]').click();
    // The reader opens in the company's default language (Dutch); choose English.
    await page.locator('[data-target="kb-language-filter"]').selectOption('en');
    await page.locator('[data-target="kb-search"]').fill(token);
    await expect(publicRows()).toHaveCount(1);
    await expect(publicRows().first()).toContainText(pub);
    await expect(page.locator('[data-target="kb-article-list"]')).not.toContainText(staffOnly);
    await expect(page.locator('[data-target="kb-article-list"]')).not.toContainText(draft);
  });

  await test.step('edit the draft and publish it: it reaches the public reader', async () => {
    await page.locator('[data-target="kb-tab-staff"]').click();
    await staffRow(draft).click();
    await page.locator('[data-target="kb-staff-edit"]').click();
    await page.locator('[data-target="kb-staff-editor-title-en"]').fill(draftRenamed);
    await page.locator('[data-target="kb-staff-editor-save"]').click();
    await expect(page.locator('[data-target="kb-staff-article-title"]')).toContainText(draftRenamed);
    await page.locator('[data-target="kb-staff-publish"]').click();
    await expect(page.locator('[data-target="kb-staff-article-status"]')).toHaveText('Published');

    // The public API answers are cached for five minutes (Cache-Control: public, max-age=300), so ask
    // with new queries instead of repeating the earlier one.
    await page.locator('[data-target="kb-tab-public"]').click();
    await page.locator('[data-target="kb-search"]').fill(draftRenamed);
    await expect(publicRows()).toHaveCount(1);
    await expect(publicRows().first()).toContainText(draftRenamed);
    await page.locator('[data-target="kb-search"]').fill(staffOnly);
    await expect(page.locator('[data-target="kb-article-list"]')).not.toContainText(staffOnly);
    await expect(publicRows()).toHaveCount(0);
  });

  errors.assertClean();
});
