# Tutorial chapter dependencies

The chapter map currently unlocks in list order. The table records the dependencies
that matter when a chapter is offered outside that order. Chapter IDs are the existing
saved-progress keys.

| Chapter | Needs at entry | Produces or teaches |
| --- | --- | --- |
| 0 · `welcome` | A signed-in learner in a tutorial or test environment | Environment banner, tabs, and tutorial controls |
| 1 · `product` | Standard demo setup and product editing access | Three components (`TUT-MOTOR`, `TUT-FRAME`, `TUT-CTRL`), the finished `TUT-CART`, and its active BOM |
| 2 · `suppliers` | The four tutorial products, found by product code | Suppliers `TUT-SUP-A` and `TUT-SUP-B` with component prices |
| 3 · `buying` | Tutorial products and Supplier A with its component prices. The existing story carries `supplierAId` from chapter 2. | An approved and sent PO, active MAIN warehouse/location if needed, two receipts, and component stock |
| 4 · `invoices` | Fully received tutorial PO and its `poId` | The match, approval, dispute, and payment workflow for supplier invoices |
| 5 · `manufacturing` | Tutorial products, an active cart BOM, and enough component stock for the build | A production division, a completed five-cart build, and output stock. It can create MAIN if needed. |
| 6 · `prices` | The four tutorial products under the current probe and a second demo price zone | `TUT-EXPORT` and the cart priced in two zones |
| 7 · `customer` | The `TUT-EXPORT` price zone from chapter 6 | Maya's simulated enquiry, a threaded ticket and contact details, and the linked Brightwheel customer |
| 8 · `quotation` | Brightwheel, a priced tutorial cart, and the cart ID used by the quantity check | An eight-cart quotation, production timing note, sent status, and PDF |
| 9 · `change` | The sent quotation and its ID, the customer, cart, ticket thread, and the stock and active BOM needed for order production | A revised quotation, a confirmed order, completed production for the order, and a separate stock build |
| 10 · `helpdesk` | Maya's tutorial ticket, which this chapter can find by sender and capture by ID | An internal note, tag, time entry, escalation, and a tour of prepared answers |

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
