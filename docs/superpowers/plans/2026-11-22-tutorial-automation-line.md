# Automation Product Line Tutorial, Product Media SVG, & PLC Licensing Configurator Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the TradoCraft tutorial around a realistic industrial automation product line (conveyor belts with 1-phase/3-phase motors, VFDs, PLCs with parallel output licensing 10/30/50/100, RS-485 expansion modules & master controller, RS-485 displays with I2C swipe card & temperature sensors, IR & 4–20 mA sensors, and PowerFET-operated solenoids), add `image/svg+xml` support to Product Media, add the PLC licensing & I/O rules to the configurator, remove `TUT-` product prefixes and `supports_24v_polarized_2wire`, and organize the new hardware into dedicated tutorial chapters.

**Architecture:**
1. **Backend (`crates/core`, `crates/products`)**: Reuse the SVG XML/active-content validator in `crates/core/src/logo.rs` inside `crates/core/src/files.rs` so `image/svg+xml` is accepted in `stage_media_stream` / `store_media` for product media (`crates/products/src/media.rs`).
2. **Configurator (`seed/configurators/conveyor_line.json`, `crates/configurator`)**: Extend the conveyor line configurator with PLC output counting, parallel licensing tiers (10 base, upgradable to 30/50/100), RS-485 expansion modules, RS-485 displays with I2C peripherals, and master network controller rules.
3. **Frontend (`app/lib/features/products`, `app/lib/features/tutorial`, `app/lib/l10n`)**: Render `image/svg+xml` in `MediaTab` via `flutter_svg`, add a parameterized `ConveyorAssemblySvg` preview (with/without motor), restructure `allMissions` with dedicated chapters for Conveyors & Motors, PLCs & Parallel Licensing, RS-485 Displays & I2C, and Sensors & PowerFET Devices, remove `TUT-` product prefixes and `supports_24v_polarized_2wire`, and update all 5 ARB localization files, Flutter tests, and Playwright E2E tests.

**Tech Stack:** Rust (`axum`, `quick_xml`, `sqlx`), PostgreSQL, Flutter/Dart (`flutter_svg`, `flutter_riverpod`), Typst/Configurators JSON, Playwright.

## Global Constraints

- Work strictly inside `.claude/worktrees/tutorial-automation-line` (`feat/tutorial-automation-line` branch).
- **No `TUT-` prefix** on tutorial product SKUs.
- **No `supports_24v_polarized_2wire`** attribute anywhere in the tutorial, localizations, docs, or tests.
- All 5 ARB languages (`en`, `nl`, `fr`, `de`, `es`) must remain complete for every tutorial key.

---

## Workstream A: `image/svg+xml` Support in Product Media

### Task A1: Expose SVG validation & accept `image/svg+xml` in `core::files`
**Files:**
- Modify: `crates/core/src/logo.rs`
- Modify: `crates/core/src/files.rs`
- Modify: `crates/products/src/media.rs`

- [ ] **Step 1:** In `crates/core/src/logo.rs`, make `svg_problem(bytes: &[u8]) -> Option<Option<String>>` `pub(crate)` (or `pub`) so `files.rs` can validate SVG uploads for well-formed XML and no active content (`<script>`, event handlers, external refs).
- [ ] **Step 2:** In `crates/core/src/files.rs`, add `image/svg+xml` recognition to `sniff_image` / `sniff_media` and `store_media` / `stage_media_stream` (handling text-based `<svg` / `<?xml` headers and running `logo::svg_problem` on SVG payloads with `MAX_FILE_BYTES` cap).
- [ ] **Step 3:** Update `crates/products/src/media.rs` doc comments on `upload_media` to reflect SVG support; keep `default_images` scoped to `image/jpeg` and `image/png` for Typst PDF embedding.
- [ ] **Step 4:** Add Rust unit/integration tests verifying valid SVG upload succeeds and active/malformed SVG is rejected with `422`.

### Task A2: Render `image/svg+xml` in Flutter Product Media
**Files:**
- Modify: `app/lib/features/products/media_tab.dart`
- Modify: `app/lib/features/products/product_form.dart`
- Test: `app/test/product_media_test.dart`

- [ ] **Step 1:** In `media_tab.dart`, add `bool get isSvg => contentType == 'image/svg+xml';` to `ProductMediaItem` and render `SvgPicture.memory(bytes)` (from `flutter_svg`) in both `_tile` and the `_open` preview dialog when `m.isSvg` is true.
- [ ] **Step 2:** Ensure `product_form.dart` and `media_tab.dart` allow picking/uploading `.svg` files cleanly.
- [ ] **Step 3:** Add widget test coverage in `app/test/product_media_test.dart` for `image/svg+xml` rendering.

---

## Workstream B: Configurator Rule for Parallel PLC Output Licensing & Buses

### Task B1: Extend `conveyor_line.json` with PLC, Parallel Licensing, RS-485 & I2C
**Files:**
- Modify: `seed/configurators/conveyor_line.json`
- Test: `crates/configurator/src/tests.rs` (or integration test)

- [ ] **Step 1:** Add project/group fields & computed expressions in `seed/configurators/conveyor_line.json`:
  - `plc_licensed_outputs`: choice (`10`, `30`, `50`, `100`; default `10`, label `"PLC licensed outputs"`).
  - `networked_master`: boolean (`"Master controller (networked PLCs)"`).
  - `rs485_displays`: integer/boolean per hall/line for `DISP-RS485`, plus `i2c_swipe_card` (`MOD-I2C-SWIPE`) and `i2c_temp_sensor` (`SENS-I2C-TEMP`).
  - Per-segment or per-line sensor/actuator flags (`ir_sensor`, `analog_4_20ma`, `reject_pusher`, `label_stamper`).
- [ ] **Step 2:** Add computed `outputs_required` (counting motor drives, PowerFET solenoids, and indicators) and emit:
  - `PLC-BASE` (standard 10-output PLC)
  - Parallel license upgrade SKU (`PLC-LIC-30`, `PLC-LIC-50`, or `PLC-LIC-100`) when `plc_licensed_outputs > 10`
  - `PLC-EXP-RS485` expansion modules when physical I/O exceeds base PLC channels
  - `PLC-MASTER` when `networked_master` is enabled
  - `DISP-RS485`, `MOD-I2C-SWIPE`, `SENS-I2C-TEMP`, `SENS-IR-24V`, `SENS-420MA`, `SOL-PUSH`, `SOL-LABEL`
- [ ] **Step 3:** Add validation rule `plc_license_insufficient` (error/warning when `outputs_required > plc_licensed_outputs`) advising upgrade to 30, 50, or 100 outputs.
- [ ] **Step 4:** Run `cargo test -p tradocraft-configurator` to verify compilation and evaluation.

---

## Workstream C: Tutorial Product Line, SVG Assembly & Dedicated Chapters

### Task C1: Conveyor Assembly SVG Widget (With / Without Motor)
**Files:**
- Create: `app/lib/features/tutorial/conveyor_svg.dart`

- [ ] **Step 1:** Build `ConveyorAssemblySvg` (using `flutter_svg` `SvgPicture.string`) generating a schematic SVG of the conveyor belt assembly with interactive/parameterized toggles:
  - `withMotor`: `false` (belt + rollers + frame only) vs `true` (adds mounted motor + coupling)
  - `motorType`: `'1p'` (`MOT-1P-037`) vs `'3p'` (`MOT-3P-055` + `VFD-3P-055`)
  - Optional overlays for `SENS-IR-24V`, `SENS-420MA`, `SOL-PUSH`, `SOL-LABEL`
- [ ] **Step 2:** Provide a helper returning the SVG `Uint8List` bytes so the tutorial can also demonstrate uploading/viewing the SVG in Product Media.

### Task C2: Dedicated Tutorial Chapters & Clean Product SKUs
**Files:**
- Modify: `app/lib/features/tutorial/missions.dart`
- Modify: `app/lib/features/tutorial/missions_attributes.dart`
- Modify: `app/lib/features/tutorial/missions_purchasing.dart`
- Modify: `app/lib/features/tutorial/missions_production.dart`
- Modify: `app/lib/features/tutorial/missions_sales.dart`
- Modify: `app/lib/features/tutorial/missions_helpdesk.dart`
- Modify: `app/lib/features/tutorial/simulated_mail.dart`
- Modify: `app/lib/features/tutorial/overlay.dart` (render `ConveyorAssemblySvg` on conveyor chapter steps)

- [ ] **Step 1:** Replace all `TUT-*` product codes with clean SKUs (`CONV-BELT-1M`, `MOT-1P-037`, `MOT-3P-055`, `VFD-3P-055`, `PLC-BASE`, `PLC-LIC-30`, `PLC-LIC-50`, `PLC-LIC-100`, `PLC-EXP-RS485`, `PLC-MASTER`, `DISP-RS485`, `MOD-I2C-SWIPE`, `SENS-I2C-TEMP`, `SENS-IR-24V`, `SENS-420MA`, `SOL-PUSH`, `SOL-LABEL`).
- [ ] **Step 2:** Split/add dedicated chapters in `allMissions`:
  1. `welcome` — Environment, tabs, controls, opening Products
  2. `conveyors` — Conveyor belts (`CONV-BELT-1M`), 1-phase & 3-phase motors (`MOT-1P-037`, `MOT-3P-055`, `VFD-3P-055`), SVG assembly preview (with/without motor) + SVG upload to Product Media, and assembly BOM
  3. `plc` — `PLC-BASE` (10 outputs), parallel licensing upgrades (`PLC-LIC-30`, `PLC-LIC-50`, `PLC-LIC-100`), RS-485 expansion (`PLC-EXP-RS485`), Master Controller (`PLC-MASTER`), and configurator rule
  4. `displays` — `DISP-RS485` over RS-485 bus, with I2C `MOD-I2C-SWIPE` (swipe card) and `SENS-I2C-TEMP` (temperature measurement)
  5. `sensors` — `SENS-IR-24V` (digital input), `SENS-420MA` (4–20 mA analog), and PowerFET-driven `SOL-PUSH` / `SOL-LABEL`
  6. `suppliers`, `buying`, `invoices`, `manufacturing`, `prices`, `customer`, `quotation`, `change`, `helpdesk` — updated to use the new conveyor/PLC products
  7. `attributes` — updated for `PLC-BASE`, **removing `supports_24v_polarized_2wire`** and defining `relay_count`, `fet_count`, `digital_inputs`, `analog_4_20ma_inputs`, `rs485_ports`, `i2c_bus`, and `licensed_outputs_tier`.

### Task C3: Localization, Documentation & Tests
**Files:**
- Modify: `app/lib/features/tutorial/strings.dart`
- Modify: `app/lib/l10n/app_{en,nl,fr,de,es}.arb` + regenerate `app_localizations*.dart`
- Modify: `docs/tutorial-chapter-dependencies.md`
- Modify: `app/test/tutorial_*.dart`
- Modify: `e2e/tests/tutorial.spec.ts`

- [ ] **Step 1:** Update `strings.dart` and all 5 ARB files with keys for the new chapters and remove `supports_24v_polarized_2wire` keys. Run `flutter gen-l10n`.
- [ ] **Step 2:** Update `docs/tutorial-chapter-dependencies.md` to match the new chapter list, SKUs, and dependencies.
- [ ] **Step 3:** Update Flutter tutorial tests and Playwright `e2e/tests/tutorial.spec.ts` (including verifying `image/svg+xml` upload/preview, configurator licensing validation, and the new dedicated chapters).
- [ ] **Step 4:** Run verification:
  - `cargo test -p tradocraft-core -p tradocraft-products -p tradocraft-configurator`
  - `flutter test test/tutorial_*.dart test/product_media_test.dart`
  - `npx playwright test tests/tutorial.spec.ts` (where environment/DB is running).
