# Browser end-to-end tests

Drives the **Flutter web build** in headless Chromium against a **real API and PostgreSQL**,
the way a user would. `tests/tutorial.spec.ts` plays the story-mission tutorial chapter by
chapter (ADR 0045): each step waits for the narrator card to show that step (its title is read
from `app/lib/l10n/app_en.arb`), does what the step asks through the UI, and the tutorial's own
completion detection moves it on, so a broken screen or API path stops the run at that step.

## Run

Needs Typst on the PATH (or `TYPST_BIN`) for the last steps of chapter 9, where the API makes the order
confirmation PDF: without it the walk ends at "Send order confirmation" and says so. Also needs PostgreSQL running (default `postgresql://tradocraft:tradocraft@localhost`, a superuser or
a role that can create databases; override with `E2E_PG_URL`), Node 22 and Flutter 3.50.

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
  editing connection a moment after the click, so typing is paced and verified.
* After picking from a search list, the next search needs a re-focus (`searchPick` retries).
* Drop-down options appear as `menuitem` roles shortly after the menu opens (`choose`).
* On record pages (a product, a supplier...) the navigation rail and the workspace tab strip are
  missing from the accessibility tree although they are on screen. `railTo` and `overviewTab`
  click at their fixed positions, so the viewport (1400x1700) must not change.
* While the narrator card is showing, the product suggestions in the "New purchase order"
  dialog do not open; the test pauses the narrator around that dialog.
* Chapter 3 says "choose the location MAIN". The seed of an older `main` had no warehouse, so the test
  creates it through the API when it is missing (the seed now has it).
* The quantity input of a quotation line has no accessible name, so the test clicks it by position.
* The Complete dialog of a production order needs a "Put into" location that the tutorial step does
  not mention.
