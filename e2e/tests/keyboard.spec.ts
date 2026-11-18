import { expect, Page, test } from '@playwright/test';
import { boot, field, tree, typeInto } from './flutter';

// Keyboard behaviour that only a real browser shows (ADR 0060). The widget tests cannot see whether the
// browser's own action for a key is cancelled, or how the browser's text input reports Enter and Esc.

type KeyLog = { key: string; prevented: boolean };

/**
 * Records, after the app's own listeners ran, whether each keydown had its default action cancelled.
 * A capture listener on the window, registered after the app's: the engine stops the propagation of
 * some events (Chromium), which a bubble listener never sees.
 */
async function watchKeys(page: Page) {
  await page.evaluate(() => {
    const w = window as unknown as { __keys: KeyLog[] };
    w.__keys = [];
    window.addEventListener('keydown', (e) => w.__keys.push({ key: e.key, prevented: e.defaultPrevented }), true);
  });
}

const lastKeyPrevented = (page: Page) =>
  page.evaluate(() => (window as unknown as { __keys: KeyLog[] }).__keys.at(-1)?.prevented);

/** Waits until the semantics tree shows this text. */
const screenShows = (page: Page, text: string) =>
  expect.poll(async () => (await tree(page)).includes(text), { timeout: 10_000 }).toBe(true);

test('the app takes the keys it handles away from the browser and leaves the others to it', async ({ page }) => {
  await boot(page);
  await watchKeys(page);

  // A list has nothing to save: the browser keeps Ctrl+S.
  await page.keyboard.press('Control+s');
  expect(await lastKeyPrevented(page)).toBe(false);

  await page.getByRole('button', { name: 'New quotation' }).click();
  await expect(page.getByRole('button', { name: 'Save draft' })).toBeVisible();

  // Ctrl+S presses Save draft (the form says what is missing); the browser must not also save the page.
  await page.keyboard.press('Control+s');
  await screenShows(page, 'Choose a customer');
  expect(await lastKeyPrevented(page)).toBe(true);

  // Alt+L goes to the add-product picker; the browser must not open one of its menus.
  await page.keyboard.press('Alt+l');
  await expect(field(page, 'Add product')).toBeFocused();
  expect(await lastKeyPrevented(page)).toBe(true);

  // Ctrl+F goes to the search field of a list instead of the browser's find bar.
  await page.getByRole('tab', { name: 'Quotations', exact: true }).click();
  await screenShows(page, 'Total excl. VAT'); // the list is built: it has a search field to go to
  await page.keyboard.press('Control+f');
  // (Two tabs can each hold a search field: look at the one that has the focus.)
  await expect(page.locator('input:focus')).toHaveAttribute('aria-label', 'Search');
  expect(await lastKeyPrevented(page)).toBe(true);
});

test('Enter goes to the next field, and a dialog opens with the cursor in its first field', async ({ page }) => {
  await boot(page);
  await page.getByRole('tab', { name: 'Customers', exact: true }).click();
  await page.getByRole('button', { name: 'New customer' }).click();

  const code = field(page, 'Code');
  const name = field(page, 'Name');
  await expect(code).toBeFocused();
  await typeInto(code, 'C1');

  // The browser also reports the Enter to the field as "done"; the next field must keep the focus.
  await page.keyboard.press('Enter');
  await expect(name).toBeFocused();
  await page.keyboard.type('Acme', { delay: 25 });
  await expect(name).toHaveValue('Acme');

  await page.keyboard.press('Shift+Enter');
  await expect(code).toBeFocused();
  await expect(code).toHaveValue('C1');

  // Ctrl+Enter confirms the dialog (it asks for what is missing), Esc closes it.
  await page.keyboard.press('Control+Enter');
  await screenShows(page, 'Required');
  await page.keyboard.press('Escape');
  await expect(code).toBeHidden();
});

test('Esc inside a text field asks before leaving an edited form', async ({ page }) => {
  await boot(page);
  await page.getByRole('button', { name: 'New quotation' }).click();
  const notes = field(page, 'Notes');
  // Wait for Flutter's replacement editing element and verify the edit before Escape.
  await typeInto(notes, 'x');
  await expect(notes).toBeFocused();

  // A text field answers the framework's dismiss intent itself; the Esc must still reach the form.
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Discard changes' })).toBeVisible();
  await page.getByRole('button', { name: 'Cancel' }).click();
  await expect(notes).toBeVisible();
});
