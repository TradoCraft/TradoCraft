import { expect, Locator, Page, test } from '@playwright/test';
import { API_PORT } from '../playwright.config';
import { boot, choose, dump, expectStep, field, next, overviewTab, railTo, searchPick, startNextChapter, takeMeThere, typeInto } from './flutter';

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
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 4: supplier invoices', async () => {
    await expectStep(page, 'invoices', 'openOrder');
    await takeMeThere(page);
    await expectStep(page, 'invoices', 'create');
    await page.getByRole('button', { name: /Create supplier invoice/ }).click();
    await page.waitForTimeout(1000);
    await dump(page, 'inv-dialog');
    await typeInto(field(page, 'Invoice number'), 'TUT-INV-001');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'invoices', 'match');
    await page.waitForTimeout(1000);
    await dump(page, 'inv-page');
    await next(page);
    await expectStep(page, 'invoices', 'approve');
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expectStep(page, 'invoices', 'second');
    await railTo(page, 'Finance');
    await overviewTab(page);
    await page.waitForTimeout(1000);
    await page.getByRole('button', { name: /New supplier invoice|New invoice/ }).first().click();
    await page.getByRole('button', { name: 'Pause' }).click(); // supplier suggestions need the narrator out of the way
    await searchPick(page, 'Supplier', 'TUT-SUP-A', /Voltaic Drives/);
    await typeInto(field(page, 'Invoice number'), 'TUT-INV-002');
    await typeInto(field(page, 'Description'), 'Motors');
    await typeInto(field(page, 'Quantity'), '10');
    await typeInto(field(page, 'Unit price'), '150');
    await page.getByRole('button', { name: 'Save' }).click();
    await page.getByRole('button', { name: 'Resume' }).click();
    // Saving opens the invoice, which completes "open invoice TUT-INV-002".
    await expectStep(page, 'invoices', 'mismatch');
    await next(page);
    await expectStep(page, 'invoices', 'dispute');
    await page.getByRole('button', { name: 'Dispute' }).click();
    await page.waitForTimeout(800);
    await dump(page, 'dispute-dialog');
    await typeInto(page.getByRole('alertdialog').getByRole('textbox').first(), 'price does not match the agreement');
    await page.getByRole('alertdialog').getByRole('button', { name: 'Dispute' }).click();
    await expectStep(page, 'invoices', 'tolerances');
    await railTo(page, 'Finance');
    await overviewTab(page);
    await page.getByRole('button', { name: 'Settings' }).click();
    await next(page);
    await expectStep(page, 'invoices', 'pay');
    await takeMeThere(page);
    await page.getByRole('button', { name: 'Mark as paid' }).click();
    await page.waitForTimeout(800);
    await dump(page, 'pay-dialog');
    await typeInto(page.getByRole('alertdialog').getByRole('textbox').first(), 'TUT-PAY-001');
    await page.getByRole('alertdialog').getByRole('button', { name: /OK|Save|Mark as paid/ }).click();
    await expectStep(page, 'invoices', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 5: production', async () => {
    await expectStep(page, 'manufacturing', 'openDivisions');
    await railTo(page, 'Production');
    await overviewTab(page);
    await takeMeThere(page);
    await expectStep(page, 'manufacturing', 'division');
    await page.getByRole('button', { name: 'Add division' }).click();
    await page.waitForTimeout(1000);
    await typeInto(field(page, 'Code'), 'TUT-ASM');
    await typeInto(field(page, 'Name'), 'Tutorial assembly');
    await page.getByRole('checkbox', { name: 'Admin User' }).click();
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'manufacturing', 'queue');
    await takeMeThere(page);
    await expectStep(page, 'manufacturing', 'release');
    await page.getByRole('button', { name: /Build for stock/ }).click();
    await page.getByRole('button', { name: 'Pause' }).click(); // product suggestions need the narrator out of the way
    await searchPick(page, 'Product', 'TUT-CART', /^TUT-CART ·/);
    await typeInto(field(page, 'Quantity'), '5');
    await page.getByRole('button', { name: 'Release to production' }).click();
    await page.getByRole('button', { name: 'Resume' }).click();
    await expectStep(page, 'manufacturing', 'assign');
    await choose(page, /^Division/, /Tutorial assembly/);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expectStep(page, 'manufacturing', 'start');
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expectStep(page, 'manufacturing', 'complete');
    await page.getByRole('button', { name: 'Complete', exact: true }).click();
    await page.waitForTimeout(1000);
    // The step does not mention it, but the finished carts need a location to go into.
    await choose(page, /^Put into/, /MAIN/);
    await page.getByRole('alertdialog').getByRole('button', { name: 'Complete' }).click();
    await expectStep(page, 'manufacturing', 'stock');
    await railTo(page, 'Stock');
    await expectStep(page, 'manufacturing', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 6: price zones and prices', async () => {
    await expectStep(page, 'prices', 'openAdmin');
    await railTo(page, 'Administration');
    await overviewTab(page);
    await expectStep(page, 'prices', 'zone');
    await page.getByRole('button', { name: 'Price zones' }).click();
    await page.waitForTimeout(1500);
    await page.getByRole('button', { name: 'New price zone' }).click();
    await typeInto(field(page, 'Code'), 'TUT-EXPORT');
    await typeInto(field(page, 'Name'), 'Export zone');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'prices', 'openCart');
    await takeMeThere(page);
    await expectStep(page, 'prices', 'priceExport');
    await page.getByRole('tab', { name: 'Prices' }).click(); // the product page keeps the tab it was left on
    await page.getByRole('button', { name: /New price/ }).click();
    await choose(page, /^Zone/, /TUT-EXPORT/);
    await typeInto(field(page, 'Unit price (excl. VAT)'), '1450');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'prices', 'priceHome');
    await page.getByRole('button', { name: /New price/ }).click();
    await choose(page, /^Zone/, /^Z1\b/);
    await typeInto(field(page, 'Unit price (excl. VAT)'), '1200');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'prices', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 7: a new customer writes in', async () => {
    await expectStep(page, 'customer', 'mail1');
    await page.getByRole('button', { name: 'Simulate customer e-mail' }).click();
    await expectStep(page, 'customer', 'openHelpdesk');
    await railTo(page, 'Helpdesk');
    await overviewTab(page);
    await expectStep(page, 'customer', 'openTicket');
    await page.getByRole('button', { name: 'All', exact: true }).click(); // the new ticket is unassigned
    await page.waitForTimeout(1000);
    await page.getByRole('button', { name: /Maya Okafor|quotation/i }).first().click();
    await expectStep(page, 'customer', 'reply');
    await typeInto(field(page, 'Message'), 'Thank you Maya. Could you send us your company name, VAT number and address?');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expectStep(page, 'customer', 'mail2');
    await page.getByRole('button', { name: 'Simulate customer e-mail' }).click();
    await expectStep(page, 'customer', 'readDetails');
    await next(page);
    await expectStep(page, 'customer', 'createCustomer');
    await page.getByRole('button', { name: 'New customer' }).click();
    await typeInto(field(page, 'Code'), 'TUT-CUST');
    await typeInto(field(page, 'Name'), 'Brightwheel Logistics BV');
    await typeInto(field(page, 'VAT number'), 'BE0123456749');
    await typeInto(field(page, 'Street'), 'Voorbeeldlaan 12');
    await typeInto(field(page, 'Postal code'), '9000');
    await typeInto(field(page, 'City'), 'Gent');
    await choose(page, /^Price zone/, /TUT-EXPORT/);
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'customer', 'linked');
    await next(page);
    await expectStep(page, 'customer', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 8: the quotation', async () => {
    await expectStep(page, 'quotation', 'openQuotations');
    await railTo(page, 'Quotations');
    await overviewTab(page);
    await expectStep(page, 'quotation', 'create');
    await page.getByRole('button', { name: /New quotation/ }).click();
    await searchPick(page, 'Customer', 'Brightwheel', /Brightwheel/);
    await searchPick(page, 'Add product', 'TUT-CART', /^TUT-CART ·/);
    // The line's quantity input has no accessible name, so it is clicked by position (fixed viewport).
    await expect(async () => {
      await page.mouse.click(568, 433);
      await page.waitForTimeout(600);
      await page.keyboard.press('Control+A');
      await page.keyboard.press('Backspace');
      await page.keyboard.type('8', { delay: 80 });
      await expect(page.getByText('11.600,00').first()).toBeVisible({ timeout: 2_500 });
    }).toPass({ timeout: 30_000 });
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'quotation', 'lead');
    await typeInto(field(page, 'Notes'), 'Delivery about 3 weeks after order.');
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'quotation', 'send');
    await page.getByRole('button', { name: 'Mark as sent' }).click();
    await expectStep(page, 'quotation', 'pdf');
    // The PDF button needs the Typst binary on the server; the step is explanation only, so it is not pressed.
    await next(page);
    await expectStep(page, 'quotation', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 9: a change, an order and production', async () => {
    await expectStep(page, 'change', 'mail3');
    await page.getByRole('button', { name: 'Simulate customer e-mail' }).click();
    await expectStep(page, 'change', 'openQuote');
    await takeMeThere(page);
    await expectStep(page, 'change', 'revise');
    await page.getByRole('button', { name: 'New revision' }).click();
    await page.getByRole('button', { name: 'Keep agreed prices' }).click();
    await expectStep(page, 'change', 'edit');
    await expect(async () => {
      await page.mouse.click(568, 433);
      await page.waitForTimeout(600);
      await page.keyboard.press('Control+A');
      await page.keyboard.press('Backspace');
      await page.keyboard.type('10', { delay: 80 });
      await expect(page.getByText('14.500,00').first()).toBeVisible({ timeout: 2_500 });
    }).toPass({ timeout: 30_000 });
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'change', 'send');
    await page.getByRole('button', { name: 'Mark as sent' }).click();
    await expectStep(page, 'change', 'accept');
    await page.getByRole('button', { name: 'Accepted' }).click();
    await expectStep(page, 'change', 'convert');
    await page.getByRole('button', { name: 'Convert to order' }).click();
    await page.waitForTimeout(1000);
    await dump(page, 'convert-dialog');
  });
});
