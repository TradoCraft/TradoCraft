import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// The light and dark theme of the app, built from the tokens in `tokens.dart`.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = appColorScheme(brightness);
    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: appDensity,
    );
    return base.copyWith(
      textTheme: appTextTheme(base.textTheme),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.all(Space.xs),
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.medium,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        horizontalMargin: Space.lg,
        columnSpacing: Space.xl,
        dividerThickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: Radii.small,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
      ),
    );
  }
}
