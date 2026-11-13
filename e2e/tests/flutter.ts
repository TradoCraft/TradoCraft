import { expect, Locator, Page } from '@playwright/test';
import { API_PORT } from '../playwright.config';

/**
 * Replaces the content of a Flutter text field. Playwright's fill() sets the DOM value without the
 * key events Flutter's text editing listens to, so real key presses are used. Flutter attaches its
 * editing connection a moment after the click and keys typed before that are lost, hence the pauses;
 * the result is checked, and a failed attempt starts by clearing the field again.
 * `refocus`: blur first. After a pick from its own list a field is still focused as far as Flutter is
 * concerned, so a plain click would keep the keys going to a stale element. A failed attempt also
 * blurs first.
 */
export async function typeInto(field: Locator, text: string, opts: { refocus?: boolean } = {}) {
  const page = field.page();
  let attempt = 0;
  await expect(async () => {
    if (opts.refocus || attempt > 0) {
      await field.evaluate((e) => (e as HTMLElement).blur());
      await page.waitForTimeout(300);
    }
    attempt++;
    await field.click();
    await expect(field).toBeFocused({ timeout: 1_000 });
    await page.waitForTimeout(300);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(100);
    await page.keyboard.type(text, { delay: 25 });
    await page.waitForTimeout(300);
    await expect(field).toHaveValue(text, { timeout: 1_000 });
  }).toPass({ timeout: 30_000 });
}

/** Opens a drop-down (a button whose name starts with `button`) and picks an option from its menu. */
export async function choose(page: Page, button: string | RegExp, option: string | RegExp) {
  await page.getByRole('button', { name: button }).click();
  await page.getByRole('menuitem', { name: option }).click();
}

/** Types into a search box and picks the suggestion whose label is `result` (a button under the box). */
export async function searchPick(page: Page, label: string, query: string, result: string | RegExp = query, nth = 0) {
  const suggestion = page.getByRole('button', { name: result }).first();
  // The box can swallow a query typed right after the previous pick: alternate between a plain click and a
  // blur-first click until the suggestions show.
  let tries = 0;
  await expect(async () => {
    await typeInto(field(page, label).nth(nth), query, { refocus: tries++ % 2 === 1 });
    await suggestion.click({ timeout: 3_000 });
  }).toPass({ timeout: 45_000 });
}

/** A text field by its exact label ("Code" must not also match "Barcode"). */
export const field = (page: Page, label: string) => page.getByRole('textbox', { name: label, exact: true });

/** Opens the Flutter web app, turns on its accessibility tree and signs in as a development user. */
export async function boot(page: Page, user = 'admin') {
  // A refused API call is often the real reason a later step never appears: say so in the test output.
  page.on('response', async (r) => {
    if (r.url().includes('/api/v1/') && r.status() >= 400) {
      const body = await r.text().catch(() => '');
      console.log(`API ${r.status()} ${r.request().method()} ${new URL(r.url()).pathname}: ${body.slice(0, 300)}`);
    }
  });
  await page.goto('/');
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60_000 });
  // Flutter draws to a canvas; the semantics tree (what Playwright sees) is off until asked for.
  await page.evaluate(() => (document.querySelector('flt-semantics-placeholder') as HTMLElement)?.click());
  await typeInto(page.getByRole('textbox', { name: 'Server' }), `http://127.0.0.1:${API_PORT}`);
  await page.getByRole('checkbox', { name: user, exact: true }).click();
  // The page rebuilds while it asks the server which environment it is: press Sign in until it is gone.
  const signIn = page.getByRole('button', { name: 'Sign in' });
  await expect(async () => {
    if (await signIn.isVisible()) await signIn.click({ timeout: 2_000 });
    await expect(signIn).toBeHidden({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
}

/** All text currently exposed by the semantics tree (labels and visible text), for diagnostics. */
export async function tree(page: Page): Promise<string> {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('flt-semantics'))
      .map((e) => {
        const el = e as HTMLElement;
        const t = el.getAttribute('aria-label') || el.innerText?.split('\n')[0] || '';
        return `${el.getAttribute('role') ?? '-'} | ${t}`;
      })
      .filter((s) => s.split('| ')[1])
      .concat(
        Array.from(document.querySelectorAll('input, textarea')).map(
          (e) => `input | ${e.getAttribute('aria-label') ?? ''} = ${(e as HTMLInputElement).value}`,
        ),
      )
      .join('\n'),
  );
}

import fs from 'node:fs';
import path from 'node:path';

const arb: Record<string, string> = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../../app/lib/l10n/app_en.arb'), 'utf8'),
);
const cap = (s: string) => s[0].toUpperCase() + s.slice(1);

/** The English narrator text of a step, read from the app's own strings (key tut<Chapter><Step><Part>). */
export function tutorialText(chapter: string, stepId: string, part: 'Title' | 'Body' | 'Hint' = 'Title'): string {
  const key = `tut${cap(chapter)}${cap(stepId)}${part}`;
  if (!(key in arb)) throw new Error(`no string ${key}`);
  return arb[key];
}

/** Waits until the narrator card shows this step (its title), so the test follows the tutorial step by step. */
export async function expectStep(page: Page, chapter: string, stepId: string) {
  await expect(page.getByText(tutorialText(chapter, stepId), { exact: true }).first()).toBeVisible({ timeout: 20_000 });
}

/** Opens a module from the navigation rail. */
export async function railTo(page: Page, module: string) {
  await page.getByRole('tab', { name: module, exact: true }).click();
}

/** The workspace's "Overview" tab: the module's list under the open records. */
export async function overviewTab(page: Page) {
  await page.getByRole('button', { name: 'Overview', exact: true }).click();
}

/** The narrator's "Take me there": goes to the screen a step is about (the app's rail is not reachable from every page). */
export async function takeMeThere(page: Page) {
  const button = page.getByRole('button', { name: 'Take me there' });
  await expect(button).toHaveCount(1);
  await button.click();
}

/** Presses Next on the narrator card (for explanation-only steps). */
export async function next(page: Page) {
  // While the card cross-fades between two steps both of them expose a Next button for a moment.
  const button = page.getByRole('button', { name: 'Next', exact: true });
  await expect(button).toHaveCount(1);
  await button.click();
}

/** Debugging aid: E2E_DUMP=1 writes the accessibility tree and a screenshot to e2e/dump/<tag>.* */
export async function dump(page: Page, tag: string) {
  if (!process.env.E2E_DUMP) return;
  fs.mkdirSync(path.resolve(__dirname, '../dump'), { recursive: true });
  fs.writeFileSync(path.resolve(__dirname, `../dump/${tag}.txt`), await tree(page));
  await page.screenshot({ path: path.resolve(__dirname, `../dump/${tag}.png`) });
}

/** Closes a finished chapter's card by starting the next chapter. */
export async function startNextChapter(page: Page) {
  const button = page.getByRole('button', { name: 'Start next chapter' });
  await expect(button).toBeVisible();
  await button.click();
}
