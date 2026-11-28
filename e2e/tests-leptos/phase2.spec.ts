import { expect, test } from '@playwright/test';
import { api, asAdmin, attachErrorCollector, openModule, signInAsAdmin, unique } from './support';

test('opportunity stage changes and baseline item types persist', async ({ page, request }) => {
  const errors = attachErrorCollector(page);
  const customers = await request.get(`${api}/customers?limit=1`, { headers: asAdmin });
  expect(customers.ok(), await customers.text()).toBeTruthy();
  const { items: [customer] } = (await customers.json()) as { items: Array<{ id: string }> };
  const title = unique('Pipeline verification');
  const create = await request.post(`${api}/opportunities`, {
    headers: asAdmin,
    data: { title, customer_id: customer.id, expected_value: '1250' },
  });
  expect(create.ok(), await create.text()).toBeTruthy();
  const { id } = (await create.json()) as { id: string };

  await signInAsAdmin(page);
  await openModule(page, 'nav-opportunities', /\/app\/opportunities$/);
  await page.getByRole('link', { name: new RegExp(title) }).click();
  await expect(page).toHaveURL(new RegExp(`/app/opportunities/${id}$`));
  await expect(page.getByRole('heading', { name: new RegExp(title) })).toBeVisible();
  await page.getByRole('button', { name: 'Change stage' }).click();
  const stage = page.getByRole('dialog', { name: 'Change stage' });
  await stage.getByLabel('Stage', { exact: true }).selectOption('qualified');
  await stage.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText(/Qualified · 25%/)).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Site baseline' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Product matches' })).toBeVisible();

  await page.getByRole('link', { name: 'All opportunities' }).click();
  await page.getByRole('button', { name: 'Pipeline' }).click();
  const lane = page.getByRole('region', { name: 'Qualified' });
  await expect(lane.getByRole('link', { name: new RegExp(title) })).toBeVisible();

  await openModule(page, 'nav-admin', /\/app\/admin(?:\/[^/]+)?$/);
  await page.locator('[data-target="admin-section-baseline"]').click();
  const code = `test_${Date.now()}`;
  await page.getByRole('button', { name: 'New baseline type' }).click();
  const form = page.getByRole('dialog', { name: 'New baseline type' });
  await form.getByLabel('Code (snake_case)', { exact: true }).fill(code);
  await form.getByLabel('Name', { exact: true }).fill('Test item type');
  await form.getByRole('button', { name: 'Save', exact: true }).click();
  const row = page.getByRole('row').filter({ hasText: code });
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Delete', exact: true }).click();
  await page.getByRole('dialog', { name: 'Delete' }).getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(row).toHaveCount(0);
  errors.assertClean();
});

test('product BOM, production release and resource planning use the staff API', async ({ page, request }) => {
  const errors = attachErrorCollector(page);
  const componentCode = unique('PART').replace(' ', '-');
  const assemblyCode = unique('ASSEMBLY').replace(' ', '-');
  const addProduct = async (code: string, product_type: string) => {
    const response = await request.post(`${api}/products`, {
      headers: asAdmin,
      data: { code, name: code, product_type },
    });
    expect(response.ok(), await response.text()).toBeTruthy();
    return (await response.json()) as { id: string };
  };
  const component = await addProduct(componentCode, 'purchased');
  const assembly = await addProduct(assemblyCode, 'manufactured');

  await signInAsAdmin(page);
  await openModule(page, 'nav-products', /\/app\/products$/);
  await page.locator('[data-target="products-search"]').fill(assemblyCode);
  await page.getByRole('link', { name: assemblyCode, exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/app/products/${assembly.id}$`));
  await page.getByRole('button', { name: 'BOMs', exact: true }).click();
  await page.getByRole('button', { name: 'New BOM revision' }).click();
  await page.getByRole('dialog', { name: 'New BOM revision' }).getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('button', { name: 'Revision 1' })).toBeVisible();

  const bomList = await request.get(`${api}/products/${assembly.id}/boms`, { headers: asAdmin });
  expect(bomList.ok(), await bomList.text()).toBeTruthy();
  const [{ id: bom }] = (await bomList.json()) as Array<{ id: string }>;
  const centreName = unique('Planning centre');
  const centre = await request.post(`${api}/production/work-centres`, {
    headers: asAdmin,
    data: { code: unique('WC').replace(' ', '-'), name: centreName },
  });
  expect(centre.ok(), await centre.text()).toBeTruthy();
  const { id: workCentre } = (await centre.json()) as { id: string };
  const routing = await request.put(`${api}/boms/${bom}/routing`, {
    headers: asAdmin,
    data: { operations: [{ name: 'Assembly', work_centre_id: workCentre, setup_minutes: 10 }] },
  });
  expect(routing.ok(), await routing.text()).toBeTruthy();
  const update = await request.put(`${api}/boms/${bom}`, {
    headers: asAdmin,
    data: { lines: [{ component_product_id: component.id, quantity: '1' }] },
  });
  expect(update.ok(), await update.text()).toBeTruthy();
  await page.getByRole('button', { name: 'Revision 1' }).click();
  await expect(page.getByRole('link', { name: new RegExp(componentCode) })).toBeVisible();
  await page.getByRole('button', { name: 'Activate revision' }).click();
  await page.getByRole('dialog', { name: 'Activate revision' }).getByRole('button', { name: 'Activate revision' }).click();
  await expect(page.getByRole('heading', { name: 'BOM revision 1 · active' })).toBeVisible();

  await openModule(page, 'nav-production', /\/app\/production$/);
  await page.getByRole('link', { name: 'Release queue' }).click();
  await page.getByRole('button', { name: 'Release for stock' }).click();
  const release = page.getByRole('dialog', { name: 'Release for stock' });
  await release.getByRole('combobox', { name: 'Manufactured product' }).fill(assemblyCode);
  await release.getByRole('option', { name: new RegExp(assemblyCode) }).click();
  await release.getByLabel('Quantity', { exact: true }).fill('1');
  await release.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('status').filter({ hasText: /Released/ })).toBeVisible();

  await page.getByRole('link', { name: 'Production orders' }).click();
  const produced = page.getByRole('row').filter({ hasText: assemblyCode });
  await expect(produced).toBeVisible();
  await produced.getByRole('link').first().click();
  await expect(page.getByRole('heading', { name: 'Components' })).toBeVisible();
  await expect(page.getByRole('link', { name: new RegExp(componentCode) })).toBeVisible();
  await page.getByRole('link', { name: 'Planning board' }).click();
  await expect(page.getByRole('heading', { name: 'Production planning board' })).toBeVisible();
  await expect(page.getByRole('rowheader', { name: new RegExp(centreName) })).toBeVisible();
  await openModule(page, 'nav-mrp', /\/app\/mrp$/);
  await expect(page.getByRole('heading', { name: 'Material requirements planning' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Run MRP' })).toBeVisible();
  errors.assertClean();
});
