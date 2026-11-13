// Production order (traveller) template. Data comes from data.json (see crates/production/src/pdf.rs).
// It is an internal document for the shop floor: there is no cost on it.
#let d = json("data.json")

#let labels = (
  nl: (title: "Productieorder", number: "Nummer", product: "Product", quantity: "Aantal", bom: "BOM-revisie", division: "Afdeling", ready: "Klaar tegen",
       order: "Verkooporder", customer: "Klant", priority: "Prioriteit", parent: "Deel van", remark: "Opmerking voor productie",
       components: "Onderdelen", pos: "Pos.", code: "Code", description: "Omschrijving", qty: "Aantal", picked: "Gepickt",
       operations: "Bewerkingen", operation: "Bewerking", work_centre: "Werkplek", planned: "Gepland (min)", dates: "Datums", actual: "Werkelijk (min)", done: "Klaar",
       setup: "opstel", output: "Resultaat", lot: "Lotnummer", serials: "Serienummers", notes: "Opmerkingen",
       subassemblies: "Onderdelen met een eigen productieorder", printed: "Afgedrukt", page: "Pagina", vat: "BTW",
       prio: (low: "Laag", normal: "Normaal", expedite: "Spoed")),
  fr: (title: "Ordre de fabrication", number: "Numéro", product: "Produit", quantity: "Quantité", bom: "Révision de la nomenclature", division: "Service", ready: "Prêt pour",
       order: "Commande", customer: "Client", priority: "Priorité", parent: "Fait partie de", remark: "Remarque pour la production",
       components: "Composants", pos: "Pos.", code: "Code", description: "Description", qty: "Qté", picked: "Prélevé",
       operations: "Opérations", operation: "Opération", work_centre: "Poste de travail", planned: "Prévu (min)", dates: "Dates", actual: "Réel (min)", done: "Fait",
       setup: "réglage", output: "Résultat", lot: "N° de lot", serials: "N° de série", notes: "Remarques",
       subassemblies: "Sous-ensembles avec leur propre ordre", printed: "Imprimé", page: "Page", vat: "TVA",
       prio: (low: "Basse", normal: "Normale", expedite: "Urgente")),
  en: (title: "Production order", number: "Number", product: "Product", quantity: "Quantity", bom: "BOM revision", division: "Division", ready: "Ready by",
       order: "Sales order", customer: "Customer", priority: "Priority", parent: "Part of", remark: "Production remark",
       components: "Components", pos: "Pos.", code: "Code", description: "Description", qty: "Qty", picked: "Picked",
       operations: "Operations", operation: "Operation", work_centre: "Work centre", planned: "Planned (min)", dates: "Dates", actual: "Actual (min)", done: "Done",
       setup: "setup", output: "Output", lot: "Lot number", serials: "Serial numbers", notes: "Notes",
       subassemblies: "Subassemblies with their own order", printed: "Printed", page: "Page", vat: "VAT",
       prio: (low: "Low", normal: "Normal", expedite: "Expedite")),
  de: (title: "Fertigungsauftrag", number: "Nummer", product: "Produkt", quantity: "Menge", bom: "Stücklistenrevision", division: "Abteilung", ready: "Fertig bis",
       order: "Kundenauftrag", customer: "Kunde", priority: "Priorität", parent: "Teil von", remark: "Hinweis für die Fertigung",
       components: "Komponenten", pos: "Pos.", code: "Artikel", description: "Beschreibung", qty: "Menge", picked: "Entnommen",
       operations: "Arbeitsgänge", operation: "Arbeitsgang", work_centre: "Arbeitsplatz", planned: "Geplant (Min.)", dates: "Termine", actual: "Ist (Min.)", done: "Erledigt",
       setup: "Rüsten", output: "Ergebnis", lot: "Chargennummer", serials: "Seriennummern", notes: "Bemerkungen",
       subassemblies: "Baugruppen mit eigenem Auftrag", printed: "Gedruckt", page: "Seite", vat: "MwSt.",
       prio: (low: "Niedrig", normal: "Normal", expedite: "Eilig")),
  es: (title: "Orden de producción", number: "Número", product: "Producto", quantity: "Cantidad", bom: "Revisión de la lista de materiales", division: "División", ready: "Listo para",
       order: "Pedido de venta", customer: "Cliente", priority: "Prioridad", parent: "Parte de", remark: "Observación para producción",
       components: "Componentes", pos: "Pos.", code: "Código", description: "Descripción", qty: "Cant.", picked: "Recogido",
       operations: "Operaciones", operation: "Operación", work_centre: "Puesto de trabajo", planned: "Previsto (min)", dates: "Fechas", actual: "Real (min)", done: "Hecho",
       setup: "preparación", output: "Resultado", lot: "Número de lote", serials: "Números de serie", notes: "Observaciones",
       subassemblies: "Subconjuntos con su propia orden", printed: "Impreso", page: "Página", vat: "IVA",
       prio: (low: "Baja", normal: "Normal", expedite: "Urgente")),
)
#let l = labels.at(d.language, default: labels.en)

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
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

#v(5mm)
#let facts = (
  (l.product, d.product_code + " · " + d.product_name),
  (l.quantity, d.quantity + " " + d.unit),
  (l.bom, str(d.bom_revision)),
  (l.division, d.division),
  (l.ready, d.planned_ready_date),
  (l.order, d.order_number),
  (l.customer, d.customer),
  (l.priority, l.prio.at(d.priority, default: d.priority)),
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
