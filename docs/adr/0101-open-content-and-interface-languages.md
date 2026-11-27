# 0101 — Open content and interface languages

**Status:** Accepted (changes the fixed language list of [ADR 0017](0017-helpdesk-sla-teams-attachments.md),
[ADR 0074](0074-price-lists.md) and [ADR 0098](0098-document-library-and-mail-merge.md); keeps the
price list fallback of ADR 0074)

**Context.** Five languages (nl, fr, en, de, es) were built in everywhere: a `LANGUAGES` constant in
the core crate and copies of it in other crates, `CHECK (language IN (...))` constraints in twelve
columns, per-language label tables in the Typst templates and in the Rust code that prints
documents and writes system mails, hard-coded lists in the Flutter app and the web UI, and five
ARB files that are the only interface languages. The application is installed by different
companies that each speak and sell in their own languages, so a company working in Italian,
Polish or Swedish could not use it without changing code.

Two different things are called "language" here:

- **content languages**: the language of what a company writes and prints for its customers
  (product names, price lists, knowledge base, prepared answers, favorites, customer and contact
  language, tickets, mail merge, printed documents and system mails);
- **interface languages**: the language of the application's own screens (Flutter app, web UI,
  customer portal).

**Decision.**

1. **Language codes are ISO 639-1.** `tradocraft_core::language` holds `ISO_639_1` (all 184
   two-letter codes, sorted) and `is_iso_639_1`. `tradocraft_core::is_language` now means "a valid
   ISO 639-1 code". The `LANGUAGES` constants are gone. Display names come from a static table
   (`tradocraft_core::languages::names`: English name and endonym per code) with the same table
   in the Flutter app (`app/lib/l10n/language_names.dart`; a Rust test keeps the two equal). No
   CLDR dependency: endonyms are enough for a language picker and the table is 184 lines.
2. **Company content languages.** `core.company_languages (company_id, language, sort_order)`
   holds the ordered list of content languages an administrator configured; the company's
   default language (`core.companies.default_language`) is always one of them. A migration seeds
   every existing company with nl, fr, en, de, es (unchanged behaviour); a company created by
   provisioning gets the languages of its spec (default: only its default language) and a
   company inserted directly gets its default language (trigger). `Company.languages` (in `GET
   /me`) carries the list to every client; `GET /languages` lists all ISO codes with names;
   `PUT /admin/company/languages` (`users.admin`) replaces the list and default. The Flutter
   administration and the web UI company page edit it.
3. **Where which check applies.**
   - The database only checks the format (`~ '^[a-z]{2}$'`). A new migration replaces the twelve
     `IN (...)` constraints; old migrations are not edited.
   - Stored content takes any ISO 639-1 code (API check `is_language`): customer and contact
     language, ticket language, texts per language (knowledge base, prepared answers, favorites,
     price list group titles and item descriptions, product translations, rebate wordings),
     mail-merge language, automation conditions, the `lang` of a printed document. Imports,
     inbound mail and records written before a language was removed from the company stay valid
     and editable.
   - Where the company publishes in a set of languages it chose, the code must be one of the
     company's languages (`languages::require_company_language`): the company default and the
     languages of a price list zone.
   - Every language picker in the clients offers the company's languages in their order (plus
     the record's current value when that is no longer configured, so it is not lost).
   - Language detection of inbound mail keeps its own word lists (nl, fr, en, de, es); a text in
     another language is simply not detected and the ticket takes the customer's language.
   - Knowledge base search uses the Postgres text search configuration of the language when
     Postgres ships one (29 languages), else `simple`.
4. **Fallback chain for content.** `languages::fallback_chain(requested, company_default,
   company_languages)` is: requested language, English, company default, then the company's other
   languages in their order; `languages::pick` takes the first available text in that order and
   else any text. English comes before the company default because a reader who does not get
   their own language is more likely to read English than the company's local language, and
   because the knowledge base and prepared answers already fell back to English first; they now
   use this chain (in SQL through `core.language_rank` and `core.language_order`, which replace
   the hard-coded `array_position(ARRAY['nl', ...])` orderings). Price lists keep their chain of
   ADR 0074 (requested, company default, the list's languages, any): a list is published only in
   the languages chosen for the zone, so English is not special there.
5. **Document and mail labels are a translation catalogue.** The fixed words of printed documents
   ("Invoice", "Quantity", "Page") and system mails are no longer tables in templates and code.
   - Shipped catalogues per language (`crates/core/i18n/<language>.json`, flat `key → text`, keys
     like `delivery_note.title` or `mail.outage.subject`, `{name}` placeholders) are compiled into
     the binary; English is complete and is the template for translators.
   - `core.translations (company_id, domain, language, entries)` stores catalogues an
     administrator adds or overrides, per company, for the domains `documents` and `mail` (and
     the interface domains below). Any ISO 639-1 language can be added without code changes.
   - `translations::catalogue(db, company, domain, language)` layers: shipped English, the
     company's English, shipped language, the company's language; a key missing in the language
     falls back to English. The PDF renderer writes the template's labels into `labels.json`
     next to `data.json`; templates read `json("labels.json")` and no longer list languages.
   - `GET /translations/{domain}`, `GET /translations/{domain}/{language}` (shipped and company
     entries, for editing and as export template), `PUT` and `DELETE
     /admin/translations/{domain}/{language}` (`users.admin`).
6. **Interface translations at runtime.** The shipped ARB files stay and are compiled in as
   before. Additional interface languages (or corrections of a shipped one) are catalogues in the
   domains `app` (Flutter app and portal) and `web` (web UI), uploaded or edited by an
   administrator and served by the API.
   - Flutter: a generated `RuntimeAppLocalizations` (from the generated `AppLocalizations`,
     `tool/gen_runtime_l10n.dart`) answers every message from the runtime catalogue when it has
     the key and from the shipped localization of the language, else English, otherwise. Messages
     with placeholders, plurals and selects are formatted at runtime by a small ICU message
     formatter (`{name}`, `plural` with CLDR plural rules from `intl`, `select`). Its delegate
     supports every shipped or installed language; Material, Cupertino and Widgets localizations
     fall back to English for languages Flutter itself does not ship. Each user chooses the
     interface language from the shipped plus installed ones (stored per device as before). The
     administration screen imports and exports ARB files and the English ARB (bundled as an asset)
     is the translator template.
   - Web UI: a catalogue context with `tr(key, english)` loads the `web` catalogue of the chosen
     language and falls back to the English text in the code; its English source catalogue can be
     exported from the language settings. Pages adopt `tr` step by step (shell and navigation
     first).
7. **Neutral defaults.** Nothing assumes a country: a new company has only its own default
   language until an administrator adds more; English is the fallback because it is the language
   the application is written in.

**Consequences.**

- Adding a content language is configuration; adding an interface language is uploading a
  catalogue. Neither needs a release.
- Removing a language from a company hides it from pickers and from new price list zones; stored
  texts in that language remain and are shown through the fallback chain.
- Labels and mails in a language without a shipped catalogue are English until an administrator
  adds a catalogue; the result is complete, never empty.
- The generated runtime localization class must be regenerated when ARB keys change
  (`dart run tool/gen_runtime_l10n.dart`, checked by a Flutter test).
