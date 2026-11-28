import { expect, Page, test } from '@playwright/test';
import { attachErrorCollector, openModule, signInAsAdmin } from './support';

async function signInAs(page: Page, email: string): Promise<void> {
  await page.goto('/app/login');
  await expect(page.locator('[data-target="login-form"]')).toBeVisible();
  await page.locator('[data-target="login-dev-user"]').fill(email);
  await page.locator('[data-target="login-submit"]').click();
  await expect(page).toHaveURL(/\/app\/home$/);
  await expect(page.locator('[data-target="active-user"]')).toBeVisible();
}

test.describe('Shell parity, banners, /home, and /setup', () => {
  test('environment banner, admin-only worker banner, and permission-gated sidebar', async ({ page }) => {
    const errors = attachErrorCollector(page);

    await test.step('admin sees tutorial env banner, worker banner, and Admin nav', async () => {
      await signInAsAdmin(page);
      await expect(page.locator('[data-target="env-banner-tutorial"]')).toBeVisible();
      await expect(page.locator('[data-target="worker-banner"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-home"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-admin"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-finance"]')).toBeVisible();
    });

    await test.step('sales sees env banner but not worker banner, Admin, or Finance', async () => {
      await page.locator('[data-target="sign-out"]').click();
      await signInAs(page, 'sales@example.com');
      await expect(page.locator('[data-target="env-banner-tutorial"]')).toBeVisible();
      await expect(page.locator('[data-target="worker-banner"]')).toHaveCount(0);
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-home"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-quotations"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-admin"]')).toHaveCount(0);
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-finance"]')).toHaveCount(0);
    });

    await test.step('viewer does not see To-do or Admin', async () => {
      await page.locator('[data-target="sign-out"]').click();
      await signInAs(page, 'viewer@example.com');
      await expect(page.locator('[data-target="worker-banner"]')).toHaveCount(0);
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-products"]')).toBeVisible();
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-todo"]')).toHaveCount(0);
      await expect(page.locator('[data-target="module-nav"] [data-target="nav-admin"]')).toHaveCount(0);
    });

    errors.assertClean();
  });

  test('/home renders role-gated overview cards and links to modules', async ({ page }) => {
    const errors = attachErrorCollector(page);

    await signInAsAdmin(page);
    await expect(page.locator('[data-target="home-page"]')).toBeVisible();
    await expect(page.locator('[data-target="home-card-todo"]')).toBeVisible();
    await expect(page.locator('[data-target="home-card-helpdesk"]')).toBeVisible();
    await expect(page.locator('[data-target="home-card-quotations"]')).toBeVisible();
    await expect(page.locator('[data-target="home-card-purchasing"]')).toBeVisible();

    await page.locator('[data-target="home-see-all-quotations"]').click();
    await expect(page).toHaveURL(/\/app\/quotations$/);
    await expect(page.locator('[data-target="quotations-page"]')).toBeVisible();

    await openModule(page, 'nav-home', /\/app\/home$/);
    await expect(page.locator('[data-target="home-page"]')).toBeVisible();

    await page.locator('[data-target="sign-out"]').click();
    await signInAs(page, 'viewer@example.com');
    await expect(page.locator('[data-target="home-card-todo"]')).toHaveCount(0);
    await expect(page.locator('[data-target="home-card-quotations"]')).toBeVisible();

    errors.assertClean();
  });

  test('/setup reports already-configured server and completes wizard when mocked', async ({ page }) => {
    const errors = attachErrorCollector(page);

    await test.step('seeded server reports setup already complete', async () => {
      await page.goto('/app/setup');
      await expect(page.locator('[data-target="setup-already-done"]')).toBeVisible();
      await page.locator('[data-target="setup-go-login"]').click();
      await expect(page).toHaveURL(/\/app\/login$/);
    });

    await test.step('step through bootstrap wizard with mocked setup endpoints', async () => {
      await page.route('**/api/v1/setup/status', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            needs_setup: true,
            token_required: true,
            auth_mode: 'oidc',
          }),
        });
      });
      await page.route('**/api/v1/setup/bootstrap', async (route) => {
        const body = route.request().postDataJSON();
        expect(body).toMatchObject({
          name: 'Mocked BV',
          country_code: 'BE',
          currency: 'EUR',
          default_language: 'en',
          admin_email: 'ada@mocked.test',
          admin_display_name: 'Ada Admin',
          token: 'boot-secret',
        });
        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            company: {
              id: '01900000-0000-7000-8000-000000000020',
              name: 'Mocked BV',
              vat_number: null,
              street: '',
              postal_code: '',
              city: '',
              country_code: 'BE',
              currency: 'EUR',
              email: null,
              phone: null,
              iban: null,
              default_language: 'en',
              languages: ['en'],
              is_primary: true,
              quotation_single_line_items: true,
              autosave_minutes: 5,
            },
            admin: {
              user_id: '01900000-0000-7000-8000-000000000010',
              email: 'ada@mocked.test',
              display_name: 'Ada Admin',
              roles: ['admin'],
            },
            auth_mode: 'oidc',
          }),
        });
      });

      await page.goto('/app/setup');
      await expect(page.locator('[data-target="setup-steps"]')).toBeVisible();

      await page.locator('[data-target="setup-next"]').click();
      await expect(page.locator('[data-target="setup-error"]')).toBeVisible();

      await page.locator('[data-target="setup-name"]').fill('Mocked BV');
      await page.locator('[data-target="setup-next"]').click();

      await expect(page.locator('[data-target="setup-country"]')).toHaveValue('BE');
      await page.locator('[data-target="setup-next"]').click();

      await page.locator('[data-target="setup-admin-email"]').fill('ada@mocked.test');
      await page.locator('[data-target="setup-admin-name"]').fill('Ada Admin');
      await page.locator('[data-target="setup-next"]').click();

      await page.locator('[data-target="setup-token"]').fill('boot-secret');
      await page.locator('[data-target="setup-next"]').click();

      await expect(page.locator('[data-target="setup-review"]')).toContainText('Mocked BV');
      await page.locator('[data-target="setup-submit"]').click();
      await expect(page.locator('[data-target="setup-complete"]')).toContainText('Mocked BV');
    });

    errors.assertClean();
  });
});
