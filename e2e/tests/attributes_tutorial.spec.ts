import { expect, test } from '@playwright/test';
import { API_PORT } from '../playwright.config';
import { boot, choose, expectStep, field, next, railTo, typeInto } from './flutter';

const api = `http://127.0.0.1:${API_PORT}/api/v1`;
const headers = { 'x-dev-user': 'admin@example.com' };

test('tutorial chapter 11 (standalone): custom product properties', async ({ page, request }) => {
  // Ensure TUT-CTRL exists so the chapter starts directly at `intro` without depending on chapter 1.
  const existing = await request.get(`${api}/products`, { headers, params: { q: 'TUT-CTRL' } });
  await expect(existing).toBeOK();
  let ctrl = (await existing.json()).items.find((i: { code: string }) => i.code === 'TUT-CTRL');
  if (!ctrl) {
    const created = await request.post(`${api}/products`, {
      headers,
      data: { code: 'TUT-CTRL', name: 'Controller', product_type: 'purchased' },
    });
    await expect(created).toBeOK();
    ctrl = await created.json();
  }

  await boot(page);
  await page.getByRole('button', { name: 'Account' }).click();
  await page.getByRole('menuitem', { name: 'Tutorial', exact: true }).click();
  for (let i = 0; i < 11; i++) {
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
    ['relays', 'relay_count', 'Relays', 'Number'],
    ['fets', 'fet_count', 'FETs', 'Number'],
    ['digitalInputs', 'digital_inputs', 'Digital inputs', 'Number'],
    ['polarized24v', 'supports_24v_polarized_2wire', '24V polarized 2-wire output', 'Yes/No'],
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
  await page.getByRole('button', { name: /^TUT-CTRL Controller/ }).click();
  await expectStep(page, 'attributes', 'suitabilityTab');
  await page.getByRole('tab', { name: 'Suitability' }).click();
  await next(page);
  await expectStep(page, 'attributes', 'fillProperties');
  await typeInto(field(page, 'Relays'), '4');
  await typeInto(field(page, 'FETs'), '2');
  await typeInto(field(page, 'Digital inputs'), '8');
  await choose(page, /^24V polarized 2-wire output/, 'Yes');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expectStep(page, 'attributes', 'done');
  await next(page);
  await expect(page.getByText('Chapter Custom product properties complete', { exact: true })).toBeVisible();

  const attrsRes = await request.get(`${api}/products/${ctrl.id}/attributes`, { headers });
  await expect(attrsRes).toBeOK();
  expect(await attrsRes.json()).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ key: 'relay_count', kind: 'number', value: '4' }),
      expect.objectContaining({ key: 'fet_count', kind: 'number', value: '2' }),
      expect.objectContaining({ key: 'digital_inputs', kind: 'number', value: '8' }),
      expect.objectContaining({ key: 'supports_24v_polarized_2wire', kind: 'boolean', value: 'true' }),
    ]),
  );
});
