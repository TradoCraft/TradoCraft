# 0068 — Site baseline on opportunities and product suitability

**Status:** Proposed (extends [ADR 0025](0025-power-grid-compatibility.md) and [ADR 0034](0034-configurators.md))

**Context.** An opportunity starts from what the customer already has at the site: clock dials with
a size, groups of bells with diameter, height, weight and motion, sometimes named. That baseline
decides which products are suitable (the dial and the motor that drives its hands must fit the dial
size; a bell motor follows from weight and motion) next to the power grid, which today is checked
only on quotations and orders and only as a warning. Nothing models the site, and products cannot
say what they are suitable for beyond one nominal voltage. The first customer is a tower clock and
bell maker, but the model must stay general and tunable by an administrator.

**Decision.**

1. **Attribute definitions.** `products.attribute_definitions` (key, label, kind `number` | `range` |
   `select` | `text`, unit, select options, scope `product` or a baseline item type) are admin data.
   Nothing about clocks or bells is hard-coded; the tower setup is seed data an admin can change.
2. **Voltage ranges.** `products.product_power_supplies` gets `voltage_min_v` and `voltage_max_v`.
   The rows already separate AC single phase, AC three phase and DC. Existing rows keep their
   meaning: without explicit bounds the range is `voltage_v` +/- `tolerance_pct`.
3. **Suitability ranges.** `products.product_attributes` gets a `range` kind (`value_min`,
   `value_max`), used for dial size and similar. The configurator ignores the kind.
4. **Baseline.** `crm.baseline_item_types` (admin defined: clock dial, bell group, bell) and
   `crm.opportunity_baseline_items`, a tree through `parent_id` (a group holds its bells) with name,
   quantity and attribute values validated against the definitions.
5. **Grid on the opportunity.** `crm.opportunities.power_grid_id`; matching and new quotations
   default to it, a quotation may override it.
6. **Motors.** Derived with the configurator's lookup tables and formulas (weight per wheel, motion,
   phases, brand), seeded from the existing tower configurator tables. No second rule engine.
7. **Matching is advisory.** `GET /opportunities/{id}/product-matches` returns `suitable`,
   `unsuitable` or `unknown` per product with reasons, like `power_warnings`; the UI may offer an
   "only suitable" filter. Missing data is `unknown`, never `unsuitable`.

**Consequences.** Delivered in phases (definitions, product suitability, baseline backend and UI,
matching, quotation integration), each with its own migration after `20270208000002`. DC ranges
have no reference data and start empty.

**Phase 3 notes (baseline backend).** Migrations `20270211000001` (types, items, seed function) and
`20270211000002` (`crm.opportunities.power_grid_id`).

* Types: `allowed_parent_codes` lists the parent types; because a bell may sit under a group and
  also stand alone, the type also has `allow_top_level` (a type without allowed parents must have
  it). The `code` is fixed after creation. Reading needs `opportunities.read`, administering
  `products.write` (the permission of the attribute definitions they are edited with). A type with
  items, attribute definitions or that another type allows as parent is refused with 409
  ("deactivate instead"); a type update that would strand existing items is a 409 too.
* Items: `GET /opportunities/{id}/baseline` returns the tree; `POST|PUT|DELETE
  /opportunities/{id}/baseline/items[/{item_id}]` follow `opportunities.write`. A parent must be an
  item of the same opportunity (composite foreign key), its type must be allowed, no cycles, at most
  8 levels, 1000 items. The type of an item cannot change. Deleting an item that has children is a
  409 (nothing is removed silently). Values are validated against the active definitions of the
  item's type: unknown keys and wrong kinds are 422, missing keys are fine, null clears a value.
  Deleting an attribute definition whose key is stored on baseline items is a 409.
* Grid: `power_grid_id` on create/update, `clear_power_grid: true` to clear (ADR 0025 convention).
  It must belong to the customer's country; on update a stored grid that no longer fits the
  customer's country is dropped, as on quotations.
* Seed: `crm.seed_baseline_defaults(company_id)` is idempotent and keeps existing rows. The
  migration applies it to every company; company provisioning and the dev seed call it for new
  ones.
* Definition updates: `PUT /attribute-definitions/{id}` refuses (409) a change of `key`, `scope` or
  `kind` while stored values use the definition (product attributes with the key, or baseline items
  of that type storing it). Label, unit, options, sort order and active stay editable; shrinking the
  options does not revalidate stored values.

**Phase 5a notes (matching engine, without motor derivation).** Migration `20270212000001`
(`crm.match_rules`; `crm.seed_baseline_defaults` now also seeds the rule). Motor derivation
(decision 6) is not part of this phase.

* Verdict: per product `suitable`, `unsuitable` or `unknown` with a list of reasons `{check, status,
  message}`; `check` is `power`, `baseline` or `rule:<rule name>`, `status` is `ok`, `fail` or
  `unknown`. Any `fail` makes the product unsuitable, otherwise any `unknown` makes it unknown,
  otherwise it is suitable. Missing data is never `unsuitable`. A product with nothing applicable
  (not electrical, no rule applies) is `suitable` with no reasons.
* No data at all: an opportunity with an empty baseline **and** no power grid says nothing about
  any product, so every product is `unknown` with the single reason `baseline` / "no baseline
  data" instead of a vacuous `suitable`. With a grid but an empty baseline the products are judged
  on power alone.
* Power reuses `products::power::check` (new `compatibility_with_grid`, which `check_products`
  now shares). Compatible and needs-external-supply give `ok` reasons, incompatible a `fail` that
  names the supported supplies and the site grid, an electrical product without an opportunity grid
  is `unknown`, a non-electrical product gets no power reason.
* Rules (`GET|POST /match-rules`, `GET|PUT|DELETE /match-rules/{id}`; read `opportunities.read`,
  write `products.write`, audited as `match_rule`): `name` (unique per company),
  `baseline_type_code`, `baseline_attribute_key` (an active `number` definition of that type),
  `product_attribute_key` (an active product definition), `operator`, `active`, `sort_order`.
  `within_range` needs a `range` product attribute (baseline value within min..max, bounds
  included), `at_most` / `at_least` a `number` one (baseline value <= / >= the product value);
  anything else is 422. Nothing references a rule, so it can always be deleted; renaming or
  deleting a definition later leaves the rule in place and it simply reads no data (`unknown` or
  not applicable). The seed adds `Dial size fits product` (`clock_dial.dial_diameter_mm`
  `within_range` product `dial_size_mm`) once per company name; like the types it is re-created by
  a re-run of the seed function if an administrator deleted it.
* Evaluation per active rule and product: a product without the attribute (or in the wrong shape)
  is not judged by the rule, nor is a baseline without an item of the type. Otherwise every item of
  that type, nested ones included and quantity ignored, gives one reason: `ok` / `fail` with the
  numbers, or `unknown` when the item lacks the value. The product must fit all items.
* `GET /opportunities/{id}/product-matches?status=&family_id=&limit=&offset=` (needs
  `opportunities.read` and `products.read`; another company's opportunity is 404, a bad `status`
  422) returns `{items, total, counts}` for the active products in code order. Because the status
  is computed, all active products are evaluated in memory (a fixed number of queries: opportunity, baseline,
  rules, products, their rule attributes and supplies; no per-product queries) and then
  filtered and paged; `limit` defaults to 100, at most 500. `counts` gives the number per status
  within the family filter, ignoring the status filter. Products are catalogue-wide (they have no
  company), the opportunity, baseline and rules are the company's.
* The matcher is the pure `crates/crm/src/matching.rs`; loading is `product_matches.rs`.

**Phase 5b notes (bell motor derivation).** Migration `20270213000001`
(`configurator.seed_bell_motors`; `crm.seed_baseline_defaults` now also seeds the motor
attributes and the tables). Decision 6 is implemented without a second engine.

* Storage: the rotating-motor tables of the reference project are the active revision of the
  configurator model `bell_motors` (tables only, no fields or outputs), one per company, seeded
  idempotently and edited through draft revisions like any configurator. Tables
  (`crates/configurator/src/motor.rs`): `motion_rules` (motion to effective `falling`/`flying`),
  `motion_bumps` (phases, brand, motion to weight classes to move up: volteo for every phases/brand
  combination, balanced for 1-phase `mez_1000`), `phase_limits` (1-phase 0.55 kW, 3-phase none)
  and `motors` (a range table over the weight per wheel, keys phases, brand, effective motion;
  columns `kw` and `size`). The module reads them with `CompiledTable::lookup`, including its
  `offset` for the bump; the shape (names, keys, columns) is checked when they are loaded.
* `required_motor(bell, phases, brand, tables)` is pure. Weight per wheel is `weight_kg /
  num_wheels` (one wheel when absent). The first class whose maximum is at or above the weight
  wins (a class covers (previous maximum, own maximum]); above the largest, or when the bump runs
  past it, the bell is too large. Without a brand every brand of the phases is tried and the
  weakest motor wins; a brand (bell attribute `motor_brand`) restricts it. Errors:
  `MissingData` (no weight, motion, grid phases, unknown motion, wheels < 1, no tables),
  `TooLarge`, `NotAvailableForPhases` (no motor for the phases, brand or motion, or the phases
  cap the power). The result carries kW, size, brand, weight per wheel, effective motion and the
  bump.
* Seeded attributes (bell scope): `num_wheels` (number) and `motor_brand` (select `mez_1000`,
  `adda_750`, `de_coster_1000`); product scope: `motor_kw` (number, kW).
* Matching: a product with a `motor_kw` attribute gets one `motor` reason per bell: `ok` when its
  kW is at least the required kW, `fail` when smaller, `fail` for `TooLarge` and
  `NotAvailableForPhases` (with the message), `unknown` for `MissingData`. Products without
  `motor_kw` are not judged. Whether the motor runs on the site grid is the existing power check
  (the product's supplies), not part of the motor check. The matcher stays pure
  (`crm::matching`); because the configurator crate depends on the CRM, the endpoint gets the
  derivation through the `BellMotorProvider` trait, installed by the API as an `Extension`
  (`configurator::motor::ConfiguratorMotors`); without it bells are `unknown`.
* Not ported from the Dart code: wheel, chain, striker and clapper lookups, motor reference codes
  and PKZ/current ratings, sprocket and mounting chair data, starting current/torque, capacitor
  and shaft columns (the `motors` table has only kW and size), the linear motors (their tables
  are skipped; nothing selects between rotating and linear), the lookup cache, and the choice of
  the number of wheels (it is an input, never derived). The Dart code throws for single phase
  above 0.55 kW after the lookup; here that is the `phase_limits` table and gives
  `NotAvailableForPhases`, but the seeded 1-phase classes never exceed 0.55 kW, so the cap only
  bites when an administrator adds larger classes or lowers it. Hard-coded in Rust, not in tables:
  the baseline type code `bell`, the bell attribute keys `weight_kg`, `motion`, `num_wheels`,
  `motor_brand` and the product attribute `motor_kw`.
