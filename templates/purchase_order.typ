// Purchase order template. Data comes from data.json (see crates/purchasing/src/document.rs).
#let d = json("data.json")

#let labels = (
  nl: (title: "Bestelbon", number: "Nummer", date: "Datum", expected: "Gewenste leverdatum", terms: "Betalingstermijn", days: "dagen",
       to: "Leverancier", deliver_to: "Leveradres", pos: "Pos.", code: "Code", supplier_code: "Uw code", description: "Omschrijving",
       qty: "Aantal", price: "Prijs", total: "Totaal", subtotal: "Totaal excl. BTW", vat: "BTW", grand: "Totaal incl. BTW", notes: "Opmerkingen",
       preview: "VOORBEELD", cancelled: "GEANNULEERD", page: "Pagina", vat_no: "BTW"),
  fr: (title: "Bon de commande", number: "Numéro", date: "Date", expected: "Date de livraison souhaitée", terms: "Délai de paiement", days: "jours",
       to: "Fournisseur", deliver_to: "Adresse de livraison", pos: "Pos.", code: "Code", supplier_code: "Votre code", description: "Description",
       qty: "Quantité", price: "Prix", total: "Total", subtotal: "Total HTVA", vat: "TVA", grand: "Total TVAC", notes: "Remarques",
       preview: "APERÇU", cancelled: "ANNULÉ", page: "Page", vat_no: "TVA"),
  en: (title: "Purchase order", number: "Number", date: "Date", expected: "Requested delivery date", terms: "Payment terms", days: "days",
       to: "Supplier", deliver_to: "Deliver to", pos: "Pos.", code: "Code", supplier_code: "Your code", description: "Description",
       qty: "Qty", price: "Price", total: "Total", subtotal: "Total excl. VAT", vat: "VAT", grand: "Total incl. VAT", notes: "Notes",
       preview: "PREVIEW", cancelled: "CANCELLED", page: "Page", vat_no: "VAT"),
  de: (title: "Bestellung", number: "Nummer", date: "Datum", expected: "Gewünschter Liefertermin", terms: "Zahlungsziel", days: "Tage",
       to: "Lieferant", deliver_to: "Lieferadresse", pos: "Pos.", code: "Artikel", supplier_code: "Ihre Nr.", description: "Beschreibung",
       qty: "Menge", price: "Preis", total: "Summe", subtotal: "Summe netto", vat: "MwSt.", grand: "Summe brutto", notes: "Bemerkungen",
       preview: "VORSCHAU", cancelled: "STORNIERT", page: "Seite", vat_no: "MwSt."),
  es: (title: "Pedido de compra", number: "Número", date: "Fecha", expected: "Fecha de entrega deseada", terms: "Plazo de pago", days: "días",
       to: "Proveedor", deliver_to: "Dirección de entrega", pos: "Pos.", code: "Código", supplier_code: "Su código", description: "Descripción",
       qty: "Cantidad", price: "Precio", total: "Total", subtotal: "Total sin IVA", vat: "IVA", grand: "Total con IVA", notes: "Observaciones",
       preview: "VISTA PREVIA", cancelled: "ANULADO", page: "Página", vat_no: "IVA"),
)
#let l = labels.at(d.language, default: labels.en)
#let mark = if d.watermark == "preview" { l.preview } else if d.watermark == "cancelled" { l.cancelled } else { none }

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 18mm, bottom: 22mm),
  background: if mark != none { rotate(-35deg, text(80pt, fill: rgb(0, 0, 0, 18), weight: "bold", mark)) },
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company.name · #d.company.street · #d.company.city_line
    #if d.company.vat_number != "" [ · #l.vat_no #d.company.vat_number]
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
    #if d.company.vat_number != "" [#l.vat_no #d.company.vat_number]
  ],
  align(right)[
    #v(10mm)
    #align(left, box(width: 70mm)[
      #text(fill: luma(100), size: 8pt, l.to) \
      *#d.supplier.name* \
      #if d.supplier.street != "" [#d.supplier.street \ ]
      #if d.supplier.contact != "" [#d.supplier.contact \ ]
      #d.supplier.country_code
      #if d.supplier.vat_number != "" [ · #l.vat_no #d.supplier.vat_number]
    ])
  ],
)

#v(8mm)
#text(18pt, weight: "bold", l.title)
#v(2mm)
#table(
  columns: 4,
  stroke: none,
  inset: (x: 0pt, right: 10mm, y: 2pt),
  [#text(fill: luma(100), l.number)], [#text(fill: luma(100), l.date)],
  [#text(fill: luma(100), l.expected)], [#text(fill: luma(100), l.terms)],
  [*#d.number*], [*#d.date*], [*#d.expected_date*], [*#d.payment_terms_days #l.days*],
)

#v(3mm)
#text(fill: luma(100), size: 8pt, l.deliver_to) \
#d.deliver_to.name, #d.deliver_to.street, #d.deliver_to.city_line

#v(5mm)
#table(
  columns: (auto, auto, auto, 1fr, auto, auto, auto),
  align: (left, left, left, left, right, right, right),
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header([*#l.pos*], [*#l.code*], [*#l.supplier_code*], [*#l.description*], [*#l.qty*], [*#l.price* (#d.currency)], [*#l.total* (#d.currency)]),
  ..d.lines.map(x => (str(x.position), x.code, x.supplier_code, x.description, [#x.quantity #x.unit], x.unit_price, x.total)).flatten()
)

#v(3mm)
#align(right, table(
  columns: (auto, auto),
  align: (left, right),
  stroke: none,
  inset: (x: 6pt, y: 2pt),
  [#l.subtotal], [#d.subtotal #d.currency],
  [#l.vat], [#d.tax_total #d.currency],
  table.hline(stroke: 0.5pt),
  [*#l.grand*], [*#d.total #d.currency*],
))

#if d.notes != "" [
  #v(6mm)
  *#l.notes* \
  #d.notes
]
