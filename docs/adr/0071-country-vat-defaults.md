# 0071. Country-aware, temporal, and building-age VAT defaults

**Status:** Accepted  
**Date:** 2026-11-16

## Context

Previously, `products.products.vat_rate` defaulted to `21` (Belgian standard rate), customer `vat_regime` defaulted to `'domestic'` regardless of customer country, Typst templates checked `country_code != "BE"`, purchase orders had no line VAT rates, and supplier invoices defaulted line VAT to `0` or hardcoded `21` in the Flutter UI. Multi-country companies (e.g. Germany `19%` / `7%`, France `20%` / `5.5%` / `10%`), historical rate periods (e.g. Germany's 2020 COVID reduction), domestic B2B construction reverse charge, and building-age renovation rates (e.g. Belgian `6%` on private dwellings aged >= 10 years) could not be expressed without manual overrides on every record.

## Decision

1. **Country VAT rate rules (`core.country_vat_rates`)**:
   - Seed EU-27 + `XI` plus key non-EU countries (`GB`, `CH`, `NO`, `IS`, `US`, `CA`, `AU`) with `category` (`standard`, `intermediate`, `reduced`, `zero`, `construction`), `rate`, optional `min_building_age_years`, `start_date`, and `end_date`.
   - Expose read access (`GET /vat-rates`) and admin CRUD (`POST/PUT/DELETE /admin/vat-rates`) behind `Permission::UsersAdmin`, with overlap detection (`409 Conflict`) and an optional `close_previous` flag to end-date an open rule atomically.
   - Pure resolver `tradocraft_core::vat_rates::resolve_rate_from_rules` evaluates: exempt regime -> explicit line/product override -> construction age rule (`purpose == "installation"`, age on quote date >= `min_building_age_years`, capped by `base_rate` so lower reduced rates stay lower) -> active category rate on date (with fallback from `intermediate`/`reduced` to `standard`).

2. **Products (`vat_category` & `vat_rate_override`)**:
   - Products carry `vat_category` (default `'standard'`) and nullable `vat_rate_override`.
   - Read and quoting paths dynamically resolve `vat_rate` from the active company's country rules on today's date / `price_date`. Direct SQL `UPDATE products.products SET vat_rate = ...` remains compatible via a `BEFORE UPDATE OF vat_rate` trigger when `tradocraft.updating_product` is not set.

3. **CRM customers & opportunities**:
   - Widen `vat_regime` to `domestic`, `domestic_reverse_charge`, `intra_eu`, `outside_eu`.
   - When `vat_regime` is omitted on customer create or CSV import, derive it via `tradocraft_core::vat::default_vat_regime` using the active company's country, customer country, and whether a VAT number is present. Store per-company regimes on `crm.customer_terms.vat_regime` so shared customers can have distinct regimes per company.
   - Add `building_construction_year` (`800..=2200`) to `crm.opportunities`.

4. **Sales quotations, orders & Typst PDFs**:
   - Auto-derive quotation `vat_regime` via `resolve_quotation_vat_regime`: domestic B2B customers (`vat_number` non-empty) with `purpose == "installation"` default to `domestic_reverse_charge` (0% VAT), overridable via `vat_regime_override`.
   - Quotations inherit `building_construction_year` from linked opportunities when omitted and apply construction VAT rules on `quote_date`.
   - Orders copy `vat_regime` and `building_construction_year` from quotations; Typst templates compare against `d.company.country_code`, support 5-language domestic reverse charge notices, and hide VAT columns on exempt order confirmations.

5. **Purchasing & Supplier Invoices**:
   - `purchasing.purchase_order_lines` stores resolved `vat_rate` (domestic suppliers resolve from product rules on `order_date`; foreign suppliers default to `0%`) and updates header `tax_total`/`total`.
   - Supplier invoices prefill `vat_rate` from PO lines and fall back to company standard rate on `invoice_date` for domestic free-text lines or `0%` for foreign suppliers.

## Consequences

- Existing Belgian single-rate assumptions (`"BE"`, `21%`) are removed across DB defaults, backend resolution, Typst PDF templates, and Flutter forms.
- API callers and existing tests creating quotes for domestic B2B customers with `purpose = "installation"` now receive `domestic_reverse_charge` (`0%` VAT) unless `vat_regime_override: "domestic"` or `purpose: "stock"` is supplied.
- Administrators can update future or historical country rates in Admin -> VAT rates without code changes.
