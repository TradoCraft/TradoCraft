# 0085 — Generic form view

**Status:** Accepted (shared UI framework, phase 3; builds on [ADR 0073](0073-concurrent-edit-protection.md),
[ADR 0077](0077-ui-theme-tokens-and-dark-mode.md), [ADR 0078](0078-repository-layer.md) and [ADR 0081](0081-generic-list-view.md))

**Context.** Lists share `EntityList`, but every record screen builds its own form: a header with a
back button, a row of buttons, the ADR 0073 conflict banner, a `_saving` flag, `_error`,
`TabScope.reportDirty` calls on every controller, a hand-written 409 branch and its own watcher on the
live channel. Customers and quotations repeat the same 150 lines with small differences, and each
new screen copies one of them. A link to another record is a `SearchPicker` that cannot be
validated, cleared or opened.

**Decision.** A small set of widgets in `app/lib/framework/form/`, adopted screen by screen.

1. **`RecordFormController<T>`** (a `ChangeNotifier`, not a provider). It holds the loaded record and
   its `version`, `dirty`, `busy`, `error`, the `formKey` and a `RecordNotice` (updated by someone,
   changed while offline, or save refused). It does not hold field values: screens keep their own
   controllers and build their own input type.
   - `track(TextEditingController)` marks the form dirty on a changed text, not on a cursor move.
     `markDirty` is ignored while busy, so values filled in by a reload or a lookup during a save are
     not edits.
   - `run(action)` is the one operation of the form: one at a time, error cleared first,
     `409 record_changed` becomes the save-refused notice with the edits kept, a thrown `String` is
     a client-side check shown as is, other errors go through `errorMessage`. A returned record is
     applied.
   - `save((expectedVersion) => …)` validates first and passes the loaded version; `reload(load)`
     applies the fresh record.
   - `apply(record)` clears dirty and the error, and clears a live notice unless the record is still
     older than the version that notice announced (the rule the quotation screen already had).
   - `watch(ref, entityType:, recordId:)` subscribes through `watchRecordChanges`; call it again once
     a new record has its id.
2. **`RecordFormView<T>`**, the page. A header (back, title, extras such as the to-do button, an
   unsaved-changes dot, a busy spinner), a control bar (actions left, status bar right, stacked under
   720 px), the conflict banner with Reload and dismiss, the error line, optional `beforeSheet`
   widgets, then the sheet: a bordered surface with smart buttons at the top right, the body and
   optional tabs. The sheet is the controller's `Form` and is locked (`lockRecordEditing`) while
   busy. Hidden tabs stay built (`Offstage`), so typed text survives a tab switch. It reports dirty to
   the enclosing workspace tab (ADR 0041) unless `reportDirty: false` (read-only).
3. **`FormStatusBar`**: the lifecycle as steps, the current one highlighted with `primaryContainer`,
   passed steps in `onSurfaceVariant`, later ones in `outline`. A current value off the path (rejected,
   cancelled) is appended. One Semantics label says "Status: …".
4. **`SmartButton`**: an outlined 48 px button with icon, label and an optional count, for related
   records (contacts, closures, rebates).
5. **`Many2OneField<T>`**, built on `SearchPicker` (which gained optional `validator`, `enabled` and
   `suffix`; its 36 existing uses are unchanged). The value only changes by picking, the clear button
   or erasing the text. Validation fails when required and empty, or when the text no longer matches
   the picked entry ("Choose an entry from the list"), so a half-typed name is never saved as the old
   link. `idOf` keeps the field stable across reloads, `onOpen` adds an open button, `readOnly` shows
   plain text.
6. **`RecordConflictNotice`** renders a controller's notice for forms that are not a page (dialogs).
7. Strings `form*` in all five languages; colours and spacing from `core/theme` tokens.

**Adoption.**

- **Customers (done).** `CustomerForm` uses the controller in both modes; the page (`screen: true`)
  is a `RecordFormView` with smart buttons for contacts, equipment, closures and rebates, and
  `CustomerScreen` passes its to-do button as a title extra. The dialog keeps its layout and uses
  `RecordConflictNotice`. The public API (`customer`, `readOnly`, `screen`, `onDone`, the
  `show…Form` helpers) is unchanged.
- **Quotations (next).** Header, actions, status bar (draft, sent, accepted; rejected off the path),
  banner and busy/error state move to the view; the customer picker becomes a `Many2OneField`. The
  line editor stays as it is.

**Consequences.**

- A new record screen gets dirty tracking, 409 handling and the live banner by constructing a
  controller and a view, instead of copying them.
- Screens still own their fields and input mapping; a field-descriptor layer (declaring fields
  instead of building widgets) is deliberately not part of this step.
- The customer page now shows the related-record buttons above the fields instead of in the
  button row, and the sheet is bordered.
- Deferred: counts on smart buttons (needs count endpoints), a one2many line editor, chatter beside
  the sheet, and moving orders and tickets onto the view.
