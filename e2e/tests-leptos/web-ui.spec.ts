import { test, expect, type Page } from '@playwright/test';

interface ErrorCollector {
  consoleErrors: string[];
  pageErrors: string[];
  assertClean: () => void;
}

function attachErrorCollector(page: Page): ErrorCollector {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];

  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    const url = msg.location()?.url ?? '';
    const text = msg.text();
    if (url.endsWith('/favicon.ico') || text.includes('favicon.ico')) return;
    consoleErrors.push(url ? `${text} (${url})` : text);
  });

  page.on('pageerror', (err) => {
    pageErrors.push(err.message || String(err));
  });

  return {
    consoleErrors,
    pageErrors,
    assertClean: () => {
      expect(pageErrors, `Uncaught page errors: ${pageErrors.join('; ')}`).toEqual([]);
      expect(consoleErrors, `Console errors: ${consoleErrors.join('; ')}`).toEqual([]);
    },
  };
}

async function signInAsAdmin(page: Page): Promise<void> {
  await page.goto('/app/login');
  await expect(page.locator('[data-target="login-form"]')).toBeVisible();

  await page.locator('[data-target="login-dev-user"]').fill('admin@example.com');
  await page.locator('[data-target="login-submit"]').click();

  await expect(page).toHaveURL(/\/app\/products$/);
  await expect(page.locator('[data-target="active-user"]')).toBeVisible();
}

test.describe('Leptos Web UI (/app)', () => {
  test('sign in, inspect master data & workflows, and exercise tutorial overlay', async ({ page }) => {
    const errors = attachErrorCollector(page);

    await test.step('Sign in as admin@example.com redirects to /app/products', async () => {
      await signInAsAdmin(page);
      await expect(page.locator('[data-target="products-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Products', exact: true })).toBeVisible();
    });

    await test.step('Products: verify BELT-M loads, open detail drawer, open + New Product', async () => {
      const beltRow = page.locator('[data-target="product-row-BELT-M"]');
      await expect(beltRow).toBeVisible();
      await beltRow.click();

      const drawer = page.locator('[data-target="product-detail-drawer"]');
      await expect(drawer).toBeVisible();
      await expect(drawer.locator('[data-target="product-form-code"]')).toHaveValue('BELT-M');

      await page.locator('[data-target="products-create"]').click();
      await expect(drawer).toBeVisible();
      await expect(drawer.getByRole('heading', { name: 'New product' })).toBeVisible();
      await expect(drawer.locator('[data-target="product-form-code"]')).toHaveValue('');
    });

    await test.step('Customers: verify C0001 row loads and opens detail drawer', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-customers"]').click();
      await expect(page).toHaveURL(/\/app\/customers$/);
      await expect(page.locator('[data-target="customers-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Customers', exact: true })).toBeVisible();

      const c0001Row = page.locator('[data-target="customer-row-C0001"]');
      await expect(c0001Row).toBeVisible();
      await c0001Row.click();

      const drawer = page.locator('[data-target="customer-detail-drawer"]');
      await expect(drawer).toBeVisible();
      await expect(drawer.locator('[data-target="customer-form"]')).toBeVisible();
    });

    await test.step('Suppliers (/app/purchasing): verify page loads and + New Supplier opens drawer', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-purchasing"]').click();
      await expect(page).toHaveURL(/\/app\/purchasing$/);
      await expect(page.locator('[data-target="suppliers-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Suppliers', exact: true })).toBeVisible();

      await page.locator('[data-target="suppliers-create"]').click();
      await expect(page.locator('[data-target="supplier-detail-drawer"]')).toBeVisible();
    });

    await test.step('Quotations: navigate and verify heading & controls', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-quotations"]').click();
      await expect(page).toHaveURL(/\/app\/quotations$/);
      await expect(page.locator('[data-target="quotations-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Quotations', exact: true })).toBeVisible();
      await expect(page.locator('[data-target="quotations-create"]')).toBeVisible();
      await expect(page.locator('[data-target="quotations-search"]')).toBeVisible();
      await expect(page.locator('[data-target="quotations-status-filter"]')).toBeVisible();
      await expect(page.locator('[data-target="quotations-table"]')).toBeVisible();
    });

    await test.step('Orders: navigate and verify heading & controls', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-orders"]').click();
      await expect(page).toHaveURL(/\/app\/orders$/);
      await expect(page.locator('[data-target="orders-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Orders', exact: true })).toBeVisible();
      await expect(page.locator('[data-target="orders-refresh"]')).toBeVisible();
      await expect(page.locator('[data-target="orders-search"]')).toBeVisible();
      await expect(page.locator('[data-target="orders-status-filter"]')).toBeVisible();
      await expect(page.locator('[data-target="orders-table"]')).toBeVisible();
    });

    await test.step('Helpdesk: navigate and verify heading & controls', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-helpdesk"]').click();
      await expect(page).toHaveURL(/\/app\/helpdesk$/);
      await expect(page.locator('[data-target="helpdesk-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Helpdesk', exact: true })).toBeVisible();
      await expect(page.locator('[data-target="helpdesk-create"]')).toBeVisible();
      await expect(page.locator('[data-target="helpdesk-search"]')).toBeVisible();
      await expect(page.locator('[data-target="helpdesk-status-filter"]')).toBeVisible();
      await expect(page.locator('[data-target="helpdesk-table"]')).toBeVisible();
    });

    await test.step('Knowledge Base: navigate and verify heading & controls', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-kb"]').click();
      await expect(page).toHaveURL(/\/app\/kb$/);
      await expect(page.locator('[data-target="kb-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Knowledge Base', exact: true })).toBeVisible();
      await expect(page.locator('[data-target="kb-refresh"]')).toBeVisible();
      await expect(page.locator('[data-target="kb-search"]')).toBeVisible();
      await expect(page.locator('[data-target="kb-category-filter"]')).toBeVisible();
      await expect(page.locator('[data-target="kb-language-filter"]')).toBeVisible();
    });

    await test.step('Customer Portal: navigate and verify heading & controls', async () => {
      await page.locator('[data-target="module-nav"] [data-target="nav-portal"]').click();
      await expect(page).toHaveURL(/\/app\/portal$/);
      await expect(page.locator('[data-target="portal-page"]')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Customer Portal', exact: true })).toBeVisible();
      await expect(page.locator('[data-target="portal-login-form"]')).toBeVisible();
      await expect(page.locator('[data-target="portal-login-email"]')).toBeVisible();
      await expect(page.locator('[data-target="portal-login-submit"]')).toBeVisible();
      await expect(page.locator('[data-target="portal-session-form"]')).toBeVisible();
    });

    await test.step('Tutorial Overlay: toggle, advance step, and open chapter map', async () => {
      await page.locator('[data-target="tutorial-toggle"]').click();
      const narrator = page.locator('[data-target="tutorial-narrator"]');
      await expect(narrator).toBeVisible();
      await expect(narrator).toContainText('Step 1 /');

      await narrator.locator('[data-target="tutorial-next"]').click();
      await expect(narrator).toContainText('Step 2 /');

      await narrator.locator('[data-target="tutorial-chapter-map"]').click();
      const modal = page.locator('[data-target="tutorial-chapter-map-modal"]');
      await expect(modal).toBeVisible();
      await expect(modal.getByRole('heading', { name: 'Tutorial Chapters' })).toBeVisible();
    });

    errors.assertClean();
  });
});
