// Price list template (ADR 0069). Data comes from data.json (see crates/documents/src/price_list.rs).
// Prices, labels and group titles are chosen and formatted by the API; this template never calculates.
#let d = json("data.json")
#let l = d.labels
#let accent = rgb(d.accent_color)

#set document(title: d.title)
#set text(size: 9pt, lang: if d.language in ("nl", "fr", "de", "es") { d.language } else { "en" })
#set page(
  paper: "a4",
  margin: (x: 16mm, top: 18mm, bottom: 20mm),
  footer: context [
    #set text(7.5pt, fill: luma(110))
    #d.company_name#if d.footer_text != "" [ · #d.footer_text]
    #h(1fr) #l.page #counter(page).display() / #counter(page).final().first()
  ],
)

#grid(
  columns: (1fr, auto),
  column-gutter: 8mm,
  align: (left + top, right + top),
  [
    #text(18pt, weight: "bold", fill: accent, d.title) \
    #text(fill: luma(90))[#d.company_name · #l.zone #d.zone_name · #l.valid_from #d.valid_from]
  ],
  if d.logo_file != none { image(d.logo_file, height: 16mm, width: 50mm, fit: "contain") },
)
#v(5mm)

#let price-cell(r) = {
  if r.on_request { text(size: 8pt, weight: "bold", l.on_request) }
  else [#d.currency #r.price#if r.net [ #text(size: 7.5pt, weight: "bold", l.net)]#if r.indicative [\*]]
}
#let columns = if d.show_unit { (30mm, 1fr, 16mm, 36mm) } else { (30mm, 1fr, 36mm) }
#let row-cells(r) = (
  r.code,
  r.description,
  ..if d.show_unit { (r.unit,) } else { () },
  align(right, price-cell(r)),
)

#let table-emitted = false
// A page break asked for by a group applies to the first thing printed from it on (its title, or
// its rows when untitled), so a hidden section or chapter node hands its break to what follows.
// Nothing breaks before the first printed content, and consecutive breaks never leave a blank page.
#let printed = false
#let pending-break = false
#for s in d.sections {
  if s.page_break { pending-break = true }
  if s.show_title or s.rows.len() > 0 {
    if pending-break and printed { pagebreak(weak: true) }
    pending-break = false
    printed = true
  }
  if s.show_title {
    // Styling follows the number of printed ancestor titles, not the depth in the tree: hidden
    // section and chapter nodes do not shrink the headings below them.
    let pl = s.print_level
    let size = if pl == 0 { 12pt } else if pl == 1 { 10.5pt } else { 9.5pt }
    v(if pl == 0 { 4mm } else { 2mm })
    block(width: 100%, below: 1.5mm, {
      text(size, weight: "bold", fill: if pl == 0 { accent } else { black }, s.title)
      if pl == 0 { line(length: 100%, stroke: 0.7pt + accent) }
    })
  } else {
    // Untitled group: no title block and (unless it is the first table of the list) no repeated column header,
    // only a gap.
    v(s.gap_mm * 1mm)
  }
  if s.rows.len() > 0 {
    block(above: if s.show_title { 1.2em } else { 0pt }, below: 0pt, table(
      columns: columns,
      stroke: (x, y) => (bottom: 0.3pt + luma(220)),
      inset: (x: 4pt, y: 3.5pt),
      ..if s.show_title or not table-emitted {
        (table.header(
          [#text(fill: luma(100), l.code)], [#text(fill: luma(100), l.description)],
          ..if d.show_unit { ([#text(fill: luma(100), l.unit)],) } else { () },
          align(right, text(fill: luma(100), l.price)),
        ),)
      } else { () },
      ..s.rows.map(row-cells).flatten(),
    ))
    table-emitted = true
  }
}

#if d.has_indicative [
  #v(4mm)
  #text(size: 8pt, fill: luma(90))[\* #l.indicative]
]
