// Service report template. Data comes from data.json (see crates/fieldservice/src/report.rs).
// Photos and the signature are files next to data.json. Nothing internal is in the data.
#let d = json("data.json")

#let labels = (
  nl: (title: "Werkbon", number: "Nummer", kind: "Soort", contract: "Onderhoudscontract", customer: "Klant", site: "Plaats van uitvoering",
       contact: "Contactpersoon", scheduled: "Gepland", started: "Gestart", completed: "Afgerond", technicians: "Technici",
       tasks: "Taken", task: "Taak", result: "Resultaat", done: "Uitgevoerd", open: "Niet uitgevoerd",
       time: "Tijd", work: "Werktijd", travel: "Reistijd", parts: "Gebruikte onderdelen", qty: "Aantal", billable: "Aangerekend", free: "Niet aangerekend",
       yes: "ja", no: "nee", equipment: "Installatie", serial: "Serienummer", warranty: "Garantie", until: "tot",
       in_warranty: "onder garantie", expired: "garantie verlopen", unknown: "garantie onbekend",
       report: "Verslag", photos: "Foto's", not_shown: "niet afgedrukt", signature: "Handtekening klant",
       signed_by: "Getekend door", declined: "De klant weigerde te tekenen", reason: "Reden", draft: "CONCEPT", page: "Pagina", vat: "BTW",
       kinds: (installation: "Installatie", maintenance: "Onderhoud", repair: "Herstelling", inspection: "Inspectie", other: "Andere")),
  fr: (title: "Rapport d'intervention", number: "Numéro", kind: "Type", contract: "Contrat d'entretien", customer: "Client", site: "Lieu d'intervention",
       contact: "Personne de contact", scheduled: "Prévu", started: "Début", completed: "Terminé", technicians: "Techniciens",
       tasks: "Tâches", task: "Tâche", result: "Résultat", done: "Effectuée", open: "Non effectuée",
       time: "Temps", work: "Temps de travail", travel: "Temps de trajet", parts: "Pièces utilisées", qty: "Quantité", billable: "Facturé", free: "Non facturé",
       yes: "oui", no: "non", equipment: "Installation", serial: "Numéro de série", warranty: "Garantie", until: "jusqu'au",
       in_warranty: "sous garantie", expired: "garantie expirée", unknown: "garantie inconnue",
       report: "Rapport", photos: "Photos", not_shown: "non imprimées", signature: "Signature du client",
       signed_by: "Signé par", declined: "Le client a refusé de signer", reason: "Motif", draft: "BROUILLON", page: "Page", vat: "TVA",
       kinds: (installation: "Installation", maintenance: "Entretien", repair: "Réparation", inspection: "Inspection", other: "Autre")),
  en: (title: "Service report", number: "Number", kind: "Type", contract: "Maintenance contract", customer: "Customer", site: "Site",
       contact: "Contact person", scheduled: "Scheduled", started: "Started", completed: "Completed", technicians: "Technicians",
       tasks: "Tasks", task: "Task", result: "Result", done: "Done", open: "Not done",
       time: "Time", work: "Work time", travel: "Travel time", parts: "Parts used", qty: "Quantity", billable: "Charged", free: "Not charged",
       yes: "yes", no: "no", equipment: "Equipment", serial: "Serial number", warranty: "Warranty", until: "until",
       in_warranty: "in warranty", expired: "warranty expired", unknown: "warranty unknown",
       report: "Report", photos: "Photos", not_shown: "not printed", signature: "Customer signature",
       signed_by: "Signed by", declined: "The customer declined to sign", reason: "Reason", draft: "DRAFT", page: "Page", vat: "VAT",
       kinds: (installation: "Installation", maintenance: "Maintenance", repair: "Repair", inspection: "Inspection", other: "Other")),
  de: (title: "Servicebericht", number: "Nummer", kind: "Art", contract: "Wartungsvertrag", customer: "Kunde", site: "Einsatzort",
       contact: "Ansprechpartner", scheduled: "Geplant", started: "Beginn", completed: "Abgeschlossen", technicians: "Techniker",
       tasks: "Aufgaben", task: "Aufgabe", result: "Ergebnis", done: "Erledigt", open: "Nicht erledigt",
       time: "Zeit", work: "Arbeitszeit", travel: "Fahrzeit", parts: "Verwendete Teile", qty: "Menge", billable: "Berechnet", free: "Nicht berechnet",
       yes: "ja", no: "nein", equipment: "Anlage", serial: "Seriennummer", warranty: "Garantie", until: "bis",
       in_warranty: "in Garantie", expired: "Garantie abgelaufen", unknown: "Garantie unbekannt",
       report: "Bericht", photos: "Fotos", not_shown: "nicht gedruckt", signature: "Unterschrift des Kunden",
       signed_by: "Unterschrieben von", declined: "Der Kunde hat die Unterschrift verweigert", reason: "Grund", draft: "ENTWURF", page: "Seite", vat: "MwSt.",
       kinds: (installation: "Installation", maintenance: "Wartung", repair: "Reparatur", inspection: "Inspektion", other: "Sonstiges")),
  es: (title: "Informe de servicio", number: "Número", kind: "Tipo", contract: "Contrato de mantenimiento", customer: "Cliente", site: "Lugar de intervención",
       contact: "Persona de contacto", scheduled: "Previsto", started: "Inicio", completed: "Finalizado", technicians: "Técnicos",
       tasks: "Tareas", task: "Tarea", result: "Resultado", done: "Realizada", open: "No realizada",
       time: "Tiempo", work: "Tiempo de trabajo", travel: "Tiempo de desplazamiento", parts: "Piezas utilizadas", qty: "Cantidad", billable: "Facturado", free: "No facturado",
       yes: "sí", no: "no", equipment: "Equipo", serial: "Número de serie", warranty: "Garantía", until: "hasta",
       in_warranty: "en garantía", expired: "garantía vencida", unknown: "garantía desconocida",
       report: "Informe", photos: "Fotos", not_shown: "no impresas", signature: "Firma del cliente",
       signed_by: "Firmado por", declined: "El cliente se negó a firmar", reason: "Motivo", draft: "BORRADOR", page: "Página", vat: "IVA",
       kinds: (installation: "Instalación", maintenance: "Mantenimiento", repair: "Reparación", inspection: "Inspección", other: "Otro")),
)
#let l = labels.at(d.language, default: labels.en)

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
    #h(1fr) #l.page #counter(page).display() / #counter(page).final().first()
  ],
)

#let muted(x) = text(fill: luma(100), x)
#let section(title) = [#v(5mm) #text(11pt, weight: "bold", title) #v(-1mm) #line(length: 100%, stroke: 0.5pt + luma(180)) #v(1mm)]
#let warranty_label(e) = {
  let s = l.at(e.warranty_status, default: l.unknown)
  if e.warranty_until != "" and e.warranty_status != "unknown" { s + " (" + l.until + " " + e.warranty_until + ")" } else { s }
}

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
    #align(left, box(width: 70mm)[
      *#d.customer.name* \
      #d.customer.street \
      #d.customer.city_line \
      #if d.customer.country_code != d.company.country_code [#d.customer.country_code \ ]
      #if d.customer.vat_number != "" [#l.vat #d.customer.vat_number]
    ])
  ],
)

#v(8mm)
#text(18pt, weight: "bold", l.title)
#v(1mm)
#text(11pt, weight: "bold", d.title)
#v(2mm)
#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 0pt, right: 6mm, y: 2.5pt),
  muted(l.number), [*#d.number*],
  muted(l.kind), l.kinds.at(d.kind, default: d.kind),
  ..if d.contract_number != "" { (muted(l.contract), d.contract_number) } else { () },
  ..if d.site != "" { (muted(l.site), d.site) } else { () },
  ..if d.contact_name != "" { (muted(l.contact), d.contact_name) } else { () },
  ..if d.scheduled_date != "" { (muted(l.scheduled), d.scheduled_date) } else { () },
  ..if d.started_date != "" { (muted(l.started), d.started_date) } else { () },
  ..if d.completed_date != "" { (muted(l.completed), d.completed_date) } else { () },
  ..if d.technicians != "" { (muted(l.technicians), d.technicians) } else { () },
)

#if d.tasks.len() > 0 [
  #section(l.tasks)
  #table(
    columns: (1fr, auto),
    stroke: (x, y) => (bottom: 0.3pt + luma(210)),
    inset: (x: 3pt, y: 4pt),
    table.header([*#l.task*], [*#l.result*]),
    ..d.tasks.map(t => (t.description, if t.done { l.done } else { text(fill: rgb("#b00020"), l.open) })).flatten()
  )
]

#section(l.time)
#grid(columns: (auto, auto, auto, auto), column-gutter: 6mm, row-gutter: 3pt,
  muted(l.work), [*#d.work_time h*], muted(l.travel), [*#d.travel_time h*])

#if d.parts.len() > 0 [
  #section(l.parts)
  #table(
    columns: (1fr, auto, auto),
    align: (left, right, left),
    stroke: (x, y) => (bottom: 0.3pt + luma(210)),
    inset: (x: 3pt, y: 4pt),
    table.header([], [*#l.qty*], [*#l.billable*]),
    ..d.parts.map(p => (p.description, [#p.quantity #p.unit], if p.billable { l.yes } else { l.free })).flatten()
  )
]

#if d.equipment.len() > 0 [
  #section(l.equipment)
  #table(
    columns: (1fr, auto, auto),
    stroke: (x, y) => (bottom: 0.3pt + luma(210)),
    inset: (x: 3pt, y: 4pt),
    table.header([], [*#l.serial*], [*#l.warranty*]),
    ..d.equipment.map(e => (e.product, e.serial_number, warranty_label(e))).flatten()
  )
]

#if d.completion_notes != "" [
  #section(l.report)
  #d.completion_notes
]

#if d.photos.len() > 0 or d.photos_not_shown > 0 [
  #block(breakable: false)[
  #section(l.photos)
  #if d.photos.len() > 0 [
    #grid(
      columns: (1fr, 1fr, 1fr), gutter: 4mm,
      ..d.photos.map(p => [
        #box(width: 100%, height: 42mm, clip: true, image(p.file, width: 100%, height: 42mm, fit: "cover"))
        #if p.caption != "" [#text(8pt, fill: luma(90), p.caption)]
      ])
    )
  ]
  #if d.photos_not_shown > 0 [#text(8pt, fill: luma(110), "+" + str(d.photos_not_shown) + " " + l.not_shown)]
  ]
]

#if d.signature != none [
  #block(breakable: false)[
    #section(l.signature)
    #if d.signature.declined [
      #l.declined \
      #muted(l.reason): #d.signature.reason
      #if d.signature.signer != "" [\ #muted(l.signed_by): #d.signature.signer]
    ] else [
      #if d.signature.file != none [
        #box(stroke: 0.5pt + luma(200), inset: 4pt, image(d.signature.file, height: 25mm))
        \
      ]
      #muted(l.signed_by): *#d.signature.signer* · #d.signature.date
    ]
  ]
]
