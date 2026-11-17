# A6 Helpdesk Reply Templates and Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend prepared answers into scoped, kinded templates that the reply editor suggests and A5 `send_email` rules can use, with a language source on tickets and a ticket-language automation condition.

**Architecture:** Prepared answers (`crates/helpdesk/src/answers.rs`, ADR 0013) stay the one template model. We add `kind`, `team_id` and `keywords`, a ranked suggest endpoint, `answer_id` on the `send_email` rule action, `tickets.language_source`, and a `ticket_languages` rule condition. Spec: `docs/superpowers/specs/2026-11-16-a6-reply-templates-design.md` (read its last section, "Revision after reading the code", first).

**Tech Stack:** Rust (axum, sqlx, utoipa), PostgreSQL, Flutter (Riverpod, Dio, generated OpenAPI client, gen-l10n).

## Global Constraints

- Work only in the worktree `/home/jo/TradoCraft/.claude/worktrees/a6-reply-templates` on branch `feat/a6-reply-templates`. Never edit the primary checkout.
- Every transactional table row carries `company_id`; every query filters on it.
- Permissions: use the existing `Permission::AnswersWrite` (write) and `Permission::HelpdeskRead` (read). Add no new permission.
- Audit every write through `audit::record` (user actions) or `audit::record_system`.
- Languages are exactly `nl, fr, en, de, es` (`tradocraft_core::LANGUAGES`, `is_language`). UI strings go in all five ARB files in `app/lib/l10n/`.
- `{x}` (A5 inline mail) and `{{x}}` (templates) stay separate syntaxes. Answers still accept unknown `{{placeholders}}`.
- Migrations get a unique timestamp; this plan uses `20270218000001` and `20270218000002`. If either is taken on `origin/main` by the time you start, use the next free `202702180000NN`.
- Environment for every command:
  ```bash
  export DATABASE_URL=postgresql://tradocraft:tradocraft@localhost:5433/tradocraft   # docker compose up -d db
  cd /home/jo/TradoCraft/.claude/worktrees/a6-reply-templates
  ```
- Crate names: backend `tradocraft-helpdesk` (`crates/helpdesk`), API tests `tradocraft-api` (`apps/api/tests`). If `cargo test -p` says the package is unknown, read the `name =` line in the crate's `Cargo.toml`.
- Commit after every task. Commit messages: `feat(helpdesk): ...`, `test(helpdesk): ...`, `docs: ...`.

## File Structure

| File | Responsibility |
|---|---|
| `migrations/20270218000001_helpdesk_answer_kinds.sql` | `kind`, `team_id`, `keywords` on `helpdesk.prepared_answers` |
| `migrations/20270218000002_ticket_language_source.sql` | `language_source` on `helpdesk.tickets` |
| `crates/helpdesk/src/answers.rs` | model, validation, CRUD, list filters, render, suggest endpoint |
| `crates/helpdesk/src/render.rs` | `{{x}}` renderer, placeholder list, `check_placeholders` |
| `crates/helpdesk/src/tickets.rs` | `language_source` on create, update and the `Ticket` struct; creator language for internal tickets |
| `crates/helpdesk/src/ingest.rs` | `language_source = detected` for inbound mail |
| `crates/helpdesk/src/automation.rs` | `answer_id` on `RuleAction`; `ticket_languages` condition and fact |
| `crates/helpdesk/src/automail.rs` | `send_email` with a template |
| `apps/api/tests/helpdesk_templates.rs` | all API tests of this item |
| `app/lib/features/helpdesk/answers_page.dart` | admin editor: kind, team, keywords |
| `app/lib/features/helpdesk/ticket_screen.dart` | picker: kind filter, ranked suggestions, `/code` |
| `app/lib/features/helpdesk/automation_page.dart` | `ticket_languages` chips, template selector on `send_email` |
| `app/test/answers_templates_test.dart` | widget tests |
| `docs/adr/0071-helpdesk-reply-templates.md`, `docs/ROADMAP.md` | ADR and roadmap |

---

### Task 1: Kind, team scope and keywords on prepared answers

**Files:**
- Create: `migrations/20270218000001_helpdesk_answer_kinds.sql`
- Create: `apps/api/tests/helpdesk_templates.rs`
- Modify: `crates/helpdesk/src/answers.rs` (struct and query edits, listed below)

**Interfaces:**
- Produces (used by Tasks 2 to 7):
  - `pub const KINDS: [&str; 4] = ["reply", "internal_note", "handover", "notice"];`
  - `pub fn clean_keywords(raw: &[String]) -> AppResult<Vec<String>>`
  - `PreparedAnswer { kind: String, team_id: Option<Uuid>, keywords: Vec<String>, .. }`
  - `PreparedAnswerInput { kind: String (default "reply"), team_id: Option<Uuid>, keywords: Vec<String> (default empty), .. }`
  - `ListParams { kind: Option<String>, team_id: Option<Uuid>, .. }` where `team_id` means "answers a ticket of this team can use": company-wide ones plus that team's.

- [ ] **Step 1: Write the migration**

```sql
-- A6 (ADR 0071): what a prepared answer is for, which team owns it, and words that rank it.
ALTER TABLE helpdesk.prepared_answers
    ADD COLUMN kind text NOT NULL DEFAULT 'reply'
        CHECK (kind IN ('reply', 'internal_note', 'handover', 'notice')),
    ADD COLUMN team_id uuid REFERENCES helpdesk.teams(id),
    ADD COLUMN keywords text[] NOT NULL DEFAULT '{}';
CREATE INDEX prepared_answers_team_idx ON helpdesk.prepared_answers (company_id, team_id);
```

- [ ] **Step 2: Write the failing API tests**

Create `apps/api/tests/helpdesk_templates.rs`:

```rust
//! Prepared answers as templates: kinds, team scope, keywords, suggestions, mail rules (ADR 0071).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}

async fn team(app: &axum::Router, name: &str) -> String {
    let (status, t) = post(app, ADMIN, "/helpdesk/teams", json!({ "name": name })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["id"].as_str().unwrap().to_string()
}

fn answer(code: &str, extra: Value) -> Value {
    let mut a = json!({
        "code": code, "name": code,
        "texts": [{ "language": "en", "subject": "Re: {{ticket.subject}}", "body": "Hello {{contact.name}}" }]
    });
    for (k, v) in extra.as_object().unwrap() {
        a[k] = v.clone();
    }
    a
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_has_a_kind_a_team_and_clean_keywords(db: PgPool) {
    let app = setup(db).await;
    let rd = team(&app, "R&D").await;
    let (status, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer(
            "firmware",
            json!({ "kind": "internal_note", "team_id": rd, "keywords": [" Firmware ", "firmware", "UPDATE", ""] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    assert_eq!(a["kind"], "internal_note");
    assert_eq!(a["team_id"], rd.as_str());
    assert_eq!(a["keywords"], json!(["firmware", "update"]));
    // Default kind is a reply, company-wide.
    let (_, plain) = post(&app, SUPPORT, "/prepared-answers", answer("plain", json!({}))).await;
    assert_eq!(plain["kind"], "reply");
    assert!(plain["team_id"].is_null());
    assert_eq!(plain["keywords"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn kind_team_and_keywords_are_validated(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("a", json!({ "kind": "shout" }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("b", json!({ "team_id": "00000000-0000-7000-8000-00000000dead" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let long = "x".repeat(41);
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("c", json!({ "keywords": [long] }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_list_filters_by_kind_and_by_the_team_that_can_use_the_answer(db: PgPool) {
    let app = setup(db).await;
    let rd = team(&app, "R&D").await;
    let net = team(&app, "Network").await;
    post(&app, SUPPORT, "/prepared-answers", answer("everyone", json!({}))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("rd-note", json!({ "kind": "internal_note", "team_id": rd }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("net-reply", json!({ "team_id": net }))).await;
    let codes = |v: &Value| -> Vec<String> {
        let mut c: Vec<String> = v.as_array().unwrap().iter().map(|a| a["code"].as_str().unwrap().to_string()).collect();
        c.sort();
        c
    };
    let (_, all) = get(&app, SUPPORT, "/prepared-answers").await;
    assert_eq!(codes(&all), ["everyone", "net-reply", "rd-note"]);
    let (_, notes) = get(&app, SUPPORT, "/prepared-answers?kind=internal_note").await;
    assert_eq!(codes(&notes), ["rd-note"]);
    // A network ticket sees company-wide answers and the network's own.
    let (_, for_net) = get(&app, SUPPORT, &format!("/prepared-answers?team_id={net}")).await;
    assert_eq!(codes(&for_net), ["everyone", "net-reply"]);
    // Update keeps working and can move an answer to another team.
    let id = all.as_array().unwrap().iter().find(|a| a["code"] == "net-reply").unwrap()["id"].as_str().unwrap().to_string();
    let (status, moved) = put(&app, SUPPORT, &format!("/prepared-answers/{id}"), answer("net-reply", json!({ "team_id": rd }))).await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["team_id"], rd.as_str());
}
```

(`call_raw` is imported for Task 5 and used there; if the compiler warns about it as unused until then, add `#[allow(unused_imports)]` on the `use common::...` line and remove it in Task 5.)

- [ ] **Step 3: Run the tests and watch them fail**

Run: `cargo test -p tradocraft-api --test helpdesk_templates 2>&1 | tail -30`
Expected: FAIL (compile is fine; assertions fail: `kind` is null, filters ignored, 201 vs 422).

- [ ] **Step 4: Implement in `answers.rs`**

4a. Imports and constants (top of file, after `type ErrorBody`):

```rust
pub const KINDS: [&str; 4] = ["reply", "internal_note", "handover", "notice"];

fn default_kind() -> String {
    "reply".into()
}

/// Lower-cased, trimmed, de-duplicated keywords (at most 20 of at most 40 characters).
pub fn clean_keywords(raw: &[String]) -> AppResult<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    for k in raw {
        let k = k.trim().to_lowercase();
        if k.is_empty() {
            continue;
        }
        if k.chars().count() > 40 {
            return Err(AppError::Validation(
                "a keyword is at most 40 characters".into(),
            ));
        }
        if !out.contains(&k) {
            out.push(k);
        }
    }
    if out.len() > 20 {
        return Err(AppError::Validation("at most 20 keywords".into()));
    }
    Ok(out)
}

/// The team must belong to the company.
async fn check_team(conn: &mut PgConnection, company_id: Uuid, team: Option<Uuid>) -> AppResult<()> {
    let Some(team) = team else { return Ok(()) };
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
    )
    .bind(team)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::NotFound("team"))
    }
}
```

4b. `PreparedAnswer` gains three fields after `category`:

```rust
    /// reply | internal_note | handover | notice
    pub kind: String,
    /// Absent: usable by every team.
    pub team_id: Option<Uuid>,
    /// Lower-case words; a ticket subject containing one ranks the answer higher.
    pub keywords: Vec<String>,
```

`PreparedAnswerInput` gains, after `category`:

```rust
    #[serde(default = "default_kind")]
    pub kind: String,
    pub team_id: Option<Uuid>,
    #[serde(default)]
    pub keywords: Vec<String>,
```

`ListParams` gains:

```rust
    /// reply | internal_note | handover | notice
    pub kind: Option<String>,
    /// Answers a ticket of this team can use: company-wide ones and this team's own.
    pub team_id: Option<Uuid>,
```

`Row` gains `kind: String, team_id: Option<Uuid>, keywords: Vec<String>`.

4c. `load`: select list becomes `id, code, name, category, kind, team_id, keywords, active, updated_at`, and the `PreparedAnswer { .. }` literal gains `kind: r.kind, team_id: r.team_id, keywords: r.keywords,`.

4d. `PreparedAnswerInput::validate` gains at the top (after the code/name check):

```rust
        if !KINDS.contains(&self.kind.as_str()) {
            return Err(AppError::Validation(format!(
                "kind must be one of {}",
                KINDS.join(", ")
            )));
        }
        clean_keywords(&self.keywords)?;
```

4e. `list_answers`: select `a.id, a.code, a.name, a.category, a.kind, a.team_id, a.keywords, a.active, a.updated_at`, add to the WHERE clause

```sql
           AND ($4::text IS NULL OR a.kind = $4)
           AND ($5::uuid IS NULL OR a.team_id IS NULL OR a.team_id = $5)
```

with `.bind(&p.kind).bind(p.team_id)` after the existing binds, and the `PreparedAnswer { .. }` literal gains `kind: r.kind, team_id: r.team_id, keywords: r.keywords,`.

4f. `create_answer`: after `input.validate()?;` add

```rust
    let keywords = clean_keywords(&input.keywords)?;
```

and after `let mut tx = ...begin().await?;` add `check_team(&mut tx, user.company_id, input.team_id).await?;`. The INSERT becomes:

```rust
    sqlx::query("INSERT INTO helpdesk.prepared_answers (id, company_id, code, name, category, active, kind, team_id, keywords) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)")
        .bind(id)
        .bind(user.company_id)
        .bind(input.code.trim())
        .bind(input.name.trim())
        .bind(input.category.as_deref().map(str::trim).filter(|c| !c.is_empty()))
        .bind(input.active)
        .bind(&input.kind)
        .bind(input.team_id)
        .bind(&keywords)
        .execute(&mut *tx)
        .await?;
```

The audit details become `serde_json::json!({ "code": input.code, "kind": input.kind, "team_id": input.team_id })`.

4g. `update_answer`: same `keywords` and `check_team` lines, and the UPDATE becomes:

```rust
        "UPDATE helpdesk.prepared_answers SET code = $3, name = $4, category = $5, active = $6, kind = $7,
                team_id = $8, keywords = $9, updated_at = now()
         WHERE id = $1 AND company_id = $2",
```

with `.bind(&input.kind).bind(input.team_id).bind(&keywords)` appended after `.bind(input.active)`. Audit details: `serde_json::json!({ "kind": input.kind, "team_id": input.team_id })`.

4h. Unit test at the bottom of `answers.rs` `tests` module:

```rust
    #[test]
    fn keywords_are_trimmed_lowercased_and_unique() {
        let raw = vec![" Firmware ".to_string(), "firmware".into(), "".into(), "Update".into()];
        assert_eq!(clean_keywords(&raw).unwrap(), ["firmware", "update"]);
        assert!(clean_keywords(&["x".repeat(41)]).is_err());
        let many: Vec<String> = (0..21).map(|i| format!("k{i}")).collect();
        assert!(clean_keywords(&many).is_err());
    }
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-helpdesk --lib answers 2>&1 | tail -15` then `cargo test -p tradocraft-api --test helpdesk_templates 2>&1 | tail -15`
Expected: PASS (1 unit test in the first, 3 tests in the second).

- [ ] **Step 6: Run the existing answer tests so nothing regressed**

Run: `cargo test -p tradocraft-api --test contacts --test helpdesk 2>&1 | tail -15`
Expected: PASS. (Existing calls send no `kind`, so they get the default.)

- [ ] **Step 7: Commit**

```bash
git add migrations/20270218000001_helpdesk_answer_kinds.sql crates/helpdesk/src/answers.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): kind, team scope and keywords on prepared answers (A6)"
```

---

### Task 2: Placeholder check, `{{team.name}}` and a render that does not need a user

**Files:**
- Modify: `crates/helpdesk/src/render.rs`
- Modify: `crates/helpdesk/src/answers.rs` (`ticket_values`, `load`, `pick_text` visibility)
- Test: `crates/helpdesk/src/render.rs` (unit), `apps/api/tests/helpdesk_templates.rs`

**Interfaces:**
- Consumes: Task 1 `PreparedAnswer`.
- Produces (used by Task 4 and 5):
  - `pub fn check_placeholders(field: &str, text: &str) -> AppResult<()>` in `render.rs`
  - `render::PLACEHOLDERS` now has 15 entries, including `"team.name"`
  - `pub async fn ticket_values_for(conn: &mut PgConnection, company_id: Uuid, agent_name: &str, ticket_id: Uuid) -> AppResult<(String, BTreeMap<String, String>)>` in `answers.rs` (the old `ticket_values(conn, user, ticket_id)` stays and calls it)
  - `pub async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<PreparedAnswer>` (was private)

- [ ] **Step 1: Write the failing unit tests in `render.rs`**

Add to the `tests` module:

```rust
    #[test]
    fn unknown_placeholders_are_found_by_the_check() {
        assert!(check_placeholders("body", "Dear {{contact.name}}, {{ team.name }} {x} { }").is_ok());
        let e = check_placeholders("body", "Dear {{contact.nme}}").unwrap_err().to_string();
        assert!(e.contains("contact.nme"), "{e}");
        assert!(e.contains("body"), "{e}");
    }

    #[test]
    fn the_team_name_is_a_placeholder() {
        assert!(PLACEHOLDERS.contains(&"team.name"));
    }
```

- [ ] **Step 2: Write the failing API test**

Append to `apps/api/tests/helpdesk_templates.rs`:

```rust
/// A ticket made by hand; its id is read back from the database.
async fn manual_ticket(app: &axum::Router, db: &PgPool, user: &str, subject: &str, extra: Value) -> String {
    let mut body = json!({ "subject": subject, "body": "asked", "category": "question" });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, r) = post(app, user, "/tickets", body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    sqlx::query_scalar("SELECT id::text FROM helpdesk.tickets WHERE subject = $1")
        .bind(subject)
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_team_name_is_filled_in_for_a_ticket_of_that_team(db: PgPool) {
    let app = setup(db.clone()).await;
    let rd = team(&app, "R&D").await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("who", json!({ "texts": [{ "language": "en", "body": "Team: {{team.name}}" }] })),
    )
    .await;
    let ticket = manual_ticket(&app, &db, SUPPORT, "Needs R&D", json!({})).await;
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2::uuid WHERE id = $1::uuid")
        .bind(&ticket)
        .bind(&rd)
        .execute(&db)
        .await
        .unwrap();
    let uri = format!("/tickets/{ticket}/prepared-answers/{}/render", a["id"].as_str().unwrap());
    let (status, r) = post(&app, SUPPORT, &uri, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["body"], "Team: R&D");
}
```

- [ ] **Step 2b: Run and confirm both fail**

Run: `cargo test -p tradocraft-helpdesk --lib render 2>&1 | tail -10; cargo test -p tradocraft-api --test helpdesk_templates the_team_name 2>&1 | tail -10`
Expected: FAIL (`check_placeholders` not found; body is `Team: {{team.name}}`).

- [ ] **Step 3: Implement in `render.rs`**

Change the top `use` and constant, and add the check:

```rust
use std::collections::BTreeMap;

use tradocraft_core::{AppError, AppResult};
```

`pub const PLACEHOLDERS: [&str; 15]` with `"team.name",` added after `"agent.name",`.

```rust
/// Rejects a `{{name}}` that is not a known placeholder. Used where a text goes out without an
/// agent reading it first (automation mail).
pub fn check_placeholders(field: &str, text: &str) -> AppResult<()> {
    let mut rest = text;
    while let Some(start) = rest.find("{{") {
        let after = &rest[start + 2..];
        let Some(end) = after.find("}}") else { break };
        let name = after[..end].trim();
        if !PLACEHOLDERS.contains(&name) {
            return Err(AppError::Validation(format!(
                "{field}: {{{{{name}}}}} is not a placeholder (use {})",
                PLACEHOLDERS.map(|p| format!("{{{{{p}}}}}")).join(", ")
            )));
        }
        rest = &after[end + 2..];
    }
    Ok(())
}
```

- [ ] **Step 4: Implement in `answers.rs`**

4a. Make `load` public: `pub async fn load(...)`.

4b. Replace the head of `ticket_values` so it delegates, and rename the body:

```rust
/// The values for the placeholders of a ticket, for the logged-in agent.
pub async fn ticket_values(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
) -> AppResult<(String, BTreeMap<String, String>)> {
    ticket_values_for(conn, user.company_id, &user.display_name, ticket_id).await
}

/// The same without a logged-in user: `agent_name` is who the text speaks for (the ticket's
/// owner in automation mail).
pub async fn ticket_values_for(
    conn: &mut PgConnection,
    company_id: Uuid,
    agent_name: &str,
    ticket_id: Uuid,
) -> AppResult<(String, BTreeMap<String, String>)> {
```

Inside, replace `user.company_id` with `company_id` (the `.bind(user.company_id)` of the ticket query) and `user.display_name.clone()` with `agent_name.to_string()`. Add `team_name: Option<String>` to `struct V`, add `tm.name AS team_name,` to the SELECT list (before `q.number`), add `LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id` after the `crm.contacts` join, and add this entry to the `BTreeMap::from` list next to `agent.name`:

```rust
        ("team.name".to_string(), v.team_name.unwrap_or_default()),
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-helpdesk --lib render 2>&1 | tail -10; cargo test -p tradocraft-api --test helpdesk_templates 2>&1 | tail -10; cargo test -p tradocraft-api --test helpdesk --test contacts 2>&1 | tail -5`
Expected: PASS everywhere.

- [ ] **Step 6: Commit**

```bash
git add crates/helpdesk/src/render.rs crates/helpdesk/src/answers.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): team.name placeholder, placeholder check, render without a user (A6)"
```

---

### Task 3: Language source and the creator's language for internal tickets

**Files:**
- Create: `migrations/20270218000002_ticket_language_source.sql`
- Modify: `crates/helpdesk/src/tickets.rs` (struct `Ticket` near line 58, SELECT near line 347, `create_ticket` near lines 715 to 746, `update_ticket` near line 855)
- Modify: `crates/helpdesk/src/ingest.rs` (new-ticket branch near lines 265 to 310)
- Test: `apps/api/tests/helpdesk_templates.rs`

**Interfaces:**
- Produces: `Ticket.language_source: String` (`record | detected | agent`), in the ticket JSON. Task 6/7 (Flutter) reads it.

- [ ] **Step 1: Write the migration**

```sql
-- A6 (ADR 0071): where a ticket's language came from. `record`: its contact, customer, creator or
-- the company default. `detected`: guessed from the first message. `agent`: given or changed by a person.
ALTER TABLE helpdesk.tickets
    ADD COLUMN language_source text NOT NULL DEFAULT 'record'
        CHECK (language_source IN ('record', 'detected', 'agent'));
```

- [ ] **Step 2: Write the failing tests**

Append to `apps/api/tests/helpdesk_templates.rs`:

```rust
async fn language_of(db: &PgPool, subject: &str) -> (String, String) {
    sqlx::query_as(
        "SELECT language::text, language_source FROM helpdesk.tickets WHERE subject = $1",
    )
    .bind(subject)
    .fetch_one(db)
    .await
    .unwrap()
}

fn mail(from: &str, subject: &str, body: &str) -> Vec<u8> {
    format!("From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n").into_bytes()
}

async fn receive(app: &axum::Router, from: &str, subject: &str, body: &str) -> String {
    let (status, r) = call_raw(app, SUPPORT, "/api/v1/helpdesk/inbound", "message/rfc822", mail(from, subject, body)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    r["ticket_id"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_internal_ticket_takes_the_creators_language(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE core.companies SET default_language = 'en'").execute(&db).await.unwrap();
    sqlx::query("UPDATE core.users SET language = 'fr' WHERE email = $1")
        .bind(SUPPORT)
        .execute(&db)
        .await
        .unwrap();
    manual_ticket(&app, &db, SUPPORT, "Switch config", json!({ "internal": true })).await;
    assert_eq!(language_of(&db, "Switch config").await, ("fr".into(), "record".into()));
    // Without a language on the creator the company default applies.
    sqlx::query("UPDATE core.users SET language = NULL WHERE email = $1").bind(SUPPORT).execute(&db).await.unwrap();
    manual_ticket(&app, &db, SUPPORT, "Switch config 2", json!({ "internal": true })).await;
    assert_eq!(language_of(&db, "Switch config 2").await, ("en".into(), "record".into()));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_language_given_or_changed_by_an_agent_is_marked_as_theirs(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = manual_ticket(&app, &db, SUPPORT, "Given", json!({ "language": "de" })).await;
    assert_eq!(language_of(&db, "Given").await, ("de".into(), "agent".into()));
    let other = manual_ticket(&app, &db, SUPPORT, "Not given", json!({})).await;
    assert_eq!(language_of(&db, "Not given").await.1, "record");
    // Saving the ticket with the same language keeps the source; another language makes it the agent's.
    let body = |lang: &str| json!({ "subject": "Not given", "status": "open", "priority": "normal", "category": "question", "language": lang });
    let current = language_of(&db, "Not given").await.0;
    let (status, r) = put(&app, SUPPORT, &format!("/tickets/{other}"), body(&current)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(language_of(&db, "Not given").await.1, "record");
    let changed = if current == "es" { "nl" } else { "es" };
    let (status, r) = put(&app, SUPPORT, &format!("/tickets/{other}"), body(changed)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(language_of(&db, "Not given").await, (changed.into(), "agent".into()));
    let _ = id;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_detected_language_is_marked_as_detected_and_a_known_customer_is_not(db: PgPool) {
    let app = setup(db.clone()).await;
    // Unknown sender, French text: the detector decides.
    receive(
        &app,
        "inconnu@nowhere.example",
        "Commande",
        "Bonjour, nous avons bien reçu le devis et nous voudrions passer la commande. Merci et cordialement",
    )
    .await;
    assert_eq!(language_of(&db, "Commande").await, ("fr".into(), "detected".into()));
    // Unknown sender, no usable text: the company default, not marked as detected.
    receive(&app, "other@nowhere.example", "OK", "OK").await;
    assert_eq!(language_of(&db, "OK").await.1, "record");
}
```

- [ ] **Step 3: Run and watch them fail**

Run: `cargo test -p tradocraft-api --test helpdesk_templates language 2>&1 | tail -20`
Expected: FAIL (column `language_source` does not exist until the migration runs, then assertions fail).

- [ ] **Step 4: Implement in `tickets.rs`**

4a. `Ticket` struct: after `pub language: String,` add

```rust
    /// record | detected | agent: where `language` came from.
    pub language_source: String,
```

4b. The ticket SELECT (the one containing `t.language::text AS language, t.customer_id, c.name AS customer_name`): add `t.language_source,` right after `t.language::text AS language,`.

4c. `create_ticket`: replace the whole `let language = match &input.language { ... };` block (lines 715 to 727) with:

```rust
    let language_given = input.language.is_some();
    let language = match &input.language {
        Some(l) if is_language(l) => l.clone(),
        Some(_) => {
            return Err(AppError::Validation(format!(
                "language must be one of {}",
                LANGUAGES.join(", ")
            )))
        }
        None => match &contact {
            Some(c) => c.effective_language.clone(),
            None if customer_id.is_none() && input.internal => {
                // A question between colleagues: the creator's language, else the company's.
                let own: Option<String> =
                    sqlx::query_scalar("SELECT language::text FROM core.users WHERE id = $1")
                        .bind(user.user_id)
                        .fetch_one(&mut *tx)
                        .await?;
                match own {
                    Some(l) => l,
                    None => customer_language(&mut tx, None, user.company_id).await?,
                }
            }
            None => customer_language(&mut tx, customer_id, user.company_id).await?,
        },
    };
```

The INSERT adds the column and a parameter:

```rust
        "INSERT INTO helpdesk.tickets (id, company_id, number, subject, status, category, language, customer_id,
                                       contact_id, contact_name, contact_email, owner_user_id, internal, created_by,
                                       language_source)
         VALUES ($1, $2, $3, $4, 'open', $5, $6, $7, $8, $9, $10, $11, $12, $11,
                 CASE WHEN $13 THEN 'agent' ELSE 'record' END)",
```

with `.bind(input.internal)` followed by `.bind(language_given)`.

(`customer_language(&mut tx, None, company)` is how the helper already behaves for no customer: it returns the company default. If its signature takes `Option<Uuid>`, the call above compiles as written; if it differs, adapt the call, not the helper.)

4d. `update_ticket`: the UPDATE statement's SET list gets, right after `language = $5,`:

```sql
language_source = CASE WHEN language::text <> $5 THEN 'agent' ELSE language_source END,
```

(no new bind: `$5` is the language).

- [ ] **Step 5: Implement in `ingest.rs`**

In the new-ticket branch, right after the `let language = customer...unwrap_or(default_language);` statement, add:

```rust
            let language_source = if customer.is_none() && detected.is_some() {
                "detected"
            } else {
                "record"
            };
```

and extend the INSERT: add `language_source` to the column list after `team_id` (making it `mailbox_id, team_id, language_source)`), the value `$15` to the VALUES list, and `.bind(language_source)` after `.bind(source.and_then(|s| s.team_id))`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-api --test helpdesk_templates 2>&1 | tail -15; cargo test -p tradocraft-api --test helpdesk --test helpdesk_mail --test contacts 2>&1 | tail -8`
Expected: PASS. If `a_detected_language...` fails because the detector returned `None` for the sample, use the French sample from `crates/helpdesk/src/language.rs` tests verbatim (it is the one above).

- [ ] **Step 7: Commit**

```bash
git add migrations/20270218000002_ticket_language_source.sql crates/helpdesk/src/tickets.rs crates/helpdesk/src/ingest.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): language source on tickets, creator language for internal tickets (A6)"
```

---

### Task 4: Ranked suggestions for a ticket

**Files:**
- Modify: `crates/helpdesk/src/answers.rs`
- Test: `crates/helpdesk/src/answers.rs` (unit), `apps/api/tests/helpdesk_templates.rs`

**Interfaces:**
- Consumes: Task 1 (`kind`, `team_id`, `keywords`), Task 2 (`ticket_values_for`, `load`).
- Produces: `GET /tickets/{id}/prepared-answers/suggest?q=&kind=` returning `Vec<SuggestedAnswer>`:

```rust
pub struct SuggestedAnswer {
    pub answer_id: Uuid, pub code: String, pub name: String, pub kind: String,
    pub team_id: Option<Uuid>, pub language: String, pub fallback: bool,
    pub subject: String, pub body: String, pub score: i32,
}
```

and the pure `pub fn score(c: &Candidate, q: &str, ticket_team: Option<Uuid>, ticket_subject: &str) -> Option<i32>`.

- [ ] **Step 1: Write the failing unit tests**

Add to the `tests` module of `answers.rs`:

```rust
    fn cand<'a>(code: &'a str, name: &'a str, keywords: &'a [String], team: Option<Uuid>, has_language: bool) -> Candidate<'a> {
        Candidate { code, name, keywords, team_id: team, has_language }
    }

    #[test]
    fn an_exact_code_beats_a_prefix_beats_a_name_match() {
        let none: Vec<String> = vec![];
        let exact = score(&cand("pump", "Pump", &none, None, true), "pump", None, "").unwrap();
        let prefix = score(&cand("pump-fault", "Fault", &none, None, true), "pump", None, "").unwrap();
        let name = score(&cand("f1", "About the pump", &none, None, true), "pump", None, "").unwrap();
        assert!(exact > prefix && prefix > name, "{exact} {prefix} {name}");
        assert_eq!(score(&cand("zzz", "Other", &none, None, true), "pump", None, ""), None);
    }

    #[test]
    fn keywords_in_the_subject_team_and_language_raise_the_score() {
        let kw = vec!["firmware".to_string()];
        let team = Uuid::from_u128(7);
        let base = score(&cand("a", "A", &kw, None, false), "", None, "Pump noise").unwrap();
        let with_kw = score(&cand("a", "A", &kw, None, false), "", None, "Firmware update").unwrap();
        let with_team = score(&cand("a", "A", &kw, Some(team), false), "", Some(team), "Pump noise").unwrap();
        let with_lang = score(&cand("a", "A", &kw, None, true), "", None, "Pump noise").unwrap();
        assert!(with_kw > base && with_team > base && with_lang > base);
    }

    #[test]
    fn a_keyword_alone_can_match_the_query() {
        let kw = vec!["firmware".to_string()];
        assert!(score(&cand("a", "A", &kw, None, true), "firm", None, "").is_some());
    }
```

- [ ] **Step 2: Write the failing API test**

Append to `apps/api/tests/helpdesk_templates.rs`:

```rust
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn suggestions_are_ranked_rendered_in_the_ticket_language_and_scoped_to_the_team(db: PgPool) {
    let app = setup(db.clone()).await;
    let rd = team(&app, "R&D").await;
    let net = team(&app, "Network").await;
    post(&app, SUPPORT, "/prepared-answers", answer("firmware", json!({ "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("generic", json!({}))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("rd-only", json!({ "team_id": rd, "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("net-only", json!({ "team_id": net, "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("note", json!({ "kind": "internal_note" }))).await;
    let ticket = manual_ticket(&app, &db, SUPPORT, "Firmware update fails", json!({})).await;
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2::uuid, language = 'en' WHERE id = $1::uuid")
        .bind(&ticket)
        .bind(&rd)
        .execute(&db)
        .await
        .unwrap();
    let (status, r) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?kind=reply")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let codes: Vec<&str> = r.as_array().unwrap().iter().map(|s| s["code"].as_str().unwrap()).collect();
    // The R&D answer ranks first (keyword and team), the network's and the note are left out.
    assert_eq!(codes.first(), Some(&"rd-only"), "{codes:?}");
    assert!(codes.contains(&"firmware") && codes.contains(&"generic"));
    assert!(!codes.contains(&"net-only") && !codes.contains(&"note"), "{codes:?}");
    let first = &r[0];
    assert_eq!(first["language"], "en");
    assert_eq!(first["subject"], "Re: Firmware update fails");
    // A query narrows the list; nothing matches a nonsense query.
    let (_, q) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?kind=reply&q=gener")).await;
    assert_eq!(q.as_array().unwrap().len(), 1);
    let (_, none) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?q=zzzz")).await;
    assert!(none.as_array().unwrap().is_empty());
}
```

- [ ] **Step 3: Run and watch them fail**

Run: `cargo test -p tradocraft-helpdesk --lib answers 2>&1 | tail -8; cargo test -p tradocraft-api --test helpdesk_templates suggestions 2>&1 | tail -8`
Expected: FAIL (`Candidate`/`score` not found; 404 on the new route).

- [ ] **Step 4: Implement in `answers.rs`**

Add the types and the pure function (place after `pick_text`):

```rust
/// What the ranking needs to know about one answer.
pub struct Candidate<'a> {
    pub code: &'a str,
    pub name: &'a str,
    pub keywords: &'a [String],
    pub team_id: Option<Uuid>,
    /// The answer has a text in the ticket's own language.
    pub has_language: bool,
}

/// How well an answer fits a ticket, or `None` when a typed query matches nothing. Higher is better:
/// exact code 100, code prefix 60, name or keyword hit 30 or 25; keywords found in the ticket
/// subject +20 each (at most 40); the ticket's own team +15; a text in the ticket's language +5.
pub fn score(
    c: &Candidate,
    q: &str,
    ticket_team: Option<Uuid>,
    ticket_subject: &str,
) -> Option<i32> {
    let q = q.trim().to_lowercase();
    let code = c.code.to_lowercase();
    let mut s = 0;
    if !q.is_empty() {
        s += if code == q {
            100
        } else if code.starts_with(&q) {
            60
        } else if c.name.to_lowercase().contains(&q) {
            30
        } else if c.keywords.iter().any(|k| k.contains(&q)) {
            25
        } else {
            return None;
        };
    }
    let subject = ticket_subject.to_lowercase();
    let hits = c.keywords.iter().filter(|k| subject.contains(k.as_str())).count() as i32;
    s += (hits * 20).min(40);
    if c.team_id.is_some() && c.team_id == ticket_team {
        s += 15;
    }
    if c.has_language {
        s += 5;
    }
    Some(s)
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestParams {
    /// Typed text: a code, part of a name or a keyword. Empty: the best fits for the ticket.
    pub q: Option<String>,
    /// reply | internal_note | handover | notice. Absent: every kind.
    pub kind: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SuggestedAnswer {
    pub answer_id: Uuid,
    pub code: String,
    pub name: String,
    pub kind: String,
    pub team_id: Option<Uuid>,
    /// Language of the text used.
    pub language: String,
    pub fallback: bool,
    pub subject: String,
    pub body: String,
    pub score: i32,
}

/// The best prepared answers for a ticket, filled in and in the ticket's language, at most ten.
/// Answers of other teams are left out.
#[utoipa::path(get, path = "/tickets/{id}/prepared-answers/suggest", tag = "helpdesk",
    params(("id" = Uuid, Path), SuggestParams),
    responses((status = 200, body = Vec<SuggestedAnswer>), (status = 404, body = ErrorBody)))]
async fn suggest(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(ticket_id): Path<Uuid>,
    Query(p): Query<SuggestParams>,
) -> AppResult<Json<Vec<SuggestedAnswer>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let (language, values) = ticket_values(&mut conn, &user, ticket_id).await?;
    let team: Option<Uuid> =
        sqlx::query_scalar("SELECT team_id FROM helpdesk.tickets WHERE id = $1 AND company_id = $2")
            .bind(ticket_id)
            .bind(user.company_id)
            .fetch_one(&mut *conn)
            .await?;
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT a.id, a.code, a.name, a.category, a.kind, a.team_id, a.keywords, a.active, a.updated_at
         FROM helpdesk.prepared_answers a
         WHERE a.company_id = $1 AND a.active AND ($2::text IS NULL OR a.kind = $2)
           AND (a.team_id IS NULL OR a.team_id = $3)",
    )
    .bind(user.company_id)
    .bind(&p.kind)
    .bind(team)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let all = texts(&mut conn, &ids).await?;
    let subject = values.get("ticket.subject").cloned().unwrap_or_default();
    let q = p.q.clone().unwrap_or_default();
    let mut ranked: Vec<(i32, Row)> = rows
        .into_iter()
        .filter_map(|r| {
            let has_language = all.iter().any(|(id, t)| *id == r.id && t.language == language);
            let s = score(
                &Candidate { code: &r.code, name: &r.name, keywords: &r.keywords, team_id: r.team_id, has_language },
                &q,
                team,
                &subject,
            )?;
            Some((s, r))
        })
        .collect();
    ranked.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.name.cmp(&b.1.name)));
    ranked.truncate(10);
    let mut out = Vec::new();
    for (s, r) in ranked {
        let mine: Vec<AnswerText> =
            all.iter().filter(|(id, _)| *id == r.id).map(|(_, t)| t.clone()).collect();
        let Some((text, fallback)) = pick_text(&mine, &language, &values["__company_language"]) else {
            continue;
        };
        out.push(SuggestedAnswer {
            answer_id: r.id,
            code: r.code,
            name: r.name,
            kind: r.kind,
            team_id: r.team_id,
            language: text.language.clone(),
            fallback,
            subject: render(&text.subject, &values),
            body: render(&text.body, &values),
            score: s,
        });
    }
    Ok(Json(out))
}
```

Register it in `router()`:

```rust
        .routes(routes!(suggest))
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-helpdesk --lib answers 2>&1 | tail -8; cargo test -p tradocraft-api --test helpdesk_templates 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add crates/helpdesk/src/answers.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): ranked template suggestions for a ticket (A6)"
```

---

### Task 5: `send_email` rules can use a template

**Files:**
- Modify: `crates/helpdesk/src/automation.rs` (`RuleAction` struct near line 76; test helper literals at lines 977, 1011, 1110, 1115, 1121, 1142, 1156, 1183)
- Modify: `crates/helpdesk/src/automail.rs` (`validate_action`, `send`)
- Test: `apps/api/tests/helpdesk_templates.rs`

**Interfaces:**
- Consumes: Task 1 (`PreparedAnswer`, `load` from Task 2), Task 2 (`check_placeholders`, `ticket_values_for`, `pick_text`).
- Produces: `RuleAction.answer_id: Option<Uuid>` (JSON field `answer_id`).

- [ ] **Step 1: Write the failing API tests**

Append to `apps/api/tests/helpdesk_templates.rs`:

```rust
async fn outbox(db: &PgPool) -> Vec<(String, String, String)> {
    sqlx::query_as(
        "SELECT to_address, subject, body FROM core.mail_outbox WHERE delivery = 'queued' ORDER BY created_at, id",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

fn mail_rule(answer: Option<&str>) -> Value {
    let mut action = json!({ "kind": "send_email", "recipient": "address", "address": "ops@example.com" });
    match answer {
        Some(id) => action["answer_id"] = json!(id),
        None => {
            action["subject"] = json!("Inline {ticket_number}");
            action["body"] = json!("Inline body");
        }
    }
    json!({ "name": "Mail ops", "trigger": "created", "actions": [action] })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_send_email_rule_uses_the_template_in_the_ticket_language(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        json!({ "code": "ops", "name": "Ops", "texts": [
            { "language": "en", "subject": "New {{ticket.number}}", "body": "English for {{ticket.subject}}" },
            { "language": "fr", "subject": "Nouveau {{ticket.number}}", "body": "Français pour {{ticket.subject}}" }
        ] }),
    )
    .await;
    let id = a["id"].as_str().unwrap();
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(id))).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    receive(
        &app,
        "inconnu@nowhere.example",
        "Commande",
        "Bonjour, nous avons bien reçu le devis et nous voudrions passer la commande. Merci et cordialement",
    )
    .await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1, "{mails:?}");
    let (to, subject, body) = &mails[0];
    assert_eq!(to, "ops@example.com");
    assert!(subject.starts_with("Nouveau T"), "{subject}");
    assert_eq!(body, "Français pour Commande");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_rule_with_a_template_is_validated_when_saved(db: PgPool) {
    let app = setup(db).await;
    // Unknown template.
    let (status, _) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some("00000000-0000-7000-8000-00000000dead"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // A typo in a placeholder would reach the customer: refused.
    let (_, typo) = post(&app, SUPPORT, "/prepared-answers", json!({ "code": "typo", "name": "Typo",
        "texts": [{ "language": "en", "subject": "Hi", "body": "Dear {{contact.nme}}" }] })).await;
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(typo["id"].as_str().unwrap()))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(r["message"].as_str().unwrap().contains("contact.nme"), "{r}");
    // Every language needs a subject.
    let (_, nosub) = post(&app, SUPPORT, "/prepared-answers", json!({ "code": "nosub", "name": "No subject",
        "texts": [{ "language": "en", "body": "Hi" }] })).await;
    let (status, _) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(nosub["id"].as_str().unwrap()))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn inline_mail_rules_keep_working_and_internal_tickets_get_no_customer_mail(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(None)).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    receive(&app, "anna@nowhere.example", "Hello", "Hello there").await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert!(mails[0].1.starts_with("Inline T"), "{:?}", mails[0]);
    // A rule that mails the customer does nothing for an internal ticket.
    let to_customer = json!({ "name": "To customer", "trigger": "created", "actions": [
        { "kind": "send_email", "recipient": "customer", "subject": "Hi", "body": "Hi" }] });
    post(&app, ADMIN, "/helpdesk/automation/rules", to_customer).await;
    let before = outbox(&db).await.len();
    manual_ticket(&app, &db, SUPPORT, "Colleague question", json!({ "internal": true })).await;
    let after: Vec<_> = outbox(&db).await;
    assert!(after.iter().skip(before).all(|m| m.0 != "customer@example.com"), "{after:?}");
    assert_eq!(after.len(), before + 1, "only the inline ops mail: {after:?}");
}
```

(The last test: the inline ops rule also fires for the manual ticket, so exactly one new mail appears (`ops@example.com`), none to a customer.)

- [ ] **Step 2: Run and watch them fail**

Run: `cargo test -p tradocraft-api --test helpdesk_templates a_send_email a_rule_with inline_mail 2>&1 | tail -20`
Expected: FAIL (unknown field is ignored by serde, validation demands a subject so the first two return 422).

- [ ] **Step 3: Add the field to `RuleAction`**

In `automation.rs`, after the `period_hours` field of `RuleAction`:

```rust
    /// `send_email`: a prepared answer (A6, ADR 0071). When set, `subject` and `body` are ignored and
    /// cleared; the answer's text in the ticket's language is sent.
    #[serde(default)]
    pub answer_id: Option<Uuid>,
```

Add `answer_id: None,` to every `RuleAction { .. }` literal in the `tests` module (the compiler lists them: `act()` and `priority()` helpers and the literals near lines 1110 to 1183). In `fn act`, the literal becomes:

```rust
        RuleAction {
            kind: kind.into(),
            user_id: None,
            team_id: None,
            value: None,
            flag: None,
            recipient: None,
            address: None,
            subject: None,
            body: None,
            period_hours: None,
            answer_id: None,
        }
```

- [ ] **Step 4: Validate in `automail::validate_action`**

Replace the part from `let subject = one_line(...)` through `a.body = Some(body);` with:

```rust
    if let Some(answer_id) = a.answer_id {
        // The text comes from a prepared answer: every language needs a subject, and a placeholder
        // that does not exist would reach the recipient as it is.
        let answer = crate::answers::load(&mut *conn, company_id, answer_id).await?;
        if answer.texts.is_empty() || answer.texts.iter().any(|t| t.subject.trim().is_empty()) {
            return Err(AppError::Validation(
                "send_email: the template needs a subject in every language it has".into(),
            ));
        }
        for t in &answer.texts {
            crate::render::check_placeholders(&format!("template {} subject", t.language), &t.subject)?;
            crate::render::check_placeholders(&format!("template {} body", t.language), &t.body)?;
        }
        a.subject = None;
        a.body = None;
    } else {
        let subject = one_line(a.subject.as_deref().unwrap_or(""));
        let body = a.body.as_deref().unwrap_or("").trim().to_string();
        if subject.is_empty() || subject.chars().count() > 200 {
            return Err(AppError::Validation(
                "send_email: a subject of at most 200 characters is required".into(),
            ));
        }
        if body.is_empty() || body.chars().count() > 5000 {
            return Err(AppError::Validation(
                "send_email: a body of at most 5000 characters is required".into(),
            ));
        }
        check_template("subject", &subject)?;
        check_template("body", &body)?;
        a.subject = Some(subject);
        a.body = Some(body);
    }
```

- [ ] **Step 5: Send in `automail::send`**

Replace the lines that build `customer`, `vars`, `subject` and `body` (from `let customer = t` through `let body = render(...)`) with:

```rust
    let (subject, body) = if let Some(answer_id) = a.answer_id {
        let (language, values) = crate::answers::ticket_values_for(
            conn,
            company_id,
            t.agent_name.as_deref().unwrap_or(""),
            ticket_id,
        )
        .await?;
        let answer = crate::answers::load(&mut *conn, company_id, answer_id).await?;
        let (text, _) =
            crate::answers::pick_text(&answer.texts, &language, &values["__company_language"])
                .ok_or_else(|| AppError::Validation("the template has no text".into()))?;
        (
            one_line(&crate::render::render(&text.subject, &values)),
            crate::render::render(&text.body, &values),
        )
    } else {
        let customer = t
            .customer_name
            .filter(|n| !n.trim().is_empty())
            .unwrap_or(t.contact_name);
        let vars = Vars {
            ticket_number: &t.number,
            subject: &t.subject,
            customer: &customer,
            agent: t.agent_name.as_deref().unwrap_or(""),
        };
        (
            one_line(&render(a.subject.as_deref().unwrap_or(""), &vars)),
            render(a.body.as_deref().unwrap_or(""), &vars),
        )
    };
```

(`t.customer_name` and `t.contact_name` are moved only in the `else` branch; `t.agent_name` is used by reference in both. Keep `.as_deref()` as written so there is no move conflict. If the compiler reports a partial-move error on `t`, clone `t.agent_name` into a local before the `if`.)

- [ ] **Step 6: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-helpdesk --lib 2>&1 | tail -8; cargo test -p tradocraft-api --test helpdesk_templates --test helpdesk_automation 2>&1 | tail -10`
Expected: PASS (the existing automation tests prove inline rules are unchanged).

- [ ] **Step 7: Commit**

```bash
git add crates/helpdesk/src/automation.rs crates/helpdesk/src/automail.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): send_email rules can use a prepared answer (A6)"
```

---

### Task 6: `ticket_languages` automation condition

**Files:**
- Modify: `crates/helpdesk/src/automation.rs` (`RuleConditions` near line 47, `Facts` near 140, `matches` near 183, `load_facts` near 385, `validate` near 631; test `facts()` near 962)
- Test: `crates/helpdesk/src/automation.rs` (unit), `apps/api/tests/helpdesk_templates.rs`

**Interfaces:**
- Produces: `RuleConditions.ticket_languages: Vec<String>` (JSON `ticket_languages`); `Facts.language: String`.

- [ ] **Step 1: Write the failing unit tests**

In the `tests` module of `automation.rs`, add `language: "nl".into(),` to the `facts()` helper literal (after `internal: false,`), then add:

```rust
    #[test]
    fn a_ticket_language_condition_matches_the_tickets_own_language() {
        let mut f = facts();
        f.language = "de".into();
        let c = RuleConditions {
            ticket_languages: vec!["de".into(), "fr".into()],
            ..Default::default()
        };
        assert!(matches(&c, &f));
        f.language = "nl".into();
        assert!(!matches(&c, &f));
        // Without the condition every language matches.
        assert!(matches(&RuleConditions::default(), &f));
    }
```

- [ ] **Step 2: Write the failing API test**

Append to `apps/api/tests/helpdesk_templates.rs`:

```rust
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_rule_can_route_tickets_by_their_language(db: PgPool) {
    let app = setup(db.clone()).await;
    let fr = team(&app, "Support FR").await;
    let (status, r) = post(
        &app,
        ADMIN,
        "/helpdesk/automation/rules",
        json!({ "name": "French to FR", "trigger": "created",
                "conditions": { "ticket_languages": ["fr"] },
                "actions": [{ "kind": "set_team", "team_id": fr }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["conditions"]["ticket_languages"], json!(["fr"]));
    manual_ticket(&app, &db, SUPPORT, "Bonjour", json!({ "language": "fr" })).await;
    manual_ticket(&app, &db, SUPPORT, "Hallo", json!({ "language": "de" })).await;
    let team_of = |subject: &'static str| {
        let db = db.clone();
        async move {
            sqlx::query_scalar::<_, Option<String>>("SELECT team_id::text FROM helpdesk.tickets WHERE subject = $1")
                .bind(subject)
                .fetch_one(&db)
                .await
                .unwrap()
        }
    };
    assert_eq!(team_of("Bonjour").await.as_deref(), Some(fr.as_str()));
    assert_ne!(team_of("Hallo").await.as_deref(), Some(fr.as_str()));
    // An unknown language code is refused.
    let (status, _) = post(
        &app,
        ADMIN,
        "/helpdesk/automation/rules",
        json!({ "name": "Bad", "trigger": "created", "conditions": { "ticket_languages": ["xx"] },
                "actions": [{ "kind": "set_priority", "value": "high" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
```

- [ ] **Step 3: Run and watch them fail**

Run: `cargo test -p tradocraft-helpdesk --lib automation::tests::a_ticket_language 2>&1 | tail -8; cargo test -p tradocraft-api --test helpdesk_templates route_tickets 2>&1 | tail -8`
Expected: FAIL (field `ticket_languages` and `language` do not exist).

- [ ] **Step 4: Implement**

`RuleConditions`, after `customer_languages`:

```rust
    /// The language of the ticket itself (nl, fr, en, de, es), which may differ from its customer's.
    #[serde(default)]
    pub ticket_languages: Vec<String>,
```

`Facts`, after `internal: bool,`: `pub language: String,`

`matches`, after the `customer_languages` block:

```rust
        && any_of(&c.ticket_languages, &f.language)
```

`load_facts`: add `language: String,` to the local `Row` struct, add `t.language::text AS language` to the SELECT (after `t.internal`: `t.internal, t.language::text AS language`), and `language: r.language,` to the returned `Facts`.

`validate`, after the `customer_languages` check:

```rust
    check_list(
        "ticket_languages",
        &c.ticket_languages,
        &tradocraft_core::LANGUAGES,
    )?;
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `cargo test -p tradocraft-helpdesk --lib 2>&1 | tail -8; cargo test -p tradocraft-api --test helpdesk_templates --test helpdesk_automation 2>&1 | tail -10`
Expected: PASS. If any other `Facts { .. }` or `RuleConditions { .. }` literal fails to compile (outside `..Default::default()`), add the new field there.

- [ ] **Step 6: Commit**

```bash
git add crates/helpdesk/src/automation.rs apps/api/tests/helpdesk_templates.rs
git commit -m "feat(helpdesk): ticket_languages automation condition (A6)"
```

---

### Task 7: Regenerate the API client and the Flutter changes

**Files:**
- Modify: `api/openapi.json`, `app/lib/api/generated/` (generated, do not edit by hand)
- Modify: `app/lib/features/helpdesk/answers_page.dart`, `ticket_screen.dart`, `automation_page.dart`
- Modify: `app/lib/l10n/app_nl.arb`, `app_fr.arb`, `app_en.arb`, `app_de.arb`, `app_es.arb` and the generated l10n Dart files
- Create: `app/test/answers_templates_test.dart`

**Interfaces:**
- Consumes: every backend task. Generated Dart names (verify after generation): `PreparedAnswer.kind/teamId/keywords`, `PreparedAnswerInput.kind/teamId/keywords`, `SuggestedAnswer`, `RuleAction.answerId`, `RuleConditions.ticketLanguages`, `Ticket.languageSource`, and the operation `suggestAnswers(id:, q:, kind:)` on the helpdesk API.

- [ ] **Step 1: Regenerate the client**

Run: `scripts/generate-api-client.sh` (read its header for prerequisites; it rewrites `api/openapi.json` and `app/lib/api/generated/`).
Then: `cd app && grep -n "suggest\|languageSource\|ticketLanguages\|answerId" lib/api/generated -r | head -20`
Expected: the five names above exist. Note the exact operation name of the suggest call and use it below; if it is not `suggestAnswers`, replace it in Steps 4 and 6.

- [ ] **Step 2: Add the strings (all five languages)**

Keys and English text (translate for nl, fr, de, es in each ARB file, next to the existing `preparedAnswers` key):

| Key | English |
|---|---|
| `answerKind` | `Kind` |
| `answerKindName` | select-style: `reply` Reply, `internal_note` Internal note, `handover` Hand-over, `notice` Notice |
| `answerTeam` | `Team` |
| `answerAllTeams` | `All teams` |
| `answerKeywords` | `Keywords (comma separated)` |
| `answerKeywordsHelp` | `Tickets whose subject contains a keyword get this answer suggested first.` |
| `answerShortcutHint` | `Type /code to insert an answer` |
| `ticketLanguageSource` | select-style: `record` Taken from the contact or customer, `detected` Detected from the message, `agent` Set by an agent |
| `ticketLanguage` | `Ticket language` |
| `mailTemplate` | `Template (optional)` |
| `mailTemplateNone` | `Write the text here` |
| `ticketLanguageCondition` | `Ticket language` |

For `answerKindName` and `ticketLanguageSource` follow the existing select-style pattern of `mailRecipientName` in the ARB files (an ICU `select` message with `other` fallback). Then run `cd app && flutter gen-l10n`.

- [ ] **Step 3: Write the failing widget tests**

Create `app/test/answers_templates_test.dart` using the same harness as `app/test/helpdesk_automation_test.dart` (copy its `_pump` helper and the `fake_http.dart` import; routes map `"METHOD /path"` to a JSON body):

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/answers_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _answer(String code, {String kind = 'reply', String? teamId}) => {
  'id': 'a-$code',
  'code': code,
  'name': 'Answer $code',
  'category': null,
  'kind': kind,
  'team_id': teamId,
  'keywords': <String>['pump'],
  'active': true,
  'updated_at': '2026-11-16T09:00:00Z',
  'texts': [
    {'language': 'en', 'subject': 'Re', 'body': 'Hello'},
  ],
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => home)]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the answer editor saves kind, team and keywords', (tester) async {
    final http = FakeHttp({
      'GET /helpdesk/teams': (_) => [
        {'id': 'team1', 'name': 'R&D', 'active': true, 'members': [], 'created_at': '2026-11-01T09:00:00Z'},
      ],
      'GET /prepared-answers/placeholders': (_) => ['ticket.number', 'team.name'],
      'POST /prepared-answers': (_) => _answer('fw', kind: 'internal_note', teamId: 'team1'),
    });
    await _pump(tester, http, const Scaffold(body: AnswerEditor()));
    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'fw');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Firmware');
    await tester.enterText(find.byKey(const ValueKey('answer-keywords')), 'Firmware, update');
    await tester.tap(find.byKey(const ValueKey('answer-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal note').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('answer-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('R&D').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Text').first, 'Body');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = http.bodies['POST /prepared-answers'] as Map;
    expect(sent['kind'], 'internal_note');
    expect(sent['team_id'], 'team1');
    expect(sent['keywords'], ['firmware', 'update']);
  });
}
```

(Adapt the label finders to the real l10n strings if `Code`/`Name`/`Text`/`Save` differ in English; they are `l.code`, `l.name`, `l.text`, `l.save` in `answers_page.dart`.)

- [ ] **Step 4: Run and watch it fail**

Run: `cd app && flutter test test/answers_templates_test.dart 2>&1 | tail -15`
Expected: FAIL (no widget with key `answer-keywords`).

- [ ] **Step 5: Implement `answers_page.dart`**

5a. In `_AnswerEditorState` add state:

```dart
  late String _kind = a?.kind ?? 'reply';
  late String? _teamId = a?.teamId;
  late final _keywords = TextEditingController(text: a?.keywords.join(', '));
```

5b. In `_save`, the `PreparedAnswerInput(...)` gains:

```dart
      kind: _kind,
      teamId: _teamId,
      keywords: _keywords.text
          .split(',')
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toList(),
```

5c. In `build`, add a team provider at the bottom of the file and read it:

```dart
final _teamsProvider = FutureProvider.autoDispose<List<Team>>(
  (ref) => ref.watch(apiProvider).helpdesk.listTeams(),
);
```

(use the generated name of the teams list call; `grep -n "teams" lib/features/helpdesk/automation_page.dart` shows how the rule editor loads them). After the first `Row` of fields (code, name, category, active) add a second row before the `TabBar`:

```dart
            gap,
            Row(
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('answer-kind'),
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.answerKind, isDense: true),
                    items: [
                      for (final k in const ['reply', 'internal_note', 'handover', 'notice'])
                        DropdownMenuItem(value: k, child: Text(l.answerKindName(k))),
                    ],
                    onChanged: (v) => setState(() => _kind = v ?? 'reply'),
                  ),
                ),
                gap,
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('answer-team'),
                    initialValue: _teamId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.answerTeam, isDense: true),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(l.answerAllTeams)),
                      for (final t in ref.watch(_teamsProvider).value ?? const <Team>[])
                        DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _teamId = v),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    key: const ValueKey('answer-keywords'),
                    controller: _keywords,
                    decoration: InputDecoration(
                      labelText: l.answerKeywords,
                      helperText: l.answerKeywordsHelp,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
```

5d. In the list page `subtitle`, show kind and team: change the `[a.code, if (a.category != null) a.category!, if (!a.active) l.inactive]` list to also include `if (a.kind != 'reply') l.answerKindName(a.kind)`.

- [ ] **Step 6: Implement the picker in `ticket_screen.dart`**

Replace `_AnswerPicker` so it takes the ticket id and the kind, asks the server for ranked suggestions and supports `/code`:

```dart
/// Ranked prepared answers for this ticket; returns the chosen one. Typing `/code` or a word narrows it.
class _AnswerPicker extends ConsumerStatefulWidget {
  const _AnswerPicker({required this.ticketId, required this.kind});
  final String ticketId;
  final String kind;

  @override
  ConsumerState<_AnswerPicker> createState() => _AnswerPickerState();
}

class _AnswerPickerState extends ConsumerState<_AnswerPicker> {
  String _q = '';
  late Future<List<SuggestedAnswer>> _answers = _load();

  Future<List<SuggestedAnswer>> _load() => ref
      .read(apiProvider)
      .helpdesk
      .suggestAnswers(
        id: widget.ticketId,
        q: _q.startsWith('/') ? _q.substring(1) : _q,
        kind: widget.kind,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.preparedAnswers),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(AppIcons.search),
                hintText: l.search,
                helperText: l.answerShortcutHint,
              ),
              onChanged: (v) => setState(() {
                _q = v.trim();
                _answers = _load();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<SuggestedAnswer>>(
                future: _answers,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _answers = _load()),
                        child: Text(errorMessage(snap.error!)),
                      ),
                    );
                  }
                  final list = snap.data ?? const <SuggestedAnswer>[];
                  return ListView(
                    children: [
                      for (final a in list)
                        ListTile(
                          key: ValueKey('suggest-${a.code}'),
                          title: Text(a.name),
                          subtitle: Text(a.code),
                          trailing: Text(a.language.toUpperCase()),
                          onTap: () => Navigator.pop(context, a),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
```

Update `_insertAnswer` (line 355): the dialog now returns a `SuggestedAnswer` that is already rendered, so the extra `renderAnswer` call goes away:

```dart
  Future<void> _insertAnswer() async {
    final answer = await showDialog<SuggestedAnswer>(
      context: context,
      builder: (_) => _AnswerPicker(
        ticketId: widget.id,
        // In the internal-note mode of the composer ask for notes, otherwise for replies.
        kind: _internalNote ? 'internal_note' : 'reply',
      ),
    );
    if (answer == null || !mounted) return;
    final l = context.l10n;
    setState(() {
      if (answer.subject.isNotEmpty) _replySubject.text = answer.subject;
      _body.text = _body.text.trim().isEmpty
          ? answer.body
          : '${_body.text.trimRight()}\n\n${answer.body}';
      _answerInfo = answer.fallback
          ? l.answerFallback(languageName(_language), languageName(answer.language))
          : null;
    });
  }
```

`_internalNote` must be the existing composer-mode field of the screen. Find it with `grep -n "internal" app/lib/features/helpdesk/ticket_screen.dart | sed -n 1,20p` (the composer already switches between reply and internal note; use that field's real name).

Also show where the ticket language came from, next to the language selector (`_language` is the ticket's language field): add a small `Text(l.ticketLanguageSource(ticket.languageSource), style: Theme.of(context).textTheme.bodySmall)` under the language dropdown, using the loaded ticket object the screen already holds (find the dropdown with `grep -n "_language" app/lib/features/helpdesk/ticket_screen.dart`).

- [ ] **Step 7: Implement `automation_page.dart`**

7a. Ticket-language chips: add state next to `_languages`:

```dart
  late final Set<String> _ticketLanguages = {
    ...?widget.rule?.conditions.ticketLanguages,
  };
```

In `RuleConditions(...)` (near line 464) add `ticketLanguages: _ticketLanguages.toList(),`. In the conditions summary (near line 88) add:

```dart
    if (c.ticketLanguages?.isNotEmpty ?? false)
      '${l.ticketLanguageCondition}: ${join(c.ticketLanguages!.map(languageName))}',
```

and in the editor, right after the `cond-language` `_chips(...)` call:

```dart
              _chips(
                l.ticketLanguageCondition,
                ruleLanguages,
                _ticketLanguages,
                languageName,
                'cond-ticket-language',
              ),
```

7b. Template selector in `_mailFields` (line 526). Add a provider at the bottom of the file:

```dart
final _mailAnswersProvider = FutureProvider.autoDispose<List<PreparedAnswer>>(
  (ref) => ref.watch(apiProvider).helpdesk.listAnswers(active: true),
);
```

Change `_MailTexts.build` so a template replaces the inline text:

```dart
  RuleAction build(RuleAction a) => RuleAction(
    kind: 'send_email',
    recipient: a.recipient ?? 'customer',
    teamId: a.recipient == 'team' ? a.teamId : null,
    address: a.recipient == 'address' ? address.text.trim() : null,
    answerId: a.answerId,
    subject: a.answerId == null ? subject.text.trim() : null,
    body: a.answerId == null ? body.text.trim() : null,
    periodHours: int.tryParse(period.text.trim()),
  );
```

In `_mailFields` change `with_` to carry the template and add a way to clear it:

```dart
    RuleAction with_({String? r, String? team, String? answer, bool clearAnswer = false}) =>
        RuleAction(
          kind: a.kind,
          recipient: r ?? recipient,
          teamId: team ?? a.teamId,
          answerId: clearAnswer ? null : (answer ?? a.answerId),
        );
```

Add, after the `address` field and before the subject `TextField`:

```dart
        DropdownButtonFormField<String?>(
          key: ValueKey('mail-template-$i'),
          initialValue: a.answerId,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.mailTemplate, isDense: true),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l.mailTemplateNone)),
            for (final x in ref.watch(_mailAnswersProvider).value ?? const <PreparedAnswer>[])
              DropdownMenuItem<String?>(value: x.id, child: Text('${x.code} · ${x.name}')),
          ],
          onChanged: (v) => setState(
            () => _actions[i] = _mailTexts[i]!.build(
              v == null ? with_(clearAnswer: true) : with_(answer: v),
            ),
          ),
        ),
```

and wrap the subject, body and (unchanged) period fields: show the subject and body `TextField`s only `if (a.answerId == null)`.

- [ ] **Step 8: Run the Flutter tests and watch them pass**

Run: `cd app && flutter analyze && flutter test test/answers_templates_test.dart test/helpdesk_automation_test.dart 2>&1 | tail -20`
Expected: no analyzer issues; PASS. Fix the existing automation tests only if they build a `RuleAction` that now needs `answerId` (it is optional, so they should not).

- [ ] **Step 9: Add two more widget tests**

Append to `answers_templates_test.dart` inside `main()`:

```dart
  testWidgets('choosing a template in a send_email action stores its id and hides the inline text',
      (tester) async {
    final http = FakeHttp({
      'GET /helpdesk/teams': (_) => <Object?>[],
      'GET /prepared-answers': (_) => [_answer('ops')],
    });
    await _pump(
      tester,
      http,
      Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showRuleEditor(c), child: const Text('open')))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Add a send_email action using the editor's own add-action control, then pick the template.
    await tester.tap(find.byKey(const ValueKey('add-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-template-0')), findsNothing);
  });
```

Before keeping this test, open `automation_page.dart` and find how an action row is added and how `send_email` is selected (`grep -n "add-action\|actionSendEmail\|kinds" app/lib/features/helpdesk/automation_page.dart`); rewrite the test body to select `send_email`, assert `mail-template-0` exists and `mail-subject-0` exists, choose the `ops · Answer ops` item, and assert `mail-subject-0` is gone. If the add-action control has a different key, use that key. The two assertions are the test; the navigation is whatever the existing `helpdesk_automation_test.dart` already does to reach a `send_email` action (copy that part).

- [ ] **Step 10: Commit**

```bash
git add api app
git commit -m "feat(app): template kind, team and keywords; ranked picker; template on mail rules; ticket language (A6)"
```

---

### Task 8: ADR, roadmap and final verification

**Files:**
- Create: `docs/adr/0071-helpdesk-reply-templates.md`
- Modify: `docs/ROADMAP.md` (status row for A6, the A6 section, a new A6b row), `docs/adr/README.md` (index line)

- [ ] **Step 1: Write the ADR**

```markdown
# 0071 Helpdesk reply templates and ticket language

**Status:** Accepted. Extends [ADR 0013](0013-helpdesk-email-and-languages.md) and [ADR 0066](0066-helpdesk-send-email-action.md).

**Context.** Prepared answers (ADR 0013) already hold one text per language with `{{placeholders}}`.
R&D and network administration also answer colleagues, and A5 mail rules had only inline text.

**Decision.**
- Prepared answers stay the one template model. They gain `kind` (`reply`, `internal_note`,
  `handover`, `notice`), an optional `team_id` and `keywords`. `code` is the shortcut (`/code`).
- `GET /tickets/{id}/prepared-answers/suggest` ranks answers (exact code, code prefix, name or keyword,
  keywords in the ticket subject, the ticket's team, a text in the ticket's language), leaves out other
  teams' answers and returns them filled in, at most ten.
- A `send_email` action can name an answer (`answer_id`, in the rule JSON). Saving checks that every
  language has a subject and only known placeholders, because nobody reads the mail first. Rules with
  inline text are unchanged.
- `tickets.language_source` is `record`, `detected` or `agent`. The order is unchanged: contact, then
  customer, then (internal tickets only) the creator's language, then the detected language of an
  unknown sender, then the company default. The detector stays the word list in `language.rs`.
- Rules can match `ticket_languages` (the ticket's own language) next to `customer_languages`.
- Permissions are unchanged: `answers.write` manages templates, `helpdesk.read` uses them.

**Deferred (A6b).** SLA notices to the customer keep their built-in texts. Using templates there needs
deadline placeholders and rendering without a logged-in user.

**Consequences.** One template model serves replies, internal notes, hand-overs and mail rules. The
agent still edits a reply before sending. Measuring the detector later is possible: a ticket whose
language was changed by an agent has `language_source = 'agent'`.
```

Add the matching line to `docs/adr/README.md` in the same format as the neighbouring entries.

- [ ] **Step 2: Update `docs/ROADMAP.md`**

Change the A6 status row to:

```markdown
| A6 Helpdesk reply templates and language | Done, [ADR 0071](adr/0071-helpdesk-reply-templates.md) (builds on the prepared answers of ADR 0013); SLA notices to the customer still use built-in texts, see A6b |
| A6b Helpdesk SLA notices from templates | Open (needs deadline placeholders and rendering without a user) |
```

and replace the "**A6 Reply templates and language detection** (medium)" bullet block with a short "done" paragraph pointing at ADR 0071 and listing what it delivered (kinds, team scope, keywords, suggestions, template on `send_email`, language source, `ticket_languages`).

- [ ] **Step 3: Run the full verification**

```bash
export DATABASE_URL=postgresql://tradocraft:tradocraft@localhost:5433/tradocraft
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cd app && flutter analyze && flutter test
```

Expected: everything passes. Fix `cargo fmt` complaints with `cargo fmt --all` and amend into the right task's commit or add a `style:` commit. Do not claim completion before every command above has printed success in this session (superpowers:verification-before-completion).

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs: ADR 0071 and roadmap for A6 reply templates"
```

- [ ] **Step 5: Finish the branch**

Use superpowers:finishing-a-development-branch: one PR for item A6 from `feat/a6-reply-templates`, merged after earlier PRs. After a rebase, regenerate (`scripts/generate-api-client.sh`, `flutter gen-l10n`) instead of resolving generated files by hand.

---

## Self-review

**Spec coverage** (spec sections and the revision section):
- kind, team scope, keywords: Task 1. Shortcut = `code`: Tasks 4 and 7 (`/code`).
- Placeholders, `{{team.name}}`, no new engine: Task 2.
- Language order, creator language for internal tickets, `language_source`: Task 3.
- Internal tickets get no customer mail: pinned by a test in Task 5 (existing behaviour).
- Suggest endpoint and picker: Tasks 4 and 7.
- `send_email` with `answer_id`, validation, inline still works: Task 5.
- `ticket_languages` condition: Task 6.
- Admin screen, picker, language source display, rule editor, five-language strings, widget tests: Task 7.
- ADR 0071, roadmap, A6b follow-up: Task 8.
- Not covered on purpose: SLA notice templates (A6b), team-lead management, a new permission, a new detector crate.

**Placeholder scan:** the only deliberately open items are two lookups the plan cannot pin without more reading, each with the exact command to resolve them and the rule to apply: the generated suggest operation name and the composer's internal-note field name (Task 7 Steps 1 and 6), and the add-action control used by the Flutter rule-editor test (Task 7 Step 9). No "TBD" or "similar to Task N" remains.

**Type consistency:** `KINDS`, `clean_keywords`, `Candidate`, `score`, `SuggestedAnswer`, `ticket_values_for(conn, company_id, agent_name, ticket_id)`, `load(conn, company_id, id)`, `check_placeholders(field, text)`, `RuleAction.answer_id`, `RuleConditions.ticket_languages`, `Facts.language`, `Ticket.language_source` are used with the same names and signatures in every task that mentions them.
