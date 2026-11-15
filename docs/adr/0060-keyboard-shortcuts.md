# 0060 — Keyboard shortcuts with hint badges

**Status:** Accepted (phase A, the core and the navigation shell; addendum 2026-11: standard chords and automatic keys)

**Context.** People who work in several business applications expect the same few keys everywhere: a letter with
Alt to create, save or go back, digits for the menu, a palette on Ctrl/Cmd+K. Our app had one global key handler
(zoom, `app/lib/app/zoom.dart`) and nothing else: no `Shortcuts`/`Actions`, about 20 hand-rolled back arrows,
about 40 Save and 40 New buttons with no common hook. We mirror **common business-app shortcuts** so users can
move between products without relearning; we copy the scheme, not any product.

**Decision.** One registry of scoped handlers, one global key listener, and a corner badge that names the key
while the modifier is held.

*Modifier.* Alt; on macOS Ctrl (Option types special characters, Cmd belongs to the system and the browser).
`isMac` reads `defaultTargetPlatform`, so tests switch it with `debugDefaultTargetPlatformOverride`.
Command palette and help always use Ctrl or Cmd.

*Key table* (`ShortcutAction` in `app/lib/app/shortcuts/actions.dart`):

| Key | Action | Phase |
| --- | --- | --- |
| B | Back: pops the active tab's route; offered only when the tab has a screen to go back to | A |
| H | Home: the first permitted menu entry (`go(0)`: shows the main area, then its path) | A |
| 1-9 | Menu entry n of the permission-filtered navigation (web: Alt+Shift+1-9) | A |
| Ctrl+N | Create (web: Alt+C; see the addendum) | B |
| Ctrl+S | Save (was Alt+S; see the addendum) | B |
| J | Discard: reset the form if it can, else the unsaved-changes prompt | B |
| Q | Focus the scope's search field | B |
| N | Load more on lists (the previous-page key P is not implemented: no list pages yet) | B |
| Shift+T | New to-do (live with to-do PR 2, ADR 0061; shell layer, needs `todo.use`) | D |
| F / Shift+S | Search / share a knowledge-base article | D |
| Ctrl/Cmd+K | Command palette | C |
| Ctrl/Cmd+/ | Shortcut help | C |

Phase A defines every action (so later phases only register handlers) but wires B, H and 1-9.

*Scoping.* `ShortcutScope(actions: {...}, layer:, child:)` registers a map action to callback in the
`ShortcutStack` (provider `shortcutRegistryProvider`) while it is mounted and visible. Resolution, top first:
**dialog** (`ShortcutLayer.dialog`, modal: what it does not handle is not passed down), then **page** (the main
area or the active tab; newest first), then **shell**. A null or missing entry means "not available now". Only the
visible screen takes part: inside the workspace a scope registers only while its tab is active
(`TabScope.activeOf`), and the main area registers only while no tab is focused (`ShortcutActivity`).
Dialogs sit above the shell overlay. `ModalShortcutObserver` makes **every**
popup route modal without touching the call sites. There is one observer per navigator: the root router, the
shell route and each workspace tab's navigator, because bottom sheets and menus (`useRootNavigator: false`) land
on the nearest navigator, not the root. Each open popup route holds its own scope on the shared stack, so
shortcuts stay blocked until every popup on any navigator is closed (a tab's observer also releases its scopes
when the tab is closed). While a dialog, bottom sheet, date picker or popup menu is open
it keeps an empty dialog-layer scope in the stack, so menu digits, Home, Back and Save are not reached. A dialog
that wants keys of its own (Save, Discard) adds a `ShortcutScope(layer: ShortcutLayer.dialog, ...)`, which is
newer and wins; a dialog-layer scope registers regardless of tab visibility. Phase B still has to add those
Save/Discard scopes (shared dialog scaffold in `shared/actions.dart`). Remaining gap: a popup pushed on a
navigator that has no observer (a new nested `Navigator` added later) must get one.

*Listener.* `ShortcutsHost` (in `MaterialApp.builder` next to `ZoomShell`) uses `HardwareKeyboard.addHandler`.
It looks at key-down only, and returns "handled" only when a handler ran, so every other key (typing, Tab, zoom)
passes through. It ignores events while an input method is composing text, and clears `modifierHeld` when the
app lifecycle changes (window blur), so badges never stick.

*Hints.* `KeyHint(action:, child:)` draws a small badge (the letter or digit; Shift chords with an arrow) on the
corner of its child while `modifierHeld` and a handler for that action is enabled in the current scope. A
`Stack(fit: passthrough, clipBehavior: none)`: layout never changes. The badge is `IgnorePointer` and
`ExcludeSemantics`; screen readers get the shortcut as a semantic hint instead. It is a sibling of
`TutorialTarget` and is not coupled to it. Do not wrap an `Expanded`/`Positioned` directly. The navigation rail
and bar carry badges for the first nine destinations.

*Web.* The same keys everywhere, except the menu digits: browsers take Alt+digit (Firefox on Linux switches
tabs), so on the web they are **Alt+Shift+digit** (`ShortcutAction.webOverride`). The digits match by key
position as well as by character, because Shift changes the character. Remap other keys only where the browser
test below shows the browser wins.

*Hazards.*
- Alt+1-9 in Firefox on Linux (tab switching): hence Alt+Shift on the web.
- Alt+F, Alt+H, Alt+B, Alt+S open or are bound by browser menus in some browsers (File, History, Bookmarks):
  verify per browser (table below).
- macOS text fields use emacs-style Ctrl keys (Ctrl+B/F/N/P/H/K/A/E/D/T/O). While a text field has the focus our
  Ctrl chords on those letters are not taken; digits, S, C, J, Q still are. Cmd+K is fine.
- A chord with an extra modifier (Ctrl+Alt, AltGr) is not ours; a held key repeats and is swallowed, not re-run.
- A modifier plus a letter never types a character: a handled key is consumed, an unhandled one is passed on
  and the text input gets no text from Alt/Ctrl chords.

*How screens adopt it (phase B).* A list wraps its body in `ShortcutScope(actions: {create: ..., search: ...,
nextPage: ...})` and puts `KeyHint(action: ShortcutAction.create, child: button)` inside its action row (around
the button, not around an `Expanded`). Dialogs use a shared scaffold in `shared/actions.dart` that pushes a
`ShortcutLayer.dialog` scope with Save and Discard. Detail headers register Save, Discard (and Back is already
registered by the tab). Existing `ValueKey`s stay.

**Browser results (Firefox, Playwright, `e2e/tests/shortcuts.spec.ts`).**

| Chord | Result in headless Firefox on Linux (Playwright 1.63) |
| --- | --- |
| Alt+Shift+2, Alt+Shift+1 (menu entries 2 and 1) | Reach the app; the menu navigates. |
| Alt+H (Home) | Reaches the app; navigates to the first entry. |
| Alt+2 (plain digit) | Ignored by the app, as intended (the browser's tab key). Headless Firefox has no tabs to switch, so the browser side is not observable. |
| Alt+B, Alt+S, Alt+F (and Alt+H opening the History menu) | Not observable headless: there is no menu bar. To verify by hand in a headed Firefox on Linux, Windows and macOS (Ctrl) before phase B registers Create/Save/Search; remap where the browser wins. |

**Consequences.** Every screen can offer shortcuts by wrapping itself in a scope; the hint badges stay correct
because they read the same registry the key handler uses. The web chords differ from desktop only for the menu
digits. Previous page (P) stays hidden until its feature exists. New to-do (Shift+T) is live: the shell scope offers it when the
user holds `todo.use` (the server drops the permission when the module is off), the dialog it opens is modal for
shortcuts, and the account menu offers the same action so it never depends on the keyboard.

## Addendum (2026-11): standard Ctrl chords, automatic Alt keys, data-entry keys

**Why.** Phase A defined Save, Create, Search, Discard and Load more but wired none of them: only Back, Home and the
menu digits had handlers, and the badge existed in two places while the app has about 840 buttons and 316 text
fields. Users on Windows and Linux also expect Ctrl+S to save, not Alt+S. Editing every call site was not an
option, so the keys now work from the widget tree itself.

**Two kinds of chord.** The *standard chords* use Ctrl (Cmd on macOS) and mean the same on every screen. The *fixed
navigation chords* stay on Alt (Ctrl on macOS): Back B, Home H, Discard J, Next page N, Search Q, Search articles F,
Add line L, the menu digits (web: Alt+Shift+digit), Shift+T and Shift+S. `ShortcutChord.mod` says which
(`ChordMod.primary`, `standard`, `none`); the standard modifier is `standardModifierLabel` ("Ctrl", "Cmd").

| Chord | Action | What it does |
| --- | --- | --- |
| Ctrl+S | `save` | The registered save handler of the topmost layer, else presses its Save button. |
| Ctrl+Enter | `confirm` | A dialog: its Save button, else its last `FilledButton`, else a confirming word. A page: its Save button only. |
| Esc | `cancel` | The registered cancel handler; else a dialog's Cancel/Close button, else the dialog's own pop (so a `PopScope` can still veto); on a page its Cancel/Close button. A workspace tab registers a handler: unsaved edits (`TabScope.reportDirty`) raise the existing unsaved-changes prompt, otherwise one screen back, at the first screen the tab closes. |
| Ctrl+F | `find` | The registered handler (also for Alt+Q), else focuses the first search field of the layer (hint or label "Search", or a search icon). |
| Ctrl+N | `create` | Presses the "New" button of the layer. On the web Ctrl+N belongs to the browser, so Alt+C is used (`webOverride`). |
| Alt+L | `addLine` | Quotation: puts the cursor in the add-product picker (draft only). |
| Ctrl+K, Ctrl+/ | palette, help | Help lists the chords in effect (`help_dialog.dart`). The palette is still not built. |

A registered `ShortcutScope` handler always wins over the generic search; the dialog layer still stops the search, so
a button below an open dialog is never reached.

**Which labels count (generic button search).** `classifyLabel` in `button_scan.dart` compares the normalized label
(lower case, accents folded, punctuation dropped) with the app's own strings, in the language of the user. To teach
the keys a new label, add the l10n string to that function; no screen changes.

| Role | Labels (l10n keys) |
| --- | --- |
| Save | `save`, `saveChanges`, `saveDraft`, and anything starting with the word `save` |
| Cancel | `cancel`, `close` |
| Confirm | `confirm`, `ok`, `yes`, `apply`, `send`, `create`, `delete`, `discardChanges` |
| Create | `newItem` and anything starting with it ("New customer") |

**Automatic Alt keys.** While Alt (Ctrl on macOS) is held, every enabled button of the topmost layer shows a letter
badge; pressing the letter presses the button. `scanTree` walks the element tree once when the modifier goes down
(the result is cached while it is held and recomputed when a popup comes or goes, after a press, and when the
cached elements leave the tree). It reads `ButtonStyleButton` (Text, Filled, Elevated, Outlined, also `.icon`) and
`IconButton`. The label is the `Text` inside, else the tooltip, the nearest `Tooltip` or `Semantics` label, or the
icon's semantic label; a button without a label gets no key. The topmost layer is the current popup route (dialog,
sheet) if there is one, else the current routes of the visible page; hidden tabs, off-stage parts and covered routes
are skipped, as are disabled buttons and buttons that already sit in a `KeyHint`.
Letters (`assignLetters`): the first letter of the first word still free in the layer, else the next free letter of
the label, else the next free letter; accents folded (é to e), a-z only. Save and Cancel choose first, so they get
S and C wherever they sit. Never assigned: the letters of the Alt chords in effect (B, H, J, N, Q, F, L; C too on the
web, where Create is Alt+C). On desktop C is free, so Cancel gets C. Badges are drawn by `ShortcutsHost` in a layer
above the app at the global rectangles of the buttons (no layout change, `IgnorePointer`, `ExcludeSemantics`) and
follow scrolling. While Ctrl (Cmd) is held the standard badges show instead: S, Enter, Esc, N on the buttons those
chords press, F on the search field. A button that shows a `KeyHint` is not given a second badge.
To give a button an explicit key: wrap it in `KeyHint(action:)` and register that action in a `ShortcutScope`
(it wins over the automatic letter), or register `save`/`confirm`/`cancel`/`find`/`create` in a `ShortcutScope`.

**Data entry** (all in `ShortcutsHost`, no screen changes).
- *Enter* in a single-line text field with no `onSubmitted`/`onEditingComplete` (and no search/send action) moves
  to the next focus like Tab, Shift+Enter back. Fields that submit, multi-line fields and buttons are untouched.
  It is taken in the HardwareKeyboard handler because the app's default shortcuts swallow Enter before the root
  focus node sees it. The last field leads to the buttons (Tab order).
- *Autofocus*: when a dialog or sheet opens, the cursor goes to its first editable field unless a field has
  `autofocus` or one already has the focus. Chosen at route level (the registry already tells when a popup opens)
  because wrapping 800 `AlertDialog`s was not an option. Forms on pages are not covered (a page has no moment of
  "opening" that is not a route change); phase 2 can add an opt-in helper to the main forms.
- *Select all*: a field with a number keyboard that gets the focus from the keyboard (Tab, Enter) selects its whole
  content so typing replaces it; a click keeps the caret where it landed.
- *Esc* is processed after the focused widget (a root focus-node fallback), so popup menus, autocompletes and
  dropdowns keep their own Esc.
- *Lists and tables*: `GridKeyNav` (`shared/grid_key_nav.dart`) wraps a region. Up/Down move to the same column of the
  next/previous row, Ctrl+Up/Down to the first/last row, Ctrl+Left/Right to the first/last field of the row; Home/End
  jump to the first/last row when a row (not a text field) has the focus, and stay caret keys inside a text field
  (Excel does the same). Rows are found by position, so any layout works. `EntityList` uses it for its rows (Down from
  the search field enters, Enter opens through the row's `InkWell`, a lazy list scrolls to unbuilt rows); the
  quotation lines table uses it for its fields.

**Guards kept.** Key repeat is swallowed, never re-run; modifier state is cleared when the app lifecycle changes
and no chord counts until the next modifier event (a key-up that went to another window); nothing fires while an
input method is composing; on macOS the emacs Ctrl letters in a text field stay text editing.

**Web.** Browsers keep Ctrl+N, Ctrl+T, Ctrl+W: Create is Alt+C there and Ctrl+N shows no badge. Ctrl+S is handled only
when a Save target exists; a handled key is `preventDefault`ed by the engine, an unhandled one is left to the
browser (its own "save page"). **This was not checked in a real browser**: tests run without a browser, so whether
Chrome, Firefox and Safari let Ctrl+S, Ctrl+F (left to the browser's find-in-page when the page has no search field),
Alt+letter and Alt+L reach the page must be verified by hand, as for the Alt chords above. Alt+letter
auto keys are the most exposed: any browser menu mnemonic that wins (Alt+F, Alt+E, Alt+V, Alt+H) would swallow it;
F and H are already reserved.

**Phase 2 (not done).** Discard (J), Load more (N) and the Alt+Q search have no handler of their own (Q now also
works through Ctrl+F). The command palette does not exist. Forms on pages do not autofocus their first field. Every
screen whose Save/Cancel buttons are not named with the l10n words above, icon-only buttons without tooltip, buttons
that are not Material buttons (`InkWell`, `PopupMenuButton`, `Checkbox`, `FloatingActionButton`), and tables other
than the two above need explicit wiring or a `GridKeyNav`.
