# 0051 — Material and Cupertino as packages

**Status:** Accepted

**Context.** Flutter 3.50 deprecates `package:flutter/material.dart`, `package:flutter/cupertino.dart`
and the Material/Cupertino localization delegates of `flutter_localizations` in favour of the
packages `material_ui` and `cupertino_ui` (same classes and names, only the library changes).
`flutter analyze` exits 1 on info-level issues, so with the deprecation the CI job failed on about
220 `deprecated_member_use` infos without any change to our code. The CI pin (3.47.9) existed to
keep new deprecations from breaking CI by themselves; it is raised together with the code change.

**Decision.** The app imports `package:material_ui/material_ui.dart`; `material_ui` and
`cupertino_ui` are direct dependencies (`flutter pub add material_ui cupertino_ui`). The imports
were rewritten with the official fix, run in `app/`:
`dart fix --apply --code=migrate_design_widgets`. `package:flutter/widgets.dart` is unaffected.

*Localizations.* The gen-l10n output (`AppLocalizations.localizationsDelegates`) still lists the
deprecated delegates from `flutter_localizations`, and `flutter gen-l10n` has no option to change
that. Every `MaterialApp` (app, portal, tests) therefore passes
`[AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]` instead. The generated
`lib/l10n/app_localizations*.dart` files are excluded from analysis (like the API client) and are
not edited by hand. `flutter_localizations` stays a dependency for gen-l10n.

*Pin policy.* CI pins `flutter-version` (now 3.50.0). It is raised only together with the code
changes a new release needs, never on its own.

*Compatibility bridge.* `MaterialUiCompatibilityBridge` (for `MaterialApp.builder`) is not used:
the full test suite passes without it, so go_router and the other dependencies work as they are.
Add it only if a dependency that still imports the old library fails with a missing
`MaterialLocalizations` or `Theme`, and remove it once that package migrates.
