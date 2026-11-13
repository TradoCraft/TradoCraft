# Browser end-to-end tests

Drives the **Flutter web build** in a browser (Firefox or Chromium) against a **real API and PostgreSQL**,
the way a user would. `tests/tutorial.spec.ts` plays the story-mission tutorial chapter by
chapter (ADR 0045): each step waits for the narrator card to show that step (its title is read
from `app/lib/l10n/app_en.arb`), does what the step asks through the UI, and the tutorial's own
completion detection moves it on, so a broken screen or API path stops the run at that step.

## Run

One-time setup, from the repository root:

```bash
cargo build -p tradocraft-api
(cd app && flutter build web --release --no-web-resources-cdn)   # no CDN: works without gstatic
cd e2e && npm ci
npx playwright install firefox                                   # local viewing; CI installs chromium
```

Also needed: PostgreSQL running (a superuser or a role that can create databases), Typst on the PATH
(or `TYPST_BIN`), Node 22 and Flutter 3.50. From chapter 9's "Send order confirmation" on, the API makes the
order confirmation PDF with Typst; without it the test **skips** locally and **fails** on CI, so a run that
stopped short can never count as a pass.

Then, from `e2e/`:

```bash
npm run test:watch   # Firefox, visible window, every action slowed by 150 ms
npm run test:ui      # Firefox in Playwright UI mode: scaled live view plus a timeline
npm test             # headless Chromium, as CI does (needs: npx playwright install --with-deps chromium)
```

`test:watch` and `test:ui` go through `run.mjs`, which first checks that the ports are free and that the API
binary, the web build and Typst exist (one line per missing thing, with the command to fix it), then runs
`playwright test`. Extra arguments are passed on (`npm run test:watch -- -g "chapter 3"`) and the exit code is
returned. Nothing is ever killed: if a port is taken the message names what listens there.

`playwright.config.ts` recreates the database on every run, starts the API as a `tutorial` environment
(dev auth, demo seed) and serves the web build.

| Variable | Default | Meaning |
| --- | --- | --- |
| `E2E_BROWSER` | `chromium` (`firefox` for the scripts above) | `firefox` or `chromium`; anything else is an error |
| `E2E_HEADED` | off (`1` for `test:watch`) | `1` shows the browser window |
| `E2E_SLOWMO` | `0` (`150` for `test:watch`) | milliseconds to wait after every action |
| `E2E_PG_URL` | see below | PostgreSQL server, `scheme://user:pass@host:port` |
| `E2E_API_PORT`, `E2E_WEB_PORT` | `18080`, `18088` | change both (and `E2E_DB_NAME`) to run next to another run |
| `E2E_DB_NAME` | `tradocraft_e2e` | the database that is dropped and recreated on every run |
| `E2E_API_BIN` | `target/debug/tradocraft-api` | API binary |
| `E2E_SKIP_PREFLIGHT` | unset | `1` skips the checks of `run.mjs` |

Each variable overrides the defaults of the npm scripts too, for example
`E2E_SLOWMO=400 npm run test:watch`.

PostgreSQL login, first match wins: `E2E_PG_URL`; the server part of `DATABASE_URL` in the repository `.env`
(only that key is read, never printed; the database name and query string are dropped); the default
`postgresql://tradocraft:tradocraft@localhost`, which is what CI uses (no `.env` there). The database that is
dropped is always `E2E_DB_NAME`, and the run refuses a name equal to the database in the `.env`'s
`DATABASE_URL`, so a mis-set variable cannot drop the real one.

The viewport is deliberately tall (1400x1700): the navigation rail only exposes the items that are on screen,
so a short window cannot reach every module. On a laptop screen the headed window is therefore cropped; UI mode
scales the page to fit and is the better way to watch.

`E2E_DUMP=1` writes the accessibility tree and a screenshot of `dump(page, tag)` calls to `e2e/dump/`.
Screenshots of a failed run are in `e2e/test-results/` (CI uploads that folder as the `e2e-failures` artifact).

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
* The purchase order form lists the supplier's goods as rows whose checkbox has no accessible name; the test
  narrows the list with the "Filter goods" box and types the quantity (which ticks the row).
* The tutorial environment is seeded without a warehouse. Chapter 3 teaches creating one (the warehouse
  MAIN; it brings its location MAIN) before the goods are received, and chapters 5 and 9 have the same
  step in front of "Complete", which is skipped when a warehouse with a location exists. The test creates
  it through the UI in chapter 3 and relies on the skip afterwards; the database is recreated on every run.

Things that used to need workarounds here and are fixed in the app (keep them fixed: each has a test
in `app/test`): the narrator card closing suggestion lists, the navigation rail and tab strip
vanishing from the accessibility tree on record pages, and the unnamed quantity input of a quotation
line.
