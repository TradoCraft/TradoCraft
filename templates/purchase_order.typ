// Purchase order template. Data comes from data.json (see crates/purchasing/src/po_doc.rs).
#let d = json("data.json")

#let labels = (
  nl: (title: "Bestelbon", number: "Nummer", date: "Datum", delivery: "Gewenste leverdatum", terms: "Betalingstermijn", days: "dagen",
       supplier: "Leverancier", pos: "Pos.", code: "Code", their_code: "Uw code", description: "Omschrijving", qty: "Aantal",
       price: "Eenheidsprijs", total: "Totaal", subtotal: "Subtotaal", tax: "BTW", grand: "Totaal", notes: "Opmerkingen",
       preview: "VOORBEELD", cancelled: "GEANNULEERD", vat: "BTW", page: "Pagina"),
  fr: (title: "Bon de commande", number: "Numéro", date: "Date", delivery: "Livraison souhaitée", terms: "Délai de paiement", days: "jours",
       supplier: "Fournisseur", pos: "Pos.", code: "Code", their_code: "Votre code", description: "Description", qty: "Quantité",
       price: "Prix unitaire", total: "Total", subtotal: "Sous-total", tax: "TVA", grand: "Total", notes: "Remarques",
       preview: "APERÇU", cancelled: "ANNULÉ", vat: "TVA", page: "Page"),
  en: (title: "Purchase order", number: "Number", date: "Date", delivery: "Requested delivery", terms: "Payment terms", days: "days",
       supplier: "Supplier", pos: "Pos.", code: "Code", their_code: "Your code", description: "Description", qty: "Qty",
       price: "Unit price", total: "Total", subtotal: "Subtotal", tax: "VAT", grand: "Total", notes: "Notes",
       preview: "PREVIEW", cancelled: "CANCELLED", vat: "VAT", page: "Page"),
  de: (title: "Bestellung", number: "Nummer", date: "Datum", delivery: "Gewünschter Liefertermin", terms: "Zahlungsziel", days: "Tage",
       supplier: "Lieferant", pos: "Pos.", code: "Artikel", their_code: "Ihre Nr.", description: "Beschreibung", qty: "Menge",
       price: "Einzelpreis", total: "Summe", subtotal: "Zwischensumme", tax: "MwSt.", grand: "Gesamt", notes: "Bemerkungen",
       preview: "VORSCHAU", cancelled: "STORNIERT", vat: "MwSt.", page: "Seite"),
  es: (title: "Orden de compra", number: "Número", date: "Fecha", delivery: "Entrega deseada", terms: "Plazo de pago", days: "días",
       supplier: "Proveedor", pos: "Pos.", code: "Código", their_code: "Su código", description: "Descripción", qty: "Cantidad",
       price: "Precio unitario", total: "Total", subtotal: "Subtotal", tax: "IVA", grand: "Total", notes: "Observaciones",
       preview: "VISTA PREVIA", cancelled: "ANULADO", vat: "IVA", page: "Página"),
)
#let l = labels.at(d.language, default: labels.en)

// A draft is a preview and a cancelled order says so on every page.
#let watermark = if d.status == "draft" { l.preview } else if d.status == "cancelled" { l.cancelled } else { none }

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
#set page(
  paper: "a4",
  margin: (x: 18mm, top: 18mm, bottom: 22mm),
  background: if watermark != none { rotate(-35deg, text(80pt, fill: rgb(0, 0, 0, 18), weight: "bold", watermark)) },
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
      #text(fill: luma(100), size: 8pt, l.supplier) \
      *#d.supplier.name* \
      #if d.supplier.street != "" [#d.supplier.street \ ]
      #if d.supplier.city_line != "" [#d.supplier.city_line \ ]
      #if d.supplier.country_code != "" [#d.supplier.country_code \ ]
      #if d.supplier.contact != "" [#text(size: 8.5pt, d.supplier.contact) \ ]
      #if d.supplier.vat_number != "" [#text(size: 8.5pt)[#l.vat #d.supplier.vat_number]]
    ])
  ],
)

#v(10mm)
#text(18pt, weight: "bold", l.title)
#v(2mm)
// Only the facts that are known get a column.
#let meta = (
  (l.number, d.number),
  (l.date, d.date),
  ..if d.expected_delivery != "" { ((l.delivery, d.expected_delivery),) } else { () },
  ..if d.payment_terms_days != "" { ((l.terms, d.payment_terms_days + " " + l.days),) } else { () },
)
#table(
  columns: meta.len(),
  stroke: none,
  inset: (x: 0pt, right: 10mm, y: 2pt),
  ..meta.map(m => text(fill: luma(100), m.at(0))),
  ..meta.map(m => strong(m.at(1))),
)

#v(6mm)
#table(
  columns: (auto, auto, auto, 1fr, auto, auto, auto),
  align: (left, left, left, left, right, right, right),
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header([*#l.pos*], [*#l.code*], [*#l.their_code*], [*#l.description*], [*#l.qty*], [*#l.price*], [*#l.total*]),
  ..d.lines.map(x => (str(x.position), x.code, x.supplier_code, x.description, x.quantity, x.unit_price, x.total)).flatten()
)

#v(3mm)
#align(right, table(
  columns: (auto, auto),
  align: (left, right),
  stroke: none,
  inset: (x: 4pt, y: 3pt),
  [#l.subtotal], [#d.subtotal #d.currency],
  ..if d.tax_total != "" { ([#l.tax], [#d.tax_total #d.currency]) } else { () },
  table.hline(stroke: 0.7pt),
  [*#l.grand*], [*#d.total #d.currency*],
))

#if d.notes != "" [
  #v(6mm)
  *#l.notes* \
  #d.notes
]
