# Browser end-to-end tests

Drives the **Flutter web build** in headless Chromium against a **real API and PostgreSQL**,
the way a user would. `tests/tutorial.spec.ts` plays the story-mission tutorial chapter by
chapter (ADR 0045): each step waits for the narrator card to show that step (its title is read
from `app/lib/l10n/app_en.arb`), does what the step asks through the UI, and the tutorial's own
completion detection moves it on, so a broken screen or API path stops the run at that step.

## Run

Needs Typst on the PATH (or `TYPST_BIN`): from chapter 9's "Send order confirmation" on, the API makes the
order confirmation PDF. Without it the test **skips** locally and **fails** on CI, so a run that stopped
short can never count as a pass. Also needs PostgreSQL running (default
`postgresql://tradocraft:tradocraft@localhost`, a superuser or a role that can create databases; override
with `E2E_PG_URL`), Node 22 and Flutter 3.50.

```bash
cargo build -p tradocraft-api
(cd app && flutter build web --release --no-web-resources-cdn)   # no CDN: works without gstatic
cd e2e && npm ci
npx playwright install --with-deps chromium   # once; --with-deps adds the Linux system libraries
npx playwright test
```

`playwright.config.ts` recreates the database `tradocraft_e2e` on every run, starts the API as a
`tutorial` environment (dev auth, demo seed) on port 18080 and serves the web build on 18088.
`E2E_DUMP=1` writes the accessibility tree and a screenshot of `dump(page, tag)` calls to
`e2e/dump/`.

CI runs this as the `e2e` job (`.github/workflows/ci.yml`).

## Driving Flutter web: what we learned

* Flutter draws to a canvas. The test turns on the accessibility tree (`boot()`), and
  Playwright's role/label selectors work on that.
* `fill()` does not reach Flutter; real key presses do (`typeInto`). Flutter attaches its
  editing connection a moment after the click, so typing is paced and verified, and a failed
  attempt blurs the field first.
* Drop-down options appear as `menuitem` roles shortly after the menu opens (`choose`).
* The navigation rail is a scrolling list that only exposes the items on screen, so the viewport
  is tall (1400x1700) and every module is reachable by role (`railTo`).
* The tutorial environment is seeded without a warehouse. Chapter 3 teaches creating one (the warehouse
  MAIN; it brings its location MAIN) before the goods are received, and chapters 5 and 9 have the same
  step in front of "Complete", which is skipped when a warehouse with a location exists. The test creates
  it through the UI in chapter 3 and relies on the skip afterwards; the database is recreated on every run.

Things that used to need workarounds here and are fixed in the app (keep them fixed: each has a test
in `app/test`): the narrator card closing suggestion lists, the navigation rail and tab strip
vanishing from the accessibility tree on record pages, and the unnamed quantity input of a quotation
line.
