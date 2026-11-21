// Order confirmation template. Data comes from data.json (see crates/sales/src/order_doc.rs).
// All amounts are pre-formatted by the API; this template never calculates.
#let d = json("data.json")

#let labels = (
  nl: (net: "netto", title: "Orderbevestiging", reference: "Uw referentie", quotation: "Offerte", number: "Nummer", revision: "Revisie", date: "Datum", vat: "BTW", code: "Code", description: "Omschrijving", qty: "Aantal", price: "Eenheidsprijs",
       discount: "Korting", total: "Totaal", subtotal: "Totaal excl. BTW", vat_on: "BTW op",
       grand: "Totaal incl. BTW", notes: "Opmerkingen", draft: "CONCEPT", page: "Pagina",
       reverse: "BTW verlegd (intracommunautaire levering)", domestic_reverse: "BTW verlegd (werken in onroerende staat, art. 20 KB nr. 1)", export: "Uitvoer buiten de EU, geen BTW"),
  fr: (net: "net", title: "Confirmation de commande", reference: "Votre référence", quotation: "Offre", number: "Numéro", revision: "Révision", date: "Date",vat: "TVA", code: "Code", description: "Description", qty: "Quantité", price: "Prix unitaire",
       discount: "Remise", total: "Total", subtotal: "Total HTVA", vat_on: "TVA sur",
       grand: "Total TVAC", notes: "Remarques", draft: "BROUILLON", page: "Page",
       reverse: "TVA en autoliquidation (livraison intracommunautaire)", domestic_reverse: "Autoliquidation (travaux immobiliers, art. 20 AR n° 1)", export: "Exportation hors UE, sans TVA"),
  en: (net: "net", title: "Order confirmation", reference: "Your reference", quotation: "Quotation", number: "Number", revision: "Revision", date: "Date",vat: "VAT", code: "Code", description: "Description", qty: "Qty", price: "Unit price",
       discount: "Discount", total: "Total", subtotal: "Total excl. VAT", vat_on: "VAT on",
       grand: "Total incl. VAT", notes: "Notes", draft: "DRAFT", page: "Page",
       reverse: "VAT reverse charged (intra-community supply)", domestic_reverse: "VAT reverse charge (work on immovable property)", export: "Export outside the EU, no VAT"),
  de: (net: "netto", title: "Auftragsbestätigung", reference: "Ihre Referenz", quotation: "Angebot", number: "Nummer", revision: "Revision", date: "Datum", vat: "MwSt.", code: "Artikel", description: "Beschreibung", qty: "Menge", price: "Einzelpreis",
       discount: "Rabatt", total: "Gesamt", subtotal: "Summe netto", vat_on: "MwSt. auf",
       grand: "Gesamtbetrag brutto", notes: "Bemerkungen", draft: "ENTWURF", page: "Seite",
       reverse: "Steuerschuldnerschaft des Leistungsempfängers (innergemeinschaftliche Lieferung)", domestic_reverse: "Steuerschuldnerschaft des Leistungsempfängers (Bauleistungen)", export: "Ausfuhr außerhalb der EU, ohne MwSt."),
  es: (net: "neto", title: "Confirmación de pedido", reference: "Su referencia", quotation: "Presupuesto", number: "Número", revision: "Revisión", date: "Fecha",vat: "IVA", code: "Código", description: "Descripción", qty: "Cantidad", price: "Precio unitario",
       discount: "Descuento", total: "Total", subtotal: "Base imponible", vat_on: "IVA sobre",
       grand: "Total IVA incl.", notes: "Observaciones", draft: "BORRADOR", page: "Página",
       reverse: "Inversión del sujeto pasivo (entrega intracomunitaria)", domestic_reverse: "Inversión del sujeto pasivo (ejecuciones de obra inmobiliaria)", export: "Exportación fuera de la UE, sin IVA"),
)
#let l = labels.at(d.language, default: labels.en)
#let cur = if d.currency == "EUR" { "€" } else { d.currency }

#set document(title: l.title + " " + d.number)
#set text(size: 9.5pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
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
  columns: 5,
  stroke: none,
  inset: (x: 0pt, right: 10mm, y: 2pt),
  [#text(fill: luma(100), l.number)], [#text(fill: luma(100), l.revision)],
  [#text(fill: luma(100), l.date)], [#text(fill: luma(100), l.quotation)],
  [#text(fill: luma(100), l.reference)],
  [*#d.number*], [*#d.revision*], [*#d.order_date*], [*#d.quotation_number*],
  [*#d.customer_reference*],
)

#v(6mm)
#table(
  columns: if d.show_vat { (auto, 1fr, auto, auto, auto, auto, auto) } else { (auto, 1fr, auto, auto, auto, auto) },
  align: if d.show_vat { (left, left, right, right, right, right, right) } else { (left, left, right, right, right, right) },
  stroke: (x, y) => if y == 0 { (bottom: 0.7pt) } else { (bottom: 0.3pt + luma(210)) },
  inset: (x: 4pt, y: 5pt),
  table.header(
    [*#l.code*], [*#l.description*], [*#l.qty*], [*#l.price*], [*#l.discount*], ..if d.show_vat { ([*#l.vat*],) } else { () }, [*#l.total*],
  ),
  ..d.lines.map(x => (
    {
      if x.image != none { box(image(x.image, width: 14mm, height: 14mm, fit: "contain")); linebreak() }
      x.code
    }, [#x.description#if x.customer_remark != "" [\ #text(size: 8.5pt, fill: luma(60), x.customer_remark)]], [#x.quantity #x.unit], [#cur #x.unit_price], if x.net { l.net } else { x.discount }, ..if d.show_vat { (x.vat_rate,) } else { () }, [#cur #x.total],
  )).flatten()
)

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
