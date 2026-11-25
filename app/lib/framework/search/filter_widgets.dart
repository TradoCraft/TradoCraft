/// Facet chips and the filter / favourites menu of a list (ADR 0083).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/shortcuts/actions.dart';
import '../../app/shortcuts/registry.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'favourite.dart';
import 'filter_model.dart';
import 'group_model.dart';

const _target = 48.0;

/// Width of a favourite row in the menu (apply button plus delete button).
const _favouriteWidth = 280.0;

/// The active filters as removable chips, one per filter.
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.defs,
    required this.selection,
    required this.onRemove,
    this.group,
    this.onRemoveGroup,
  });

  final List<FilterDef> defs;
  final FilterSelection selection;

  /// Called with the filter key whose chip was removed.
  final ValueChanged<String> onRemove;

  /// The active grouping (ADR 0089), shown as a chip after the filter chips; null: none.
  final GroupDef? group;
  final VoidCallback? onRemoveGroup;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final chips = selection.activeChips(defs, l.listOr);
    if (chips.isEmpty && group == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        for (final c in chips)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _target),
            child: Center(
              widthFactor: 1,
              child: InputChip(
                label: Text(c.text),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => onRemove(c.key),
                onDeleted: () => onRemove(c.key),
                deleteButtonTooltipMessage: l.listRemoveFilter(c.filterLabel),
              ),
            ),
          ),
        if (group != null)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _target),
            child: Center(
              widthFactor: 1,
              child: InputChip(
                label: Text(l.listGroupChip(group!.label)),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: onRemoveGroup,
                onDeleted: onRemoveGroup,
                deleteButtonTooltipMessage: l.listRemoveGrouping(group!.label),
              ),
            ),
          ),
      ],
    );
  }
}

/// The button that opens the menu: a checkable list of options per filter, "Clear filters" and,
/// when [favourites] is not null, the favourites section.
class FilterMenuButton extends StatelessWidget {
  const FilterMenuButton({
    super.key,
    required this.defs,
    required this.selection,
    required this.onToggle,
    required this.onClear,
    this.onToggleAll,
    this.favourites,
    this.onSaveFavourite,
    this.onRetryFavourites,
    this.onApplyFavourite,
    this.onDeleteFavourite,
    this.groupDefs = const [],
    this.groupBy,
    this.onGroupBy,
  });

  final List<FilterDef> defs;
  final FilterSelection selection;
  final void Function(String key, String value) onToggle;
  final VoidCallback onClear;
  final VoidCallback? onToggleAll;

  /// The saved favourites; null hides the favourites section.
  final List<Favourite>? favourites;

  /// Null disables saving (the stored favourites are not known yet).
  final VoidCallback? onSaveFavourite;

  /// Not null shows a retry entry: the stored favourites could not be read.
  final VoidCallback? onRetryFavourites;
  final ValueChanged<Favourite>? onApplyFavourite;
  final ValueChanged<Favourite>? onDeleteFavourite;

  /// The groupings on offer (ADR 0089); empty hides the "Group by" section.
  final List<GroupDef> groupDefs;

  /// The key of the active grouping; null: "None".
  final String? groupBy;
  final ValueChanged<String?>? onGroupBy;

  static final _itemStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(_target, _target)),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final n = selection.activeCount(defs) + (groupBy == null ? 0 : 1);
    final allSelected = selection.isAllSelected(defs);
    return MenuAnchor(
      menuChildren: [
        if (onToggleAll != null)
          _OptionalMenuShortcutScope(
            action: ShortcutAction.selectAll,
            onTrigger: onToggleAll!,
            child: MenuItemButton(
              key: const ValueKey('filter-toggle-all'),
              closeOnActivate: false,
              style: _itemStyle,
              leadingIcon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
              ),
              trailingIcon: Text(
                ShortcutAction.selectAll.describe(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: onToggleAll,
              child: Text(allSelected ? l.listDeselectAll : l.filterSelectAll),
            ),
          ),
        if (onToggleAll != null) const Divider(height: 1),
        for (final d in defs) ...[
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                d.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final o in d.options)
            CheckboxMenuButton(
              closeOnActivate: false,
              style: _itemStyle,
              value: selection.contains(d.key, o.$1),
              onChanged: (_) => onToggle(d.key, o.$1),
              child: Text(o.$2),
            ),
        ],
        if (groupDefs.isNotEmpty) ...[
          const Divider(height: 1),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l.listGroupBy,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          RadioMenuButton<String?>(
            closeOnActivate: false,
            style: _itemStyle,
            value: null,
            groupValue: groupBy,
            onChanged: (v) => onGroupBy?.call(v),
            child: Text(l.listGroupNone),
          ),
          for (final g in groupDefs)
            RadioMenuButton<String?>(
              closeOnActivate: false,
              style: _itemStyle,
              value: g.key,
              groupValue: groupBy,
              onChanged: (v) => onGroupBy?.call(v),
              child: Text(g.label),
            ),
        ],
        const Divider(height: 1),
        MenuItemButton(
          style: _itemStyle,
          onPressed: allSelected ? null : onClear,
          child: Text(l.listClearFilters),
        ),
        if (favourites != null) ...[
          const Divider(height: 1),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l.listFavourites,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (onRetryFavourites != null)
            MenuItemButton(
              style: _itemStyle,
              leadingIcon: const Icon(AppIcons.refresh),
              onPressed: onRetryFavourites,
              child: Text(l.retry),
            )
          else if (favourites!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l.listNoFavourites,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final f in favourites!)
            SizedBox(
              width: _favouriteWidth,
              child: Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) => Semantics(
                        label: l.listApplyFavourite(f.name),
                        excludeSemantics: true,
                        button: true,
                        onTap: () {
                          onApplyFavourite?.call(f);
                          MenuController.maybeOf(context)?.close();
                        },
                        child: MenuItemButton(
                          style: _itemStyle,
                          onPressed: () => onApplyFavourite?.call(f),
                          child: Text(f.name),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.listDeleteFavourite(f.name),
                    constraints: const BoxConstraints(
                      minWidth: _target,
                      minHeight: _target,
                    ),
                    icon: const Icon(AppIcons.delete),
                    onPressed: () => onDeleteFavourite?.call(f),
                  ),
                ],
              ),
            ),
          MenuItemButton(
            style: _itemStyle,
            leadingIcon: const Icon(AppIcons.bookmark),
            onPressed: onSaveFavourite,
            child: Text(l.listSaveFavourite),
          ),
        ],
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: l.listFilters,
        constraints: const BoxConstraints(
          minWidth: _target,
          minHeight: _target,
        ),
        icon: Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: const Icon(AppIcons.filterList),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Registers [action] on the dialog shortcut layer when a [ProviderScope] is present.
class _OptionalMenuShortcutScope extends StatelessWidget {
  const _OptionalMenuShortcutScope({
    required this.action,
    required this.onTrigger,
    required this.child,
  });

  final ShortcutAction action;
  final VoidCallback onTrigger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var hasScope = false;
    try {
      ProviderScope.containerOf(context, listen: false);
      hasScope = true;
    } catch (_) {}
    if (!hasScope) return child;
    return ShortcutScope(
      layer: ShortcutLayer.dialog,
      actions: {action: onTrigger},
      child: child,
    );
  }
}

/// Asks for the name of a new favourite; null when cancelled.
Future<String?> askFavouriteName(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _NameDialog());

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.listSaveFavourite),
      content: TextField(
        controller: _c,
        autofocus: true,
        inputFormatters: [
          LengthLimitingTextInputFormatter(Favourite.maxNameLength),
        ],
        decoration: InputDecoration(labelText: l.listFavouriteName),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _c.text.trim().isEmpty ? null : _submit,
          child: Text(l.save),
        ),
      ],
    );
  }
}
