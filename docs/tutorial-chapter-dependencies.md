# Tutorial chapter dependencies

The chapter map currently unlocks in list order. The table records the dependencies
that matter when a chapter is offered outside that order. Chapter IDs are the existing
saved-progress keys.

| Chapter | Needs at entry | Produces or teaches |
| --- | --- | --- |
| 0 · `welcome` | A signed-in learner in a tutorial or test environment | Environment banner, tabs, and tutorial controls |
| 1 · `conveyors` | Standard demo setup and product editing access | `MOT-1P-037`, `MOT-3P-055`, `VFD-3P-055`, `CONV-BELT-1M`, interactive SVG assembly preview (with/without motor), and its active BOM |
| 2 · `plc` | Standard demo setup and product editing access | `PLC-BASE` (10 outputs), parallel output licenses (`PLC-LIC-30`, `PLC-LIC-50`, `PLC-LIC-100`), `PLC-EXP-RS485`, and `PLC-MASTER` |
| 3 · `displays` | Standard demo setup and product editing access | `DISP-RS485` (RS-485 bus) with I2C `MOD-I2C-SWIPE` (swipe card) and `SENS-I2C-TEMP` (temperature) |
| 4 · `sensors` | Standard demo setup and product editing access | `SENS-IR-24V` (digital input), `SENS-420MA` (4–20 mA), and PowerFET devices `SOL-PUSH` & `SOL-LABEL` |
| 5 · `suppliers` | The four core story products (`MOT-3P-055`, `VFD-3P-055`, `PLC-BASE`, `CONV-BELT-1M`), found by product code | Suppliers `TUT-SUP-A` and `TUT-SUP-B` with component prices |
| 6 · `buying` | Core story products and Supplier A with its component prices. The existing story carries `supplierAId` from `suppliers`. | An approved and sent PO, active MAIN warehouse/location if needed, two receipts, and component stock |
| 7 · `invoices` | Fully received tutorial PO and its `poId` | The match, approval, dispute, and payment workflow for supplier invoices |
| 8 · `manufacturing` | Core story products, an active conveyor BOM, and enough component stock for the build | A production division, a completed five-unit build, and output stock. It can create MAIN if needed. |
| 9 · `prices` | The four core story products under the current probe and a second demo price zone | `TUT-EXPORT` and `CONV-BELT-1M` priced in two zones |
| 10 · `customer` | The `TUT-EXPORT` price zone from `prices` | Maya's simulated enquiry, a threaded ticket and contact details, and the linked Brightwheel customer |
| 11 · `quotation` | Brightwheel, a priced `CONV-BELT-1M`, and the product ID used by the quantity check | An eight-unit quotation, production timing note, sent status, and PDF |
| 12 · `change` | The sent quotation and its ID, the customer, `CONV-BELT-1M`, ticket thread, and the stock and active BOM needed for order production | A revised quotation, a confirmed order, completed production for the order, and a separate stock build |
| 13 · `helpdesk` | Maya's tutorial ticket, which this chapter can find by sender and capture by ID | An internal note, tag, time entry, escalation, and a tour of prepared answers |
| 14 · `attributes` | `PLC-BASE` (Standard PLC), which this chapter can find by code or create via Assist | Seven company-specific `product`-scope attribute definitions (`relay_count`, `fet_count`, `digital_inputs`, `analog_4_20ma_inputs`, `rs485_ports`, `i2c_bus`, `licensed_outputs_tier`) and their typed values on `PLC-BASE` |

The production chapters also depend on the relevant production setup and permissions.
The existing full story uses the development admin as the learner. Selecting a path
should leave the signed-in identity and permissions in place.

## Entry points for the first two paths

- **Sales & CRM:** An opportunity exercise can start with a demo customer. To reuse the
  quotation chapter directly, prepare the tutorial customer and a usable cart price,
  then capture both IDs. The full story can still teach how those records were created.
  Order conversion and order production are later chapters with their own requirements.
- **Helpdesk:** A tutorial ticket with a stable identifier is enough to start
  `helpdesk`. A practice-data entry point can supply it independently of Sales.
  The full story should still resolve the ticket created by its simulated enquiry.
- **Progress:** Chapter completion and record readiness need separate checks. Skipping
  a chapter currently unlocks the next one. A skipped chapter cannot supply an ID or
  verify that the underlying record is ready.

## Browser regression coverage

Keep the full-story Playwright walkthrough to exercise module handoffs. Give the new
Sales and Helpdesk paths separate fresh-start tests. Fixture setup can create starting
records. The learner's actions should go through the UI, with outcomes checked from
the saved record or API.

On the baseline at `2a3deb9`, all 97 focused Flutter tutorial tests passed, including
the required localization keys in all five languages. The full Playwright walkthrough
completed chapters 0–10 against a fresh PostgreSQL database. Both the full walkthrough
and a focused chapter 10 run verified the saved internal note, tag, 15-minute entry and
escalation separately from the completion card.

The baseline browser run exposed a gap in chapter 7. The second simulated email changed the
ticket version and the open ticket tried to save the customer link using the older version.
The chapter advanced even though the API rejected the update with `409 record_changed`.
The open ticket now refreshes after the simulated reply. The link step checks the saved
customer ID before advancing and recognizes a link that was already saved when resuming.
A focused browser run verified the reply in the open ticket and read the saved customer
link back from the API before proceeding to chapter 8.
