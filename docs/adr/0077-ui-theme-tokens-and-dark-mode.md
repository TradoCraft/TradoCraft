# 0077 — UI theme tokens and dark mode

**Status:** Accepted (builds on [ADR 0051](0051-material-and-cupertino-as-packages.md))

**Context.** The app's theme was one inline `ThemeData` in `main.dart` (seed colour, compact
density, outlined inputs). There was no dark theme, no shared spacing, radius or type values, and no
way for a user to choose light or dark. A shared UI framework needs one place for these values.

**Decision.**

1. **Tokens in `app/lib/core/theme/`.** `tokens.dart` holds the brand seed `0xFF2F5D62`, the
   colour scheme per brightness (`ColorScheme.fromSeed`, neutral surfaces, the seed as the one
   accent), a 4pt spacing scale (`Space`), radii (`Radii`), a compact type scale and the density
   (`VisualDensity.compact`). Widgets take values from the tokens or from `Theme.of(context)`, not
   from literals.
2. **`AppTheme.light()` and `AppTheme.dark()`** return the `ThemeData`, keeping outlined, dense
   inputs and adding consistent card, divider, data table, app bar and tooltip themes.
3. **`themeModeProvider`** (Riverpod `Notifier<ThemeMode>`) defaults to the system mode and stores a
   chosen light or dark in the `kvStoreProvider` under `theme_mode` (so it is per profile); choosing
   system removes the key. The user menu in the shell has a System/Light/Dark entry.
   `main.dart` passes `theme`, `darkTheme` and `themeMode` to `MaterialApp.router`.
4. **Tests.** Unit tests check both themes for brightness, density and a contrast of at least 4.5:1
   for onSurface on surface and onPrimary on primary, and check that the provider persists. A
   golden harness (`test/golden/`) renders a small sampler under both themes at a fixed size.
   Goldens are generated on Linux CI with the default test font; regenerate them there.
5. **Not in this step.** Existing screens that read `theme.brightness` keep doing so; they already
   follow the theme. The separate customer portal keeps its own theme for now.

**Consequences.** Dark mode is available everywhere the theme is used, and later components share
one set of tokens. Hard-coded colours in older screens may look wrong in dark mode and are fixed as
those screens are moved onto the framework.
