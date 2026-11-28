import { expect, test } from '@playwright/test';
import { api, asAdmin, attachErrorCollector, openModule, signInAsAdmin, unique } from './support';

test.describe('Workspace tabs, deep links, chatter, global search, and linked to-dos', () => {
  test('global search, real workspace tabs, chatter persistence, inbox, and linked to-dos', async ({
    page,
    request,
  }) => {
    const errors = attachErrorCollector(page);

    // Discover a seeded customer from the API so the test never hardcodes UUIDs.
    const custRes = await request.get(`${api}/customers?limit=5`, { headers: asAdmin });
    expect(custRes.ok(), await custRes.text()).toBeTruthy();
    const custPage = (await custRes.json()) as {
      items: Array<{ id: string; code: string; name: string }>;
    };
    expect(custPage.items.length).toBeGreaterThan(0);
    const customer = custPage.items[0];

    await test.step('Deep link while signed out prompts to sign in', async () => {
      await page.goto(`/app/customers/${customer.id}`);
      await expect(page.locator('[data-target="record-detail-go-login"]')).toBeVisible();
    });

    await test.step('Sign in and open the customer via Global Search (Ctrl+K)', async () => {
      await signInAsAdmin(page);
      await page.keyboard.press('Control+k');
      await expect(page.locator('[data-target="global-search"]')).toBeVisible();
      await page.locator('[data-target="global-search-input"]').fill(customer.code);
      const hit = page
        .locator('[data-target="global-search-group-customers"] [data-target^="global-search-hit-"]')
        .filter({ hasText: customer.name })
        .first();
      await expect(hit).toBeVisible();
      await hit.click();

      await expect(page).toHaveURL(
        new RegExp(`^https?://[^/]+/app/customers/${customer.id}$`),
      );
      await expect(page.locator('[data-target="record-detail-customer"]')).toBeVisible();
      await expect(page.locator('[data-target="record-detail-title"]')).toContainText(customer.name);
      await expect(page.locator('[data-target="workspace-tab-placeholder"]')).toHaveCount(0);
      await expect(
        page.locator(`[data-target="workspace-tab-customer:${customer.id}"]`),
      ).toBeVisible();
    });

    const noteText = unique('Chatter verification note');
    const activitySummary = unique('Follow up call');

    await test.step('Post chatter note, toggle follow, schedule & complete activity', async () => {
      await expect(page.locator('[data-target="chatter-panel"]')).toBeVisible();
      await expect(page.locator('[data-target="chatter-follow-toggle"]')).toBeVisible();
      const followBefore = await page
        .locator('[data-target="chatter-follow-toggle"]')
        .textContent();
      await page.locator('[data-target="chatter-follow-toggle"]').click();
      await expect(page.locator('[data-target="chatter-follow-toggle"]')).not.toHaveText(
        followBefore ?? '',
      );

      await page.locator('[data-target="chatter-note-input"]').fill(noteText);
      await page.locator('[data-target="chatter-post-note"]').click();
      await expect(page.locator('[data-target="chatter-thread"]')).toContainText(noteText);

      await page.locator('[data-target="chatter-activity-toggle"]').click();
      await page.locator('[data-target="chatter-activity-summary"]').fill(activitySummary);
      await page.locator('[data-target="chatter-activity-submit"]').click();
      await expect(page.locator('[data-target="chatter-activities"]')).toContainText(
        activitySummary,
      );

      // Verify Inbox drawer opens cleanly and shows activities/button works.
      await page.locator('[data-target="inbox-toggle"]').click();
      await expect(page.locator('[data-target="inbox-drawer"]')).toBeVisible();
      await page.locator('[data-target="inbox-drawer-close"]').click();

      // Complete the scheduled activity.
      const actRow = page
        .locator('[data-target="chatter-activities"] li')
        .filter({ hasText: activitySummary })
        .first();
      await actRow.locator('[data-target="chatter-activity-done"]').click();
      await expect(page.locator('[data-target="chatter-activities"]')).not.toContainText(
        activitySummary,
      );
    });

    const linkedTodo = unique('Call purchasing team');

    await test.step('Create and complete a linked to-do via ObjectTodosButton + verify sidebar badge', async () => {
      await page.locator('[data-target="object-todos-button"]').click();
      await expect(page.locator('[data-target="object-todos-modal"]')).toBeVisible();
      await page.locator('[data-target="object-todos-add-input"]').fill(linkedTodo);
      await page.locator('[data-target="object-todos-add-submit"]').click();

      await expect(page.locator('[data-target="object-todos-list"]')).toContainText(linkedTodo);
      await expect(page.locator('[data-target="todo-nav-badge"]')).toBeVisible();
      await page.locator('[data-target="object-todos-modal-close"]').click();
      await expect(page.locator('[data-target="object-todos-badge"]')).toBeVisible();

      // Clean up the linked to-do via /app/todo (also confirming link badge appears).
      await openModule(page, 'nav-todo', /\/app\/todo$/);
      const todoRow = page.locator('[data-target^="todo-item-"]').filter({ hasText: linkedTodo });
      await expect(todoRow).toBeVisible();
      await expect(todoRow.locator('[data-target^="todo-link-"]')).toContainText(customer.name);
      await todoRow.locator('input[type="checkbox"]').click();
      await expect(todoRow).toHaveCount(0);
    });

    await test.step('Open tab from Customer drawer mounts real detail view', async () => {
      await openModule(page, 'nav-customers', /\/app\/customers$/);
      await page.locator('[data-target^="customer-row-"]').first().click();
      await expect(page.locator('[data-target="open-workspace-tab"]')).toBeVisible();
      await page.locator('[data-target="open-workspace-tab"]').click();

      await expect(page.locator('[data-target="workspace-tab-view"]')).toBeVisible();
      await expect(page.locator('[data-target="record-detail-customer"]')).toBeVisible();
      await expect(page.locator('[data-target="chatter-thread"]')).toContainText(noteText);
      await expect(page.locator('[data-target="workspace-tab-placeholder"]')).toHaveCount(0);

      // Switching back to Overview restores the underlying list view.
      await page.locator('[data-target="workspace-tab-overview"]').click();
      await expect(page.locator('[data-target="customers-page"]')).toBeVisible();
    });

    errors.assertClean();
  });
});
