# 0045 — Story-mission tutorial

**Status:** Accepted

**Context.** New users learn the app by being told what to click. We want a guided tutorial that
runs on the real screens, walks through a believable business story (components, a finished
product, suppliers, purchase orders, quotations, ...) and does not need a separate demo mode. It
creates records, so it must never run against live data (ADR 0043). It has to survive changes
to the screens, work in five languages, and be extended chapter by chapter as new screens land.

**Decision.** A client-only feature in `app/lib/features/tutorial/`; the backend is not involved.

*Story missions.* A `Mission` is a chapter made of `Step`s. Each step has a narrator text
(title, body, optional hint), an optional spotlight target, an optional route to navigate to and
one completion rule: `onApi` (a successful call of a method and path, optionally checked by a
predicate on the JSON answer), `onRoute`, `manualNext`, or an `action` button that runs code. Values
a step needs later (the id of a product just created) are captured from API answers into a
`MissionContext` and substituted in routes and probe paths (`/products/{cartId}`).

*Where it runs.* Only in environments of kind `test` or `tutorial`, never `live`. On a live
environment the chapter map shows a refusal and offers to switch to another environment or to add
one (the existing switcher dialogs). Starting is refused in the controller too, and a switch to a
live environment stops a running mission.

*Completion detection.* A Dio interceptor, added to the client built by `dioProvider`, emits an
`ApiEvent` (method, path, status, parsed JSON) on a broadcast stream, but only while a mission is
running; otherwise nothing is parsed or kept. A step may carry an idempotent GET `probe` that
tells whether the work is already done (the product exists, the BOM has three lines), so resuming
or replaying a chapter skips what is done and a tutorial interrupted by a reload heals itself.
Missions are tested against `FakeHttp`, so a changed API path breaks a test, not a user.

*Spotlight without a package.* `TutorialTarget(id, child)` registers a `GlobalKey` in a registry.
`TutorialHost`, mounted in `MaterialApp.builder` (above the navigator, so it also covers dialogs),
paints a scrim with a rounded cut-out (`CustomPainter`, even-odd fill) over the target's rectangle.
The scrim never blocks input, so dialogs and drop-down menus keep working. When the target is
missing, covered or off-screen the card falls back to text and a "Take me there" button. The
docked narrator card has Next, Back, Skip step and Pause, is readable in light and dark, reachable
by keyboard, announced to screen readers, and has no motion beyond what the platform allows.

*Progress.* Stored client-side in the device `KvStore`, keyed by environment id and user (a
chapter done in one environment is not done in another). Unreadable data is ignored. A restart
never resumes by itself; the user presses Resume. No server table.

*Strings.* Every mission text is an ARB key `tut<Chapter><Step>{Title,Body,Hint}` in all five
languages (en, nl, fr, de, es). A test derives the keys from the missions and fails when one is
missing in a locale.

*Roles.* The tutorial user is the admin, who plays every role in turn; the narrator names the
"hat" worn in each chapter (product manager, purchaser, salesperson). There is no role switching.

*Chapters.* Chapter 0 (welcome: banner, tabs, tutorial controls) and chapter 1 (components, a
finished product and its bill of materials) ship with the engine. Later chapters are added as
the screens they teach exist (suppliers, purchase orders, supplier invoices, price zones, the
simulated e-mail, quotations, production); a chapter is a list in `missions.dart`, its strings
and, where needed, `TutorialTarget` wrappers.

**Consequences.** Missions depend on API paths and a few widget ids; both are covered by tests.
The scrim does not force the user onto the highlighted control, which is deliberate. Progress is
per device, so a second device starts the tutorial again (its probes skip finished work).
