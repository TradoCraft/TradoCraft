# Frontend UX & Ease-of-Use Roadmap

> **For agentic workers:** Implement one phase at a time in its own dedicated worktree/PR, verifying each with `flutter analyze` and `flutter test` before moving to the next.

**Goal:** Improve navigation discoverability, mobile/narrow responsiveness, list ergonomics, role-aware landing, and non-blocking form editing across the TradoCraft Flutter app (`app/lib/`).

---

## Phase 1: `EntityList` Search Clear & Responsive Header (Quick Win)

**Target:** `app/lib/shared/entity_list.dart`

- [x] **1.1 Search Clear Button:** Add a `suffixIcon` clear (`IconButton(icon: Icon(AppIcons.close))`) to the search `TextField` when `_search.text.isNotEmpty`, resetting the controller and triggering `_onSearchChanged('')`.
- [x] **1.2 Wrapping / Overflow-Safe Header:** Replace the rigid `Row` in `_body` (`widget.title`, `Spacer`, `...widget.actions`, `_createButton`) with a responsive `Wrap` (or collapse secondary `actions` into an overflow `PopupMenuButton` below `700px` width) so narrow windows never clip titles or buttons.
- [x] **1.3 Tests:** Add widget tests in `app/test/` verifying clear-search behavior and narrow-viewport header layout without overflow.

---

## Phase 2: Navigation Discoverability & Top-Bar Search

**Targets:** `app/lib/core/navigation/app_switcher.dart`, `app/lib/app/shell.dart`, `app/lib/core/navigation/breadcrumbs.dart`, `app/lib/core/navigation/global_search.dart`

- [x] **2.1 Active Group Indicator:** Show the active `AppGroup` label/chip alongside or inside `AppSwitcherButton` so users always see which suite (`Sales`, `Service`, `Operations`, `Master data`, `Back office`, `Insight`) they are in.
- [x] **2.2 Prominent Global Search Trigger:** Add a clickable search pill/button (`Search… Ctrl+K`) in `SectionBreadcrumbs` / the top header bar on wide screens (in addition to the rail button) so cross-module jumping is immediately discoverable.
- [x] **2.3 Tests:** Update/add shell and navigation widget tests verifying the active group indicator and top-bar search trigger, and ensure tutorial `TutorialTarget` keys remain intact.

---

## Phase 3: Narrow-Screen `NavigationBar` Overflow Fix

**Targets:** `app/lib/app/shell.dart`

- [x] **3.1 Cap Bottom Destinations:** When `!wide` and `shownIdx.length > 5` (e.g., `service` and `sales` with 6 destinations), show the top 4 destinations plus a `More` destination that opens a clean modal bottom sheet listing the remaining destinations in the active group (and a quick link to switch groups).
- [x] **3.2 Tests:** Add narrow-viewport (`400x800`) widget tests confirming `NavigationBar` renders ≤ 5 items and all destinations remain reachable via `More`.

---

## Phase 4: Role-Aware Home / Today Landing View

**Targets:** `app/lib/app/router.dart`, `app/lib/app/shell.dart`, `app/lib/features/todo/` (and/or new `app/lib/features/home/`)

- [x] **4.1 Today Overview Screen:** Create a lightweight `/home` dashboard surfacing permission-filtered cards: open to-dos (`/todo`), assigned helpdesk tickets, pending quotation/PO approvals, and recent workspace tabs.
- [x] **4.2 Navigation Integration:** Add `/home` as the default landing route (or pinned top rail item) while preserving deep links and tutorial entry points.
- [x] **4.3 Tests:** Add widget tests verifying permission-gated card visibility and navigation from home cards into detail tabs.

---

## Phase 5: Non-Blocking Editing for Complex Forms

**Targets:** `app/lib/features/products/product_form.dart` (and similar heavy modal forms)

- [x] **5.1 Tab / Side-Panel Mode:** Support opening `ProductForm` (with media uploads, pricing flags, VAT, tracking) in a workspace tab or wide side-sheet instead of a blocking modal `AlertDialog`, so users can reference other open tabs mid-creation.
- [x] **5.2 Unsaved Changes Guard:** Hook into `WorkspaceNotifier`'s dirty-tab tracking so closing a tab with unsaved form edits prompts for confirmation.
- [x] **5.3 Tests:** Add widget tests for tab/panel creation, dirty-state prompt, and tutorial `product-form-save` target compatibility.
