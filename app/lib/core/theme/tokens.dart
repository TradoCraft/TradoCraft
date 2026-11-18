import 'package:material_ui/material_ui.dart';

/// The seed colour of the brand; both colour schemes are derived from it.
const Color brandSeed = Color(0xFF2F5D62);

/// Light and dark colour schemes from the one seed. Surfaces stay neutral and the seed is the
/// only accent.
ColorScheme appColorScheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: brandSeed, brightness: brightness);

/// Spacing on a 4pt grid.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;

  static const BorderRadius small = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius medium = BorderRadius.all(Radius.circular(md));
  static const BorderRadius large = BorderRadius.all(Radius.circular(lg));
}

/// A compact business-app type scale (Material sizes, a step smaller for dense screens).
TextTheme appTextTheme(TextTheme base) => base.copyWith(
  headlineSmall: base.headlineSmall?.copyWith(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  ),
  titleLarge: base.titleLarge?.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  ),
  titleMedium: base.titleMedium?.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  ),
  titleSmall: base.titleSmall?.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  ),
  bodyLarge: base.bodyLarge?.copyWith(fontSize: 15),
  bodyMedium: base.bodyMedium?.copyWith(fontSize: 14),
  bodySmall: base.bodySmall?.copyWith(fontSize: 12),
  labelLarge: base.labelLarge?.copyWith(fontSize: 13),
  labelMedium: base.labelMedium?.copyWith(fontSize: 12),
  labelSmall: base.labelSmall?.copyWith(fontSize: 11),
);

/// The density of the app: compact, as before.
const VisualDensity appDensity = VisualDensity.compact;
