# 0063 — Helpdesk automation: the `send_email` action

**Status:** Accepted

**Context.** ADR 0021 gave automation rules six actions that change the ticket and said "no e-mail".
Teams want a rule to tell somebody: acknowledge a complaint, warn the owner of an urgent ticket, copy a
shared mailbox. A6 (templates) does not exist yet, so the text lives in the action for now. Mail must
not escape from a test or tutorial environment (ADR 0043, 0048) and a rule must not be able to mail
the same person over and over.

**Decision.**

* **Action** `send_email` joins the flat `RuleAction` (ADR 0021) with `recipient` (`customer` |
  `assignee` | `team` | `address`), `team_id` (for `team`), `address` (for `address`), `subject`,
  `body` and `period_hours`. Rules are still stored as JSON, so there is no migration for the rule
  itself. When A6 arrives the inline `subject`/`body` are replaced by a `template_id`; the other
  fields stay.
* **Recipients.** `customer` is the ticket's contact address (never on an internal ticket, nothing
  when it is empty or malformed); `assignee` is the owner when the user is active; `team` is every
  active member of the team who belongs to the company; `address` is a fixed address (lower-cased,
  checked at save time). A recipient that cannot be resolved means no mail, not an error.
* **Placeholders** `{ticket_number}`, `{subject}`, `{customer}` (customer name, else the contact
  name) and `{agent}` (the owner's name, empty when there is none). Other text, including braces, is
  left alone, but a `{lower_case_word}` that is not a placeholder is a 422 when the rule is saved, so a
  typo is caught early. The subject is collapsed to one line (no header injection); subject is at
  most 200 and body at most 5000 characters. Text is plain, in the language the author wrote it in.
* **Queueing.** The mail is written to `core.mail_outbox` in the transaction of the ticket event and
  sent by the worker's system-mail loop. That loop is the single place where the outbound policy of
  ADR 0048 is applied, so outside a live environment the mail becomes a `.eml` file and is never sent.
* **When.** After all changes of the run (including the SLA re-sync), for every matched rule, in
  rule and action order, so `{agent}` shows the owner a `set_owner` action just set. A rule with
  `stop_on_match` still ends the run for later rules, but its own mails are sent.
* **Loop guard.** `helpdesk.automation_mail_log (rule_id, ticket_id, action_no, sent_at)`. An action
  claims the right to send with one atomic upsert that succeeds only when no mail was queued for the
  same rule, ticket and action position within `period_hours` (default 24, 1 to 2160). Concurrent
  events send once. Two rules mailing the same address are two mails: the guard is per rule. The log
  is deleted with the rule or the ticket. Moving or deleting actions of a rule can reuse an old
  position's record, which only ever suppresses a mail, never repeats one.
* **Audit.** `automation_mail_queued` on the ticket (system event, no user): rule, recipient kind
  and the number of mails. Addresses are not stored in the audit data.
* **Dry run** lists the action as a change of kind `send_email` and sends nothing.
* **Flutter.** The rule editor offers *Send e-mail*: recipient, team or address, subject, message
  with the placeholder list, and the period. Typed text survives adding, removing and re-typing other
  actions.

**Consequences.**
* A rule that matches on every `updated` event mails at most once per period; the customer who
  replies to an automatic mail can trigger `customer_replied` rules, and the guard bounds the chain.
* The mail is not part of the ticket thread (it is system mail, not an article), so a customer's
  reply to it is not threaded unless the author puts the number in the text. Use `{ticket_number}`.
* The text is not translated; a company that serves several languages writes one rule per
  `customer_languages` condition until A6.

**Not yet.** Templates (A6), per-language text in one action, HTML mail, attachments, CC and a
send log in the app.
