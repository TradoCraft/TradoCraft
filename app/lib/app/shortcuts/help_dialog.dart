import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import 'actions.dart';
import 'platform.dart';

/// Opens the list of keyboard shortcuts (Ctrl+/): the standard chords, the navigation chords in
/// effect on this platform, and how the automatic button keys work.
Future<void> showShortcutHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ShortcutHelp(),
);

class _ShortcutHelp extends StatelessWidget {
  const _ShortcutHelp();

  static const _standard = [
    ShortcutAction.save,
    ShortcutAction.confirm,
    ShortcutAction.cancel,
    ShortcutAction.find,
    ShortcutAction.create,
    ShortcutAction.help,
  ];
  static const _navigation = [
    ShortcutAction.back,
    ShortcutAction.home,
    ShortcutAction.addLine,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget row(String name, String keys) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(
            keys,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(s, style: theme.textTheme.titleSmall),
    );
    final first = ShortcutAction.menu1.describe();
    final modifier = first.substring(0, first.lastIndexOf('1'));
    return AlertDialog(
      title: Text(l.shortcutHelp),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              heading(l.shortcutHelpStandard),
              for (final a in _standard) row(a.label(l), a.describe()),
              heading(l.shortcutHelpNavigation),
              for (final a in _navigation) row(a.label(l), a.describe()),
              row(
                l.shortcutMenuItem(1).replaceAll('1', 'n'),
                '${modifier}1 - 9',
              ),
              const SizedBox(height: 12),
              Text(l.shortcutHelpAltKeys(primaryModifierLabel)),
              const SizedBox(height: 8),
              Text(l.shortcutHelpEnter),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
