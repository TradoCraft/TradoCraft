# 0090 — Work-centre planning board and finite loading

**Status:** Accepted (in implementation; the work-centre half of C3 of the roadmap; extends
[ADR 0063](0063-work-centres-routings-and-operations.md), reuses the board of
[ADR 0024](0024-planning-board.md))

**Context.** ADR 0063 gave operations dates and the capacity page shows the load per work centre and
day, but scheduling ignores every other order (infinite capacity), an operation can be moved onto a
closed day or an overloaded centre without a word, and planners have no board to move work on. The
field-jobs half of C3 (ADR 0024) has one: `ResourceBoard`, a dry-run check with `force`, conflicts
with translated message keys.

**Decision.**

1. **Day granularity.** `production.order_operations` keeps `planned_start` and `planned_end` as dates;
   there is no migration. An operation's minutes are spread over the working days of its range in
   proportion to what each day offers (`schedule::spread_load`, as the capacity page does). The board
   shows one block per day.
2. **Finite rule** (`finite::schedule_finite`). A day offers the centre's capacity minutes (one unit's
   minutes times its parallel units) minus the minutes the other operations already book. One
   operation runs on one unit, so it takes at most one unit's minutes of a day however many units
   are free. Operations of one call count against each other. A centre with no free working day in
   two years gives up with the same message as infinite scheduling.
3. **Conflicts of a move** (`finite::detect`, pure). Errors, which need `force` (except an inactive
   work centre and an operation that has started or finished, which are never moved): inactive work centre,
   operation already started or finished, a first or last day without working minutes (closure or
   day off), overload of a day (this operation's share plus the others' load exceeds the capacity),
   starting before the previous operation of the order ends. Warnings: ending after the next
   operation of the order starts, ending after the order's planned-ready date. Each has a
   `message_key` `production.conflict.*` the app translates. Parent and subassembly orders are not
   modelled: moving work between orders only warns through these date checks.
4. **Endpoints.** `GET /production/planning-board?from&to&division_id` (`production.read`, at most 62
   days) returns the capacity per centre and day of `GET /production/capacity` plus the open
   operations of released and in-progress orders with the neighbouring dates the checks need.
   `PUT /production-orders/{id}/operations/{operation_id}/move?dry_run&force` (`production.write`) takes
   the body of the existing operation update and returns the conflicts; `dry_run` never writes, errors
   without `force` are a 409 naming the conflict keys (a forced move is also recorded as
   `operation_move_forced`), a write records `operation_updated` in the audit
   trail like the unchecked `PUT`, which stays for compatibility. No new permission and no new module.
5. **Finite re-schedule.** `POST /production-orders/{id}/schedule` takes `finite: true` to place the
   pending operations around the load of the other operations; the default stays infinite so existing
   planners and tests see no change. The planned-ready date still never moves by itself.
6. **Load of a running operation** counts in full, as on the capacity page, because no progress is
   recorded.
7. **App.** A work-centre board on `ResourceBoard` (rows are centres with a utilisation badge, shades
   for closed and overloaded days, a debounced dry-run preview while dragging, a confirmation to force
   a move with errors, late operations listed beside the board, an agenda under 720 px).

**Consequences.**

- No stored data changes, so nothing to back-fill; the finite rule only applies to the new board, the
  move endpoint and the `finite` option.
- Capacity is per day, not per hour: two operations may share a day without a sequence on the centre.
- A forced move leaves the overload visible on the capacity page and the board; nothing re-flows the
  other operations (a whole-queue re-flow is later work).

**Not done yet.** Suggestions of the earliest free slot or centre; per-hour or sequenced loading on a
centre; a re-flow of the queue after a move; moving whole production orders; dependencies between a
parent order and its subassembly orders in the checks; per-person capacity.
