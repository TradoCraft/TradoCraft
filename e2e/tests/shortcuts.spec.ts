import { expect, test } from '@playwright/test';
import { boot } from './flutter';

// Keyboard shortcuts in the style of common business-app shortcuts (ADR 0060). On the web the menu digits are
// Alt+Shift+digit, because browsers keep Alt+digit. This checks the browser does not eat the chord and the app
// navigates. Run it in Firefox as well with a local config that sets `browserName: 'firefox'`.
test('Alt+Shift+digit and Alt+H move through the menu', async ({ page }) => {
  await boot(page);
  const tab = (name: string) => page.getByRole('tab', { name, exact: true });
  // The administrator's menu starts with Opportunities, then Quotations (permission-filtered, in menu order).
  await expect(tab('Opportunities')).toBeVisible();

  await page.keyboard.press('Alt+Shift+2');
  await expect(tab('Quotations')).toHaveAttribute('aria-selected', 'true');

  await page.keyboard.press('Alt+Shift+1');
  await expect(tab('Opportunities')).toHaveAttribute('aria-selected', 'true');

  await page.keyboard.press('Alt+Shift+2');
  await expect(tab('Quotations')).toHaveAttribute('aria-selected', 'true');
  // Home is the first entry again.
  await page.keyboard.press('Alt+H');
  await expect(tab('Opportunities')).toHaveAttribute('aria-selected', 'true');

  // The plain Alt+digit is the browser's (Firefox on Linux switches browser tabs): the app ignores it.
  await page.keyboard.press('Alt+2');
  await expect(tab('Opportunities')).toHaveAttribute('aria-selected', 'true');
});
