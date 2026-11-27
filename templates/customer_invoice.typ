#let d = json("data.json")
// Labels in the document language with English for missing ones (ADR 0101): written by the
// renderer from the translation catalogue (crates/core/i18n/documents, company overrides).
#let l = json("labels.json")
#let title = if d.kind == "credit_note" { l.credit } else { l.invoice }
#set document(title: title + " " + d.number)
#set text(size: 10pt, lang: d.language)
#set page(paper: "a4", margin: 18mm)
#let party(label, p) = [
  #text(fill: luma(80), label) \
  #strong(p.name) \
  #p.street \
  #p.postal_code #p.city \
  #p.country_code
  #if p.vat_number != none and p.vat_number != "" [ \ #l.vat #p.vat_number ]
]

#grid(columns: (1fr, 1fr), gutter: 12mm, party(l.seller, d.seller), party(l.customer, d.customer))

#v(9mm)
= #title #d.number
#l.date #d.date
#if d.due_date != none [ \ #l.due #d.due_date ]
#if d.source_invoice_number != none [
  \ #l.original #d.source_invoice_number
]
#if d.reason != "" [ \ #l.reason #d.reason ]

#v(5mm)
#table(
  columns: (auto, 1fr, auto, auto, auto, auto),
  align: (left, left, right, right, right, right),
  stroke: (bottom: 0.35pt + luma(210)),
  table.header(
    table.cell(fill: luma(240), strong(l.code)),
    table.cell(fill: luma(240), strong(l.item)),
    table.cell(fill: luma(240), strong(l.qty)),
    table.cell(fill: luma(240), strong(l.price)),
    table.cell(fill: luma(240), strong(l.vat)),
    table.cell(fill: luma(240), strong(l.net)),
  ),
  ..d.lines.map(line => (
    line.code, line.description, [#line.quantity #line.unit], line.net_unit_price,
    [#line.vat_rate%], line.net_total,
  )).flatten(),
)

#align(right, table(
  columns: (auto, auto), align: (left, right), stroke: none,
  l.net, [#d.net_total #d.currency],
  l.vat, [#d.vat_total #d.currency],
  strong(l.total), strong([#d.gross_total #d.currency]),
))
#if d.vat_regime != "domestic" [
  #align(right, text(size: 9pt, if d.vat_regime == "intra_eu" { l.reverse }
    else if d.vat_regime == "domestic_reverse_charge" { l.domestic_reverse }
    else { l.export }))
]
#if d.rebate != none [
  #v(4mm)
  #d.rebate.message
]
