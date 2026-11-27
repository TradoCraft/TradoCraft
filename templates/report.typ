// User-defined report (ADR 0042). Data comes from data.json (see crates/reports/src/pdf.rs).
// Every value is formatted by the API; this template only lays it out.
#let d = json("data.json")

// Labels in the document language with English for missing ones (ADR 0101): written by the
// renderer from the translation catalogue (crates/core/i18n/documents, company overrides).
#let l = json("labels.json")

#set document(title: d.title)
#set text(size: 9pt, lang: d.language)
#set page(
  paper: "a4",
  flipped: d.columns.len() > 6,
  margin: (x: 15mm, top: 16mm, bottom: 18mm),
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company · #l.generated #d.generated
    #h(1fr) #l.page #counter(page).display() / #counter(page).final().first()
  ],
)

#let muted(x) = text(fill: luma(100), x)

#text(17pt, weight: "bold", d.title)
#if d.description != "" [ \ #muted(d.description)]
#v(1mm)
#muted[#d.row_count #l.rows · #l.generated #d.generated]

#if d.filters.len() > 0 [
  #v(3mm)
  #text(9.5pt, weight: "bold", l.filters) #muted[(#if d.logic == "or" { l.any } else { l.all })]
  #for f in d.filters [
    - #f
  ]
]

#if d.chart != none [
  #v(4mm)
  #block(breakable: false)[
    #text(9.5pt, weight: "bold", d.chart.title)
    #v(1mm)
    #grid(
      columns: (42mm, 1fr, 28mm),
      column-gutter: 3mm,
      row-gutter: 1.6mm,
      ..d.chart.bars.map(b => (
        align(right, b.label),
        box(width: 100%, height: 4mm, align(left, box(width: b.pct * 1%, height: 100%, fill: rgb("#3b6ea5")))),
        [#b.text #if b.share != "" [#muted[(#b.share)]]],
      )).flatten(),
    )
  ]
]

#v(4mm)
#if d.rows.len() == 0 [
  #muted(l.empty)
] else [
  #table(
    columns: d.columns.len() * (auto,),
    align: d.columns.map(c => if c.align == "right" { right } else { left }),
    inset: (x: 4pt, y: 3pt),
    stroke: (x: none, y: 0.4pt + luma(200)),
    fill: (_, y) => if y == 0 { luma(235) },
    table.header(..d.columns.map(c => strong(c.label))),
    ..d.rows.flatten(),
    ..if d.totals != none { d.totals.map(c => strong(c)) } else { () },
  )
]
