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
