import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/field/offline/kv_store.dart';

/// The chosen theme mode; system until the user picks light or dark.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  /// Set once a mode was chosen, so a slower read of the stored one cannot overwrite it.
  bool _changed = false;

  @override
  ThemeMode build() {
    _changed = false;
    ref.read(kvStoreProvider).get(_key).then((name) {
      if (_changed || !ref.mounted) return;
      for (final m in ThemeMode.values) {
        if (m.name == name) state = m;
      }
    }, onError: (Object _) {});
    return ThemeMode.system;
  }

  /// Chooses the mode and stores it.
  Future<void> set(ThemeMode mode) async {
    _changed = true;
    state = mode;
    final store = ref.read(kvStoreProvider);
    if (mode == ThemeMode.system) {
      await store.remove(_key);
    } else {
      await store.set(_key, mode.name);
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
