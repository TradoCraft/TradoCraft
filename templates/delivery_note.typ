// Delivery note template. Data comes from data.json (see crates/delivery/src/pdf.rs).
#let d = json("data.json")

#let labels = (
  nl: (title: "Leveringsbon", number: "Nummer", order: "Order", reference: "Uw referentie", date: "Datum", carrier: "Vervoerder", tracking: "Tracking",
       ship_to: "Leveradres", pos: "Pos.", code: "Code", description: "Omschrijving", qty: "Aantal", serial: "Lot / serienummer", notes: "Opmerkingen",
       preview: "VOORBEELD", vat: "BTW", page: "Pagina", received: "Ontvangen door (naam, datum, handtekening)"),
  fr: (title: "Bon de livraison", number: "Numéro", order: "Commande", reference: "Votre référence", date: "Date", carrier: "Transporteur", tracking: "Suivi",
       ship_to: "Adresse de livraison", pos: "Pos.", code: "Code", description: "Description", qty: "Quantité", serial: "Lot / n° de série", notes: "Remarques",
       preview: "APERÇU", vat: "TVA", page: "Page", received: "Reçu par (nom, date, signature)"),
  en: (title: "Delivery note", number: "Number", order: "Order", reference: "Your reference", date: "Date", carrier: "Carrier", tracking: "Tracking",
       ship_to: "Deliver to", pos: "Pos.", code: "Code", description: "Description", qty: "Qty", serial: "Lot / serial number", notes: "Notes",
       preview: "PREVIEW", vat: "VAT", page: "Page", received: "Received by (name, date, signature)"),
  de: (title: "Lieferschein", number: "Nummer", order: "Auftrag", reference: "Ihre Referenz", date: "Datum", carrier: "Spediteur", tracking: "Sendungsnummer",
       ship_to: "Lieferadresse", pos: "Pos.", code: "Artikel", description: "Beschreibung", qty: "Menge", serial: "Charge / Seriennummer", notes: "Bemerkungen",
       preview: "VORSCHAU", vat: "MwSt.", page: "Seite", received: "Erhalten von (Name, Datum, Unterschrift)"),
  es: (title: "Albarán de entrega", number: "Número", order: "Pedido", reference: "Su referencia", date: "Fecha", carrier: "Transportista", tracking: "Seguimiento",
       ship_to: "Dirección de entrega", pos: "Pos.", code: "Código", description: "Descripción", qty: "Cantidad", serial: "Lote / n.º de serie", notes: "Observaciones",
       preview: "VISTA PREVIA", vat: "IVA", page: "Página", received: "Recibido por (nombre, fecha, firma)"),
)
#let l = labels.at(d.language, default: labels.en)

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 18mm, bottom: 22mm),
  background: if d.planned { rotate(-35deg, text(80pt, fill: rgb(0, 0, 0, 18), weight: "bold", l.preview)) },
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company.name · #d.company.street · #d.company.city_line
    #if d.company.vat_number != "" [ · #l.vat #d.company.vat_number]
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
      #text(fill: luma(100), size: 8pt, l.ship_to) \
      *#d.ship_to.name* \
      #d.ship_to.street \
      #d.ship_to.city_line \
      #if d.ship_to.country_code != d.company.country_code [#d.ship_to.country_code]
    ])
  ],
)

#v(10mm)
#text(18pt, weight: "bold", l.title)
#v(2mm)
#table(
  columns: 5,
  stroke: none,
  inset: (x: 0pt, right: 10mm, y: 2pt),
  [#text(fill: luma(100), l.number)], [#text(fill: luma(100), l.order)],
  [#text(fill: luma(100), l.reference)], [#text(fill: luma(100), l.date)],
  [#text(fill: luma(100), l.carrier)],
  [*#d.number*], [*#d.order_number*], [*#d.customer_reference*], [*#d.date*], [*#d.carrier*],
)
#if d.tracking_number != "" [
  #v(1mm)
  #text(fill: luma(100), l.tracking): *#d.tracking_number*
]

#v(6mm)
#table(
  columns: (auto, auto, 1fr, auto, auto),
  align: (left, left, left, right, left),
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header([*#l.pos*], [*#l.code*], [*#l.description*], [*#l.qty*], [*#l.serial*]),
  ..d.lines.map(x => (str(x.order_position), x.code, x.description, [#x.quantity #x.unit], x.tracking)).flatten()
)

#if d.notes != "" [
  #v(6mm)
  *#l.notes* \
  #d.notes
]

#v(1fr)
#line(length: 80mm, stroke: 0.5pt)
#text(size: 8pt, fill: luma(100), l.received)
