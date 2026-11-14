# Import fixtures

Spreadsheet files that were NOT produced by our own writers, so the readers are tested against a
foreign producer (used by `crates/core/src/import/tests.rs`).

* `foreign.fods` is the hand-written source: a flat OpenDocument spreadsheet with two sheets
  (`Products`, `Second`), typed cells (text with leading zeros, a float 7.5 and 0.1 and 1234567.89,
  booleans, a date, formulas with cached values, two empty rows, a text with repeated spaces and a
  line break, a text starting with `=`).
* `foreign.xlsx` and `foreign.ods` were made from it with LibreOffice 24.2:

      soffice --headless --convert-to xlsx foreign.fods
      soffice --headless --convert-to ods foreign.fods

Regenerate them the same way if the source changes; the tests state exactly what they expect.
