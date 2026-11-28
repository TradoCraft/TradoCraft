// Quotation template. Data comes from data.json (see crates/sales/src/pdf.rs).
// All amounts are pre-formatted by the API; this template never calculates.
#let d = json("data.json")

// Labels in the document language with English for missing ones (ADR 0101): written by the
// renderer from the translation catalogue (crates/core/i18n/documents, company overrides).
#let l = json("labels.json")
#let cur = if d.currency == "EUR" { "€" } else { d.currency }

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: d.language)
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 18mm, bottom: 22mm),
  background: if d.draft { rotate(-35deg, text(80pt, fill: rgb(0, 0, 0, 18), weight: "bold", l.draft)) },
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company.name · #d.company.street · #d.company.city_line
    #if d.company.vat_number != "" [ · #l.vat #d.company.vat_number]
    #if d.iban != "" [ · IBAN #d.iban]
    #h(1fr) #l.page #counter(page).display() / #counter(page).final().first()
  ],
)

#grid(
  columns: (1fr, 1fr),
  [
    #text(15pt, weight: "bold", d.company.name) \
    #d.company.street \
    #d.company.city_line \
    #if d.company.contact != "" [#d.company.contact \ ]
    #if d.company.vat_number != "" [#l.vat #d.company.vat_number]
  ],
  align(right)[
    #v(14mm)
    #align(left, box(width: 70mm)[
      *#d.customer.name* \
      #d.customer.street \
      #d.customer.city_line \
      #if d.customer.country_code != d.company.country_code [#d.customer.country_code \ ]
      #if d.customer.vat_number != "" [#l.vat #d.customer.vat_number]
    ])
  ],
)

#v(10mm)
#text(18pt, weight: "bold", l.title)
#v(2mm)
#table(
  columns: 4,
  stroke: none,
  inset: (x: 0pt, right: 10mm, y: 2pt),
  [#text(fill: luma(100), l.number)], [#text(fill: luma(100), l.revision)],
  [#text(fill: luma(100), l.date)], [#text(fill: luma(100), l.valid)],
  [*#d.number*], [*#d.revision*], [*#d.quote_date*], [*#d.valid_until*],
)

#v(6mm)
// One row per line; sub-lines (options) are indented below their parent. Lines are grouped by
// section with a heading and a subtotal; lines without a section come without a heading.
#let line-row(x) = (
  {
    if x.image != none { box(image(x.image, width: 14mm, height: 14mm, fit: "contain")); linebreak() }
    text(size: if x.level > 0 { 8.5pt } else { 9.5pt }, x.code)
  },
  pad(left: x.level * 4mm)[
    #if x.level > 0 [#text(fill: luma(120), sym.arrow.r.curve) ]#x.description
    #if x.percent_of_parent != "" [#text(fill: luma(110), size: 8pt)[ (#x.percent_of_parent #l.of_parent)]]
    #if x.customer_remark != "" [\ #text(size: 8.5pt, fill: luma(60), x.customer_remark)]
    #if x.comment != "" [\ #text(size: 8pt, fill: luma(90), emph(x.comment))]
  ],
  [#x.quantity #x.unit],
  [#cur #x.unit_price#if x.indicative [\*]],
  if x.net { l.net } else { x.discount },
  ..if d.show_vat { (x.vat_rate,) } else { () },
  [#cur #x.total#if x.indicative [\*]],
)
#let named = d.groups.filter(g => g.title != "").len() > 0
#let ncols = if d.show_vat { 7 } else { 6 }
#table(
  columns: if d.show_vat { (auto, 1fr, auto, auto, auto, auto, auto) } else { (auto, 1fr, auto, auto, auto, auto) },
  align: if d.show_vat { (left, left, right, right, right, right, right) } else { (left, left, right, right, right, right) },
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header(
    [*#l.code*], [*#l.description*], [*#l.qty*], [*#l.price*], [*#l.discount*], ..if d.show_vat { ([*#l.vat*],) } else { () }, [*#l.total*],
  ),
  ..d.groups.map(g => {
    let rows = ()
    if g.title != "" {
      rows.push(table.cell(colspan: ncols, fill: luma(240), text(weight: "bold", g.title)))
    }
    for x in g.lines { rows += line-row(x) }
    if named and g.title != "" {
      rows.push(table.cell(colspan: ncols - 1, align(right, text(fill: luma(90), [#l.section_total #g.title]))))
      rows.push(align(right, text(fill: luma(90), [#cur #g.subtotal])))
    }
    rows
  }).flatten()
)
#if d.has_indicative [
  #text(size: 8pt, fill: luma(90))[\* #l.indicative]
]

#v(4mm)
#align(right, box(width: 85mm, table(
  columns: (1fr, auto),
  align: (left, right),
  stroke: none,
  inset: (x: 0pt, y: 3pt),
  ..if d.show_vat {
    (
      [#l.subtotal], [#cur #d.subtotal],
      ..d.vat_groups.map(g => ([#l.vat #g.rate #text(fill: luma(110))[(#l.vat_on #cur #g.base)]], [#cur #g.vat])).flatten(),
      table.hline(stroke: 0.7pt),
      [*#l.grand*], [*#cur #d.total*],
    )
  } else {
    ([*#l.total*], [*#cur #d.total*])
  },
)))
#if not d.show_vat [
  #align(right, text(size: 8.5pt, fill: luma(90), if d.vat_regime == "intra_eu" { l.reverse } else if d.vat_regime == "domestic_reverse_charge" { l.domestic_reverse } else { l.export }))
]

#if d.notes != "" [
  #v(8mm)
  *#l.notes* \
  #d.notes
]
