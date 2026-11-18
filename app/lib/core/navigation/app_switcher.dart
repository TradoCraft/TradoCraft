import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/module_icon.dart';
import '../theme/tokens.dart';
import 'app_groups.dart';

/// The launcher button of the application switcher: opens a grid of the permitted groups.
class AppSwitcherButton extends StatelessWidget {
  const AppSwitcherButton({
    super.key,
    required this.groups,
    required this.active,
    required this.onSelected,
  });

  final List<AppGroup> groups;
  final AppGroup? active;

  /// Called with the chosen group; the shell goes to its first permitted destination.
  final ValueChanged<AppGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.appSwitcherTooltip;
    return IconButton(
      key: const ValueKey('app-switcher'),
      tooltip: label,
      icon: const Icon(AppIcons.apps),
      onPressed: () async {
        final picked = await showDialog<AppGroup>(
          context: context,
          builder: (_) => _AppSwitcherDialog(groups: groups, active: active),
        );
        if (picked != null) onSelected(picked);
      },
    );
  }
}

class _AppSwitcherDialog extends StatelessWidget {
  const _AppSwitcherDialog({required this.groups, required this.active});

  final List<AppGroup> groups;
  final AppGroup? active;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.appSwitcherTitle),
      content: SizedBox(
        width: 420,
        child: Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final g in groups)
              _GroupTile(
                group: g,
                selected: g.id == active?.id,
                autofocus:
                    g.id == active?.id || (active == null && g == groups.first),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.autofocus,
  });

  final AppGroup group;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = group.label(context.l10n);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: Radii.large,
          child: InkWell(
            key: ValueKey('app-group-${group.id}'),
            autofocus: autofocus,
            borderRadius: Radii.large,
            onTap: () => Navigator.of(context).pop(group),
            child: SizedBox(
              width: 120,
              height: 104,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ModuleIcon(group.art, size: 40),
                  const SizedBox(height: Space.sm),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
