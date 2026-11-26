import { expect, test } from '@playwright/test';
import { attachErrorCollector, openModule, reloadAndReturn, signInAsAdmin, unique } from './support';

// Gate: a staff user can open To-do from the navigation, create a task and a sub-item, edit the task and
// its due date, complete and reopen it, and filter the list by Open, Done or All. Changes survive a reload.

test('To-do: create, sub-item, edit, complete, reopen, filter and reload', async ({ page }) => {
  const errors = attachErrorCollector(page);
  const title = unique('Plan review');
  const renamed = `${title} (moved)`;
  const subTitle = unique('Prepare slides');
  const item = (text: string) =>
    page.locator('[data-target^="todo-item-"]').filter({ hasText: text });

  await signInAsAdmin(page);

  await test.step('To-do opens from the navigation', async () => {
    await openModule(page, 'nav-todo', /\/app\/todo$/);
    await expect(page.locator('[data-target="todo-page"]')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'To-do', exact: true })).toBeVisible();
  });

  await test.step('create a task with a due date', async () => {
    await page.locator('[data-target="todo-add-title"]').fill(title);
    await page.locator('[data-target="todo-add-due"]').fill('2027-01-15');
    await page.locator('[data-target="todo-add-submit"]').click();
    await expect(item(title)).toBeVisible();
    await expect(item(title)).toContainText('2027-01-15');
    // The form is emptied once the task is saved.
    await expect(page.locator('[data-target="todo-add-title"]')).toHaveValue('');
  });

  await test.step('add a sub-item', async () => {
    await item(title).getByRole('button', { name: '+ Sub-item' }).click();
    await page.locator('[data-target^="todo-child-title-"]').fill(subTitle);
    await page.locator('[data-target^="todo-child-submit-"]').click();
    await expect(item(subTitle)).toBeVisible();
  });

  await test.step('changes survive a reload', async () => {
    await reloadAndReturn(page, 'nav-todo', /\/app\/todo$/);
    await expect(item(title)).toBeVisible();
    await expect(item(subTitle)).toBeVisible();
  });

  await test.step('edit the task and its due date', async () => {
    await item(title).getByRole('button', { name: 'Edit', exact: true }).click();
    await page.locator('[data-target^="todo-edit-title-"]').fill(renamed);
    await page.locator('[data-target^="todo-edit-due-"]').fill('2027-02-20');
    await page.locator('[data-target^="todo-edit-save-"]').click();
    await expect(item(renamed)).toBeVisible();
    await expect(item(renamed)).toContainText('2027-02-20');
    await expect(item(title).filter({ hasNotText: '(moved)' })).toHaveCount(0);
  });

  await test.step('completing a task with an open sub-item asks first', async () => {
    await item(renamed).locator('input[type="checkbox"]').click();
    await expect(page.locator('[data-target^="todo-confirm-"]')).toBeVisible();
    // The box is put back while the question is open.
    await expect(item(renamed).locator('input[type="checkbox"]')).not.toBeChecked();
    await page.locator('[data-target^="todo-complete-all-"]').click();
    // Open filter: the finished task and its sub-item are gone.
    await expect(item(renamed)).toHaveCount(0);
    await expect(item(subTitle)).toHaveCount(0);
  });

  await test.step('Done and All filters show it, Open does not', async () => {
    await page.locator('[data-target="todo-filter-done"]').click();
    await expect(item(renamed)).toBeVisible();
    await expect(item(subTitle)).toBeVisible();
    await page.locator('[data-target="todo-filter-all"]').click();
    await expect(item(renamed)).toBeVisible();
    await page.locator('[data-target="todo-filter-open"]').click();
    await expect(item(renamed)).toHaveCount(0);
  });

  await test.step('reopen a finished task, and it survives a reload', async () => {
    await page.locator('[data-target="todo-filter-done"]').click();
    await item(renamed).locator('input[type="checkbox"]').click();
    await expect(item(renamed)).toHaveCount(0);
    await reloadAndReturn(page, 'nav-todo', /\/app\/todo$/);
    await expect(item(renamed)).toBeVisible();
    await page.locator('[data-target="todo-filter-done"]').click();
    await expect(item(renamed)).toHaveCount(0);
  });

  errors.assertClean();
});
