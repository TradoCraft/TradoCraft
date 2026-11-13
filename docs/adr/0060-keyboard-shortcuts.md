# 0060 — Keyboard shortcuts with hint badges

**Status:** Accepted (phase A, the core and the navigation shell; screens adopt it in phase B)

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
| C | Create (list create button, detail header) | B |
| S | Save | B |
| J | Discard: reset the form if it can, else the unsaved-changes prompt | B |
| Q | Focus the scope's search field | B |
| N | Load more on lists (the previous-page key P is not implemented: no list pages yet) | B |
| Shift+T | New to-do | D |
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
digits. Previous page (P) and the to-do key stay hidden until their features exist.
