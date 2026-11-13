// Playwright globalSetup for headed Firefox runs: proves, before the long run, that the page really is
// as tall as the tests assume. A real window cannot extend below the screen, and a click in the part
// that is not there is reported as successful but never arrives. So this opens a throw-away window
// with the same settings as the suite, clicks a button in the bottom-right corner of the 1400x1700
// viewport and checks that it received the click. It only warns, it never fails the run.
const { firefox } = require('@playwright/test');

module.exports = async function globalSetup() {
  const raw = process.env.E2E_FIT_PLAN;
  const plan = raw ? JSON.parse(raw) : undefined;
  const prefs = plan ? { 'layout.css.devPixelsPerPx': String(plan.scale) } : {};
  let browser;
  try {
    browser = await firefox.launch({ headless: false, firefoxUserPrefs: prefs });
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
  } catch (e) {
    console.warn(`e2e: window check skipped (${e.message.split('\n')[0]})`);
  } finally {
    await browser?.close().catch(() => {});
  }
};
