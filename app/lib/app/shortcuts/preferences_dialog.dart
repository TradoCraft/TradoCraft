import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../api.dart';
import '../session.dart';
import 'actions.dart';
import 'platform.dart';

int _prefsEpoch = 0;

/// Loads the signed-in user's preferences from the backend and syncs [ShortcutBindings].
final userPreferencesProvider = FutureProvider<UserPreferences>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.isSignedIn) {
    ShortcutBindings.setOverrides(const {});
    return const UserPreferences();
  }
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final epoch = ++_prefsEpoch;
  final prefs = await ref.watch(apiProvider).core.getPreferences();
  if (disposed ||
      epoch != _prefsEpoch ||
      !identical(ref.read(sessionProvider), session)) {
    return prefs;
  }
  applyUserShortcutPreferences(prefs);
  return prefs;
});

/// Parses [prefs.shortcuts] and applies valid entries to [ShortcutBindings].
void applyUserShortcutPreferences(UserPreferences prefs) {
  final overrides = <ShortcutAction, ShortcutChord>{};
  for (final entry in (prefs.shortcuts ?? const {}).entries) {
    final action = ShortcutAction.values
        .where((a) => a.name == entry.key)
        .firstOrNull;
    if (action == null) continue;
    final key = ShortcutBindings.keyFromName(entry.value.key);
    final mod = ShortcutBindings.modFromName(entry.value.mod);
    if (key == null || mod == null) continue;
    if (action != ShortcutAction.cancel && mod == ChordMod.none) continue;
    overrides[action] = ShortcutChord(
      key,
      mod: mod,
      shift: entry.value.shift ?? false,
    );
  }
  ShortcutBindings.setOverrides(overrides);
}

/// Available draft autosave intervals in minutes (`0` disables autosave).
const autosaveIntervals = [0, 1, 2, 5, 10, 15, 30];

/// Effective draft autosave interval in minutes (user override, else company default, else 5).
final effectiveAutosaveMinutesProvider = Provider<int>((ref) {
  final userOverride = ref.watch(userPreferencesProvider).value?.autosaveMinutes;
  if (userOverride != null) return userOverride;
  return ref.watch(meProvider).value?.company.autosaveMinutes ?? 5;
});

/// Opens the User Preferences dialog (with the Shortcuts customization tab).
Future<void> showUserPreferences(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const UserPreferencesDialog(),
);

class UserPreferencesDialog extends ConsumerStatefulWidget {
  const UserPreferencesDialog({super.key});

  @override
  ConsumerState<UserPreferencesDialog> createState() =>
      _UserPreferencesDialogState();
}

class _UserPreferencesDialogState extends ConsumerState<UserPreferencesDialog> {
  static const _standard = [
    ShortcutAction.save,
    ShortcutAction.confirm,
    ShortcutAction.find,
    ShortcutAction.create,
    ShortcutAction.selectAll,
    ShortcutAction.palette,
    ShortcutAction.help,
  ];
  static const _navigation = [
    ShortcutAction.back,
    ShortcutAction.home,
    ShortcutAction.discard,
    ShortcutAction.addLine,
    ShortcutAction.nextPage,
    ShortcutAction.search,
  ];
  static const _domain = [
    ShortcutAction.newTodo,
    ShortcutAction.kbSearch,
    ShortcutAction.kbShare,
    ShortcutAction.ticketEscalate,
    ShortcutAction.ticketDelegate,
    ShortcutAction.ticketMerge,
    ShortcutAction.ticketSplit,
  ];

  bool _saving = false;
  String? _conflictError;

  Future<void> _saveOverrides(
    Map<ShortcutAction, ShortcutChord> next,
    UserPreferences loaded,
  ) async {
    setState(() {
      _saving = true;
      _conflictError = null;
    });
    final merged = Map<String, ShortcutBinding>.of(
      loaded.shortcuts ?? const {},
    );
    for (final a in ShortcutAction.values) {
      final chord = next[a];
      if (chord == null) {
        merged.remove(a.name);
      } else {
        if (a != ShortcutAction.cancel && chord.mod == ChordMod.none) continue;
        merged[a.name] = ShortcutBinding(
          key: ShortcutBindings.keyToName(chord.key),
          mod: ShortcutBindings.modToName(chord.mod),
          shift: chord.shift,
        );
      }
    }
    final payload = UserPreferences(
      autosaveMinutes: loaded.autosaveMinutes,
      shortcuts: merged,
    );
    final container = ProviderScope.containerOf(context, listen: false);
    final session = container.read(sessionProvider);
    final epoch = ++_prefsEpoch;
    final ok = await runAction(context, () async {
      final saved = await container
          .read(apiProvider)
          .core
          .putPreferences(body: payload);
      if (epoch == _prefsEpoch &&
          identical(container.read(sessionProvider), session) &&
          session.isSignedIn) {
        applyUserShortcutPreferences(saved);
      }
      container.invalidate(userPreferencesProvider);
    }, success: context.l10n.saved);
    if (mounted) {
      setState(() => _saving = false);
      if (ok) setState(() {});
    }
  }

  Future<void> _saveAutosave(int? minutes, UserPreferences loaded) async {
    setState(() => _saving = true);
    final payload = UserPreferences(
      autosaveMinutes: minutes,
      shortcuts: loaded.shortcuts,
    );
    final container = ProviderScope.containerOf(context, listen: false);
    await runAction(context, () async {
      await container.read(apiProvider).core.putPreferences(body: payload);
      container.invalidate(userPreferencesProvider);
    }, success: context.l10n.saved);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _editAction(
    ShortcutAction action,
    UserPreferences loaded,
  ) async {
    final picked = await showDialog<ShortcutChord>(
      context: context,
      builder: (_) => _KeyCaptureDialog(action: action),
    );
    if (picked == null || !mounted) return;
    final next = Map<ShortcutAction, ShortcutChord>.of(ShortcutBindings.all);
    if (ShortcutBindings.sameChord(picked, action.defaultChord())) {
      next.remove(action);
    } else {
      next[action] = picked;
    }
    await _saveOverrides(next, loaded);
  }

  Future<void> _resetAction(
    ShortcutAction action,
    UserPreferences loaded,
  ) async {
    final def = action.defaultChord();
    final conflict = ShortcutBindings.findConflict(
      action,
      def,
      web: kIsWeb,
    );
    if (conflict != null) {
      setState(() {
        _conflictError = context.l10n.shortcutConflict(
          conflict.label(context.l10n),
          _describeChord(def),
        );
      });
      return;
    }
    final next = Map<ShortcutAction, ShortcutChord>.of(ShortcutBindings.all)
      ..remove(action);
    await _saveOverrides(next, loaded);
  }

  Future<void> _resetAll(UserPreferences loaded) async {
    await _saveOverrides(const {}, loaded);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final prefsAsync = ref.watch(userPreferencesProvider);
    final loaded = prefsAsync.value;
    if (loaded != null) {
      applyUserShortcutPreferences(loaded);
    }
    final ready = loaded != null && !prefsAsync.isLoading && !prefsAsync.hasError;

    Widget section(String title, List<ShortcutAction> actions) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(a.label(l))),
                      if (ShortcutBindings.isCustomized(a)) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l.shortcutCustom,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                InkWell(
                  key: ValueKey('pref-shortcut-${a.name}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: !ready || _saving
                      ? null
                      : () => _editAction(a, loaded),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Center(
                        child: Text(
                          a.describe(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: !ready
                                ? theme.disabledColor
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('pref-reset-${a.name}'),
                  tooltip: l.shortcutReset,
                  icon: const Icon(AppIcons.refresh, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  onPressed:
                      !ready || _saving || !ShortcutBindings.isCustomized(a)
                      ? null
                      : () => _resetAction(a, loaded),
                ),
              ],
            ),
          ),
      ],
    );

    final companyAutosave =
        ref.watch(meProvider).value?.company.autosaveMinutes ?? 5;
    final userAutosave = loaded?.autosaveMinutes;

    return AlertDialog(
      title: Text(l.userPreferences),
      content: SizedBox(
        width: 520,
        height: 520,
        child: DefaultTabController(
          length: 1,
          child: Column(
            children: [
              DropdownButtonFormField<int?>(
                key: const ValueKey('user-autosave-minutes'),
                initialValue:
                    userAutosave == null ||
                        autosaveIntervals.contains(userAutosave)
                    ? userAutosave
                    : null,
                decoration: InputDecoration(
                  labelText: l.autosaveTitle,
                  helperText: l.autosaveUserHelp,
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      companyAutosave == 0
                          ? l.autosaveDefaultOff
                          : l.autosaveDefault(companyAutosave),
                    ),
                  ),
                  for (final m in autosaveIntervals)
                    DropdownMenuItem<int?>(
                      value: m,
                      child: Text(
                        m == 0 ? l.autosaveOff : l.autosaveMinutes(m),
                      ),
                    ),
                ],
                onChanged: !ready || _saving
                    ? null
                    : (v) => _saveAutosave(v, loaded),
              ),
              const SizedBox(height: 8),
              TabBar(tabs: [Tab(text: l.shortcutsTab)]),
              if (prefsAsync.isLoading) const LinearProgressIndicator(),
              if (prefsAsync.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          errorMessage(prefsAsync.error!),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('pref-retry'),
                        onPressed: () => ref.invalidate(userPreferencesProvider),
                        child: Text(l.retry),
                      ),
                    ],
                  ),
                ),
              if (_conflictError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _conflictError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          section(l.shortcutHelpStandard, _standard),
                          section(l.shortcutHelpNavigation, _navigation),
                          section(l.shortcutsTab, _domain),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pref-reset-all'),
          onPressed: !ready || _saving || ShortcutBindings.all.isEmpty
              ? null
              : () => _resetAll(loaded),
          child: Text(l.shortcutResetDefaults),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}

String _describeChord(ShortcutChord c) {
  final keyText = switch (c.key) {
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.enter => 'Enter',
    LogicalKeyboardKey.escape => 'Esc',
    _ => c.key.keyLabel.toUpperCase(),
  };
  return [
    switch (c.mod) {
      ChordMod.primary => primaryModifierLabel,
      ChordMod.standard => standardModifierLabel,
      ChordMod.none => null,
    },
    if (c.shift) 'Shift',
    keyText,
  ].whereType<String>().join('+');
}

class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({required this.action});
  final ShortcutAction action;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  static final _modifierKeys = {
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  ShortcutChord? _candidate;
  String? _error;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_modifierKeys.contains(e.logicalKey)) return KeyEventResult.handled;

    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed;
    final alt = kb.isAltPressed;
    final meta = kb.isMetaPressed;
    final shift = kb.isShiftPressed;

    // Allow unmodified Tab / Shift+Tab for standard focus traversal.
    if (e.logicalKey == LogicalKeyboardKey.tab && !ctrl && !alt && !meta) {
      return KeyEventResult.ignored;
    }

    ChordMod? mod;
    if (isMac) {
      if (meta && !ctrl && !alt) mod = ChordMod.standard;
      if (ctrl && !meta && !alt) mod = ChordMod.primary;
    } else {
      if (ctrl && !alt && !meta) mod = ChordMod.standard;
      if (alt && !ctrl && !meta) mod = ChordMod.primary;
    }

    if (mod == null) {
      setState(() {
        _candidate = null;
        _error = context.l10n.shortcutNeedsModifier;
      });
      return KeyEventResult.handled;
    }

    final candidate = ShortcutChord(e.logicalKey, mod: mod, shift: shift);
    final conflict = ShortcutBindings.findConflict(
      widget.action,
      candidate,
      web: kIsWeb,
    );
    setState(() {
      _candidate = candidate;
      _error = conflict == null
          ? null
          : context.l10n.shortcutConflict(
              conflict.label(context.l10n),
              _describeChord(candidate),
            );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.action.label(l)),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _candidate == null
                        ? l.shortcutPressKeys
                        : _describeChord(_candidate!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('capture-save'),
          onPressed: _candidate != null && _error == null
              ? () => Navigator.pop(context, _candidate)
              : null,
          child: Text(l.save),
        ),
      ],
    );
  }
}
