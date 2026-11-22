#let d = json("data.json")
#let labels = (
  en: (invoice: "Invoice", credit: "Credit note", date: "Date", due: "Due date", original: "Original invoice", reason: "Reason", seller: "Seller", customer: "Customer", code: "Code", item: "Description", qty: "Quantity", price: "Unit price", net: "Excl. VAT", vat: "VAT", total: "Total", reverse: "VAT reverse charged (intra-community supply)", domestic_reverse: "VAT reverse charge (work on immovable property)", export: "Export outside the EU, no VAT"),
  nl: (invoice: "Factuur", credit: "Creditnota", date: "Datum", due: "Vervaldatum", original: "Oorspronkelijke factuur", reason: "Reden", seller: "Verkoper", customer: "Klant", code: "Code", item: "Omschrijving", qty: "Aantal", price: "Eenheidsprijs", net: "Excl. btw", vat: "Btw", total: "Totaal", reverse: "BTW verlegd (intracommunautaire levering)", domestic_reverse: "BTW verlegd (werken in onroerende staat, art. 20 KB nr. 1)", export: "Uitvoer buiten de EU, geen BTW"),
  fr: (invoice: "Facture", credit: "Note de crédit", date: "Date", due: "Échéance", original: "Facture d’origine", reason: "Motif", seller: "Vendeur", customer: "Client", code: "Code", item: "Description", qty: "Quantité", price: "Prix unitaire", net: "Hors TVA", vat: "TVA", total: "Total", reverse: "TVA en autoliquidation (livraison intracommunautaire)", domestic_reverse: "Autoliquidation (travaux immobiliers, art. 20 AR n° 1)", export: "Exportation hors UE, sans TVA"),
  de: (invoice: "Rechnung", credit: "Gutschrift", date: "Datum", due: "Fällig am", original: "Ursprüngliche Rechnung", reason: "Grund", seller: "Verkäufer", customer: "Kunde", code: "Code", item: "Beschreibung", qty: "Menge", price: "Einzelpreis", net: "Ohne MwSt.", vat: "MwSt.", total: "Gesamt", reverse: "Steuerschuldnerschaft des Leistungsempfängers (innergemeinschaftliche Lieferung)", domestic_reverse: "Steuerschuldnerschaft des Leistungsempfängers (Bauleistungen)", export: "Ausfuhr außerhalb der EU, ohne MwSt."),
  es: (invoice: "Factura", credit: "Nota de crédito", date: "Fecha", due: "Vencimiento", original: "Factura original", reason: "Motivo", seller: "Vendedor", customer: "Cliente", code: "Código", item: "Descripción", qty: "Cantidad", price: "Precio unitario", net: "Sin IVA", vat: "IVA", total: "Total", reverse: "Inversión del sujeto pasivo (entrega intracomunitaria)", domestic_reverse: "Inversión del sujeto pasivo (ejecuciones de obra inmobiliaria)", export: "Exportación fuera de la UE, sin IVA"),
)
#let l = labels.at(d.language, default: labels.en)
#let title = if d.kind == "credit_note" { l.credit } else { l.invoice }
#set document(title: title + " " + d.number)
#set text(size: 10pt, lang: if d.language in labels.keys() { d.language } else { "en" })
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
