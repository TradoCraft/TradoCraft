import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'common.dart';
import 'draft.dart';
import 'editor_state.dart';
import 'formula_editor.dart';

/// Units per dimension, the canonical one first (mirrors `definition::units` on the server).
const dimensionUnits = <String, List<String>>{
  'mass': ['kg', 'g', 't'],
  'length': ['m', 'mm', 'cm', 'km'],
  'power': ['kW', 'W', 'MW'],
  'voltage': ['V', 'mV', 'kV'],
  'current': ['A', 'mA', 'kA'],
  'speed': ['m/s', 'm/min', 'km/h'],
};

const fieldTypes = [
  'number',
  'integer',
  'boolean',
  'choice',
  'text',
  'product',
];

/// Properties that only belong to some field types; changing the type drops the others (the
/// server refuses them).
const _typeProps = <String, List<String>>{
  'number': ['dimension', 'unit', 'display_units', 'min', 'max', 'step'],
  'integer': ['dimension', 'unit', 'display_units', 'min', 'max', 'step'],
  'choice': ['options', 'options_from'],
  'text': ['max_length', 'pattern'],
  'product': ['family', 'product_filter'],
};

/// Changes a field's type, removing what does not belong to the new type, and a default that no
/// longer fits.
void changeFieldType(Json field, String type) {
  final keep = _typeProps[type] ?? const [];
  for (final props in _typeProps.values) {
    for (final p in props) {
      if (!keep.contains(p)) field.remove(p);
    }
  }
  field['type'] = type;
  field.remove('default');
}

String scopeTitle(AppLocalizations l10n, DefinitionDraft d, ScopeSel s) =>
    switch (s.kind) {
      'project' => l10n.cfgbScopeProject,
      'group' => l10n.cfgbScopeGroup,
      _ => l10n.cfgbScopeItems(
        s.table! < d.itemTableNames().length
            ? d.itemTableNames()[s.table!]
            : '?',
      ),
    };

/// The scopes as a vertical list (project, group, each item table) with "add item table".
class ScopeList extends StatelessWidget {
  const ScopeList({
    super.key,
    required this.draft,
    required this.selected,
    required this.onSelect,
    this.onAddTable,
    this.errorIn,
  });

  final DefinitionDraft draft;
  final ScopeSel selected;
  final ValueChanged<ScopeSel> onSelect;
  final VoidCallback? onAddTable;
  final bool Function(ScopeSel s)? errorIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in draft.scopes())
          ListTile(
            key: ValueKey('scope-$s'),
            dense: true,
            selected: s == selected,
            selectedTileColor: theme.colorScheme.secondaryContainer,
            leading: Icon(
              s.isItem
                  ? AppIcons.viewList
                  : s.kind == 'group'
                  ? AppIcons.folder
                  : AppIcons.dashboardCustomize,
              size: 20,
            ),
            title: Text(scopeTitle(l10n, draft, s)),
            trailing: (errorIn?.call(s) ?? false)
                ? Icon(AppIcons.error, size: 18, color: theme.colorScheme.error)
                : null,
            onTap: () => onSelect(s),
          ),
        if (onAddTable != null && !ReadOnlyScope.of(context))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddTable,
              icon: const Icon(AppIcons.add),
              label: Text(l10n.cfgbAddItemTable),
            ),
          ),
      ],
    );
  }
}

/// Fields & layout: the scopes, the fields of the selected scope (drag to reorder), the item
/// table's own properties and the editor of the selected field.
class FieldsTab extends ConsumerWidget {
  const FieldsTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final scope =
        s.fieldScope.isItem && s.fieldScope.table! >= d.itemTables().length
        ? const ScopeSel.project()
        : s.fieldScope;
    final o = d.readScope(scope);
    final fields = jsonList(o, 'fields');
    final index = s.fieldIndex != null && s.fieldIndex! < fields.length
        ? s.fieldIndex
        : null;

    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.cfgbScopes),
        ScopeList(
          draft: d,
          selected: scope,
          onSelect: (sc) => n.selectField(sc, null),
          errorIn: (sc) => s.errorsAt(sc.path).isNotEmpty,
          onAddTable: () {
            n.edit((d) {
              final name = DefinitionDraft.freeName(
                'items',
                d.itemTableNames(),
              );
              mutableList(d.json, 'item_tables').add(<String, Object?>{
                'name': name,
                'label': '',
                'fields': <Object?>[],
              });
            });
            n.selectField(ScopeSel.item(d.itemTables().length - 1), null);
          },
        ),
        const Divider(height: 24),
        SectionTitle(l10n.cfgbFieldsOf(scopeTitle(l10n, d, scope))),
        EditableList(
          listKey: 'fields-$scope',
          titles: [for (final f in fields) str(f['name']) ?? ''],
          subtitles: [
            for (final f in fields)
              '${str(f['type']) ?? ''} · ${str(f['label']) ?? ''}',
          ],
          selected: index,
          errorAt: (i) => s.errorsAt('${scope.path}.fields[$i]').isNotEmpty,
          onSelect: (i) => n.selectField(scope, i),
          onReorder: (from, to) {
            n.edit(
              (d) =>
                  moveInList(mutableList(d.scope(scope), 'fields'), from, to),
            );
            n.selectField(scope, to);
          },
          addLabel: l10n.cfgbAddField,
          onAdd: () {
            n.edit((d) {
              final name = DefinitionDraft.freeName('field', d.allValueNames());
              mutableList(d.scope(scope), 'fields').add(<String, Object?>{
                'name': name,
                'type': 'number',
                'label': '',
              });
            });
            n.selectField(scope, fields.length);
          },
          onRemove: (i) {
            n.edit((d) {
              final o = d.scope(scope);
              mutableList(o, 'fields').removeAt(i);
              dropEmpty(o, 'fields');
            });
            n.selectField(scope, null);
          },
        ),
      ],
    );

    final detail = index != null
        ? FieldEditor(
            key: ValueKey('field-$scope-$index-${s.navigation}'),
            id: id,
            scope: scope,
            index: index,
          )
        : scope.isItem
        ? ItemTableEditor(
            key: ValueKey('table-$scope-${s.navigation}'),
            id: id,
            table: scope.table!,
          )
        : scope.kind == 'group'
        ? _GroupEditor(id: id)
        : Text(l10n.cfgbSelectField);
    return MasterDetail(master: master, detail: detail);
  }
}

class _GroupEditor extends ConsumerWidget {
  const _GroupEditor({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final g = s.draft!.readScope(const ScopeSel.group());
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.cfgbGroupHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        PropBlock(
          child: PropText(
            label: l10n.cfgbGroupLabel,
            value: str(g['label']) ?? '',
            onChanged: (v) => n.edit(
              (d) => setProp(d.scope(const ScopeSel.group()), 'label', v),
            ),
          ),
        ),
        TranslationsEditor(
          value: g['translations'],
          help: false,
          onChanged: (t) => n.edit(
            (d) => setProp(d.scope(const ScopeSel.group()), 'translations', t),
          ),
        ),
      ],
    );
  }
}

/// The properties of an item table: name, label, group field, item label, row limits.
class ItemTableEditor extends ConsumerWidget {
  const ItemTableEditor({super.key, required this.id, required this.table});
  final String id;
  final int table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final sel = ScopeSel.item(table);
    final t = d.readScope(sel);
    final path = sel.path;
    void set(String key, Object? v) =>
        n.edit((d) => setProp(d.scope(sel), key, v));
    final groupable = [
      for (final f in jsonList(t, 'fields'))
        if (f['type'] == 'text' || f['type'] == 'choice') str(f['name']) ?? '',
    ];
    String? err(String prop) {
      final e = s.errorsAt('$path.$prop');
      return e.isEmpty ? null : e.first.message;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.cfgbItemTable,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!s.readOnly)
              TextButton.icon(
                onPressed: () {
                  n.edit((d) {
                    mutableList(d.json, 'item_tables').removeAt(table);
                    dropEmpty(d.json, 'item_tables');
                  });
                  n.selectField(const ScopeSel.project(), null);
                },
                icon: const Icon(AppIcons.delete),
                label: Text(l10n.cfgbRemoveItemTable),
              ),
          ],
        ),
        ProblemsBox(
          messages: [
            for (final e in s.errors)
              if (e.path == path) e.message,
          ],
        ),
        PropRow(
          children: [
            PropText(
              label: l10n.name,
              value: str(t['name']) ?? '',
              width: 220,
              monospace: true,
              errorText: err('name'),
              highlight: s.focusProperty == 'name',
              onChanged: (v) => set('name', v),
            ),
            PropText(
              label: l10n.cfgbLabel,
              value: str(t['label']) ?? '',
              width: 260,
              onChanged: (v) => n.edit((d) => d.scope(sel)['label'] = v),
            ),
          ],
        ),
        PropRow(
          children: [
            PropDropdown<String>(
              label: l10n.cfgbGroupField,
              value: str(t['group_field']),
              allowNone: true,
              items: {for (final g in groupable) g: g},
              onChanged: (v) => set('group_field', v),
            ),
            PropNumber(
              label: l10n.cfgbMinRows,
              value: t['min_rows'],
              integer: true,
              errorText: err('min_rows'),
              onChanged: (v) => set('min_rows', v),
            ),
            PropNumber(
              label: l10n.cfgbMaxRows,
              value: t['max_rows'],
              integer: true,
              errorText: err('max_rows'),
              onChanged: (v) => set('max_rows', v),
            ),
          ],
        ),
        PropBlock(
          child: FormulaField(
            key: ValueKey('$path.item_label'),
            label: l10n.cfgbItemLabel,
            helper: l10n.cfgbItemLabelHelp,
            template: true,
            value: str(t['item_label']) ?? '',
            context: FormulaContext(d, sel),
            enabled: !s.readOnly,
            serverProblems: s.formulaProblems('$path.item_label'),
            onChanged: (v) => set('item_label', v),
          ),
        ),
        TranslationsEditor(
          value: t['translations'],
          help: false,
          onChanged: (v) => set('translations', v),
        ),
      ],
    );
  }
}

/// The editor of one field, with the properties of its type.
class FieldEditor extends ConsumerWidget {
  const FieldEditor({
    super.key,
    required this.id,
    required this.scope,
    required this.index,
  });

  final String id;
  final ScopeSel scope;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final fields = jsonList(d.readScope(scope), 'fields');
    if (index >= fields.length) return const SizedBox.shrink();
    final f = fields[index];
    final path = '${scope.path}.fields[$index]';
    final type = str(f['type']) ?? 'text';
    final ctx = FormulaContext(d, scope);

    Json field(DefinitionDraft d) =>
        asJson(mutableList(d.scope(scope), 'fields')[index]);
    void set(String key, Object? v) => n.edit((d) => setProp(field(d), key, v));
    String? err(String prop) {
      final e = s.errorsAt('$path.$prop');
      return e.isEmpty ? null : e.first.message;
    }

    Widget formula(
      String prop,
      String label, {
      String? helper,
      List<String> locals = const [],
    }) => PropBlock(
      child: FormulaField(
        key: ValueKey('$path.$prop'),
        label: label,
        helper: helper,
        value: str(f[prop]) ?? '',
        context: FormulaContext(d, scope, locals: locals),
        enabled: !s.readOnly,
        serverProblems: s.formulaProblems('$path.$prop'),
        onChanged: (v) => set(prop, v),
      ),
    );

    final layout = asJson(f['layout']);
    void setLayout(String key, Object? v) => n.edit((d) {
      final fl = field(d);
      final lo = mutableMap(fl, 'layout');
      setProp(lo, key, v);
      if (lo.isEmpty) fl.remove('layout');
    });
    final sections = [for (final sc in d.sections()) str(sc['name']) ?? ''];

    return Column(
      key: const ValueKey('field-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.cfgbFieldTitle(str(f['name']) ?? ''),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ProblemsBox(
          messages: [
            for (final e in s.errors)
              if (e.path == path) e.message,
          ],
        ),
        PropRow(
          children: [
            PropText(
              key: const ValueKey('field-name'),
              label: l10n.name,
              value: str(f['name']) ?? '',
              width: 200,
              monospace: true,
              errorText: err('name'),
              highlight: s.focusProperty == 'name',
              onChanged: (v) => n.edit((d) => field(d)['name'] = v),
            ),
            PropDropdown<String>(
              key: const ValueKey('field-type'),
              label: l10n.type,
              value: type,
              width: 160,
              items: {for (final t in fieldTypes) t: fieldTypeLabel(l10n, t)},
              onChanged: (v) {
                if (v != null && v != type) {
                  n.edit((d) => changeFieldType(field(d), v));
                }
              },
            ),
            PropText(
              label: l10n.cfgbLabel,
              value: str(f['label']) ?? '',
              width: 260,
              onChanged: (v) => n.edit((d) => field(d)['label'] = v),
            ),
          ],
        ),
        PropBlock(
          child: PropText(
            label: l10n.cfgbHelp,
            value: str(f['help']) ?? '',
            onChanged: (v) => set('help', v),
          ),
        ),
        PropSwitch(
          label: l10n.cfgbRequired,
          value: f['required'] == true,
          onChanged: (v) => n.edit((d) {
            final fl = field(d);
            if (v) {
              fl['required'] = true;
            } else if (fl.containsKey('required')) {
              fl['required'] = false;
            }
          }),
        ),
        const SizedBox(height: 8),
        // Type-specific properties.
        if (type == 'number' || type == 'integer')
          _NumberProps(
            field: f,
            set: set,
            err: err,
            integer: type == 'integer',
          ),
        if (type == 'choice')
          _ChoiceProps(
            id: id,
            field: f,
            path: path,
            set: set,
            edit: (fn) => n.edit((d) => fn(field(d))),
          ),
        if (type == 'text')
          PropRow(
            children: [
              PropNumber(
                label: l10n.cfgbMaxLength,
                value: f['max_length'],
                integer: true,
                onChanged: (v) => set('max_length', v),
              ),
              PropText(
                label: l10n.cfgbPattern,
                value: str(f['pattern']) ?? '',
                width: 260,
                monospace: true,
                errorText: err('pattern'),
                onChanged: (v) => set('pattern', v),
              ),
            ],
          ),
        if (type == 'product') ...[
          PropRow(
            children: [
              PropText(
                label: l10n.cfgbFamily,
                value: str(f['family']) ?? '',
                width: 220,
                monospace: true,
                errorText: err('family'),
                onChanged: (v) => set('family', v),
              ),
            ],
          ),
          formula(
            'product_filter',
            l10n.cfgbProductFilter,
            helper: l10n.cfgbProductFilterHelp,
            locals: const ['p'],
          ),
        ],
        const SizedBox(height: 8),
        SectionTitle(l10n.cfgbDefault),
        _DefaultEditor(field: f, type: type, set: set, err: err),
        formula(
          'default_expr',
          l10n.cfgbDefaultExpr,
          helper: l10n.cfgbDefaultExprHelp,
        ),
        SectionTitle(l10n.cfgbConditions),
        formula('visible_if', l10n.cfgbVisibleIf),
        formula('enabled_if', l10n.cfgbEnabledIf),
        SectionTitle(l10n.cfgbLayout),
        PropRow(
          children: [
            PropDropdown<String>(
              label: l10n.cfgbSection,
              value: str(layout['section']),
              allowNone: true,
              width: 200,
              items: {for (final sc in sections) sc: sc},
              onChanged: (v) => setLayout('section', v),
            ),
            PropNumber(
              label: l10n.cfgbColumn,
              value: layout['column'],
              integer: true,
              width: 100,
              onChanged: (v) => setLayout('column', v),
            ),
            PropNumber(
              label: l10n.cfgbOrder,
              value: layout['order'],
              integer: true,
              width: 100,
              onChanged: (v) => setLayout('order', v),
            ),
            PropNumber(
              label: l10n.cfgbWidth,
              value: layout['width'],
              integer: true,
              width: 100,
              onChanged: (v) => setLayout('width', v),
            ),
          ],
        ),
        TranslationsEditor(
          value: f['translations'],
          onChanged: (v) => set('translations', v),
        ),
        // Keep the formula context alive for type-dependent hints.
        if (ctx.scope.isItem) const SizedBox.shrink(),
      ],
    );
  }
}

String fieldTypeLabel(AppLocalizations l10n, String t) => switch (t) {
  'number' => l10n.cfgbTypeNumber,
  'integer' => l10n.cfgbTypeInteger,
  'boolean' => l10n.cfgbTypeBoolean,
  'choice' => l10n.cfgbTypeChoice,
  'product' => l10n.cfgbTypeProduct,
  _ => l10n.cfgbTypeText,
};

String dimensionLabel(AppLocalizations l10n, String d) => switch (d) {
  'mass' => l10n.cfgbDimMass,
  'length' => l10n.cfgbDimLength,
  'power' => l10n.cfgbDimPower,
  'voltage' => l10n.cfgbDimVoltage,
  'current' => l10n.cfgbDimCurrent,
  _ => l10n.cfgbDimSpeed,
};

class _NumberProps extends StatelessWidget {
  const _NumberProps({
    required this.field,
    required this.set,
    required this.err,
    required this.integer,
  });

  final Json field;
  final void Function(String key, Object? v) set;
  final String? Function(String prop) err;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dim = str(field['dimension']);
    final units = dimensionUnits[dim] ?? const <String>[];
    final display = [
      for (final u in (field['display_units'] as List? ?? const [])) '$u',
    ];
    final readOnly = ReadOnlyScope.of(context);
    return Column(
      key: const ValueKey('number-props'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropRow(
          children: [
            PropDropdown<String>(
              key: const ValueKey('field-dimension'),
              label: l10n.cfgbDimension,
              value: dim,
              allowNone: true,
              width: 180,
              items: {
                for (final d in dimensionUnits.keys) d: dimensionLabel(l10n, d),
              },
              onChanged: (v) {
                set('dimension', v);
                set('display_units', null);
                set('unit', v == null ? null : dimensionUnits[v]!.first);
              },
            ),
            if (units.isNotEmpty)
              PropDropdown<String>(
                key: const ValueKey('field-unit'),
                label: l10n.unit,
                value: str(field['unit']),
                width: 120,
                items: {for (final u in units) u: u},
                onChanged: (v) => set('unit', v),
              )
            else
              PropText(
                key: const ValueKey('field-unit-text'),
                label: l10n.unit,
                value: str(field['unit']) ?? '',
                width: 120,
                errorText: err('unit'),
                onChanged: (v) => set('unit', v),
              ),
          ],
        ),
        if (units.isNotEmpty)
          PropBlock(
            child: Wrap(
              key: const ValueKey('display-units'),
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.cfgbDisplayUnits),
                for (final u in units)
                  FilterChip(
                    label: Text(u),
                    selected: display.contains(u),
                    onSelected: readOnly
                        ? null
                        : (on) {
                            final next = [
                              for (final x in units)
                                if (x == u ? on : display.contains(x)) x,
                            ];
                            set('display_units', next);
                          },
                  ),
              ],
            ),
          ),
        PropRow(
          children: [
            PropNumber(
              key: const ValueKey('field-min'),
              label: l10n.cfgbMin,
              value: field['min'],
              integer: integer,
              errorText: err('min'),
              onChanged: (v) => set('min', v),
            ),
            PropNumber(
              key: const ValueKey('field-max'),
              label: l10n.cfgbMax,
              value: field['max'],
              integer: integer,
              errorText: err('max'),
              onChanged: (v) => set('max', v),
            ),
            PropNumber(
              key: const ValueKey('field-step'),
              label: l10n.cfgbStep,
              value: field['step'],
              errorText: err('step'),
              onChanged: (v) => set('step', v),
            ),
          ],
        ),
      ],
    );
  }
}

/// Choice options: a static list (value, label, translations) or taken from a table column or a
/// product family.
class _ChoiceProps extends ConsumerWidget {
  const _ChoiceProps({
    required this.id,
    required this.field,
    required this.path,
    required this.set,
    required this.edit,
  });

  final String id;
  final Json field;
  final String path;
  final void Function(String key, Object? v) set;
  final void Function(void Function(Json field) fn) edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final d = ref.watch(revisionEditorProvider(id)).draft!;
    final from = asJson(field['options_from']);
    final mode = field.containsKey('options_from')
        ? (from.containsKey('family') ? 'family' : 'table')
        : 'static';
    final options = jsonList(field, 'options');
    final readOnly = ReadOnlyScope.of(context);
    return Column(
      key: const ValueKey('choice-props'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropBlock(
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'static',
                label: Text(l10n.cfgbOptionsStatic),
              ),
              ButtonSegment(value: 'table', label: Text(l10n.cfgbOptionsTable)),
              ButtonSegment(
                value: 'family',
                label: Text(l10n.cfgbOptionsFamily),
              ),
            ],
            selected: {mode},
            onSelectionChanged: readOnly
                ? null
                : (sel) => edit((f) {
                    switch (sel.first) {
                      case 'static':
                        f.remove('options_from');
                        f.putIfAbsent('options', () => <Object?>[]);
                      case 'table':
                        f.remove('options');
                        f['options_from'] = <String, Object?>{
                          'table': '',
                          'column': '',
                        };
                      case 'family':
                        f.remove('options');
                        f['options_from'] = <String, Object?>{'family': ''};
                    }
                  }),
          ),
        ),
        if (mode == 'static') ...[
          for (final (i, o) in options.indexed)
            Padding(
              key: ValueKey('option-$i'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  PropText(
                    label: l10n.cfgbValue,
                    value: numberText(o['value']),
                    width: 140,
                    monospace: true,
                    onChanged: (v) => edit((f) {
                      final opt = asJson(mutableList(f, 'options')[i]);
                      // Numbers stay numbers (`3`), other text is a string value.
                      final parsed = parseNumberText(v);
                      opt['value'] = parsed ?? '';
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PropText(
                      label: l10n.cfgbLabel,
                      value: str(o['label']) ?? '',
                      onChanged: (v) => edit((f) {
                        setProp(
                          asJson(mutableList(f, 'options')[i]),
                          'label',
                          v,
                        );
                      }),
                    ),
                  ),
                  if (!readOnly) ...[
                    IconButton(
                      tooltip: l10n.cfgbMoveUp,
                      icon: const Icon(AppIcons.arrowUpward, size: 18),
                      onPressed: i == 0
                          ? null
                          : () => edit(
                              (f) => moveInList(
                                mutableList(f, 'options'),
                                i,
                                i - 1,
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: l10n.remove,
                      icon: const Icon(AppIcons.delete, size: 18),
                      onPressed: () =>
                          edit((f) => mutableList(f, 'options').removeAt(i)),
                    ),
                  ],
                ],
              ),
            ),
          if (!readOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('add-option'),
                onPressed: () => edit(
                  (f) => mutableList(
                    f,
                    'options',
                  ).add(<String, Object?>{'value': ''}),
                ),
                icon: const Icon(AppIcons.add),
                label: Text(l10n.cfgbAddOption),
              ),
            ),
        ],
        if (mode == 'table')
          PropRow(
            children: [
              PropDropdown<String>(
                label: l10n.cfgbTable,
                value: str(from['table']),
                items: {for (final t in d.tableNames()) t: t},
                onChanged: (v) => edit((f) {
                  final m = mutableMap(f, 'options_from');
                  setProp(m, 'table', v);
                  m.remove('column');
                }),
              ),
              PropDropdown<String>(
                label: l10n.cfgbColumnName,
                value: str(from['column']),
                items: {
                  for (final c in d.tableColumns(str(from['table']) ?? ''))
                    c: c,
                },
                onChanged: (v) => edit(
                  (f) => setProp(mutableMap(f, 'options_from'), 'column', v),
                ),
              ),
            ],
          ),
        if (mode == 'family')
          PropRow(
            children: [
              PropText(
                label: l10n.cfgbFamily,
                value: str(from['family']) ?? '',
                width: 220,
                monospace: true,
                onChanged: (v) =>
                    edit((f) => mutableMap(f, 'options_from')['family'] = v),
              ),
            ],
          ),
      ],
    );
  }
}

/// The literal default, typed by the field type.
class _DefaultEditor extends StatelessWidget {
  const _DefaultEditor({
    required this.field,
    required this.type,
    required this.set,
    required this.err,
  });

  final Json field;
  final String type;
  final void Function(String key, Object? v) set;
  final String? Function(String prop) err;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = field['default'];
    if (type == 'boolean') {
      return PropBlock(
        child: Align(
          alignment: Alignment.centerLeft,
          child: PropDropdown<bool>(
            key: const ValueKey('field-default'),
            label: l10n.cfgbDefault,
            value: v is bool ? v : null,
            allowNone: true,
            width: 160,
            items: {true: l10n.yes, false: l10n.no},
            onChanged: (b) => set('default', b),
          ),
        ),
      );
    }
    if (type == 'choice') {
      final options = jsonList(field, 'options');
      if (options.isNotEmpty) {
        final values = {
          for (final o in options) numberText(o['value']): o['value'],
        };
        return PropBlock(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PropDropdown<String>(
              key: const ValueKey('field-default'),
              label: l10n.cfgbDefault,
              value: v == null ? null : numberText(v),
              allowNone: true,
              width: 200,
              items: {for (final k in values.keys) k: k},
              onChanged: (k) => set('default', k == null ? null : values[k]),
            ),
          ),
        );
      }
    }
    final numeric = type == 'number' || type == 'integer';
    return PropBlock(
      child: Align(
        alignment: Alignment.centerLeft,
        child: numeric
            ? PropNumber(
                key: const ValueKey('field-default'),
                label: l10n.cfgbDefault,
                value: v,
                integer: type == 'integer',
                errorText: err('default'),
                onChanged: (x) => set('default', x),
              )
            : PropText(
                key: const ValueKey('field-default'),
                label: l10n.cfgbDefault,
                value: v == null ? '' : '$v',
                width: 260,
                errorText: err('default'),
                onChanged: (x) => set('default', x),
              ),
      ),
    );
  }
}
