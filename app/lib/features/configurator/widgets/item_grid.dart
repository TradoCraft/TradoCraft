import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../definition.dart';
import '../runner_state.dart';
import 'field_widgets.dart';

/// One item table as an editable grid: a row per item, a column per field and shown computed
/// value. Rows are grouped by the table's group field; rows can be added (to a group),
/// duplicated and deleted, and a whole column can be set from its header.
class ItemGrid extends StatelessWidget {
  const ItemGrid({super.key, required this.view, required this.table});

  final RunnerView view;
  final CfgItemTable table;

  static const _numberWidth = 60.0;
  static const _actionsWidth = 104.0;

  double _width(CfgEntry e) {
    final base = switch (e) {
      CfgField(type: CfgFieldType.boolean) => 110.0,
      CfgField(type: CfgFieldType.text || CfgFieldType.product) => 150.0,
      CfgField(type: CfgFieldType.choice) => 150.0,
      CfgComputed(overridable: true) => 170.0,
      _ => 120.0,
    };
    return base * e.width.clamp(1, 3);
  }

  String _groupOf(int row) {
    final r = view.index.row(table.name, row);
    if (r != null) return r.group;
    final gf = table.groupField;
    if (gf == null) return '';
    final f = table.entry(gf);
    final raw =
        view.inputs.rows(table.name)[row][gf] ??
        (f is CfgField ? f.defaultValue : null);
    return displayValue(raw).trim();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final columns = byLayoutOrder([
      ...table.fields,
      ...table.computed.where((c) => c.show),
    ]);
    final rows = view.inputs.rows(table.name);
    final grouped = table.groupField != null;
    final groups = <String, List<int>>{};
    for (var i = 0; i < rows.length; i++) {
      (groups[grouped ? _groupOf(i) : ''] ??= []).add(i);
    }
    final width =
        _numberWidth +
        _actionsWidth +
        columns.fold(0.0, (s, c) => s + _width(c));
    final border = BorderSide(color: theme.dividerColor);
    final full = table.maxRows != null && rows.length >= table.maxRows!;
    final itemLabel = table.labelIn(lang);

    Widget cell(double w, Widget child, {Color? color}) => Container(
      width: w,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      color: color,
      child: child,
    );

    final header = Container(
      decoration: BoxDecoration(border: Border(bottom: border)),
      child: Row(
        children: [
          cell(_numberWidth, Text('#', style: theme.textTheme.labelMedium)),
          for (final c in columns)
            cell(_width(c), _ColumnHeader(view: view, table: table, entry: c)),
          cell(_actionsWidth, const SizedBox.shrink()),
        ],
      ),
    );

    Widget rowWidget(int i) {
      final r = view.index.row(table.name, i);
      final hasError =
          view.index.evaluation?.issues.any(
            (x) =>
                x.scope == '${table.name}[$i]' &&
                x.severity == IssueSeverity.error,
          ) ??
          false;
      return Container(
        key: ValueKey('row-${table.name}-$i'),
        decoration: BoxDecoration(border: Border(bottom: border)),
        child: Row(
          children: [
            cell(
              _numberWidth,
              Tooltip(
                message: r?.label ?? '',
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: hasError ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            ),
            for (final c in columns)
              cell(
                _width(c),
                ConfigEntryWidget(
                  view: view,
                  entry: c,
                  ref: FieldRef.item(table.name, i, c.name),
                  dense: true,
                ),
              ),
            cell(
              _actionsWidth,
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.cfgDuplicateRow,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(AppIcons.copy, size: 18),
                    onPressed: full
                        ? null
                        : () => view.actions.duplicateRow(table.name, i),
                  ),
                  IconButton(
                    tooltip: l10n.cfgDeleteRow,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(AppIcons.delete, size: 18),
                    onPressed: () => view.actions.deleteRow(table.name, i),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget groupHeader(String name, int count) => Container(
      key: ValueKey('group-${table.name}-$name'),
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 36,
      child: Row(
        children: [
          Text(name.isEmpty ? '—' : name, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text('($count)', style: theme.textTheme.bodySmall),
          IconButton(
            tooltip: l10n.cfgAddRowToGroup(name),
            visualDensity: VisualDensity.compact,
            icon: const Icon(AppIcons.add, size: 18),
            onPressed: full
                ? null
                : () => view.actions.addRow(table.name, {
                    table.groupField!: name,
                  }),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(itemLabel, style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              table.maxRows == null
                  ? '${rows.length}'
                  : '${rows.length} / ${table.maxRows}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  for (final g in groups.entries) ...[
                    if (grouped) groupHeader(g.key, g.value.length),
                    for (final i in g.value) rowWidget(i),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: full
              ? null
              : () => view.actions.addRow(table.name, {
                  if (grouped && rows.isNotEmpty)
                    table.groupField!: rows.last[table.groupField!],
                }),
          icon: const Icon(AppIcons.add),
          label: Text(l10n.cfgAddRow(itemLabel)),
        ),
      ],
    );
  }
}

/// Column title with its unit; inputs get a menu to set the column for all rows (and to
/// choose the display unit).
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.view,
    required this.table,
    required this.entry,
  });

  final RunnerView view;
  final CfgItemTable table;
  final CfgEntry entry;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final e = entry;
    final unit = switch (e) {
      CfgField f => view.displayUnit(FieldRef.item(table.name, 0, f.name), f),
      CfgComputed c => c.unit ?? '',
    };
    final required = e is CfgField && e.required;
    final title = Text(
      '${e.labelIn(lang)}${required ? ' *' : ''}${unit.isEmpty ? '' : ' ($unit)'}',
      style: theme.textTheme.labelMedium?.copyWith(
        fontStyle: e is CfgComputed ? FontStyle.italic : null,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
    if (e is! CfgField) {
      return Tooltip(message: e.helpIn(lang), child: title);
    }
    final units = e.inputUnits;
    final unitKey = RunnerView.unitKey(FieldRef.item(table.name, 0, e.name));
    return Row(
      children: [
        Expanded(
          child: Tooltip(message: e.helpIn(lang), child: title),
        ),
        PopupMenuButton<String>(
          key: ValueKey('bulk-${table.name}-${e.name}'),
          tooltip: context.l10n.cfgSetForAll,
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: const Icon(AppIcons.arrowDropDown),
          itemBuilder: (_) => [
            PopupMenuItem(value: '', child: Text(context.l10n.cfgSetForAll)),
            if (units.length > 1) const PopupMenuDivider(),
            for (final u in units)
              CheckedPopupMenuItem(
                value: 'unit:$u',
                checked: u == unit,
                child: Text(u),
              ),
          ],
          onSelected: (v) async {
            if (v.startsWith('unit:')) {
              view.actions.setDisplayUnit(unitKey, v.substring(5));
              return;
            }
            final result = await showDialog<_BulkValue>(
              context: context,
              builder: (_) => _BulkDialog(view: view, table: table, field: e),
            );
            if (result != null) {
              view.actions.bulkSet(table.name, e.name, result.value);
            }
          },
        ),
      ],
    );
  }
}

class _BulkValue {
  const _BulkValue(this.value);
  final Object? value;
}

class _BulkDialog extends StatefulWidget {
  const _BulkDialog({
    required this.view,
    required this.table,
    required this.field,
  });

  final RunnerView view;
  final CfgItemTable table;
  final CfgField field;

  @override
  State<_BulkDialog> createState() => _BulkDialogState();
}

class _BulkDialogState extends State<_BulkDialog> {
  Object? _value;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final f = widget.field;
    final ref = FieldRef.item(widget.table.name, 0, f.name);
    final first = widget.view.index[ref];
    // The options of the first row (choices computed from tables or families), always shown.
    final result = ValueResult(
      enabled: true,
      visible: true,
      kind: 'field',
      name: f.name,
      source: ValueSource.empty,
      value: null,
      options: first?.options,
    );
    return AlertDialog(
      title: Text(context.l10n.cfgSetForAllTitle(f.labelIn(lang))),
      content: SizedBox(
        width: 320,
        child: ConfigFieldInput(
          key: const ValueKey('bulk-input'),
          field: f,
          result: result,
          input: _value,
          displayUnit: widget.view.displayUnit(ref, f),
          onChanged: (v) => setState(() => _value = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _BulkValue(_value)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
