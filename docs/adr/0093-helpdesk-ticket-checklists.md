# 0093 — Helpdesk ticket checklists

**Status:** Accepted (retrospective; A7 of the roadmap, PR #100; extends [ADR 0017](0017-helpdesk-sla-teams-attachments.md)
and [ADR 0021](0021-helpdesk-business-hours-automation-reporting.md); the item shape follows the field job checklist of
[ADR 0015](0015-repairs-field-service-and-photos.md) and [ADR 0020](0020-field-service-reports-contracts.md))

**Context.** Some tickets need the same steps every time (a return, an installation question, a
complaint), and nothing on the ticket said which steps were done or by whom. Agents kept such lists
in notes, which cannot be ticked off, counted or checked before a ticket is closed. Field jobs
already had a checklist (`field.job_tasks`: ordered tasks, a done flag, who and when).

**Decision.** Part of `tradocraft-helpdesk` (module `checklists`, migration
`20270219000001_helpdesk_checklists.sql`).

1. **Items on the ticket.** `helpdesk.ticket_checklist_items` has the shape of `field.job_tasks`
   (`position`, `description`, `done`, `done_by`, `done_at`, unique `(ticket_id, position)`) plus the
   `template_id` it came from (set to NULL when the template is deleted). It is a table of its own,
   not shared with field service: the two lists belong to different records and permissions. Marking
   an item done records the user and the time; marking an already done item done again keeps the
   first ones; undoing clears both.
2. **Endpoints.** `GET` and `POST /helpdesk/tickets/{id}/checklist` (an added item goes to the
   end), `PATCH /helpdesk/tickets/{id}/checklist/{item_id}` (`done`, `description` and/or a
   1-based `position`, clamped; the others keep their order and are renumbered in two passes through
   negative positions, so the unique constraint never collides) and `DELETE` of an item. Reading
   needs `helpdesk.read`, writing `helpdesk.write`. Every write locks the ticket row
   (`checklists::lock_ticket`, `SELECT ... FOR UPDATE`), the same lock that status changes, notes,
   replies and mail ingestion take, so a tick and a close cannot cross. After the commit the open
   ticket screens are told of the change (`notify_change`, [ADR 0075](0075-helpdesk-live-ticket-updates.md)).
   Item changes are not written to the audit trail.
3. **Templates.** `helpdesk.checklist_templates` (per company: `name`, optional `team_id`, optional
   `category` from the ticket categories, `active`) with ordered `helpdesk.checklist_template_items`.
   `GET /helpdesk/checklist-templates` (filters `team_id`, `category`, `active`) needs
   `helpdesk.read`; `POST`, `PUT` and `DELETE /helpdesk/checklist-templates/{id}` need
   `helpdesk.admin` and are audited (`checklist_template`). Saving replaces the template's items.
   Team and category only describe where a template fits: nothing is applied automatically because
   of them.
4. **Applying a template.** `POST /helpdesk/tickets/{id}/checklist/apply-template` (`template_id`,
   `helpdesk.write`) appends the template's items after the existing ones. It is idempotent per
   ticket and template: `helpdesk.ticket_applied_templates` (primary key `(ticket_id, template_id)`)
   records the first application, and a second one changes nothing. An inactive template is refused
   (422). Items copied from a template are ordinary items afterwards; later changes to the template
   do not reach tickets.
5. **Automation action `apply_checklist`** (`template_id`) for the rules of
   [ADR 0021](0021-helpdesk-business-hours-automation-reporting.md), through the same
   `apply_template_to_ticket`. Saving a rule checks that the template exists in the company. When
   the rule runs and the template has since been deleted or made inactive, the action is skipped
   (logged), not an error.
6. **Close gate per team.** `helpdesk.teams.require_checklist_done` (default false, set by
   `helpdesk.admin` on the team). While it is set, changing a ticket of that team to `closed` with an
   open item is refused with 409 `checklist_incomplete`. The check runs in `set_status` and again
   after the automation rules have run (a rule may change the team), on every path that changes the
   status: ticket update, note and reply with a status, `POST /tickets/{id}/status`
   ([ADR 0088](0088-tickets-on-the-kanban-board.md)) and the bundle mass update
   ([ADR 0076](0076-helpdesk-ticket-links-and-bundles.md)). A ticket without a team, or one already
   closed, is not checked.
7. **Progress on the ticket.** `Ticket` carries `checklist_total` and `checklist_done` (counted in
   the ticket query).
8. **App.** `ChecklistProgressBadge` (`done/total`, green when complete) on the ticket list, the
   ticket board and the ticket screen, shown only when the ticket has items. `TicketChecklistCard` on
   the ticket screen: tick, add, edit, move up and down, delete, and apply a template from a menu of
   active templates, those matching the ticket's team or category first. A refused close shows its
   own message. Helpdesk settings gain the team switch and a checklist templates card; the automation
   page offers `apply_checklist` with a template picker.

**Consequences.**

- Templates are snapshots: improving a template does not update the tickets it was applied to, and
  a template applied once cannot be applied to the same ticket again, even after its items were
  deleted.
- Deleting a template keeps the items on tickets; rules that name it stop doing anything without
  telling anyone.
- Merging a ticket into another closes it without the gate.
- The gate is all or nothing per team; there are no optional items and no gate per category.
- Checklists are internal: the customer portal does not show them.

**Not done yet.** Applying templates by team or category without a rule; optional or required
items; an audit or timeline entry for ticked items; showing checklists in the portal; sharing one
checklist model with field service.
