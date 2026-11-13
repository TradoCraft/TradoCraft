// Playwright globalSetup for headed Firefox runs: proves, before the long run, that the page really is
// as tall as the tests assume. A real window cannot extend below the screen, and a click in the part
// that is not there is reported as successful but never arrives. So this opens a throw-away window
// with the same settings as the suite, clicks a button in the bottom-right corner of the 1400x1700
// viewport and checks that it received the click. It only warns, it never fails the run, and the whole
// probe (launch to close) runs under one deadline (E2E_FIT_CHECK_TIMEOUT ms, default 30000) so a hung
// headed browser cannot block the suite.
const { firefox } = require('@playwright/test');
const { withDeadline } = require('./lib.cjs');

/** The probe itself; `launch` is injectable for tests. Registers the browser in `state` as soon as it exists. */
async function probe(launch, plan, state) {
  const prefs = plan ? { 'layout.css.devPixelsPerPx': String(plan.scale) } : {};
  const browser = await launch({ headless: false, firefoxUserPrefs: prefs });
  state.browser = browser;
  if (state.abandoned) {
    // the deadline passed while the browser was starting: nobody waits for it any more
    Promise.resolve(browser.close()).catch(() => {});
    return;
  }
  const page = await browser.newPage({ viewport: { width: 1400, height: 1700 } });
  await page.setContent(
    '<body style="margin:0"><button id="b" style="position:fixed;right:0;bottom:0;width:200px;height:120px" ' +
      'onclick="this.dataset.hit=1">corner</button></body>',
  );
  await page.waitForTimeout(500);
  const [w, h] = await page.evaluate(() => [innerWidth, innerHeight]);
  await page.mouse.click(1400 - 60, 1700 - 40);
  await page.waitForTimeout(200);
  const hit = await page.evaluate(() => document.getElementById('b').dataset.hit === '1');
  const outer = await page.evaluate(() => [outerWidth, outerHeight]);
  const how = plan ? `fit mode, scale ${plan.scale}` : 'fit mode off';
  const cropped = outer[0] < 1400 || outer[1] < 1744; // the window (in CSS px) must hold the page and Firefox's toolbar
  if (w < 1395 || h < 1695 || !hit || cropped) {
    console.warn(
      `e2e: WARNING the page is not really 1400x1700 in this window (${how}): CSS viewport ${w}x${h}, ` +
        `window ${outer[0]}x${outer[1]}, click in the bottom-right corner ${hit ? 'arrived' : 'was LOST'}${cropped ? ', the window is smaller than the page' : ''}.\n` +
        '  Clicks near the bottom will be lost and the run will fail at a random step. Options: unset E2E_FIT=0, a smaller E2E_SCALE\n' +
        '  (e.g. E2E_SCALE=0.45), E2E_WINDOW=<W>x<H> if the screen size was misdetected, or run headless (drop E2E_HEADED).',
    );
  } else {
    console.log(`e2e: window check ok (${how}): CSS viewport ${w}x${h}, window ${outer[0]}x${outer[1]}, corner click arrived.`);
  }
  await browser.close(); // inside the deadline: a clean close is part of the probe
  state.browser = undefined;
}

async function check(launch = (o) => firefox.launch(o), env = process.env) {
  const plan = env.E2E_FIT_PLAN ? JSON.parse(env.E2E_FIT_PLAN) : undefined;
  const ms = Number(env.E2E_FIT_CHECK_TIMEOUT ?? 30_000);
  const state = { browser: undefined, abandoned: false };
  try {
    const r = await withDeadline(() => probe(launch, plan, state), Number.isFinite(ms) && ms > 0 ? ms : 30_000);
    if (r.timedOut) {
      state.abandoned = true;
      console.warn(
        `e2e: WARNING window check gave up after ${ms} ms (a headed Firefox that does not answer?); continuing without it. ` +
          'If the run hangs too, try headless (drop E2E_HEADED) or E2E_FIT_CHECK_TIMEOUT=<ms>.',
      );
    }
  } catch (e) {
    console.warn(`e2e: window check skipped (${String(e?.message ?? e).split('\n')[0]})`);
  }
  // Close without waiting: a hung browser may never answer. Also covers the abandoned and failed cases.
  if (state.browser) Promise.resolve(state.browser.close()).catch(() => {});
}

module.exports = async function globalSetup() {
  await check();
};
module.exports.check = check;
