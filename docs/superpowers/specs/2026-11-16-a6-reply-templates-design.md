# A6 Helpdesk reply templates and language: design

Status: draft for review. Roadmap item A6. ADR to be written with the implementation: 0071.

## Finding that shapes the scope

Most of the roadmap's A6 text already exists:

- Prepared answers ([ADR 0013](../../adr/0013-helpdesk-email-and-languages.md), `crates/helpdesk/src/answers.rs`):
  a text per language (nl, fr, en, de, es), `{{placeholders}}`, list/create/update endpoints and
  `POST /tickets/{id}/prepared-answers/{answer_id}/render`.
- `crates/helpdesk/src/language.rs`: a common-word language guesser, used when an inbound mail
  creates a ticket. `tickets.language` exists.
- Tickets already have an `internal` flag, `pending_internal` and internal notes (colleagues such as
  R&D and network admin answer colleagues).

A6 is therefore an **extension of prepared answers**, not a new template system. The roadmap entry
is corrected as part of this item.

## Goals

1. One template model and one placeholder syntax for replies, internal notes, hand-overs and A5 mails.
2. Templates scoped to the company or to a team, with a `kind`.
3. A language chain that also works for internal tickets (requester is an employee).
4. Templates usable from the reply editor (search and shortcut) and from A5 automation and notices.
5. A `language` automation condition so tickets can route by language.

## Non-goals

- A new detector crate. The current word-list detector stays; revisit when measured on real tickets.
- A standalone chat or messaging feature, personal private templates, automatic sending by keyword.
- Changing the existing `{{x}}` semantics (values inserted stay literal).

## Design

### Data (one migration, with a timestamp unique among open branches)

On `helpdesk.prepared_answers`:
- `kind text not null default 'reply'`: `reply | internal_note | handover | notice`.
- `team_id uuid null` (null means company-wide), references the team table.
- `shortcut text null`, unique per company (case-insensitive) when set.
- `keywords text[] not null default '{}'`: used only to rank suggestions.

On `helpdesk.tickets`:
- `language_source text not null default 'default'`: `detected | customer | user | agent | default`.
  Backfilled as `default` for existing rows (unknown history is not guessed).

On the automation action (`send_email`) and the SLA notice settings: an optional `answer_id`.
When set it overrides the inline subject and body; when null the inline text keeps working
unchanged. No automatic conversion of existing rules.

### Placeholders

One module in `core` or `helpdesk` that owns the placeholder list and rendering. It accepts both
`{{name}}` (answers) and `{name}` (A5), because a stored text may use either. Unknown names are
rejected on save. New names: `{{order}}` is kept, `{{team}}` is added. Inserted values stay literal
(no re-expansion), subjects are one line. `automail::render` and `answers` call the shared module
so there is one set of tests.

### Language chain

`resolve_ticket_language(ticket)`, a pure function with a table test:

1. language set by the agent (`language_source = agent`);
2. detected language, when the detector returns one;
3. for a customer ticket: the contact's, then the customer's language;
   for an `internal` ticket: the requester user's `users.language`;
4. the company default language.

A template renders in that language; if it has no such variant: English, then any variant, and the
agent is warned (existing behaviour, kept). The agent can override the language on the ticket
(`PATCH`), which sets `language_source = agent`.

### Internal tickets

- Customer-only mail is not sent for `internal` tickets: SLA notices to the customer and the CSAT
  survey. A `send_email` rule with a customer recipient on an internal ticket is skipped and logged.
- Templates of kind `internal_note` and `handover` are offered in the note and hand-over dialogs.
- A team (for example R&D, network admin) can own templates for its own internal answers.

### Permissions

- Use: any agent with `helpdesk.reply` (replies) or note rights (notes).
- Manage company-wide templates: `helpdesk.templates.manage` (administrators).
- Manage team templates: the same permission or team lead of that team.
- Every change goes through `audit::record`.

### API

- `GET /prepared-answers?kind=&team_id=&q=&shortcut=` (extended).
- `GET /tickets/{id}/prepared-answers/suggest?q=` ranked by shortcut match, keyword match, team and
  language; already rendered in the resolved language.
- `PUT /prepared-answers/{id}` accepts the new fields.
- `PATCH` of the ticket language sets the source.
- OpenAPI and the Dart client regenerated with `scripts/generate-api-client.sh`.

### Automation

- New condition `language` (one of the five codes) in the rule engine; validated on save.
- The `send_email` action and SLA notice settings accept `answer_id` (see Data).

### Flutter

- Reply and note editors: a template picker (search, kinds filtered by context, typing `/shortcut`
  inserts). Shows the language that will be used and a warning on fallback.
- Ticket header: language chip showing the source, with an override menu.
- Administration: a template list with kind, team, shortcut and keywords; a variant editor per
  language with a placeholder helper and preview.
- Automation rule and SLA notice screens: an optional "use template" selector.
- Strings in nl, fr, en, de, es.

## Testing

- Unit: placeholder rendering and rejection (both syntaxes, literal values), `resolve_ticket_language`
  table (every branch, internal and customer), suggestion ranking.
- `sqlx::test`: team versus company scope, shortcut uniqueness, permissions, tenant isolation
  (`company_id`), internal tickets skip customer mail, `answer_id` overrides inline text and
  inline-only rules are unchanged.
- Automation: `language` condition routing.
- Widget tests: picker, shortcut insertion, language override, admin editor.
- Per-item verification commands from `docs/ROADMAP.md`.

## Deliverables

Migration, API, regenerated OpenAPI and Dart client, Flutter screens, five-language strings, tests,
ADR 0071, and the roadmap updated (A6 status, corrected description).

## Open decisions (made here, change on review)

- Existing A5 rules are not auto-converted to templates.
- Keywords only rank suggestions; nothing is sent automatically.
- The detector stays as it is. `language_source` shows how often agents override a detection, which is
  the data needed to judge it later.

## Revision after reading the code (supersedes the lines above where they conflict)

Found while writing the plan; each point replaces the earlier text.

- **No `shortcut` column.** `prepared_answers.code` is already unique per company and is the shortcut
  (`/code` in the picker). Keywords only rank suggestions.
- **Language order stays as it is today** (contact or customer language beats the detector, which only
  decides for an unknown sender). New: an `internal` ticket without contact or customer takes the
  language of its creator (`core.users.language`), then the company default. `language_source` is
  `record` (taken from contact, customer, creator or company), `detected`, or `agent` (given or
  changed by an agent). The earlier chain that put detection first is dropped.
- **Customer-only mail on internal tickets needs no new work:** `automail::send` already skips the
  `customer` recipient for internal tickets, and SLA notices only go to the channels `email` and
  `portal`. The plan adds a test that pins this.
- **SLA notices are deferred to a follow-up (A6b).** They are built-in five-language texts with
  deadline data that prepared-answer placeholders cannot express yet, and rendering needs a system
  context without a logged-in user. A6 covers the `send_email` action only; an A6b entry goes on the
  roadmap.
- **The new condition is `ticket_languages`** (the ticket's own language). The existing
  `customer_languages` condition stays.
- **`answer_id` on `send_email` is stored in the rule's JSON**, so it needs no migration. When set,
  the inline subject and body are ignored and cleared. Every language variant of the answer must have
  a subject and only known placeholders when the rule is saved. (Answers themselves still accept
  unknown placeholders: agents rely on them staying visible.)
- **Permissions:** `answers.write` (already held by support, sales and admin) manages templates; there
  is no new permission and no team-lead management. Reading stays `helpdesk.read`.
- **New placeholder:** `{{team.name}}`. `{x}` (A5) and `{{x}}` (answers) stay separate syntaxes: A5
  rules with inline text keep `{x}`, templates use `{{x}}`.
