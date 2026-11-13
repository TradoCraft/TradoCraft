import { expect, Locator, Page, test } from '@playwright/test';
import { API_PORT } from '../playwright.config';
import { boot, choose, dump, expectStep, field, next, overviewTab, railTo, searchPick, takeMeThere, typeInto } from './flutter';

/** Adds a product to the supplier's price list through the "Add product" dialog. */
async function addSupplierPrice(page: Page, code: string, price: number, leadDays: number, moq: number) {
  await page.getByRole('button', { name: 'Add product' }).click();
  await searchPick(page, 'Product', code, new RegExp(`^${code} ·`));
  await typeInto(field(page, 'Unit price'), String(price));
  await typeInto(field(page, 'Lead time (days)'), String(leadDays));
  await typeInto(field(page, 'Min. order qty'), String(moq));
  await page.getByRole('button', { name: 'Save' }).click();
}

/** Books a goods receipt on the open purchase order into warehouse location MAIN: `qty` of every line. */
async function receiveGoods(page: Page, qty: number) {
  await page.getByRole('button', { name: /Receive goods/ }).first().click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toBeVisible();
  await choose(page, /^Destination location/, /MAIN/);
  for (let i = 0; i < 3; i++) await typeInto(field(page, 'Quantity to receive').nth(i), String(qty));
  await dialog.getByRole('button', { name: 'Receive goods' }).click();
  await expect(dialog).toBeHidden();
}

test('the whole tutorial, chapter by chapter', async ({ page, request }) => {
  // The development seed has no warehouse, yet chapter 3 says "choose the location MAIN" (companies made
  // through the setup wizard get one). Create it here, as an administrator would.
  const made = await request.post(`http://127.0.0.1:${API_PORT}/api/v1/inventory/warehouses`, {
    headers: { 'X-Dev-User': 'admin@example.com' },
    data: { code: 'MAIN', name: 'Main warehouse' },
  });
  expect(made.status()).toBe(201);
  await boot(page);
  await page.getByRole('button', { name: 'Start the tutorial' }).click();

  await test.step('chapter 0: welcome', async () => {
    await expectStep(page, 'welcome', 'banner');
    await next(page);
    await expectStep(page, 'welcome', 'tabs');
    await next(page);
    await expectStep(page, 'welcome', 'controls');
    await next(page);
    await expectStep(page, 'welcome', 'menu');
    await next(page);
    await expectStep(page, 'welcome', 'products');
    await page.getByRole('tab', { name: 'Products' }).click();
    await expect(page.getByRole('button', { name: 'Start next chapter' })).toBeVisible();
    await page.getByRole('button', { name: 'Start next chapter' }).click();
  });

  await test.step('chapter 1: products and bill of materials', async () => {
    await expectStep(page, 'product', 'motor');
    await page.getByRole('button', { name: 'New product' }).click();
    await typeInto(field(page, 'Code'), 'TUT-MOTOR');
    await typeInto(field(page, 'Name'), 'Motor');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'product', 'frame');
    for (const [step, code, name, type] of [
      ['frame', 'TUT-FRAME', 'Frame', 'purchased'],
      ['controller', 'TUT-CTRL', 'Controller', 'purchased'],
      ['cart', 'TUT-CART', 'Cart', 'manufactured'],
    ] as const) {
      await expectStep(page, 'product', step);
      await page.getByRole('button', { name: 'New product' }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      if (type === 'manufactured') {
        await choose(page, 'Type purchased', 'manufactured');
        await expect(page.getByRole('button', { name: 'Type manufactured' })).toBeVisible();
      }
      await page.getByRole('button', { name: 'Save' }).click();
    }
    await expectStep(page, 'product', 'openCart');
    await page.getByRole('button', { name: /^TUT-CART Cart/ }).click();
    await expectStep(page, 'product', 'bomTab');
    await page.getByRole('tab', { name: 'Bill of materials' }).click();
    await next(page);
    await expectStep(page, 'product', 'revision');
    await page.getByRole('button', { name: 'New revision' }).click();
    await expectStep(page, 'product', 'lines');
    await expect(page.getByRole('button', { name: /Save draft/ })).toBeVisible();
    await dump(page, 'bom-draft');
    for (const code of ['TUT-MOTOR', 'TUT-FRAME', 'TUT-CTRL']) {
      await searchPick(page, 'Add component', code, new RegExp(`^${code} ·`));
    }
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'product', 'activate');
    await page.getByRole('button', { name: 'Activate' }).click();
    await expectStep(page, 'product', 'done');
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Start next chapter' })).toBeVisible();
    await page.getByRole('button', { name: 'Start next chapter' }).click();
  });

  await test.step('chapter 2: suppliers and price lists', async () => {
    await expectStep(page, 'suppliers', 'open');
    await railTo(page, 'Purchasing');
    await expectStep(page, 'suppliers', 'supplierA');
    for (const [step, code, name] of [
      ['supplierA', 'TUT-SUP-A', 'Voltaic Drives Ltd'],
      ['supplierB', 'TUT-SUP-B', 'Ironbridge Frames'],
    ] as const) {
      await expectStep(page, 'suppliers', step);
      await page.getByRole('button', { name: /New supplier/ }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      await page.getByRole('button', { name: 'Save' }).click();
      // Saving opens the new supplier; go back to the list.
      await expect(page.getByRole('button', { name: 'Add product' })).toBeVisible();
      if (step === 'supplierA') await overviewTab(page); // back to the list
    }
    await expectStep(page, 'suppliers', 'openA');
    await takeMeThere(page); // the supplier's own screen
    for (const [step, code, price, lead, moq] of [
      ['priceMotor', 'TUT-MOTOR', 120, 14, 5],
      ['priceFrame', 'TUT-FRAME', 45, 10, 5],
      ['priceController', 'TUT-CTRL', 30, 7, 5],
    ] as const) {
      await expectStep(page, 'suppliers', step);
      await addSupplierPrice(page, code, price, lead, moq);
    }
    await expectStep(page, 'suppliers', 'openB');
    await takeMeThere(page);
    await expectStep(page, 'suppliers', 'priceMotorB');
    await addSupplierPrice(page, 'TUT-MOTOR', 135, 5, 1);
    await expectStep(page, 'suppliers', 'done');
    await next(page);
    await expect(page.getByRole('button', { name: 'Start next chapter' })).toBeVisible();
    await page.getByRole('button', { name: 'Start next chapter' }).click();
  });

  await test.step('chapter 3: purchase orders and goods receipt', async () => {
    await expectStep(page, 'buying', 'open');
    await railTo(page, 'Purchasing');
    await overviewTab(page);
    await page.getByRole('button', { name: 'Purchase orders' }).click();
    await expectStep(page, 'buying', 'order');
    await page.getByRole('button', { name: /New purchase order/ }).click();
    // While the narrator card is up, the product suggestions in this dialog do not open (see README): pause it.
    await page.getByRole('button', { name: 'Pause' }).click();
    await searchPick(page, 'Supplier', 'TUT-SUP-A', /Voltaic Drives/);
    const components = ['TUT-MOTOR', 'TUT-FRAME', 'TUT-CTRL'];
    for (const [i, code] of components.entries()) {
      if (i > 0) await page.getByRole('button', { name: 'Add line' }).click();
      // A picked product turns into a label, so the next empty Product box is always the first one.
      await searchPick(page, 'Product', code, new RegExp(`^${code} ·`));
      await typeInto(field(page, 'Quantity').nth(i), '30');
    }
    await dump(page, 'po-filled');
    await page.getByRole('button', { name: 'Save' }).click();
    await page.getByRole('button', { name: 'Resume' }).click();
    // Saving opens the order, which completes the "open the order" step by itself.
    await expectStep(page, 'buying', 'approve');
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expectStep(page, 'buying', 'send');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expectStep(page, 'buying', 'receivePart');
    await receiveGoods(page, 10);
    await expectStep(page, 'buying', 'receiveRest');
    await receiveGoods(page, 20);
    await expectStep(page, 'buying', 'stock');
    await railTo(page, 'Stock');
    await expectStep(page, 'buying', 'done');
    await dump(page, 'stock');
  });
});
