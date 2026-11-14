// Checks of the .env URL parsing: npm run test:lib (node --test). Not part of CI.
const test = require('node:test');
const assert = require('node:assert');
const { splitPgUrl } = require('./lib.cjs');

test('path database, query stripped from the server part', () => {
  assert.deepStrictEqual(splitPgUrl('postgresql://u:p@h:5432/real?sslmode=disable'), { server: 'postgresql://u:p@h:5432', db: 'real' });
});
test('path wins over dbname', () => {
  assert.strictEqual(splitPgUrl('postgres://u@h/real?dbname=other').db, 'real');
});
test('dbname query parameter', () => {
  assert.deepStrictEqual(splitPgUrl('postgresql://u:p@h/?dbname=foo'), { server: 'postgresql://u:p@h', db: 'foo' });
  assert.deepStrictEqual(splitPgUrl('postgres://h?sslmode=x&dbname=foo'), { server: 'postgres://h', db: 'foo' });
});
test('percent-encoded names', () => {
  assert.strictEqual(splitPgUrl('postgres://h?dbname=my%20db%2Fx').db, 'my db/x');
  assert.strictEqual(splitPgUrl('postgres://h/a%2Bb').db, 'a+b');
});
test('no database', () => {
  assert.strictEqual(splitPgUrl('postgres://u:p@h:5432').db, undefined);
  assert.strictEqual(splitPgUrl('postgres://h?dbname=').db, undefined);
  assert.strictEqual(splitPgUrl('not a url'), undefined);
});

// ---- fit-to-screen mode ----
const { parseXrandr, parseWorkArea, parseWindowSpec, detectScreen, fitPlan, fitWanted, withDeadline } = require('./lib.cjs');
const XRANDR = `Screen 0: minimum 320 x 200, current 3840 x 1080, maximum 16384 x 16384
HDMI-1 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 527mm x 296mm
   1920x1080     60.00*+
eDP connected primary 1366x768+0+0 (normal left inverted right x axis y axis) 344mm x 193mm
   1366x768     144.15*+
DP-1 disconnected (normal left inverted right x axis y axis)
`;

test('xrandr: the primary output wins, else the first connected one', () => {
  assert.deepStrictEqual(parseXrandr(XRANDR), { width: 1366, height: 768 });
  assert.deepStrictEqual(parseXrandr(XRANDR.replace(' primary', '')), { width: 1920, height: 1080 });
  assert.deepStrictEqual(parseXrandr('eDP connected 1080x1920+0+0 left (normal) 1mm x 1mm'), { width: 1080, height: 1920 });
  assert.strictEqual(parseXrandr('DP-1 disconnected\n'), undefined);
  assert.strictEqual(parseXrandr(''), undefined);
});
test('work area from xprop, window spec', () => {
  assert.deepStrictEqual(parseWorkArea('_NET_WORKAREA(CARDINAL) = 0, 0, 1920, 1040, 0, 0, 1920, 1040'), { width: 1920, height: 1040 });
  assert.strictEqual(parseWorkArea('_NET_WORKAREA:  not found.'), undefined);
  assert.deepStrictEqual(parseWindowSpec('1280x720'), { width: 1280, height: 720 });
  assert.deepStrictEqual(parseWindowSpec(' 2560X1440 '), { width: 2560, height: 1440 });
  assert.throws(() => parseWindowSpec('wide'), /E2E_WINDOW/);
});
test('screen detection: override, xrandr with work area, xrandr alone, fallbacks', () => {
  const exec = (cmd) => (cmd === 'xrandr' ? XRANDR : '_NET_WORKAREA(CARDINAL) = 0, 0, 1366, 728');
  assert.deepStrictEqual(detectScreen({ E2E_WINDOW: '1600x900' }, 'linux', exec), { width: 1600, height: 900, workArea: false, source: 'E2E_WINDOW' });
  assert.deepStrictEqual(detectScreen({ DISPLAY: ':0' }, 'linux', exec), { width: 1366, height: 728, workArea: true, source: 'xrandr + _NET_WORKAREA' });
  // a work area spanning several monitors is not this screen's
  const wide = (cmd) => (cmd === 'xrandr' ? XRANDR : '_NET_WORKAREA(CARDINAL) = 0, 0, 3840, 1040');
  assert.deepStrictEqual(detectScreen({ DISPLAY: ':0' }, 'linux', wide), { width: 1366, height: 768, workArea: false, source: 'xrandr' });
  const none = detectScreen({}, 'linux', () => '');
  assert.deepStrictEqual([none.width, none.height, none.source], [1920, 1080, 'fallback']);
  assert.match(none.note, /Wayland/);
  assert.strictEqual(detectScreen({}, 'darwin', () => '').source, 'fallback');
  assert.deepStrictEqual(detectScreen({}, 'win32', () => '1920x1040\r\n'), { width: 1920, height: 1040, workArea: true, source: 'powershell WorkingArea' });
});
test('fit plan: scale, window and overrides', () => {
  // 1920x1080 without work area: 960 usable height / (1700+88) -> 0.53
  const p = fitPlan({ width: 1920, height: 1080, workArea: false }, {});
  assert.strictEqual(p.scale, 0.53);
  assert.deepStrictEqual(p.window, { width: 742, height: 948 });
  assert.deepStrictEqual(p.css, { width: 1400, height: 1700 });
  assert.ok(p.fits);
  // the work area allows a larger window
  assert.strictEqual(fitPlan({ width: 1920, height: 1040, workArea: true }, {}).scale, 0.57);
  // a huge screen is capped at 1
  assert.strictEqual(fitPlan({ width: 3840, height: 2400, workArea: false }, {}).scale, 1);
  // a narrow screen is limited by the width
  assert.strictEqual(fitPlan({ width: 800, height: 4000, workArea: false }, {}).scale, 0.54);
  // overrides
  assert.strictEqual(fitPlan({ width: 1920, height: 1080 }, { E2E_SCALE: '0.4' }).scale, 0.4);
  assert.throws(() => fitPlan({ width: 1920, height: 1080 }, { E2E_SCALE: '0.2' }), /E2E_SCALE/);
  assert.throws(() => fitPlan({ width: 1920, height: 1080 }, { E2E_SCALE: '1.5' }), /E2E_SCALE/);
  assert.throws(() => fitPlan({ width: 1920, height: 1080 }, { E2E_SCALE: 'x' }), /E2E_SCALE/);
  assert.strictEqual(fitPlan({ width: 1920, height: 1080 }, { E2E_SCALE: '1' }).fits, false);
});
test('fit applies to headed Firefox only, E2E_FIT=0 disables it', () => {
  assert.strictEqual(fitWanted({ E2E_HEADED: '1', E2E_BROWSER: 'firefox' }), true);
  assert.strictEqual(fitWanted({ E2E_HEADED: '1', E2E_BROWSER: 'firefox', E2E_FIT: '0' }), false);
  assert.strictEqual(fitWanted({ E2E_BROWSER: 'firefox' }), false);
  assert.strictEqual(fitWanted({ E2E_HEADED: '1' }), false);
  assert.strictEqual(fitWanted({}), false);
});

test('withDeadline: finishes in time, rejects in time, times out, swallows a late rejection', async () => {
  assert.deepStrictEqual(await withDeadline(async () => 7, 1000), { timedOut: false, value: 7 });
  await assert.rejects(withDeadline(async () => { throw new Error('boom'); }, 1000), /boom/);
  await assert.rejects(withDeadline(() => { throw new Error('sync'); }, 1000), /sync/);
  assert.deepStrictEqual(await withDeadline(() => new Promise(() => {}), 20), { timedOut: true });
  // the work rejects after the deadline: no unhandled rejection
  const unhandled = [];
  const onUnhandled = (e) => unhandled.push(e);
  process.on('unhandledRejection', onUnhandled);
  const r = await withDeadline(() => new Promise((_, rej) => setTimeout(() => rej(new Error('late')), 40)), 10);
  assert.deepStrictEqual(r, { timedOut: true });
  await new Promise((res) => setTimeout(res, 100));
  process.off('unhandledRejection', onUnhandled);
  assert.deepStrictEqual(unhandled, []);
});
test('withDeadline clears its timer when the work finishes', async () => {
  const real = global.clearTimeout;
  let cleared = 0;
  global.clearTimeout = (t) => { cleared++; return real(t); };
  try {
    await withDeadline(async () => 1, 60_000);
  } finally {
    global.clearTimeout = real;
  }
  assert.strictEqual(cleared, 1);
});
