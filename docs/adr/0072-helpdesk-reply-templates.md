# 0072 Helpdesk reply templates and ticket language

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
