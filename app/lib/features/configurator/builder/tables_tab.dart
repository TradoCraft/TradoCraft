import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/csv_transfer.dart';
import 'common.dart';
import 'draft.dart';
import 'editor_state.dart';

const columnTypes = ['number', 'integer', 'text', 'boolean'];

String columnTypeLabel(AppLocalizations l10n, String t) => switch (t) {
  'number' => l10n.cfgbTypeNumber,
  'integer' => l10n.cfgbTypeInteger,
  'boolean' => l10n.cfgbTypeBoolean,
  _ => l10n.cfgbTypeText,
};

/// Renames a column of a table everywhere it is used in that table: rows, keys and range.
/// A name another column already has is not applied (returns false): moving the row values
/// would overwrite that column's, so the rename waits until the name is unique.
bool renameColumn(Json table, int index, String name) {
  final cols = mutableList(table, 'columns');
  final col = asJson(cols[index]);
  final old = str(col['name']) ?? '';
  for (final (i, c) in cols.indexed) {
    if (i != index && str(asJson(c)['name']) == name) return false;
  }
  col['name'] = name;
  for (final r in jsonList(table, 'rows')) {
    if (r.containsKey(old)) r[name] = r.remove(old);
  }
  final keys = table['keys'];
  if (keys is List) {
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] == old) keys[i] = name;
    }
  }
  final range = table['range'];
  if (range is Map) {
    for (final k in ['min', 'max']) {
      if (range[k] == old) range[k] = name;
    }
  }
  return true;
}

/// Lookup tables: a list, the table's settings (kind, keys, range, on missing), its columns and
/// a grid of rows, with CSV import and export.
class TablesTab extends ConsumerWidget {
  const TablesTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final tables = d.tables();
    final index = s.tableIndex != null && s.tableIndex! < tables.length
        ? s.tableIndex
        : null;
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.cfgbTables),
        EditableList(
          listKey: 'tables',
          titles: [for (final t in tables) str(t['name']) ?? ''],
          subtitles: [
            for (final t in tables)
              '${str(t['kind']) ?? 'exact'} · ${l10n.cfgbRowCount(jsonList(t, 'rows').length)}',
          ],
          selected: index,
          errorAt: (i) => s.errorsAt('\$.tables[$i]').isNotEmpty,
          onSelect: (i) => n.selectTable(i),
          onReorder: (from, to) {
            n.edit((d) => moveInList(mutableList(d.json, 'tables'), from, to));
            n.selectTable(to);
          },
          addLabel: l10n.cfgbAddTable,
          onAdd: () {
            n.edit((d) {
              mutableList(d.json, 'tables').add(<String, Object?>{
                'name': DefinitionDraft.freeName('table', d.tableNames()),
                'kind': 'exact',
                'keys': <Object?>['key'],
                'on_missing': 'error',
                'columns': <Object?>[
                  <String, Object?>{'name': 'key', 'type': 'text'},
                  <String, Object?>{'name': 'value', 'type': 'number'},
                ],
                'rows': <Object?>[],
              });
            });
            n.selectTable(tables.length);
          },
          onRemove: (i) {
            n.edit((d) {
              mutableList(d.json, 'tables').removeAt(i);
              dropEmpty(d.json, 'tables');
            });
            n.selectTable(null);
          },
        ),
      ],
    );
    final detail = index == null
        ? Text(l10n.cfgbSelectTable)
        : TableEditor(
            key: ValueKey('table-$index-${s.navigation}'),
            id: id,
            index: index,
          );
    return MasterDetail(master: master, detail: detail, masterWidth: 280);
  }
}

class TableEditor extends ConsumerWidget {
  const TableEditor({super.key, required this.id, required this.index});
  final String id;
  final int index;

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ref.read(csvPickerProvider)();
    if (picked == null) return;
    final n = ref.read(revisionEditorProvider(id).notifier);
    final table = ref.read(revisionEditorProvider(id)).draft!.tables()[index];
    final r = csvToRows(utf8.decode(picked.bytes, allowMalformed: true), table);
    if (r.errors.isNotEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.cfgbCsvProblems),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(child: Text(r.errors.join('\n'))),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
      return;
    }
    n.edit((d) => d.tables()[index]['rows'] = r.rows);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.cfgbCsvImported(r.rows.length))),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final table = ref.read(revisionEditorProvider(id)).draft!.tables()[index];
    final name = '${str(table['name']) ?? 'table'}.csv';
    await ref.read(csvSaverProvider)(
      name,
      Uint8List.fromList(utf8.encode(tableToCsv(table))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final tables = d.tables();
    if (index >= tables.length) return const SizedBox.shrink();
    final t = tables[index];
    final jp = '\$.tables[$index]';
    Json table(DefinitionDraft d) => d.tables()[index];
    void set(String key, Object? v) => n.edit((d) => setProp(table(d), key, v));
    final columns = jsonList(t, 'columns');
    final colNames = [for (final c in columns) str(c['name']) ?? ''];
    final kind = str(t['kind']) ?? 'exact';
    final keys = [for (final k in (t['keys'] as List? ?? const [])) '$k'];
    final range = asJson(t['range']);
    final readOnly = s.readOnly;
    final numberCols = [
      for (final c in columns)
        if (c['type'] == 'number' || c['type'] == 'integer')
          str(c['name']) ?? '',
    ];

    return Column(
      key: const ValueKey('table-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.cfgbTableTitle(str(t['name']) ?? ''),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                key: const ValueKey('csv-import'),
                onPressed: () => _import(context, ref),
                icon: const Icon(AppIcons.fileUpload),
                label: Text(l10n.cfgbCsvImport),
              ),
            TextButton.icon(
              key: const ValueKey('csv-export'),
              onPressed: () => _export(context, ref),
              icon: const Icon(AppIcons.fileDownload),
              label: Text(l10n.cfgbCsvExport),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProblemsBox(
          messages: [
            for (final e in s.errorsAt(jp))
              '${e.path.replaceFirst(jp, '')}: ${e.message}',
          ],
        ),
        PropRow(
          children: [
            PropText(
              label: l10n.name,
              value: str(t['name']) ?? '',
              width: 200,
              monospace: true,
              highlight: s.focusProperty == 'name',
              onChanged: (v) => n.edit((d) => table(d)['name'] = v),
            ),
            PropText(
              label: l10n.cfgbLabel,
              value: str(t['label']) ?? '',
              width: 240,
              onChanged: (v) => set('label', v),
            ),
            PropDropdown<String>(
              key: const ValueKey('table-kind'),
              label: l10n.cfgbTableKind,
              value: kind,
              width: 160,
              items: {'exact': l10n.cfgbKindExact, 'range': l10n.cfgbKindRange},
              onChanged: (v) => n.edit((d) {
                final x = table(d);
                x['kind'] = v ?? 'exact';
                if (v == 'range') {
                  x.putIfAbsent(
                    'range',
                    () => <String, Object?>{
                      'key': 'value',
                      'min': '',
                      'max': '',
                    },
                  );
                } else {
                  x.remove('range');
                }
              }),
            ),
            PropDropdown<String>(
              label: l10n.cfgbOnMissing,
              value: str(t['on_missing']) ?? 'error',
              width: 280,
              helper: str(t['on_missing']) == 'clamp'
                  ? l10n.cfgbOnMissingHelp
                  : null,
              items: {
                'error': l10n.cfgbOnMissingError,
                'clamp': l10n.cfgbOnMissingClamp,
                'null': l10n.cfgbOnMissingNull,
              },
              onChanged: (v) =>
                  n.edit((d) => table(d)['on_missing'] = v ?? 'error'),
            ),
          ],
        ),
        PropBlock(
          child: Wrap(
            key: const ValueKey('table-keys'),
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.cfgbKeys),
              for (final c in colNames)
                FilterChip(
                  label: Text(c),
                  selected: keys.contains(c),
                  onSelected: readOnly
                      ? null
                      : (on) => n.edit((d) {
                          table(d)['keys'] = [
                            for (final x in colNames)
                              if (x == c ? on : keys.contains(x)) x,
                          ];
                        }),
                ),
            ],
          ),
        ),
        if (kind == 'range')
          PropRow(
            children: [
              PropText(
                label: l10n.cfgbRangeKey,
                helper: l10n.cfgbRangeKeyHelp,
                value: str(range['key']) ?? '',
                width: 180,
                monospace: true,
                onChanged: (v) =>
                    n.edit((d) => mutableMap(table(d), 'range')['key'] = v),
              ),
              PropDropdown<String>(
                label: l10n.cfgbRangeMin,
                value: str(range['min']),
                width: 160,
                items: {for (final c in numberCols) c: c},
                onChanged: (v) => n.edit(
                  (d) => mutableMap(table(d), 'range')['min'] = v ?? '',
                ),
              ),
              PropDropdown<String>(
                label: l10n.cfgbRangeMax,
                value: str(range['max']),
                width: 160,
                items: {for (final c in numberCols) c: c},
                onChanged: (v) => n.edit(
                  (d) => mutableMap(table(d), 'range')['max'] = v ?? '',
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        TableGrid(id: id, index: index, highlightRow: s.tableRow),
      ],
    );
  }
}

/// The grid: a header row of columns (name and type) and the rows, each cell typed by its column.
class TableGrid extends ConsumerWidget {
  const TableGrid({
    super.key,
    required this.id,
    required this.index,
    this.highlightRow,
  });

  final String id;
  final int index;
  final int? highlightRow;

  static const cellWidth = 150.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = d.tables()[index];
    final columns = jsonList(t, 'columns');
    final rows = jsonList(t, 'rows');
    final readOnly = s.readOnly;
    Json table(DefinitionDraft d) => d.tables()[index];
    final jp = '\$.tables[$index]';

    Widget cell(Widget child, {Color? color}) => Container(
      width: cellWidth,
      padding: const EdgeInsets.all(4),
      color: color,
      child: child,
    );

    final header = Row(
      children: [
        const SizedBox(width: 48),
        for (final (ci, c) in columns.indexed)
          cell(
            Column(
              children: [
                PropText(
                  key: ValueKey('col-name-$ci'),
                  label: l10n.cfgbColumnName,
                  value: str(c['name']) ?? '',
                  monospace: true,
                  errorText: s.errorsAt('$jp.columns[$ci]').isEmpty
                      ? null
                      : s.errorsAt('$jp.columns[$ci]').first.message,
                  onChanged: (v) =>
                      n.edit((d) => renameColumn(table(d), ci, v)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: PropDropdown<String>(
                        key: ValueKey('col-type-$ci'),
                        label: l10n.type,
                        value: str(c['type']) ?? 'text',
                        width: null,
                        items: {
                          for (final x in columnTypes)
                            x: columnTypeLabel(l10n, x),
                        },
                        onChanged: (v) => n.edit(
                          (d) => asJson(
                            mutableList(table(d), 'columns')[ci],
                          )['type'] = v ?? 'text',
                        ),
                      ),
                    ),
                    if (!readOnly)
                      IconButton(
                        key: ValueKey('col-remove-$ci'),
                        tooltip: l10n.cfgbRemoveColumn,
                        icon: const Icon(AppIcons.delete, size: 18),
                        onPressed: () => n.edit((d) {
                          final x = table(d);
                          final name = str(columns[ci]['name']);
                          mutableList(x, 'columns').removeAt(ci);
                          for (final r in jsonList(x, 'rows')) {
                            r.remove(name);
                          }
                          final keys = x['keys'];
                          if (keys is List) keys.remove(name);
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!readOnly)
          IconButton(
            key: const ValueKey('add-column'),
            tooltip: l10n.cfgbAddColumn,
            icon: const Icon(AppIcons.add),
            onPressed: () => n.edit((d) {
              final x = table(d);
              final names = [
                for (final c in jsonList(x, 'columns')) str(c['name']) ?? '',
              ];
              mutableList(x, 'columns').add(<String, Object?>{
                'name': DefinitionDraft.freeName('column', names),
                'type': 'text',
              });
            }),
          ),
      ],
    );

    final body = [
      for (final (ri, r) in rows.indexed)
        Container(
          key: ValueKey('row-$ri'),
          color: ri == highlightRow
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
              : null,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: readOnly
                    ? Text('${ri + 1}', textAlign: TextAlign.center)
                    : IconButton(
                        key: ValueKey('row-remove-$ri'),
                        tooltip: l10n.cfgbRemoveRow,
                        icon: const Icon(AppIcons.close, size: 16),
                        onPressed: () => n.edit((d) {
                          mutableList(table(d), 'rows').removeAt(ri);
                        }),
                      ),
              ),
              for (final c in columns)
                cell(
                  PropText(
                    key: ValueKey('cell-$ri-${c['name']}'),
                    label: '',
                    value: numberText(r[str(c['name'])]),
                    monospace: true,
                    errorText:
                        s.errors.any(
                          (e) => e.path == '$jp.rows[$ri].${c['name']}',
                        )
                        ? '!'
                        : null,
                    onChanged: (v) => n.edit((d) {
                      final row = asJson(mutableList(table(d), 'rows')[ri]);
                      final name = str(c['name']) ?? '';
                      final typed = typedCell(v, str(c['type']));
                      if (typed == null) {
                        row.remove(name);
                      } else {
                        // Text that does not fit the column is kept; the server reports it.
                        row[name] = typed is CsvCellError ? typed.text : typed;
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            key: const ValueKey('table-grid'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, const Divider(height: 8), ...body],
          ),
        ),
        if (!readOnly)
          TextButton.icon(
            key: const ValueKey('add-row'),
            onPressed: () => n.edit(
              (d) => mutableList(table(d), 'rows').add(<String, Object?>{}),
            ),
            icon: const Icon(AppIcons.add),
            label: Text(l10n.cfgbAddRow),
          ),
      ],
    );
  }
}
