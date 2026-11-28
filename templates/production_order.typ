// Production order (traveller) template. Data comes from data.json (see crates/production/src/pdf.rs).
// It is an internal document for the shop floor: there is no cost on it.
#let d = json("data.json")

// Labels in the document language with English for missing ones (ADR 0101): written by the
// renderer from the translation catalogue (crates/core/i18n/documents, company overrides).
#let l = json("labels.json")

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: d.language)
#set page(
  paper: "a4",
  margin: (x: 16mm, top: 16mm, bottom: 20mm),
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company.name · #d.company.street · #d.company.city_line
    #if d.company.vat_number != "" [ · #l.vat #d.company.vat_number]
    #h(1fr) #l.printed #d.printed · #l.page #counter(page).display() / #counter(page).final().first()
  ],
)

#let tick = box(width: 4.2mm, height: 4.2mm, stroke: 0.6pt, baseline: 0.8mm)
#let blank = box(width: 16mm, height: 5mm, stroke: (bottom: 0.5pt), baseline: 0.5mm)
#let grey(x) = text(fill: luma(100), x)

#grid(
  columns: (1fr, auto),
  align: (left + horizon, right + horizon),
  [
    #text(20pt, weight: "bold", l.title) \
    #text(15pt, weight: "bold", d.number)
  ],
  text(11pt, weight: "bold", d.company.name),
)

#if d.status == "cancelled" [
  #v(3mm)
  #block(width: 100%, fill: rgb(200, 30, 30), inset: 7pt, radius: 2pt)[
    #align(center, text(14pt, weight: "bold", fill: white, l.cancelled))
  ]
]

#v(5mm)
#let facts = (
  (l.product, d.product_code + " · " + d.product_name),
  (l.quantity, d.quantity + " " + d.unit),
  (l.bom, str(d.bom_revision)),
  (l.division, d.division),
  (l.ready, d.planned_ready_date),
  (l.order, d.order_number),
  (l.customer, d.customer),
  (l.priority, l.at("prio." + d.priority, default: d.priority)),
  (l.parent, d.parent_number),
).filter(f => f.at(1) != "")
#table(
  columns: (auto, 1fr, auto, 1fr),
  stroke: none,
  inset: (x: 0pt, right: 6mm, y: 2.5pt),
  ..facts.map(f => (grey(f.at(0)), [*#f.at(1)*])).flatten()
)

#if d.production_remark != "" [
  #v(4mm)
  #block(width: 100%, stroke: 0.8pt, inset: 7pt, radius: 2pt)[
    #grey(l.remark) \
    *#d.production_remark*
  ]
]

#if d.notes != "" [
  #v(3mm)
  #grey(l.notes) \
  #d.notes
]

#v(6mm)
#text(11pt, weight: "bold", l.components)
#v(1mm)
#table(
  columns: (auto, auto, 1fr, auto, auto),
  align: (left, left, left, right, center),
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header([*#l.pos*], [*#l.code*], [*#l.description*], [*#l.qty*], [*#l.picked*]),
  ..d.components.map(x => (str(x.position), x.code, x.name, [#x.quantity #x.unit], tick)).flatten()
)

#if d.operations.len() > 0 [
  #v(6mm)
  #text(11pt, weight: "bold", l.operations)
  #v(1mm)
  #table(
    columns: (auto, 1fr, auto, auto, auto, auto, auto),
    align: (left, left, left, right, left, left, center),
    stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
    inset: (x: 4pt, y: 6pt),
    table.header([*#l.pos*], [*#l.operation*], [*#l.work_centre*], [*#l.planned*], [*#l.dates*], [*#l.actual*], [*#l.done*]),
    ..d.operations.map(x => (
      str(x.position),
      [
        #x.name
        #if x.setup_minutes != "0" [ #text(fill: luma(100), size: 8pt)[(#l.setup #x.setup_minutes min)]]
        #if x.notes != "" [ \ #text(fill: luma(100), size: 8pt, x.notes)]
      ],
      x.work_centre,
      x.planned_minutes,
      if x.planned_start == x.planned_end { x.planned_start } else { x.planned_start + " – " + x.planned_end },
      blank,
      tick,
    )).flatten()
  )
]

#if d.sub_orders.len() > 0 [
  #v(6mm)
  #text(11pt, weight: "bold", l.subassemblies)
  #v(1mm)
  #table(
    columns: (auto, auto, 1fr, auto),
    align: (left, left, left, right),
    stroke: (x, y) => (bottom: 0.3pt + luma(210)),
    inset: (x: 4pt, y: 4pt),
    ..d.sub_orders.map(x => (x.number, x.code, x.name, [#x.quantity #x.unit])).flatten()
  )
]

#if d.product_tracking != "none" [
  #v(6mm)
  #text(11pt, weight: "bold", l.output)
  #v(2mm)
  #if d.product_tracking == "serial" [#grey(l.serials): #box(width: 1fr, stroke: (bottom: 0.5pt), height: 5mm)] else [#grey(l.lot): #box(width: 60mm, stroke: (bottom: 0.5pt), height: 5mm)]
]
