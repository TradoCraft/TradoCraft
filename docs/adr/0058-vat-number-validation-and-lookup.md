# 0058 — VAT number validation, VIES lookup and duplicate warning

**Status:** Accepted. One point is open: the VIES request and answer were written from the public
descriptions and tested against a stand-in; they have not been run against the live service (see
*Verification*).

**Context.** The VAT number of a customer was stored as typed. A typo went unnoticed until an invoice
or a reverse-charge check needed the number; the same company could be entered twice under different
spellings; and every new customer or supplier meant copying the name and address from the company's
website. Suppliers have `tax_id`, a free-text field that nothing looks at. Roadmap item D4.

**Decision.** Validate EU VAT numbers locally, warn about duplicates, and offer a VIES lookup that
pre-fills the form, never as a gate.

*Which numbers are checked.* Numbers of EU member states and `XI` (Northern Ireland), identified by
their two-letter prefix, or, typed without one, by the record's country (Greece: the number says `EL`,
the country says `GR`; both are understood). Anything else (a Swiss UID, a British or American number,
a number without a country that is in the EU) is stored as typed and never refused. Refusing it would
block a customer for no reason.

*What is checked* (`core::vat`, pure functions). The format of the country (`BE` ten digits starting 0 or
1, `NL` nine digits, `B`, two digits, and so on for all 27; for Spain the first and last character
may not both be digits) and, for 19 countries, the check digits:
AT BE DE DK EE EL FI FR HR HU IT LU NL PL PT RO SE SI SK. The other countries get the format test and
the answer says so (`format_ok`: the shape is right, the check digits are not verified here). A
rule is only here if it could be checked against an independent implementation.

*When it applies.* On create, and on update only when the number changed (compared after removing
spaces, dots and dashes). Numbers that are already in the database were entered before there was a
check; one of them being wrong must not stop anyone editing the phone number of that customer. The
same holds for the CSV import: a re-import of an export leaves unchanged numbers alone. A wrong number
is a validation error (422) that says whether the shape or the check digits are wrong.

*Storage is unchanged.* The number is stored as typed (trimmed). Normalising it to `BE0428759497`
would change what customers see on quotations and delivery notes, where Belgian numbers are written
`BE 0428.759.497`. Comparison uses a key instead.

*The check endpoints.* `GET /customers/vat-check` and `GET /suppliers/vat-check`
(`vat_number`, `country_code`, `exclude_id`, `lookup`) return the local verdict (`valid`, `format_ok`,
`bad_format`, `bad_checksum`, `not_checked`, `empty`), the number in VIES form, the records that
already carry it, and with `lookup=true` VIES's answer. The form calls it as the user types, so the
user sees "check digits do not match" before pressing save. Checking needs the read permission of the
module; the lookup makes the server call an outside service, so it needs the write permission.

*Duplicates.* Compared through `core.vat_key(text)`: letters and digits only, upper case, `GR` as `EL`,
with expression indexes. The typed number is reduced in Rust by `vat::key`, the same rule written
again, and a test holds the two together on awkward input (parentheses, non-ASCII letters, `GR`).
A number is looked for in every spelling it is accepted in: Belgian numbers with and without the
leading 0 (`BE0428759497`, `BE428759497`) and Greek ones with eight or nine digits. A record stored without a prefix matches when it is in the number's country.
Customers are shared master data (ADR 0003), so customers are compared across the whole table, which
is also what the customer list shows every company. Suppliers are compared within the company. Only a
warning: two branches of one company legitimately share a number. The record being edited is
excluded, and an inactive record is reported as inactive.

*VIES.* `core::vies` posts `{countryCode, vatNumber}` to `{VIES_URL}/check-vat-number` (default: the
Commission's public REST API; `VIES_URL=off` switches it off) and reads the answer leniently (`isValid`
or `valid`, optional `userError`), because the published descriptions of the REST API disagree about
the field names. The answer has four states: `valid` (with name and address where the member state
discloses them; `---` counts as not disclosed), `invalid` (VIES does not know the number),
`unavailable` (with a reason: `disabled`, `timeout`, `network`, `http_503`, or VIES's own code such as
`ms_unavailable`) and `not_applicable` (not an EU number, or the local check already failed: nothing
is sent). Every failure, including a timeout after eight seconds and an unreachable host, ends as
`unavailable`; the form then says to fill in the details by hand. Only the VAT number leaves the
installation: no credentials, no company data, no requester number. The server's `VIES_URL` is
configuration, so a test, a proxy or a changed path needs no code, and the application built for tests
has the lookup off unless a test passes a stand-in.

*Environments.* The lookup is an outbound call, and ADR 0048 gates every outbound integration by
`EnvironmentConfig::outbound_allowed()`: it works in a live environment only. In a test or tutorial
environment (a clone of live data, or a throwaway) it is off whatever `VIES_URL` says, answers
`unavailable` with reason `disabled`, and the start-up warning lists it with the other outbound side
effects. The local check and the duplicate warning work everywhere.

*Pre-filling.* VIES writes the address as lines: the street lines, then "postal code city". The server
splits it as well as it can (`1000 BRUXELLES`, `B-1000 BRUXELLES`, `1234 AB AMSTERDAM`; the two
letters after the postal code belong to it only for Dutch addresses, so `7100 LA LOUVIERE` keeps its
city) and returns the
parts together with the full text. The customer form fills the empty name, street, postal code and city
and leaves fields that already hold text alone; the supplier form fills an empty name (suppliers keep
no address). It says what it did ("name and address filled in", or that the member state does not
disclose them).

*Suppliers.* The roadmap said suppliers had no VAT field; they have `purchasing.suppliers.tax_id`
(free text, from ADR 0031). It is the VAT number: it is validated and compared like the customer's,
using the supplier's country. No column was added.

**Verification.**
- The check digits were compared with `python-stdnum` (an independent implementation, used only as
  an oracle and not copied) over about 43,000 generated numbers in 27 countries: no number it accepts
  is rejected here. Four countries are looser (IT, NL, RO, SK: they do not check province codes,
  birth-number dates or the like), never stricter. Cases the oracle exposed while this was written:
  the Belgian rule accepts check digits 00, 98 and 99; Slovak numbers include birth-number-based ones
  (leading 0 from the year 2000, and a check digit 0 when the remainder is 10); Romania accepts 13-digit
  personal codes. A fixed sample of the oracle's numbers is a unit test.
- The VIES client is tested against a local HTTP stand-in (valid with and without details, unknown,
  member state down, HTTP 503, timeout, connection refused) and the request body is asserted to be
  exactly the country code and the number.
- **Not verified:** the live VIES service. The build environment cannot reach it, and the public
  descriptions of the REST API are inconsistent (a POST to `check-vat-number` and a GET on
  `ms/{country}/vat/{number}` are both described; so are `isValid` and `valid`). One lookup against the
  real service should be done once before relying on the pre-fill; if the request shape is wrong, the
  symptom is `unavailable` with a reason, not a wrong answer, and `core::vies` is the one place to fix.

**Alternatives.**
- *Reject numbers VIES calls invalid.* VIES is down often enough, and several member states answer
  "valid" without a name or "unavailable" for a day; a gate would block customers for a reason that
  has nothing to do with them. The local check catches typos; VIES is for convenience.
- *Check digits for every country.* Wrong rules reject real customers, which is worse than accepting a
  typo. A country's rule is added when it can be checked against the oracle.
- *Normalise on save.* See above: it would change printed documents, and the comparison key makes it
  unnecessary.
- *A unique constraint on the number.* Legitimate duplicates exist (branches, a customer that is also a
  supplier's group), and legacy data has some.
- *The app calls VIES itself.* Every client (desktop, mobile, web) would then need to reach the
  Commission, and nothing could switch the call off or bound it in one place. The server is that
  place, and it is also where the write permission is enforced.

**Consequences.**
- Existing wrong numbers are not found or fixed by this change. They surface when someone changes the
  number, and `GET /customers/vat-check` shows them as `bad_checksum` in the form of the record.
- `GET /customers/vat-check` and the supplier equivalent are advice. Nothing relies on them having
  been called: the server checks again on save.
- The company's own VAT number (set in the setup wizard) is not validated; it is the same rule and
  can be added where companies are edited.
- The lookup is rate-limited only by VIES itself. A burst of lookups shows up as `unavailable`
  with VIES's `server_busy` or similar.
- `VIES_URL` is a new setting (`.env.example`).
