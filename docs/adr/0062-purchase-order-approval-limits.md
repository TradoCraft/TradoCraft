# 0062 — Approval limits on purchase orders

**Status:** Accepted

**Context.** Any user with `purchasing.approve` could approve an order of any size. ADR 0046 listed
"approval limits and multi-level approval" as out of scope. A 20-50 user company wants its purchasers
to approve routine orders and a manager to approve the large ones.

**Decision.** Migration `20270203000001_purchasing_approval_limits.sql`; module
`purchasing::approval`.

* **Per role, not per user.** Roles are fixed in code (ADR 0004) and users are administered by role,
  so a limit belongs to a role: `purchasing.approval_limits (company_id, role, max_amount)`. Per-user
  limits would need their own screen and a rule for people who leave; they can follow.
* **No row means no limit.** Nothing changes for an installation until an administrator sets a limit.
  `admin` is never limited and cannot be given a limit, so the company cannot lock itself out of
  approving. Only roles that may approve (`purchasing.approve`) can be given one: today `purchaser`.
* **What is compared.** The order's **net total** (`subtotal`, excluding VAT) against the limit, in
  the **company's currency**. An order exactly at the limit may be approved. There is no currency
  conversion, so an order in another currency can only be approved by someone without a limit.
* **Several roles.** A user with more than one approving role gets the best of them: no limit when
  any approving role has none, else the largest limit. Roles that cannot approve do not count.
* **The check.** `orders::approve` calls `approval::check` after the status check and before the
  update, inside the same transaction. A refusal is a **403** with a message that names the order,
  its net total and the limit; the order stays a draft.
* **Who sets limits.** `PUT /purchasing/approval-limits` needs `users.admin`, so the people who are
  limited cannot raise their own limit. It takes `{ limits: [{ role, max_amount }] }`; a null or
  missing `max_amount` removes the limit, roles that are not listed are left alone, an unknown or
  non-approving role, `admin`, a negative amount or more than two decimals is a 422. Every change
  is audited with the limits before and after.
* **Reading.** `GET /purchasing/approval-limits` (`purchasing.read`) returns the currency, every
  limitable role with its limit and the caller's own (`your_limit`, null when unlimited).
* **App.** An "Approval limits" segment in Purchasing, visible with `users.admin`: one field per
  role, an empty field meaning no limit. A refused approval shows the server's message in the
  order's banner.

**Not done.**
* No multi-level approval (a second approver above a threshold) and no rule against approving your
  own order. Both are plain additions to `approval::check`.
* No per-user or per-supplier limits, no currency conversion, and no limit on goods receipt or on
  approving supplier invoices (ADR 0046 has its own approve permission).
* The order screen does not warn before the click; the refusal appears after it.
