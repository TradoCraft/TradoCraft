# A7 — Helpdesk Ticket Checklists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-ticket checklists, reusable checklist templates (optionally scoped by team/category), idempotent template application (manual and via automation rules), list/detail progress (`done/total`), and a per-team `require_checklist_done` close gate.

**Architecture:** Dedicated relational tables in `helpdesk` (`checklist_templates`, `checklist_template_items`, `ticket_checklist_items`, `ticket_applied_templates`) mirroring `field.job_tasks`, plus a `require_checklist_done` boolean on `helpdesk.teams`. Backend logic lives in a new `crates/helpdesk/src/checklists.rs` module wired into `lib.rs`, `teams.rs`, `tickets.rs`, and `automation.rs`, followed by OpenAPI/Dart client regeneration and Flutter UI updates.

**Tech Stack:** Rust (`axum`, `sqlx`, `utoipa`, `utoipa_axum`), PostgreSQL migrations, Flutter/Dart (`app/`), ARB localization.

## Global Constraints

- Work strictly inside the `.claude/worktrees/a7-ticket-checklists` worktree (`feat/a7-ticket-checklists` branch).
- Mirror `field.job_tasks` (`position`, `description`, `done`, `done_by`, `done_at`) for ticket checklist items.
- Template application is **idempotent append** via `helpdesk.ticket_applied_templates (ticket_id, template_id)` — re-applying the same template is a no-op even if an item was deleted.
- Close gate is **per team** (`helpdesk.teams.require_checklist_done`): reject closing (`status = "closed"`) with `AppError::ConflictCode("checklist_incomplete", ...)` (HTTP 409) when the ticket's team has `require_checklist_done = true` and open checklist items exist. Tickets without a team or merges are not blocked.
- Automatic application is **automation rules only** (`apply_checklist` action with `template_id`).

---

## File Structure

- Create: `migrations/20270219000001_helpdesk_checklists.sql` — schema for templates, template items, ticket items, applied templates, and `teams.require_checklist_done`.
- Create: `crates/helpdesk/src/checklists.rs` — template CRUD, ticket checklist CRUD, reordering, `apply_template_to_ticket`, and unit/integration tests.
- Modify: `crates/helpdesk/src/lib.rs` — export `pub mod checklists;` and merge `checklists::router()`.
- Modify: `crates/helpdesk/src/teams.rs` — expose and persist `require_checklist_done` on `Team` / `TeamInput`.
- Modify: `crates/helpdesk/src/tickets.rs` — add `checklist_total` & `checklist_done` to `Ticket` and `TICKET_COLS`; enforce close gate in `set_status`.
- Modify: `crates/helpdesk/src/automation.rs` — add `apply_checklist` to `ACTIONS`, `RuleAction`, `plan_action`, `apply_change`, and `validate_action`.
- Regenerate: `app/lib/api/generated/...` via `scripts/generate-api-client.sh`.
- Modify: `app/lib/l10n/app_{en,nl,de,fr,es}.arb` and regenerate `app_localizations*.dart`.
- Modify: `app/lib/features/helpdesk/helpdesk_settings_page.dart` — team `require_checklist_done` switch + checklist templates management UI.
- Modify: `app/lib/features/helpdesk/automation_page.dart` — `apply_checklist` action option + template picker.
- Modify: `app/lib/features/helpdesk/tickets_page.dart` — `done/total` checklist progress badge when `checklistTotal > 0`.
- Modify: `app/lib/features/helpdesk/ticket_screen.dart` — Checklist card/section (apply template, toggle, add, edit, reorder, delete) + 409 conflict message on close.
- Create/Modify: `app/test/helpdesk_checklist_test.dart` — Flutter widget tests for checklist UI & list badge.

---

### Task 1: Database Migration & Team `require_checklist_done` Setting

**Files:**
- Create: `migrations/20270219000001_helpdesk_checklists.sql`
- Modify: `crates/helpdesk/src/teams.rs`

**Interfaces:**
- Produces: SQL tables `helpdesk.checklist_templates`, `helpdesk.checklist_template_items`, `helpdesk.ticket_checklist_items`, `helpdesk.ticket_applied_templates`, and column `helpdesk.teams.require_checklist_done`.
- Produces: `Team.require_checklist_done: bool` and `TeamInput.require_checklist_done: bool` in `crates/helpdesk/src/teams.rs`.

- [ ] **Step 1: Write the SQL migration**

Create `migrations/20270219000001_helpdesk_checklists.sql`:

```sql
-- Helpdesk ticket checklists (A7): reusable templates, per-ticket checklist items,
-- idempotent template application tracking, and per-team close gate.

ALTER TABLE helpdesk.teams
    ADD COLUMN require_checklist_done boolean NOT NULL DEFAULT false;

CREATE TABLE helpdesk.checklist_templates (
    id          uuid PRIMARY KEY,
    name        text NOT NULL CHECK (btrim(name) <> ''),
    team_id     uuid REFERENCES helpdesk.teams(id) ON DELETE SET NULL,
    category    text,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE helpdesk.checklist_template_items (
    id          uuid PRIMARY KEY,
    template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE,
    position    integer NOT NULL,
    description text NOT NULL CHECK (btrim(description) <> ''),
    UNIQUE (template_id, position)
);

CREATE TABLE helpdesk.ticket_checklist_items (
    id          uuid PRIMARY KEY,
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    template_id uuid REFERENCES helpdesk.checklist_templates(id) ON DELETE SET NULL,
    position    integer NOT NULL,
    description text NOT NULL CHECK (btrim(description) <> ''),
    done        boolean NOT NULL DEFAULT false,
    done_by     uuid REFERENCES core.users(id),
    done_at     timestamptz,
    UNIQUE (ticket_id, position)
);

CREATE INDEX ticket_checklist_items_ticket_idx
    ON helpdesk.ticket_checklist_items (ticket_id, position);

CREATE TABLE helpdesk.ticket_applied_templates (
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ticket_id, template_id)
);
```

- [ ] **Step 2: Write a failing test in `crates/helpdesk/src/teams.rs` for `require_checklist_done`**

Add a test in `crates/helpdesk/src/teams.rs` verifying `TeamInput { ..., require_checklist_done: true }` persists and loads `team.require_checklist_done == true` (and defaults to `false`).

- [ ] **Step 3: Run the test to verify it fails**

Run: `cargo test -p tradocraft-helpdesk teams`
Expected: FAIL (compile error: `require_checklist_done` field does not exist on `Team` / `TeamInput`).

- [ ] **Step 4: Update `crates/helpdesk/src/teams.rs`**

Add `#[serde(default)] pub require_checklist_done: bool` to `TeamInput`, `pub require_checklist_done: bool` to `Team` and `TeamRow`, update `load_teams` `SELECT` to include `require_checklist_done`, and update `INSERT` / `UPDATE` queries in `create_team` / `update_team` to bind `require_checklist_done`.

- [ ] **Step 5: Run tests to verify pass**

Run: `cargo test -p tradocraft-helpdesk teams`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add migrations/20270219000001_helpdesk_checklists.sql crates/helpdesk/src/teams.rs
git commit -m "feat(helpdesk): add checklist schema and team require_checklist_done setting"
```

---

### Task 2: Checklist Templates & Ticket Checklist Module (`crates/helpdesk/src/checklists.rs`)

**Files:**
- Create: `crates/helpdesk/src/checklists.rs`
- Modify: `crates/helpdesk/src/lib.rs`

**Interfaces:**
- Consumes: `helpdesk.checklist_templates`, `helpdesk.checklist_template_items`, `helpdesk.ticket_checklist_items`, `helpdesk.ticket_applied_templates`, `crate::tickets::CATEGORIES`.
- Produces:
  - `pub fn router() -> OpenApiRouter<AppState>`
  - `pub async fn apply_template_to_ticket(conn: &mut PgConnection, ticket_id: Uuid, template_id: Uuid, require_active: bool) -> AppResult<Vec<ChecklistItem>>`
  - Endpoints:
    - `GET /helpdesk/checklist-templates`
    - `POST /helpdesk/checklist-templates`
    - `PUT /helpdesk/checklist-templates/{id}`
    - `DELETE /helpdesk/checklist-templates/{id}`
    - `GET /helpdesk/tickets/{id}/checklist`
    - `POST /helpdesk/tickets/{id}/checklist`
    - `PATCH /helpdesk/tickets/{id}/checklist/{item_id}`
    - `DELETE /helpdesk/tickets/{id}/checklist/{item_id}`
    - `POST /helpdesk/tickets/{id}/checklist/apply-template`

- [ ] **Step 1: Write failing tests in `crates/helpdesk/src/checklists.rs`**

Write `#[sqlx::test]` tests covering:
1. Template CRUD & validation (empty name rejected, invalid category rejected, ordered items preserved).
2. Ticket checklist add, toggle `done` (`done_by` and `done_at` set when `true`, cleared when `false`), edit description, reorder `position`, and delete.
3. `apply_template_to_ticket`: appends items at `max(position) + 1`, records `(ticket_id, template_id)`, and is idempotent on second call even after deleting one of the applied items.

- [ ] **Step 2: Implement `crates/helpdesk/src/checklists.rs` and mount in `crates/helpdesk/src/lib.rs`**

Implement DTOs (`ChecklistTemplate`, `ChecklistTemplateItem`, `ChecklistTemplateInput`, `ChecklistTemplateItemInput`, `ChecklistItem`, `AddChecklistItemInput`, `UpdateChecklistItemInput`, `ApplyTemplateInput`) with `#[derive(ToSchema)]`, handlers with `#[utoipa::path]`, permission checks (`helpdesk.manage` for templates, `helpdesk.use` for ticket checklist), and `apply_template_to_ticket`.
In `crates/helpdesk/src/lib.rs`, add `pub mod checklists;` and `.merge(checklists::router())`.

Note on reordering in `PATCH /helpdesk/tickets/{id}/checklist/{item_id}`:
When `position` is provided, re-sequence all items of the ticket in Rust into the new order, then update positions in two passes (or negative temporary positions `-(idx + 1)` then `idx + 1`) inside a transaction so `UNIQUE (ticket_id, position)` never collides.

- [ ] **Step 3: Run tests to verify pass**

Run: `cargo test -p tradocraft-helpdesk checklists`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add crates/helpdesk/src/checklists.rs crates/helpdesk/src/lib.rs
git commit -m "feat(helpdesk): add checklist templates and ticket checklist endpoints"
```

---

### Task 3: Ticket Progress Counts & Close Gate (`crates/helpdesk/src/tickets.rs`)

**Files:**
- Modify: `crates/helpdesk/src/tickets.rs`

**Interfaces:**
- Consumes: `helpdesk.ticket_checklist_items`, `helpdesk.teams.require_checklist_done`.
- Produces: `Ticket.checklist_total: i64` and `Ticket.checklist_done: i64`; `AppError::ConflictCode("checklist_incomplete", ...)` in `set_status`.

- [ ] **Step 1: Write failing tests in `crates/helpdesk/src/tickets.rs`**

Write `#[sqlx::test]` tests covering:
1. Ticket list & detail return accurate `checklist_total` and `checklist_done` counts (`2` of `5`).
2. Closing a ticket (`set_status` to `"closed"`) on a team with `require_checklist_done = true` fails with `AppError::ConflictCode("checklist_incomplete", ...)` while open items exist.
3. Closing succeeds when all items are `done = true`, when checklist is empty, when `require_checklist_done = false`, or when `team_id` is `None`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p tradocraft-helpdesk checklist`
Expected: FAIL.

- [ ] **Step 3: Update `Ticket`, `TICKET_COLS`, and `set_status` in `crates/helpdesk/src/tickets.rs`**

- Add `pub checklist_total: i64` and `pub checklist_done: i64` to `Ticket`.
- Add subqueries to `TICKET_COLS`:
  ```sql
  (SELECT count(*) FROM helpdesk.ticket_checklist_items c WHERE c.ticket_id = t.id) AS checklist_total,
  (SELECT count(*) FROM helpdesk.ticket_checklist_items c WHERE c.ticket_id = t.id AND c.done) AS checklist_done,
  ```
- In `set_status`, before updating `status` when `status == "closed" && !was_closed`:
  ```rust
  let blocked: bool = sqlx::query_scalar(
      "SELECT EXISTS (
          SELECT 1
          FROM helpdesk.tickets t
          JOIN helpdesk.teams tm ON tm.id = t.team_id
          WHERE t.id = $1
            AND tm.require_checklist_done
            AND EXISTS (
                SELECT 1 FROM helpdesk.ticket_checklist_items c
                WHERE c.ticket_id = t.id AND NOT c.done
            )
      )",
  )
  .bind(ticket_id)
  .fetch_one(&mut *conn)
  .await?;
  if blocked {
      return Err(AppError::ConflictCode(
          "checklist_incomplete",
          "Complete all checklist items before closing this ticket".into(),
      ));
  }
  ```

- [ ] **Step 4: Run tests to verify pass**

Run: `cargo test -p tradocraft-helpdesk`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add crates/helpdesk/src/tickets.rs
git commit -m "feat(helpdesk): expose checklist progress on tickets and enforce team close gate"
```

---

### Task 4: Automation `apply_checklist` Action (`crates/helpdesk/src/automation.rs`)

**Files:**
- Modify: `crates/helpdesk/src/automation.rs`

**Interfaces:**
- Consumes: `crate::checklists::apply_template_to_ticket`.
- Produces: `"apply_checklist"` in `ACTIONS`, `RuleAction.template_id: Option<Uuid>`, validation & execution in `automation.rs`.

- [ ] **Step 1: Write failing tests in `crates/helpdesk/src/automation.rs`**

Write tests verifying:
1. Saving a rule with `kind: "apply_checklist"` and `template_id: None` fails validation; with a valid `template_id` succeeds.
2. Running automation on ticket creation/update applies the template's items idempotently (running twice does not duplicate items).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p tradocraft-helpdesk automation`
Expected: FAIL.

- [ ] **Step 3: Update `crates/helpdesk/src/automation.rs`**

- Add `"apply_checklist"` to `ACTIONS`.
- Add `#[serde(default)] pub template_id: Option<Uuid>` to `RuleAction`.
- In `plan_action`, handle `"apply_checklist"` (emit `RuleChange` carrying `template_id`).
- In `apply_change`, handle `"apply_checklist"` by calling `crate::checklists::apply_template_to_ticket(conn, ticket_id, template_id, true).await?;`.
- In `validate_action`, verify `a.template_id` is `Some(id)` and exists in `helpdesk.checklist_templates`.

- [ ] **Step 4: Run tests to verify pass**

Run: `cargo test -p tradocraft-helpdesk automation`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add crates/helpdesk/src/automation.rs
git commit -m "feat(helpdesk): add apply_checklist automation action"
```

---

### Task 5: Regenerate OpenAPI & Dart API Client + Localization

**Files:**
- Regenerate: `app/lib/api/generated/...`
- Modify: `app/lib/l10n/app_en.arb`, `app_nl.arb`, `app_de.arb`, `app_fr.arb`, `app_es.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`

- [ ] **Step 1: Run API client codegen**

Run: `./scripts/generate-api-client.sh`
Expected: Regenerates OpenAPI spec and Dart models/endpoints (`ChecklistTemplate`, `ChecklistItem`, `Ticket.checklistTotal`, `Ticket.checklistDone`, `Team.requireChecklistDone`, `RuleAction.templateId`).

- [ ] **Step 2: Add localization keys to `app/lib/l10n/app_{en,nl,de,fr,es}.arb` and run `flutter gen-l10n`**

Add keys: `checklistTitle`, `checklistProgress` (`"{done}/{total}"`), `checklistAddItem`, `checklistApplyTemplate`, `checklistNoTemplates`, `checklistEmpty`, `checklistTemplatesTitle`, `checklistTemplateNew`, `checklistTemplateName`, `checklistTemplateItemsHint`, `teamRequireChecklistDone`, `ticketCloseBlockedChecklist`, `automationActionApplyChecklist`, `automationTemplateLabel`.
Run: `cd app && flutter gen-l10n`

- [ ] **Step 3: Commit generated client and localizations**

```bash
git add app/lib/api/generated app/lib/l10n
git commit -m "chore(app): regenerate API client and l10n for helpdesk checklists"
```

---

### Task 6: Helpdesk Settings & Automation UI (`helpdesk_settings_page.dart`, `automation_page.dart`)

**Files:**
- Modify: `app/lib/features/helpdesk/helpdesk_settings_page.dart`
- Modify: `app/lib/features/helpdesk/automation_page.dart`

- [ ] **Step 1: Add `requireChecklistDone` switch to team editor in `helpdesk_settings_page.dart`**

Add a `SwitchListTile` bound to `requireChecklistDone` in the team create/edit dialog, passing it in `TeamInput`.

- [ ] **Step 2: Add Checklist Templates management section to `helpdesk_settings_page.dart`**

Add a section/tab listing checklist templates (name, optional team badge, optional category badge, item count, active badge) with create/edit/delete dialogs (name, optional team dropdown, optional category dropdown, active switch, ordered item list with add/remove/reorder).

- [ ] **Step 3: Add `apply_checklist` action to `automation_page.dart`**

Add `'apply_checklist'` to the action kind dropdown and show a template dropdown when selected, populating `RuleAction.templateId`.

- [ ] **Step 4: Run `flutter analyze`**

Run: `cd app && flutter analyze lib/features/helpdesk/helpdesk_settings_page.dart lib/features/helpdesk/automation_page.dart`
Expected: No errors or warnings.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/helpdesk/helpdesk_settings_page.dart app/lib/features/helpdesk/automation_page.dart
git commit -m "feat(app): add helpdesk checklist templates, team toggle, and automation action UI"
```

---

### Task 7: Ticket List Badge, Ticket Detail Checklist UI & Widget Tests

**Files:**
- Modify: `app/lib/features/helpdesk/tickets_page.dart`
- Modify: `app/lib/features/helpdesk/ticket_screen.dart`
- Create: `app/test/helpdesk_checklist_test.dart`

- [ ] **Step 1: Write widget tests in `app/test/helpdesk_checklist_test.dart`**

Write widget tests covering:
1. Ticket list row renders `2/5` checklist progress badge when `checklistTotal > 0` and omits it when `checklistTotal == 0`.
2. Ticket detail checklist section renders items, toggles `done`, adds a new item, and applies a template (with matching team/category templates listed first).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/helpdesk_checklist_test.dart`
Expected: FAIL.

- [ ] **Step 3: Update `tickets_page.dart` and `ticket_screen.dart`**

- In `tickets_page.dart`: render a compact badge with `AppIcons.checklist` and `${t.checklistDone}/${t.checklistTotal}` when `t.checklistTotal > 0`.
- In `ticket_screen.dart`: add the Checklist card (header with `done/total` and "Apply template" menu sorting matching team/category templates first; ordered items with checkbox, description, `doneByName` + `doneAt`, inline edit/reorder/delete; inline add-item field) and handle `checklist_incomplete` / 409 error when closing a ticket with a clear message.

- [ ] **Step 4: Run Flutter tests and analyze**

Run: `cd app && flutter test test/helpdesk_checklist_test.dart && flutter analyze`
Expected: All tests PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/helpdesk/tickets_page.dart app/lib/features/helpdesk/ticket_screen.dart app/test/helpdesk_checklist_test.dart
git commit -m "feat(app): add helpdesk ticket checklist UI and list progress badge"
```
