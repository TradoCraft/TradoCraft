import { test } from '@playwright/test';
import { attachErrorCollector, openModule, signInAsAdmin } from './support';

// A page that is left while its list request is still running must not crash the app: the late response
// arrives after the page's reactive state is gone. (Sign-in lands on Products, so every other spec leaves it
// at once; on a cold server that request is the slowest.)

const slowPages = [
  { name: 'Customers', nav: 'nav-customers', url: /\/app\/customers$/, api: '**/api/v1/customers*' },
  { name: 'Helpdesk', nav: 'nav-helpdesk', url: /\/app\/helpdesk$/, api: '**/api/v1/tickets*' },
  { name: 'Standard answers', nav: 'nav-answers', url: /\/app\/helpdesk\/answers$/, api: '**/api/v1/prepared-answers*' },
  { name: 'To-do', nav: 'nav-todo', url: /\/app\/todo$/, api: '**/api/v1/todo/items*' },
  { name: 'Knowledge Base', nav: 'nav-kb', url: /\/app\/kb$/, api: '**/api/v1/kb/entries*' },
];

for (const slow of slowPages) {
  test(`leaving ${slow.name} while its request is slow`, async ({ page }) => {
    const errors = attachErrorCollector(page);
    await signInAsAdmin(page);
    await page.route(slow.api, async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      await route.continue();
    });
    await openModule(page, slow.nav, slow.url);
    // Leave at once, then give the delayed response time to arrive.
    await openModule(page, 'nav-quotations', /\/app\/quotations$/);
    await page.waitForTimeout(2200);
    errors.assertClean();
  });
}

test('leaving Products while its first request is slow', async ({ page }) => {
  const errors = attachErrorCollector(page);
  await page.route('**/api/v1/products*', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1500));
    await route.continue();
  });
  await signInAsAdmin(page);
  await openModule(page, 'nav-todo', /\/app\/todo$/);
  await page.waitForTimeout(2200);
  errors.assertClean();
});
