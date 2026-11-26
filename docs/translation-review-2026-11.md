# Translation review, November 2026: price lists and site baseline

Scope: ARB keys `pl*`, `priceList*`, `pricedOnPriceListOf`, `revisionPriceLists`, `useAnotherPriceListDate`, `purchPriceList` (price lists) and `baseline*`, `adminBaselineTypes` (site baseline, deferred from the first release but reviewed anyway). Each language was compared with `app_en.arb` for meaning, completeness, terminology versus the rest of the same file, register, placeholders (all `{name}` placeholders match English in every string) and button-length risk.

Reviewed per language: 117 strings (all five languages have every key; no untranslated or missing entries). Four of the 117 are not pure translations (`plGeneratePdf`, `plGenerateXlsx`, `baselineImportUnmappedRow`, `baselineImportWarning`) and were already correct.

Established glossary (from existing keys): quotation = nl Offerte / fr Offre / de Angebot / es Presupuesto; order = nl Order / fr Commande / de Auftrag / es Pedido; quantity = Aantal / Quantité / Menge / Cantidad; unit = Eenheid / Unité / Einheit / Unidad; administration = Beheer / Administration / Verwaltung / Administración; price list = Prijslijst / Liste de prix (and Tarif for the dated list) / Preisliste / Lista de precios (and Tarifa for the dated list). Register: nl imperative or "U", fr vous, de Sie, es usted.

## nl (6 changes)

| Key | Old -> New | Reason |
|---|---|---|
| adminBaselineTypes | Basistypes -> Types uitgangssituatie | "Basis" did not match the feature name (Uitgangssituatie) |
| baselineNoTypes | ...onder Beheer, Basistypes. -> ...onder Beheer, Types uitgangssituatie. | Must name the menu entry exactly |
| baselineImportDone | Basislijn geïmporteerd. -> Uitgangssituatie geïmporteerd. | "Basislijn" is a literal calque; use the feature term |
| baselineEmpty | uurwerkwijzerplaten -> wijzerplaten | Clock dials; the long compound was unnatural |
| plDeleteConfirm | ...met groepen en artikelen... -> ...met alle groepen en producten erin... | "artikelen" was inconsistent with "producten" used everywhere else in the price-list screens |
| plGenSummary | bewaard -> opgeslagen | Standard term for saved files |

## fr (1 change)

| Key | Old -> New | Reason |
|---|---|---|
| baselineImportUnmapped | Champs non reconnus -> Champs non associés | "not mapped" means not assigned, not "not recognised" |

Checked and kept: "Chiffrée" (agrees with "Offre", feminine), Tarif vs Liste de prix (both already used in the file), "l'existant" as noun for the baseline.

## de (10 changes)

| Key | Old -> New | Reason |
|---|---|---|
| baselineTitle | Bestand vor Ort -> Ist-Zustand vor Ort | "Bestand" means stock elsewhere in the file (count*, delivery*): ambiguous and wrong here |
| adminBaselineTypes | Bestandstypen -> Typen des Ist-Zustands | same |
| baselineTypesTitle | Eintragstypen des Bestands -> Eintragstypen des Ist-Zustands | same |
| baselineNoTypes | ...Verwaltung, Bestandstypen -> ...Verwaltung, Typen des Ist-Zustands | must match menu entry |
| baselineImportDone | Bestand importiert. -> Ist-Zustand importiert. | same |
| baselineParent | Untergeordnet zu -> Übergeordneter Eintrag | Old text said the opposite (subordinate to); the field selects the parent |
| plIndent | Zur Untergruppe der darüberliegenden Gruppe machen -> Zur Untergruppe der Gruppe darüber machen | Shorter, less clumsy |
| plNoZones | erzeugen -> erstellen | Consistent with the button "Erstellen" |
| plGenNothing | erzeugen -> erstellen | same |
| plExportsHint | erzeugt -> erstellt | same |

## es (6 changes)

| Key | Old -> New | Reason |
|---|---|---|
| baselineTitle | Situación existente en el sitio -> Situación existente en el emplazamiento | "sitio" reads as website; "emplazamiento" is the installation site |
| baselineEmpty | del sitio -> del emplazamiento | same |
| adminBaselineTypes | Tipos de existente -> Tipos de situación existente | "existente" is not a noun in Spanish |
| baselineImportDone | Situación actual importada. -> Situación existente importada. | Use the same term as the title |
| baselineParent | Colocado bajo -> Ubicado bajo | More natural for a location |
| plExportDeleteConfirm | "{name}" -> «{name}» | Match the «» quotes used in plDeleteGroupConfirm |

(plNotPrintedNote was re-saved with identical text.)

## Open questions for native speakers

- nl: is "item" acceptable in Belgian business Dutch for baseline items (the file uses it widely), or should it be "onderdeel"? Should the wijzerplaat/-platen and klok(ken) forms in baselineImportCreates become a cleaner phrasing?
- nl: the file mixes imperative and "U" forms (e.g. "Voeg ... toe" versus "U kunt ..."); not changed.
- fr: should "Tarif" (dated list) and "Liste de prix" be unified? Both are established in the file. Is "Existant sur site" the right label for the baseline?
- de: is "Ist-Zustand" the preferred term for the surveyed state at a tower, or would "Bestandsaufnahme" fit better? ("Position" vs "Eintrag" for baseline items: "Eintrag" kept.)
- es: the file mixes usted and tú (idpLinkExplain uses "Elige"); price-list and baseline strings use usted, consistent with most of the file. Confirm "Ubicado bajo" and "Tarifa" vs "Lista de precios".
- All: no button text became noticeably longer; the longest new strings are the es title and nl admin menu label, both menu or heading text rather than buttons.
