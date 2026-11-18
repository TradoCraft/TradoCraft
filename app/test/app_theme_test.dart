import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/core/theme/app_theme.dart';
import 'package:tradocraft_app/core/theme/theme_mode.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final (name, theme, brightness) in [
    ('light', AppTheme.light(), Brightness.light),
    ('dark', AppTheme.dark(), Brightness.dark),
  ]) {
    test(
      '$name theme has the right brightness, density and readable colours',
      () {
        final s = theme.colorScheme;
        expect(s.brightness, brightness);
        expect(theme.visualDensity, VisualDensity.compact);
        expect(theme.inputDecorationTheme.isDense, isTrue);
        expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
        expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      },
    );
  }

  group('themeModeProvider', () {
    ProviderContainer make(MemoryKvStore store) {
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('defaults to system', () {
      expect(make(MemoryKvStore()).read(themeModeProvider), ThemeMode.system);
    });

    test('persists the choice and restores it', () async {
      final store = MemoryKvStore();
      final c = make(store);
      await c.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(store.data['theme_mode'], 'dark');

      final c2 = make(store);
      c2.read(themeModeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(themeModeProvider), ThemeMode.dark);

      await c2.read(themeModeProvider.notifier).set(ThemeMode.system);
      expect(store.data.containsKey('theme_mode'), isFalse);
    });
  });
}
