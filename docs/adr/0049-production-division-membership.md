# 0049 — Production division membership

**Status:** Accepted

**Context.** ADR 0036 introduced production divisions (electricity, electronics, mechanics, ...) as the
teams orders are queued for, but divisions were not linked to people. Every user with
`production.read` saw the whole queue and had to pick their division by hand in a dropdown each time.
Workers want to open the queue and see their own work; some workers belong to several divisions;
planners, sales and the administrator need the whole picture. ADR 0036 left this open: this ADR
adds membership and does not change the decisions of ADR 0036.

**Decision.** Divisions get members, and the production queue uses them as a default scope.

*Schema.* `production.division_members (company_id, division_id, user_id)` with primary key
`(division_id, user_id)`, so one user can be in several divisions and in one only once. Both foreign
keys cascade on delete and are composite with the company: `(division_id, company_id)` references
`production.divisions` (made unique on `(id, company_id)` for this) and `(user_id, company_id)`
references `core.user_companies`, so the database itself refuses a member of another company.
Members are maintained by the administrator (`production.admin`) as part of the division.

*API.* A `Division` carries `members` (user id and display name) and `is_member`, whether the calling
user is one of them. `DivisionInput.member_user_ids` replaces all members when present and leaves
them unchanged when absent. Only active users of the company are accepted (422 otherwise). Member
changes are audited with the division's `created` and `updated` events. `GET /production-orders`
takes `mine` (default false). With `mine=true` the queue holds the orders whose division is one of the
caller's divisions, plus the orders that have no division, so unassigned work is never lost. It
combines with the `division_id` filter. A caller without any division gets only the unassigned orders
with `mine=true`, which is why the app does not offer the scope to them.

*Scope rule in the app.* The queue defaults to "My divisions" when the user is a member of at least
one division and holds neither `production.write` nor `production.admin`. Planners, sales, admins and
workers without a division start on "All divisions". A segmented control switches between both, next
to the existing division dropdown, and the choice is remembered per user on the device. The control
is hidden when the user has no division. The user's divisions are shown as chips. An empty "My
divisions" view says that unassigned orders are included and offers "Show all divisions".

*Unassigned orders.* An order with no division belongs to nobody and therefore to everybody: it is
shown in every "My divisions" view until a planner gives it a division.

*Default scope, not enforcement.* Nothing is hidden by the server: `mine` is an opt-in filter and
every user with `production.read` can still read, open and (with the right permission) work on any
order. Divisions describe who normally does what, not who may. A worker often helps another team, an
order moves between divisions, and permission to act stays with the roles (ADR 0036). Hiding orders
would have to be mirrored in every screen that links to a production order (sales order, delivery,
tickets), and would turn a forgotten membership into an invisible order.

*Follow-up.* Membership for other work (work centres, routings) is not part of this decision. ADR 0036 is not changed; this ADR extends its divisions.
