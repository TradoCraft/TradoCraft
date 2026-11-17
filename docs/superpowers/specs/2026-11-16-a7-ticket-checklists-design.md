# A7 — Helpdesk Ticket Checklists Design

**Date:** 2026-11-16
**Roadmap item:** A7 Ticket checklists (`docs/ROADMAP.md`)
**Branch:** `feat/a7-ticket-checklists`

## Overview

Add per-ticket checklists to Helpdesk, mirroring the `field.job_tasks` model from ADR 0020:
- Ordered checklist items on each ticket (`position`, `description`, `done`, `done_by`, `done_at`).
- Reusable checklist templates, optionally scoped by `team_id` and/or ticket `category`.
- Idempotent template application: manual from the ticket UI or automatic via an `apply_checklist` helpdesk automation action.
- Progress indicator (`done/total`, e.g. `2/5`) in the ticket list and ticket detail view.
- Per-team `require_checklist_done` setting that blocks closing a ticket while checklist items remain open.

---

## 1. Database Schema

Add a new migration in `migrations/` (following the latest migration timestamp):

1. **`helpdesk.teams`**
   - Add `require_checklist_done boolean NOT NULL DEFAULT false`.

2. **`helpdesk.checklist_templates`**
   - `id uuid PRIMARY KEY`
   - `name text NOT NULL CHECK (btrim(name) <> '')`
   - `team_id uuid REFERENCES helpdesk.teams(id) ON DELETE SET NULL`
   - `category text` (nullable; validated in application code against `helpdesk::tickets::CATEGORIES`)
   - `active boolean NOT NULL DEFAULT true`
   - `created_at timestamptz NOT NULL DEFAULT now()`
   - `updated_at timestamptz NOT NULL DEFAULT now()`

3. **`helpdesk.checklist_template_items`**
   - `id uuid PRIMARY KEY`
   - `template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE`
   - `position integer NOT NULL`
   - `description text NOT NULL CHECK (btrim(description) <> '')`
   - `UNIQUE (template_id, position)`

4. **`helpdesk.ticket_checklist_items`** (mirrors `field.job_tasks`)
   - `id uuid PRIMARY KEY`
   - `ticket_id uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE`
   - `template_id uuid REFERENCES helpdesk.checklist_templates(id) ON DELETE SET NULL`
   - `position integer NOT NULL`
   - `description text NOT NULL CHECK (btrim(description) <> '')`
   - `done boolean NOT NULL DEFAULT false`
   - `done_by uuid REFERENCES core.users(id)`
   - `done_at timestamptz`
   - `UNIQUE (ticket_id, position)`
   - Index on `(ticket_id, position)`.

5. **`helpdesk.ticket_applied_templates`**
   - `ticket_id uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE`
   - `template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE`
   - `applied_at timestamptz NOT NULL DEFAULT now()`
   - `PRIMARY KEY (ticket_id, template_id)`

---

## 2. Backend Architecture (`crates/helpdesk`)

Create `crates/helpdesk/src/checklists.rs` and wire it into `crates/helpdesk/src/lib.rs`, `teams.rs`, `tickets.rs`, and `automation.rs`.

### 2.1 Team Setting (`teams.rs`)
- Expose `require_checklist_done: bool` on `Team` and `TeamInput` (default `false`).
- Persist in `helpdesk.teams` on create/update.

### 2.2 Checklist Templates API
- `GET /helpdesk/checklist-templates` — list templates with their ordered items; optional query filters `team_id`, `category`, `active`.
- `POST /helpdesk/checklist-templates` — create template + ordered items (requires `helpdesk.manage`).
- `PUT /helpdesk/checklist-templates/{id}` — update template metadata + replace ordered items (requires `helpdesk.manage`).
- `DELETE /helpdesk/checklist-templates/{id}` — delete template (requires `helpdesk.manage`).
- Validation: non-empty template name, at least zero or more items each with non-empty trimmed description, `category` (if `Some`) in `CATEGORIES`, `team_id` (if `Some`) exists in `helpdesk.teams`.

### 2.3 Ticket Checklist API
All endpoints require `helpdesk.use`:
- `GET /helpdesk/tickets/{id}/checklist` — returns `Vec<ChecklistItem>` ordered by `position` ASC, including `done_by_name: Option<String>` joined from `core.users`.
- `POST /helpdesk/tickets/{id}/checklist` — `{ description: String }` appends a single ad-hoc item at `COALESCE(MAX(position), 0) + 1`.
- `PATCH /helpdesk/tickets/{id}/checklist/{item_id}` — `{ done?: bool, description?: String, position?: i32 }`:
  - When `done` changes to `true`: set `done = true`, `done_by = current_user.id`, `done_at = now()`.
  - When `done` changes to `false`: set `done = false`, `done_by = NULL`, `done_at = NULL`.
  - When `description` is provided: trim and validate non-empty.
  - When `position` is provided: reorder items within a transaction (defer/shift positions cleanly so `UNIQUE (ticket_id, position)` is preserved).
- `DELETE /helpdesk/tickets/{id}/checklist/{item_id}` — delete item from the ticket.
- `POST /helpdesk/tickets/{id}/checklist/apply-template` — `{ template_id: Uuid }` calls `apply_template_to_ticket(pool, ticket_id, template_id)`.

### 2.4 Idempotent Template Application
`apply_template_to_ticket(tx, ticket_id, template_id)`:
1. Verify template exists (and is active when triggered by automation; manual apply also checks existence).
2. Attempt `INSERT INTO helpdesk.ticket_applied_templates (ticket_id, template_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`.
3. If `rows_affected == 0`, return early (no-op; already applied).
4. Otherwise, append all `checklist_template_items` ordered by `position` starting at `COALESCE(MAX(position), 0) + 1` into `helpdesk.ticket_checklist_items` with `template_id = Some(template_id)`.

### 2.5 Ticket List & Detail Progress (`tickets.rs`)
- Add `checklist_total: i64` and `checklist_done: i64` to `TicketSummary` and `Ticket` (computed via `COUNT(*)` and `COUNT(*) FILTER (WHERE done)` on `helpdesk.ticket_checklist_items`).

### 2.6 Close Gate (`tickets.rs`)
- When `PATCH /helpdesk/tickets/{id}` transitions `status` to `"closed"` (where previous status was not `"closed"`):
  - Check if the ticket has a `team_id` whose `helpdesk.teams.require_checklist_done = true` AND `EXISTS (SELECT 1 FROM helpdesk.ticket_checklist_items WHERE ticket_id = $1 AND NOT done)`.
  - If so, return `409 Conflict` (`ApiError::Conflict` or equivalent) with a clear message: `"Complete all checklist items before closing this ticket"`.
  - Tickets with no `team_id`, teams with `require_checklist_done = false`, or tickets with zero open items close normally.
  - Ticket merge (`POST /helpdesk/tickets/{id}/merge`) is not blocked so duplicate tickets can still be merged cleanly.

### 2.7 Automation Action (`automation.rs`)
- Add `apply_checklist` to `RuleAction.kind` using `template_id: Option<Uuid>`.
- Validation: `kind == "apply_checklist"` requires `template_id.is_some()` and that the template exists.
- Execution: when a rule matches on `created`, `updated`, or `customer_replied`, call `apply_template_to_ticket` (idempotent append).

---

## 3. Frontend Architecture (`app/lib/features/helpdesk/`)

1. **OpenAPI & Codegen**:
   - Export updated OpenAPI schema from backend and regenerate Dart models/clients in `app/lib/api/generated/`.
2. **Ticket List (`tickets_page.dart`)**:
   - Show a compact checklist progress badge (`2/5` with `AppIcons.checklist`) when `checklistTotal > 0` (styled green/complete when `checklistDone == checklistTotal`).
3. **Ticket Detail (`ticket_screen.dart`)**:
   - Add a **Checklist** card/section showing:
     - Header with `done/total` progress and an **"Apply template"** button/menu (listing active templates, with templates matching the ticket's `team_id` or `category` grouped/sorted first).
     - Ordered list of items with checkbox (`done`), description, and subtle `done_by_name` + relative/formatted `done_at` when completed.
     - Inline **"Add checklist item"** input, plus edit/reorder/delete controls on items.
   - Handle `409 Conflict` when closing a ticket by showing a clear snackbar/error banner.
4. **Helpdesk Settings (`helpdesk_settings_page.dart`)**:
   - Add **"Require checklist done before closing"** switch to the team create/edit form.
   - Add a **Checklist Templates** section/tab to create, edit, activate/deactivate, and delete templates with an ordered item editor.
5. **Automation (`automation_page.dart`)**:
   - Add **"Apply checklist"** to the action kind dropdown with a template picker.
6. **Localization**:
   - Add strings to `app_en.arb`, `app_nl.arb`, `app_de.arb`, `app_fr.arb`, `app_es.arb` and regenerate `app_localizations*.dart`.

---

## 4. Testing

- **Backend (`crates/helpdesk`)**:
  - Template CRUD & validation (empty name/description, invalid category/team).
  - Ticket checklist CRUD, `done` toggle (`done_by`/`done_at` set and cleared), and reordering.
  - Idempotent `apply_template` (re-applying is a no-op even if an item was deleted).
  - `checklist_total` and `checklist_done` accuracy on ticket list and detail endpoints.
  - Close gate: blocks closing (`409`) when team has `require_checklist_done = true` and open items exist; allows closing when all items are done, when checklist is empty, when `require_checklist_done = false`, or when ticket has no team.
  - Automation rule with `apply_checklist` on `created` and `updated`.
- **Frontend (`app/test/`)**:
  - Widget tests for ticket checklist rendering, toggling, adding an item, `2/5` badge in ticket list, and template/automation selectors.
