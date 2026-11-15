# 0028 — Modules and user administration

**Status:** Accepted

**Context.** Not every user needs every area of the ERP, and until now the only way to create a
user or change roles was SQL. We need (a) to hide whole areas per company and per user, enforced on
the server, and (b) screens/endpoints to manage the people of a company. The customer portal is a
different identity model (contacts with single-use links) and is out of scope.

**Decision.** Migration `20270106000001_modules_users_admin.sql`; code in
`crates/core/src/{modules,admin}.rs` and the `CurrentUser` extractor in `auth.rs`.

The header comment of `20270106000001_modules_users_admin.sql` cites ADR 0027, the number this ADR had when the file was first committed. It is frozen on purpose (sqlx checksums); see the [runbook](../runbooks/sqlx-migration-checksums.md).

* **Modules** are a fixed catalogue in code (`Module`), each owning a set of permissions. A
  permission belongs to exactly one module or is on the always-on list (`modules::ALWAYS_ON`,
  today only `users.admin`); a unit test fails when a new `Permission` is neither.

  | Module (code) | Permissions | Requires |
  |---|---|---|
  | `customers` | customers.read/write, contacts.write, opportunities.read/write, rebates.write | none |
  | `products` | products.read/write, prices.write, price_lists.read/write, inventory.cost | none |
  | `sales` | quotations.read/write, orders.read/write, prices.backdate, shipping.manage | customers, products |
  | `engineering` | bom.read/write, serials.read/write | products |
  | `inventory` | inventory.read/write/admin | products |
  | `helpdesk` | helpdesk.read/write/reply/admin, answers.write | none |
  | `kb` | kb.read/write/admin | none |
  | `repairs` | repairs.read/write/route, departments.write | customers |
  | `field` | field.read/work/plan | customers |

  Shipping requests belong to `sales`. `inventory.cost` (standard cost) is owned by `products`
  because it is a property of the product master; the inventory module only reads it.
* **`requires`** lists the modules whose records a module cannot do without, derived from
  mandatory references in the data model (NOT NULL foreign keys) rather than from permission
  checks, because handlers do not check each other's permissions (cross-crate library calls are not
  permission based): quotations and orders reference a customer and product lines; BOMs and serials
  reference products; stock is kept per product; repairs and field jobs reference a customer.
  Optional links (tickets to customers, knowledge base to helpdesk tickets) are not dependencies;
  the two KB routes that need both `kb.read` and `helpdesk.read` simply return 403 when helpdesk is
  off. The list is deliberately minimal.
* **Storage: only what is disabled.** `core.companies.disabled_modules text[]` (company level) and
  `core.user_companies.disabled_modules text[]` (per member). Defaults are empty, so existing
  installs keep everything on with no backfill. A user's effective set is the **union**: a user can
  narrow what the company allows, never widen it. Saving validates that codes are known and that no
  enabled module requires a disabled one (company: on the company set; user: on the combined set).
* **Enforcement** is in the extractor: both arrays are loaded with the membership, `CurrentUser`
  carries the effective disabled modules, `can()` is false for permissions of a disabled module,
  `permissions()` (and so `/me`) drops them, and `require()` answers 403 "module X is disabled" when
  the module is the cause (plain "missing permission" if the role never granted it). `/me` gains
  `modules: [{code, enabled}]`. Library calls between crates are unaffected. The customer portal
  does not use `CurrentUser` and is unaffected by module switches.
* **Roles stay in code** (`ROLES`, `role_grants`; ADR 0004). The admin picks from the 12 existing
  roles; `GET /roles` exposes role to permission lists for the UI. Custom roles are not part of this.
* **Permission `users.admin`** (admin role only) guards `/roles` and every `/admin/*` endpoint.
* **Per-membership deactivation.** `core.user_companies.active` (default true). An inactive
  membership is refused with 403 by the extractor, disappears from `/users` (assignment pickers) and
  from the `memberships` in `/me`, but stays listed in `/admin/users`. The global `core.users.active`
  is not touched, because a person can work for several companies.
* **Users and invitation.** No passwords are managed in the ERP; sign-in stays with the identity
  provider and the first OIDC login binds the subject to the user found by e-mail (ADR 0004).
  `POST /admin/users` creates `core.users` for an unknown e-mail (compared case-insensitively,
  stored lower-case), or only adds a membership for an existing one (name kept; 409 if already a
  member, or if the account is globally disabled). The first membership of a person is their
  default. One invitation mail is queued in `core.mail_outbox` in the same transaction; it names the
  company, the roles and the e-mail address to sign in with and contains no secret. `POST
  /admin/users/{id}/invite` queues it again and answers 409 once the person has signed in
  (`has_signed_in`, nothing left to invite) or when the membership is deactivated.
* **Guards** on `PUT /admin/users/{id}`: roles must exist and be non-empty; module codes known;
  members of other companies are 404; you cannot deactivate yourself or drop your own admin role;
  the company must keep an active admin (a defence in depth, since only admins can administer and
  cannot remove themselves). Every write is audited (`audit::record` in the transaction).
* **Modules endpoints:** `GET/PUT /admin/modules` (catalogue with `requires`, `permissions`,
  `enabled`; PUT takes the full list of disabled codes).

**Consequences.** Hidden areas are really closed, not only hidden in the app. Removing a module
from a user never deletes data. A new `Permission` must be assigned to a module (test enforced).
Changes apply on the next request because nothing is cached in tokens. Mail delivery depends on the
worker's SMTP configuration like every other system mail.
