import { expect, Page, test } from '@playwright/test';
import { attachErrorCollector, openModule, signInAsAdmin } from './support';

// A page that is left while its list request is still running must not crash the app: the late response
// arrives after the page's reactive state is gone. (Sign-in lands on Home, so leaving Home and Products
// while their initial requests are in flight are covered alongside the other modules.)
//
// The tests do not guess how long the server needs: the request is held at the browser until the page has
// been left, then released, and the test waits for the response to be delivered and for the app to have run
// its callbacks before it looks for page errors.

/** Holds every request matching `pattern` until `release()`; `settle()` lets them through and waits. */
async function holdRequests(page: Page, pattern: string) {
  let open!: () => void;
  const opened = new Promise<void>((resolve) => (open = resolve));
  const inflight: Promise<void>[] = [];
  let held = 0;

  await page.route(pattern, (route) => {
    held += 1;
    inflight.push(
      (async () => {
        await opened;
        // fetch + fulfill: resolves once the response has been handed to the page.
        const response = await route.fetch();
        await route.fulfill({ response });
      })(),
    );
  });

  return {
    /** The number of requests that arrived and are being held. */
    count: () => held,
    /** Releases the held requests, waits until each response reached the page, then lets the app run. */
    settle: async () => {
      open();
      await Promise.all(inflight);
      // Two frames: the app's `spawn_local` callbacks for the responses have run by then.
      await page.evaluate(
        () => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))),
      );
    },
  };
}

const slowPages = [
  { name: 'Customers', nav: 'nav-customers', url: /\/app\/customers$/, api: '**/api/v1/customers*' },
  { name: 'Helpdesk', nav: 'nav-helpdesk', url: /\/app\/helpdesk$/, api: '**/api/v1/tickets*' },
  { name: 'Standard answers', nav: 'nav-answers', url: /\/app\/helpdesk\/answers$/, api: '**/api/v1/prepared-answers*' },
  { name: 'To-do', nav: 'nav-todo', url: /\/app\/todo$/, api: '**/api/v1/todo/items*' },
  { name: 'Knowledge Base', nav: 'nav-kb', url: /\/app\/kb$/, api: '**/api/v1/kb/entries*' },
  { name: 'Administration', nav: 'nav-admin', url: /\/app\/admin$/, api: '**/api/v1/admin/users*' },
];

for (const slow of slowPages) {
  test(`leaving ${slow.name} while its request is slow`, async ({ page }) => {
    const errors = attachErrorCollector(page);
    await signInAsAdmin(page);
    const held = await holdRequests(page, slow.api);
    await openModule(page, slow.nav, slow.url);
    // The request is on its way and held; leave the page, then let the response arrive.
    await expect.poll(held.count).toBeGreaterThan(0);
    await openModule(page, 'nav-quotations', /\/app\/quotations$/);
    await held.settle();
    errors.assertClean();
  });
}

test('leaving Home while its overview requests are slow', async ({ page }) => {
  const errors = attachErrorCollector(page);
  const held = await holdRequests(page, '**/api/v1/quotations*');
  await signInAsAdmin(page);
  await expect.poll(held.count).toBeGreaterThan(0);
  await openModule(page, 'nav-todo', /\/app\/todo$/);
  await held.settle();
  errors.assertClean();
});

test('leaving Products while its first request is slow', async ({ page }) => {
  const errors = attachErrorCollector(page);
  await signInAsAdmin(page);
  const held = await holdRequests(page, '**/api/v1/products*');
  await openModule(page, 'nav-products', /\/app\/products$/);
  await expect.poll(held.count).toBeGreaterThan(0);
  await openModule(page, 'nav-todo', /\/app\/todo$/);
  await held.settle();
  errors.assertClean();
});
