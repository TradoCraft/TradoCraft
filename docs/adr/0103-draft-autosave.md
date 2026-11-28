# 0103 — Draft autosave (D8)

**Status:** Proposed (builds on [ADR 0073](0073-concurrent-edit-protection.md) and the local storage of
[ADR 0022](0022-technician-offline-queue.md))

**Context.** A long text typed in the app is lost when a tab closes, the app crashes or the connection
drops: a ticket reply, an internal note, a knowledge base article, a quotation remark. Today the only
saved draft is the one mail-merge draft per user (ADR 0098). The "autosave" setting in preferences
refers to saving records periodically in the form view, not to these texts.

**Decision.**
- **One generic draft store**, `core.drafts`: `company_id`, `user_id`, `kind`, `record_id`, `field`,
  `body`, `base_version` (nullable), `updated_at`, unique on `(company_id, user_id, kind, record_id,
  field)`. A user sees and changes only their own drafts. Kinds are an allowlist: `ticket_reply`,
  `ticket_note`, `kb_article`, `quotation_remark`; each maps to the permission needed to read the
  record, which is checked on every call. An unsent draft is private: no audit event, no chatter.
- **API** (`crates/core`, tag `drafts`): `PUT /drafts/{kind}/{record_id}/{field}` stores or replaces,
  `GET` returns one (404 when none), `DELETE` removes, `GET /drafts?kind=` lists the caller's drafts
  (for a "you have unsent drafts" hint). `PUT` is idempotent, takes `If-Match`-style `base_version`
  from ADR 0073 where the record has one, and refuses a body above 200 KB (422). An empty body deletes.
- **Cleared by the action, not only by the client.** The handlers that complete the action delete the
  matching draft inside their own transaction: ticket reply sent, internal note added, article saved or
  published, quotation remark saved. A client that crashes after sending therefore cannot bring back a
  draft that was already sent. The client also calls `DELETE` after success, which is a no-op then.
- **Retention.** The worker deletes drafts not touched for 30 days (`DRAFT_RETENTION_DAYS`, default 30).
  Environment clones anonymise or drop drafts (ADR 0043), like the mail-merge draft.
- **Client behaviour (Flutter and Leptos).** One small controller per text field:
  - A local copy is written on every change batch (about 500 ms debounce): `shared_preferences` in
    Flutter (reusing the key prefix of the offline queue, ADR 0022), `localStorage` in Leptos. Keys
    include server, company and user so two people on one device never see each other's text.
  - A server save runs every 5 s while the text changed, and on leaving the screen. The preferences
    interval (`autosaveMinutes`) keeps governing record autosave in forms and does not slow this.
  - On return the newer of the local and server copy is offered ("restore your draft from 14:02"),
    with a discard choice. A draft whose `base_version` is older than the record's current version is
    offered next to the current text, not silently applied (ADR 0073).
  - Offline, saves wait for the next successful request; the local copy covers the gap.
  - Never autosave an empty or unchanged text, and never write a draft for a field the user cannot
    change.
- **Fields in scope for this round.**

  | Kind | Flutter | Leptos |
  |---|---|---|
  | `ticket_reply` | ticket screen reply box | ticket page reply box |
  | `ticket_note` | ticket screen internal note | ticket page internal note |
  | `kb_article` | article editor (body, per language) | staff KB editor |
  | `quotation_remark` | quotation line remark | not available: Leptos has no remark editor |

  `field` carries the language for articles and replies (`body.nl`), so a draft per language survives.

**Consequences.** A crash, a closed tab or a lost connection loses at most a few seconds of typing. A
draft is one row per user and field, so storage stays small; the 30-day sweep keeps it that way. The
store is generic: other long texts join by adding a kind and a permission check.

**Deferred.** Drafts for other long texts (order remarks, field job reports), a list screen for
unsent drafts, and sharing a draft with a colleague.
