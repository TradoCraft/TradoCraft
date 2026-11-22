import { APIRequestContext, expect, Page, test } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { API_PORT } from '../playwright.config';
import { boot, choose, dump, expectStep, field, next, overviewTab, railTo, searchPick, startNextChapter, takeMeThere, typeInto } from './flutter';

const api = `http://127.0.0.1:${API_PORT}/api/v1`;
const headers = { 'x-dev-user': 'admin@example.com' };

async function tutorialTicket(request: APIRequestContext) {
  const response = await request.get(`${api}/tickets`, { headers, params: { q: 'CONV-BELT-1M' } });
  await expect(response).toBeOK();
  const matches = (await response.json()).items.filter(
    (item: { contact_email: string }) => item.contact_email === 'maya.okafor@example.test',
  );
  expect(matches).toHaveLength(1);
  return matches[0];
}

/** Whether a Typst binary can be found (TYPST_BIN or on PATH); the server needs it for PDFs. */
function typstAvailable(): boolean {
  const names = process.platform === 'win32' ? ['typst.exe'] : ['typst'];
  const dirs = (process.env.PATH ?? '').split(path.delimiter);
  return [process.env.TYPST_BIN, ...dirs.flatMap((d) => names.map((n) => path.join(d, n)))].some((p) => p && fs.existsSync(p));
}

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
  // The tutorial environment starts without a warehouse: chapter 3 teaches creating one (MAIN, with its
  // location MAIN), and the goods are received into it. The database is recreated on every run.
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
    await expect(page.getByText('Menu path · Switch application › Master data › Products')).toBeVisible();
    await takeMeThere(page);
    await expect(page.getByText('Tutorial shortcut · Switch application › Master data › Products')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Start next chapter' })).toBeVisible();
    await page.getByRole('button', { name: 'Start next chapter' }).click();
  });

  await test.step('chapter 1: conveyor belts & motors', async () => {
    await expectStep(page, 'conveyors', 'motor1p');
    for (const [step, code, name, type] of [
      ['motor1p', 'MOT-1P-037', 'Single-Phase AC Motor', 'purchased'],
      ['motor', 'MOT-3P-055', '3-Phase AC Motor', 'purchased'],
      ['vfd', 'VFD-3P-055', 'Variable Frequency Drive', 'purchased'],
      ['conveyor', 'CONV-BELT-1M', 'Conveyor Belt Assembly', 'manufactured'],
    ] as const) {
      await expectStep(page, 'conveyors', step);
      await page.getByRole('button', { name: 'New product' }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      if (type === 'manufactured') {
        await choose(page, 'Type purchased', 'manufactured');
        await expect(page.getByRole('button', { name: 'Type manufactured' })).toBeVisible();
      }
      await page.getByRole('button', { name: 'Save' }).click();
    }
    await expectStep(page, 'conveyors', 'openConveyor');
    await page.getByRole('button', { name: /^CONV-BELT-1M Conveyor Belt Assembly/ }).click();
    await expectStep(page, 'conveyors', 'svgPreview');
    await next(page);
    await expectStep(page, 'conveyors', 'bomTab');
    await page.getByRole('tab', { name: 'Bill of materials' }).click();
    await next(page);
    await expectStep(page, 'conveyors', 'revision');
    await page.getByRole('button', { name: 'New revision' }).click();
    await expectStep(page, 'conveyors', 'lines');
    await expect(page.getByRole('button', { name: /Save draft/ })).toBeVisible();
    await dump(page, 'bom-draft');
    for (const code of ['MOT-3P-055', 'VFD-3P-055']) {
      await searchPick(page, 'Add component', code, new RegExp(`^${code} ·`));
    }
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'conveyors', 'activate');
    await page.getByRole('button', { name: 'Activate' }).click();
    await expectStep(page, 'conveyors', 'done');
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Start next chapter' })).toBeVisible();
    await page.getByRole('button', { name: 'Start next chapter' }).click();
  });

  await test.step('chapter 2: PLCs, parallel licensing & network', async () => {
    await expectStep(page, 'plc', 'base');
    for (const [step, code, name, type] of [
      ['base', 'PLC-BASE', 'Standard PLC (10 Outputs)', 'purchased'],
      ['lic30', 'PLC-LIC-30', 'PLC 30-Output Parallel License', 'service'],
      ['lic50', 'PLC-LIC-50', 'PLC 50-Output Parallel License', 'service'],
      ['lic100', 'PLC-LIC-100', 'PLC 100-Output Parallel License', 'service'],
      ['expansion', 'PLC-EXP-RS485', 'RS-485 I/O Expansion Module', 'purchased'],
      ['master', 'PLC-MASTER', 'Master Network Controller', 'purchased'],
    ] as const) {
      await expectStep(page, 'plc', step);
      await page.getByRole('button', { name: 'New product' }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      if (type !== 'purchased') {
        await choose(page, 'Type purchased', type);
      }
      await page.getByRole('button', { name: 'Save' }).click();
    }
    await expectStep(page, 'plc', 'done');
    await startNextChapter(page);
  });

  await test.step('chapter 3: RS-485 displays & I2C peripherals', async () => {
    await expectStep(page, 'displays', 'display');
    for (const [step, code, name] of [
      ['display', 'DISP-RS485', 'RS-485 Operator Display'],
      ['swipe', 'MOD-I2C-SWIPE', 'I2C Swipe Card Reader'],
      ['temp', 'SENS-I2C-TEMP', 'I2C Temperature Sensor'],
    ] as const) {
      await expectStep(page, 'displays', step);
      await page.getByRole('button', { name: 'New product' }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      await page.getByRole('button', { name: 'Save' }).click();
    }
    await expectStep(page, 'displays', 'done');
    await startNextChapter(page);
  });

  await test.step('chapter 4: sensors & PowerFET devices', async () => {
    await expectStep(page, 'sensors', 'ir');
    for (const [step, code, name] of [
      ['ir', 'SENS-IR-24V', 'IR Photoelectric Sensor'],
      ['analog', 'SENS-420MA', '4-20 mA Analog Sensor'],
      ['pusher', 'SOL-PUSH', 'PowerFET Solenoid Pusher'],
      ['labeler', 'SOL-LABEL', 'PowerFET Label Stamper'],
    ] as const) {
      await expectStep(page, 'sensors', step);
      await page.getByRole('button', { name: 'New product' }).click();
      await typeInto(field(page, 'Code'), code);
      await typeInto(field(page, 'Name'), name);
      await page.getByRole('button', { name: 'Save' }).click();
    }
    await expectStep(page, 'sensors', 'done');
    await startNextChapter(page);
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
      ['priceMotor', 'MOT-3P-055', 120, 14, 5],
      ['priceFrame', 'VFD-3P-055', 45, 10, 5],
      ['priceController', 'PLC-BASE', 30, 7, 5],
    ] as const) {
      await expectStep(page, 'suppliers', step);
      await addSupplierPrice(page, code, price, lead, moq);
    }
    await expectStep(page, 'suppliers', 'openB');
    await takeMeThere(page);
    await expectStep(page, 'suppliers', 'priceMotorB');
    await addSupplierPrice(page, 'MOT-3P-055', 135, 5, 1);
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
    await searchPick(page, 'Supplier', 'TUT-SUP-A', /Voltaic Drives/);
    // The goods picker lists the supplier's price list as rows with a checkbox (no accessible name) and a
    // quantity box. Typing a quantity above zero ticks the row, so narrow the list with the filter box and
    // type 30 into the one remaining row's Quantity (the first one: "Other products" comes below the list).
    for (const code of ['MOT-3P-055', 'VFD-3P-055', 'PLC-BASE']) {
      await typeInto(field(page, 'Filter goods'), code);
      await typeInto(field(page, 'Quantity').first(), '30');
    }
    await dump(page, 'po-filled');
    await page.getByRole('button', { name: 'Save' }).click();
    // Saving opens the order, which completes the "open the order" step by itself.
    await expectStep(page, 'buying', 'approve');
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expectStep(page, 'buying', 'send');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expectStep(page, 'buying', 'openWarehouses');
    await railTo(page, 'Stock');
    await page.getByRole('button', { name: 'Warehouses', exact: true }).click();
    await expectStep(page, 'buying', 'warehouse');
    await page.getByRole('button', { name: 'New warehouse' }).click();
    await typeInto(field(page, 'Code'), 'MAIN');
    await typeInto(field(page, 'Name'), 'Main warehouse');
    await page.getByRole('button', { name: 'Save' }).click();
    // The new warehouse brings its location MAIN; the step after it sends us back to the order.
    await expectStep(page, 'buying', 'receivePart');
    await takeMeThere(page);
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
    await searchPick(page, 'Supplier', 'TUT-SUP-A', /Voltaic Drives/);
    await typeInto(field(page, 'Invoice number'), 'TUT-INV-002');
    await typeInto(field(page, 'Description'), 'Motors');
    await typeInto(field(page, 'Quantity'), '10');
    await typeInto(field(page, 'Unit price'), '150');
    await page.getByRole('button', { name: 'Save' }).click();
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
    await searchPick(page, 'Product', 'CONV-BELT-1M', /^CONV-BELT-1M ·/);
    await typeInto(field(page, 'Quantity'), '5');
    await page.getByRole('button', { name: 'Release to production' }).click();
    await expectStep(page, 'manufacturing', 'assign');
    await choose(page, /^Division/, /Tutorial assembly/);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expectStep(page, 'manufacturing', 'start');
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expectStep(page, 'manufacturing', 'complete');
    await page.getByRole('button', { name: 'Complete', exact: true }).click();
    await page.waitForTimeout(1000);
    // Chapter 3 created the warehouse, so the warehouse step is skipped; the finished carts go into MAIN.
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
    await typeInto(field(page, 'TUT-EXPORT'), '1450');
    await page.getByRole('button', { name: 'Save' }).click();
    await expectStep(page, 'prices', 'priceHome');
    await page.getByRole('button', { name: /New price/ }).click();
    await typeInto(field(page, 'Z1'), '1200');
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
    await expect(page.getByText(/Our company details/)).toBeVisible();
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
    await expectStep(page, 'customer', 'done');
    const customers = await request.get(`${api}/customers`, { headers, params: { q: 'TUT-CUST' } });
    await expect(customers).toBeOK();
    const customer = (await customers.json()).items.find((item: { code: string }) => item.code === 'TUT-CUST');
    expect(customer).toBeDefined();
    expect((await tutorialTicket(request)).customer_id).toBe(customer.id);
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
    await searchPick(page, 'Add product', 'CONV-BELT-1M', /^CONV-BELT-1M ·/);
    await typeInto(field(page, 'Quantity'), '8');
    await expect(page.getByText('11.600,00').first()).toBeVisible();
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
    await typeInto(field(page, 'Quantity'), '10');
    await expect(page.getByText('14.500,00').first()).toBeVisible();
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expectStep(page, 'change', 'send');
    await page.getByRole('button', { name: 'Mark as sent' }).click();
    await expectStep(page, 'change', 'accept');
    await page.getByRole('button', { name: 'Accepted' }).click();
    await expectStep(page, 'change', 'convert');
    await page.getByRole('button', { name: 'Convert to order' }).click();
    await typeInto(field(page, 'Customer reference'), 'TUT-PO-1');
    await page.getByRole('alertdialog').getByRole('button', { name: 'OK' }).click();
    // Converting opens the order, which completes "open the order" by itself.
    await expectStep(page, 'change', 'sendOrder');
    await page.getByRole('button', { name: /Send order confirmation/ }).click();
    if (!typstAvailable()) {
      // The confirmation PDF is made by the Typst binary; without it the server refuses this step and the
      // tutorial cannot go on (the step says so itself). Never let CI pass a walk that stopped here.
      const why = 'no typst on PATH (or TYPST_BIN): the tutorial cannot get past "Send order confirmation"';
      if (process.env.CI) throw new Error(why);
      test.skip(true, why);
    }
    await page.getByRole('alertdialog').getByRole('button', { name: 'Send' }).click();
    await expectStep(page, 'change', 'confirm');
    await page.getByRole('button', { name: 'Confirm on behalf of customer' }).click();
    await typeInto(page.getByRole('alertdialog').getByRole('textbox').first(), 'confirmed by e-mail');
    await page.getByRole('alertdialog').getByRole('button', { name: 'OK' }).click();
    await expectStep(page, 'change', 'release');
    await railTo(page, 'Production');
    await overviewTab(page);
    await page.getByRole('button', { name: 'To release' }).click();
    await page.getByRole('button', { name: 'Release to production' }).first().click();
    await expectStep(page, 'change', 'start');
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expectStep(page, 'change', 'complete');
    await page.getByRole('button', { name: 'Complete', exact: true }).click();
    await choose(page, /^Put into/, /MAIN/);
    await page.getByRole('alertdialog').getByRole('button', { name: 'Complete' }).click();
    await expectStep(page, 'change', 'ready');
    await next(page);
    await expectStep(page, 'change', 'stock');
    await railTo(page, 'Production');
    await overviewTab(page);
    await page.getByRole('button', { name: /Build for stock/ }).click();
    await searchPick(page, 'Product', 'CONV-BELT-1M', /^CONV-BELT-1M ·/);
    await typeInto(field(page, 'Quantity'), '4');
    await page.getByRole('button', { name: 'Release to production' }).click();
    await expectStep(page, 'change', 'done');
    await next(page);
    await startNextChapter(page);
  });

  await test.step('chapter 10: working a helpdesk ticket', async () => {
    const ticket = await tutorialTicket(request);
    const note = 'Maya wants a quotation for 8 carts.';
    const timeNote = 'Read the request and replied';

    // The ticket of chapter 7 exists, so the "needs" step is skipped.
    await expectStep(page, 'helpdesk', 'note');
    await railTo(page, 'Helpdesk');
    await overviewTab(page);
    await page.getByRole('button', { name: 'All', exact: true }).click();
    await page.getByRole('button', { name: ticket.subject }).click();
    await page.getByRole('button', { name: 'Internal note' }).click();
    await typeInto(field(page, 'Internal note'), note);
    await page.getByRole('button', { name: 'Add note', exact: true }).click();
    await expectStep(page, 'helpdesk', 'tag');
    await typeInto(field(page, 'Add tag'), 'quotation');
    await page.getByRole('button', { name: 'Add', exact: true }).click();
    await expectStep(page, 'helpdesk', 'time');
    await page.getByRole('button', { name: 'Log time' }).click();
    await typeInto(field(page, 'Minutes'), '15');
    await typeInto(field(page, 'Note'), timeNote);
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expectStep(page, 'helpdesk', 'escalate');
    await expect(page.getByText(/Shortcut: Alt\+Shift\+E/)).toBeVisible();
    await page.getByRole('button', { name: 'Show control', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Show instructions', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Escalate', exact: true })).toBeInViewport();
    await page.getByRole('button', { name: 'Show instructions', exact: true }).click();
    await page.getByRole('button', { name: 'Pause', exact: true }).click();
    await page.keyboard.press('Alt+Shift+E');
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await choose(page, /^Escalate to/, /Support Agent/);
    await typeInto(field(page, 'Reason (required)'), 'Needs a second pair of eyes on the delivery time.');
    await page.getByRole('button', { name: 'Escalate', exact: true }).last().click();
    await expect(page.getByRole('alertdialog')).toBeHidden();
    await page.getByRole('button', { name: 'Resume', exact: true }).click();
    await expectStep(page, 'helpdesk', 'tour');
    await takeMeThere(page);
    await next(page);
    await expectStep(page, 'helpdesk', 'done');
    await next(page);
    await expect(page.getByText('Chapter Working a ticket complete', { exact: true })).toBeVisible();

    // Verify saved business outcomes independently of the narrator's progress.
    const savedTicket = await request.get(`${api}/tickets/${ticket.id}`, { headers });
    await expect(savedTicket).toBeOK();
    const detail = await savedTicket.json();
    expect(detail.articles).toEqual(expect.arrayContaining([expect.objectContaining({ kind: 'note', body: note })]));
    expect(detail.ticket.tags).toContain('quotation');
    expect(detail.ticket.escalated_at).toEqual(expect.any(String));

    const timeEntries = await request.get(`${api}/tickets/${ticket.id}/time-entries`, { headers });
    await expect(timeEntries).toBeOK();
    expect((await timeEntries.json()).items).toEqual(
      expect.arrayContaining([expect.objectContaining({ minutes: 15, note: timeNote })]),
    );
    await startNextChapter(page);
  });

  await test.step('chapter 11: custom product properties', async () => {
    // PLC-BASE was created in chapter 1, so `needs` is skipped automatically.
    await expectStep(page, 'attributes', 'intro');
    await next(page);
    await expectStep(page, 'attributes', 'openAdmin');
    await railTo(page, 'Administration');
    await page.getByRole('button', { name: 'Attributes', exact: true }).click();

    for (const [step, key, label, kind] of [
      ['relays', 'relay_count', 'Relay outputs', 'Number'],
      ['fets', 'fet_count', 'PowerFET outputs', 'Number'],
      ['digitalInputs', 'digital_inputs', 'Digital inputs', 'Number'],
      ['analog420', 'analog_4_20ma_inputs', '4-20 mA analog inputs', 'Number'],
      ['rs485Ports', 'rs485_ports', 'RS-485 ports', 'Number'],
      ['i2cBus', 'i2c_bus', 'I2C peripheral bus', 'Yes/No'],
      ['licensedOutputs', 'licensed_outputs_tier', 'Licensed outputs tier', 'Number'],
    ] as const) {
      await expectStep(page, 'attributes', step);
      await page.getByRole('button', { name: 'New attribute' }).click();
      const dialog = page.getByRole('alertdialog');
      await expect(dialog).toBeVisible();
      await typeInto(field(dialog, 'Key'), key);
      await typeInto(field(dialog, 'Label'), label);
      if (kind !== 'Number') {
        await choose(page, /^Type/, kind);
      }
      await dialog.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toBeHidden();
    }

    await expectStep(page, 'attributes', 'openController');
    await railTo(page, 'Products');
    await page.getByRole('button', { name: /^PLC-BASE Standard PLC/ }).click();
    await expectStep(page, 'attributes', 'suitabilityTab');
    await page.getByRole('tab', { name: 'Suitability' }).click();
    await next(page);
    await expectStep(page, 'attributes', 'fillProperties');
    await typeInto(field(page, 'Relay outputs'), '4');
    await typeInto(field(page, 'PowerFET outputs'), '6');
    await typeInto(field(page, 'Digital inputs'), '8');
    await typeInto(field(page, '4-20 mA analog inputs'), '2');
    await typeInto(field(page, 'RS-485 ports'), '2');
    await choose(page, /^I2C peripheral bus/, 'Yes');
    await typeInto(field(page, 'Licensed outputs tier'), '10');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expectStep(page, 'attributes', 'done');
    await next(page);
    await expect(page.getByText('Chapter Custom product properties complete', { exact: true })).toBeVisible();

    // Verify saved attribute definitions and controller properties via API.
    const defsRes = await request.get(`${api}/attribute-definitions`, {
      headers,
      params: { scope: 'product' },
    });
    await expect(defsRes).toBeOK();
    expect(await defsRes.json()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: 'relay_count', kind: 'number', scope: 'product' }),
        expect.objectContaining({ key: 'fet_count', kind: 'number', scope: 'product' }),
        expect.objectContaining({ key: 'digital_inputs', kind: 'number', scope: 'product' }),
        expect.objectContaining({ key: 'analog_4_20ma_inputs', kind: 'number', scope: 'product' }),
        expect.objectContaining({ key: 'rs485_ports', kind: 'number', scope: 'product' }),
        expect.objectContaining({ key: 'i2c_bus', kind: 'boolean', scope: 'product' }),
        expect.objectContaining({ key: 'licensed_outputs_tier', kind: 'number', scope: 'product' }),
      ]),
    );

    const prodRes = await request.get(`${api}/products`, { headers, params: { q: 'PLC-BASE' } });
    await expect(prodRes).toBeOK();
    const ctrl = (await prodRes.json()).items.find((i: { code: string }) => i.code === 'PLC-BASE');
    expect(ctrl).toBeTruthy();

    const attrsRes = await request.get(`${api}/products/${ctrl.id}/attributes`, { headers });
    await expect(attrsRes).toBeOK();
    expect(await attrsRes.json()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: 'relay_count', kind: 'number', value: '4' }),
        expect.objectContaining({ key: 'fet_count', kind: 'number', value: '6' }),
        expect.objectContaining({ key: 'digital_inputs', kind: 'number', value: '8' }),
        expect.objectContaining({ key: 'analog_4_20ma_inputs', kind: 'number', value: '2' }),
        expect.objectContaining({ key: 'rs485_ports', kind: 'number', value: '2' }),
        expect.objectContaining({ key: 'i2c_bus', kind: 'boolean', value: 'true' }),
        expect.objectContaining({ key: 'licensed_outputs_tier', kind: 'number', value: '10' }),
      ]),
    );
  });
});

const tutorialAttrKeys = [
  'relay_count',
  'fet_count',
  'digital_inputs',
  'analog_4_20ma_inputs',
  'rs485_ports',
  'i2c_bus',
  'licensed_outputs_tier',
];

async function cleanupAttributes(request: APIRequestContext, ctrlId: string) {
  const attrsRes = await request.get(`${api}/products/${ctrlId}/attributes`, { headers });
  if (attrsRes.ok()) {
    const existing = (await attrsRes.json()) as Array<{ key: string }>;
    const remaining = existing.filter((a) => !tutorialAttrKeys.includes(a.key));
    if (remaining.length !== existing.length) {
      await request.put(`${api}/products/${ctrlId}/attributes`, { headers, data: remaining });
    }
  }
  const defsRes = await request.get(`${api}/attribute-definitions`, {
    headers,
    params: { scope: 'product' },
  });
  if (defsRes.ok()) {
    const defs = (await defsRes.json()) as Array<{ id: string; key: string }>;
    for (const def of defs) {
      if (tutorialAttrKeys.includes(def.key)) {
        await request.delete(`${api}/attribute-definitions/${def.id}`, { headers });
      }
    }
  }
}

test('chapter 11 (standalone): custom product properties', async ({ page, request }) => {
  // Ensure PLC-BASE exists so the chapter starts directly at `intro` without depending on chapter 1.
  const existing = await request.get(`${api}/products`, { headers, params: { q: 'PLC-BASE' } });
  await expect(existing).toBeOK();
  let ctrl = (await existing.json()).items.find((i: { code: string }) => i.code === 'PLC-BASE');
  if (!ctrl) {
    const created = await request.post(`${api}/products`, {
      headers,
      data: { code: 'PLC-BASE', name: 'Standard PLC (10 Outputs)', product_type: 'purchased' },
    });
    await expect(created).toBeOK();
    ctrl = await created.json();
  }

  await cleanupAttributes(request, ctrl.id);

  try {
    await boot(page);
    await page.getByRole('button', { name: 'Account' }).click();
    await page.getByRole('menuitem', { name: 'Tutorial', exact: true }).click();
    for (let i = 0; i < 14; i++) {
      await page.getByRole('button', { name: 'Skip chapter' }).first().click();
    }
    const start = page.getByRole('button', { name: 'Start', exact: true }).last();
    await start.scrollIntoViewIfNeeded();
    await start.click();

    await expectStep(page, 'attributes', 'intro');
    await next(page);
    await expectStep(page, 'attributes', 'openAdmin');
    await railTo(page, 'Administration');
    await page.getByRole('button', { name: 'Attributes', exact: true }).click();

    for (const [step, key, label, kind] of [
      ['relays', 'relay_count', 'Relay outputs', 'Number'],
      ['fets', 'fet_count', 'PowerFET outputs', 'Number'],
      ['digitalInputs', 'digital_inputs', 'Digital inputs', 'Number'],
      ['analog420', 'analog_4_20ma_inputs', '4-20 mA analog inputs', 'Number'],
      ['rs485Ports', 'rs485_ports', 'RS-485 ports', 'Number'],
      ['i2cBus', 'i2c_bus', 'I2C peripheral bus', 'Yes/No'],
      ['licensedOutputs', 'licensed_outputs_tier', 'Licensed outputs tier', 'Number'],
    ] as const) {
      await expectStep(page, 'attributes', step);
      await page.getByRole('button', { name: 'New attribute' }).click();
      const dialog = page.getByRole('alertdialog');
      await expect(dialog).toBeVisible();
      await typeInto(field(dialog, 'Key'), key);
      await typeInto(field(dialog, 'Label'), label);
      if (kind !== 'Number') {
        await choose(page, /^Type/, kind);
      }
      await dialog.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toBeHidden();
    }

    await expectStep(page, 'attributes', 'openController');
    await railTo(page, 'Products');
    await page.getByRole('button', { name: /^PLC-BASE Standard PLC/ }).click();
    await expectStep(page, 'attributes', 'suitabilityTab');
    await page.getByRole('tab', { name: 'Suitability' }).click();
    await next(page);
    await expectStep(page, 'attributes', 'fillProperties');
    await typeInto(field(page, 'Relay outputs'), '4');
    await typeInto(field(page, 'PowerFET outputs'), '6');
    await typeInto(field(page, 'Digital inputs'), '8');
    await typeInto(field(page, '4-20 mA analog inputs'), '2');
    await typeInto(field(page, 'RS-485 ports'), '2');
    await choose(page, /^I2C peripheral bus/, 'Yes');
    await typeInto(field(page, 'Licensed outputs tier'), '10');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await expectStep(page, 'attributes', 'done');
    await next(page);
    await expect(page.getByText('Chapter Custom product properties complete', { exact: true })).toBeVisible();

    const attrsRes = await request.get(`${api}/products/${ctrl.id}/attributes`, { headers });
    await expect(attrsRes).toBeOK();
    expect(await attrsRes.json()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ key: 'relay_count', kind: 'number', value: '4' }),
        expect.objectContaining({ key: 'fet_count', kind: 'number', value: '6' }),
        expect.objectContaining({ key: 'digital_inputs', kind: 'number', value: '8' }),
        expect.objectContaining({ key: 'analog_4_20ma_inputs', kind: 'number', value: '2' }),
        expect.objectContaining({ key: 'rs485_ports', kind: 'number', value: '2' }),
        expect.objectContaining({ key: 'i2c_bus', kind: 'boolean', value: 'true' }),
        expect.objectContaining({ key: 'licensed_outputs_tier', kind: 'number', value: '10' }),
      ]),
    );
  } finally {
    await cleanupAttributes(request, ctrl.id);
  }
});
