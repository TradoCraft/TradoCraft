import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'common.dart';
import 'draft.dart';
import 'editor_state.dart';
import 'fields_tab.dart';
import 'formula_editor.dart';

// ---------------------------------------------------------------------------------------------
// Computed values
// ---------------------------------------------------------------------------------------------

/// Computed values per scope: named formulas, optionally overridable by the user.
class ComputedTab extends ConsumerWidget {
  const ComputedTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final scope =
        s.computedScope.isItem &&
            s.computedScope.table! >= d.itemTables().length
        ? const ScopeSel.project()
        : s.computedScope;
    final list = jsonList(d.readScope(scope), 'computed');
    final index = s.computedIndex != null && s.computedIndex! < list.length
        ? s.computedIndex
        : null;
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.cfgbScopes),
        ScopeList(
          draft: d,
          selected: scope,
          onSelect: (sc) => n.selectComputed(sc, null),
          errorIn: (sc) => s.errorsAt('${sc.path}.computed').isNotEmpty,
        ),
        const Divider(height: 24),
        SectionTitle(l10n.cfgbComputedOf(scopeTitle(l10n, d, scope))),
        EditableList(
          listKey: 'computed-$scope',
          titles: [for (final c in list) str(c['name']) ?? ''],
          subtitles: [for (final c in list) str(c['expr']) ?? ''],
          selected: index,
          errorAt: (i) => s.errorsAt('${scope.path}.computed[$i]').isNotEmpty,
          onSelect: (i) => n.selectComputed(scope, i),
          onReorder: (from, to) {
            n.edit(
              (d) =>
                  moveInList(mutableList(d.scope(scope), 'computed'), from, to),
            );
            n.selectComputed(scope, to);
          },
          addLabel: l10n.cfgbAddComputed,
          onAdd: () {
            n.edit((d) {
              final name = DefinitionDraft.freeName('value', d.allValueNames());
              mutableList(
                d.scope(scope),
                'computed',
              ).add(<String, Object?>{'name': name, 'label': '', 'expr': ''});
            });
            n.selectComputed(scope, list.length);
          },
          onRemove: (i) {
            n.edit((d) {
              final o = d.scope(scope);
              mutableList(o, 'computed').removeAt(i);
              dropEmpty(o, 'computed');
            });
            n.selectComputed(scope, null);
          },
        ),
      ],
    );
    final detail = index == null
        ? Text(l10n.cfgbSelectComputed)
        : _ComputedEditor(
            key: ValueKey('computed-$scope-$index-${s.navigation}'),
            id: id,
            scope: scope,
            index: index,
          );
    return MasterDetail(master: master, detail: detail);
  }
}

class _ComputedEditor extends ConsumerWidget {
  const _ComputedEditor({
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
    final list = jsonList(d.readScope(scope), 'computed');
    if (index >= list.length) return const SizedBox.shrink();
    final c = list[index];
    final path = '${scope.path}.computed[$index]';
    Json item(DefinitionDraft d) =>
        asJson(mutableList(d.scope(scope), 'computed')[index]);
    void set(String key, Object? v) => n.edit((d) => setProp(item(d), key, v));
    String? err(String prop) {
      final e = s.errorsAt('$path.$prop');
      return e.isEmpty ? null : e.first.message;
    }

    final layout = asJson(c['layout']);
    return Column(
      key: const ValueKey('computed-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.cfgbComputedTitle(str(c['name']) ?? ''),
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
              label: l10n.name,
              value: str(c['name']) ?? '',
              width: 200,
              monospace: true,
              errorText: err('name'),
              highlight: s.focusProperty == 'name',
              onChanged: (v) => n.edit((d) => item(d)['name'] = v),
            ),
            PropText(
              label: l10n.cfgbLabel,
              value: str(c['label']) ?? '',
              width: 260,
              onChanged: (v) => n.edit((d) => item(d)['label'] = v),
            ),
            PropText(
              label: l10n.unit,
              value: str(c['unit']) ?? '',
              width: 100,
              onChanged: (v) => set('unit', v),
            ),
          ],
        ),
        PropBlock(
          child: FormulaField(
            key: ValueKey('$path.expr'),
            label: l10n.cfgbExpr,
            value: str(c['expr']) ?? '',
            context: FormulaContext(d, scope),
            maxLines: 4,
            enabled: !s.readOnly,
            serverProblems: s.formulaProblems('$path.expr'),
            onChanged: (v) => n.edit((d) => item(d)['expr'] = v),
          ),
        ),
        PropSwitch(
          label: l10n.cfgbOverridable,
          subtitle: l10n.cfgbOverridableHelp,
          value: c['overridable'] == true,
          onChanged: (v) => n.edit((d) {
            final x = item(d);
            if (v) {
              x['overridable'] = true;
            } else {
              x['overridable'] = false;
              x.remove('options_from');
            }
          }),
        ),
        if (c['overridable'] == true)
          PropBlock(
            child: FormulaField(
              key: ValueKey('$path.options_from'),
              label: l10n.cfgbOptionsFrom,
              helper: l10n.cfgbOptionsFromHelp,
              value: str(c['options_from']) ?? '',
              context: FormulaContext(d, scope),
              enabled: !s.readOnly,
              serverProblems: s.formulaProblems('$path.options_from'),
              onChanged: (v) => set('options_from', v),
            ),
          ),
        PropSwitch(
          label: l10n.cfgbShow,
          value: c['show'] != false,
          onChanged: (v) => n.edit((d) {
            final x = item(d);
            if (v) {
              x.remove('show');
            } else {
              x['show'] = false;
            }
          }),
        ),
        PropBlock(
          child: PropText(
            label: l10n.cfgbHelp,
            value: str(c['help']) ?? '',
            onChanged: (v) => set('help', v),
          ),
        ),
        PropRow(
          children: [
            PropNumber(
              label: l10n.cfgbOrder,
              value: layout['order'],
              integer: true,
              width: 100,
              onChanged: (v) => n.edit((d) {
                final x = item(d);
                final lo = mutableMap(x, 'layout');
                setProp(lo, 'order', v);
                if (lo.isEmpty) x.remove('layout');
              }),
            ),
          ],
        ),
        TranslationsEditor(
          value: c['translations'],
          onChanged: (v) => set('translations', v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Output rules
// ---------------------------------------------------------------------------------------------

String _rulePathKey(List<int> p) => p.join('.');

/// Output rules as a tree: top-level rules with their option lines (children).
class OutputsTab extends ConsumerWidget {
  const OutputsTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final selected = s.rulePath != null && d.rule(s.rulePath!) != null
        ? s.rulePath
        : null;
    final readOnly = s.readOnly;

    final rows = <Widget>[];
    void walk(List<Json> rules, List<int> prefix) {
      for (final (i, r) in rules.indexed) {
        final path = [...prefix, i];
        final key = _rulePathKey(path);
        final isSel = selected != null && _rulePathKey(selected) == key;
        final hasErr = s.errorsAt(_jsonPath(path)).isNotEmpty;
        final code = str(r['code_template']) ?? str(r['code']) ?? '';
        rows.add(
          Material(
            key: ValueKey('rule-$key'),
            color: isSel
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            child: InkWell(
              onTap: () => n.selectRule(path),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.0 + prefix.length * 20, 6, 4, 6),
                child: Row(
                  children: [
                    Icon(
                      prefix.isEmpty ? AppIcons.rule : AppIcons.subdirectory,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(r['id']) ?? '',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          Text(
                            [
                              if (prefix.isEmpty) str(r['scope']) ?? 'project',
                              code,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (hasErr)
                      Icon(
                        AppIcons.error,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                    if (!readOnly) ...[
                      IconButton(
                        tooltip: l10n.cfgbMoveUp,
                        icon: const Icon(AppIcons.arrowUpward, size: 18),
                        onPressed: i == 0
                            ? null
                            : () {
                                n.edit(
                                  (d) => moveInList(
                                    d.ruleSiblings(path),
                                    i,
                                    i - 1,
                                  ),
                                );
                                n.selectRule([...prefix, i - 1]);
                              },
                      ),
                      IconButton(
                        tooltip: l10n.cfgbMoveDown,
                        icon: const Icon(AppIcons.arrowDownward, size: 18),
                        onPressed: i == rules.length - 1
                            ? null
                            : () {
                                n.edit(
                                  (d) => moveInList(
                                    d.ruleSiblings(path),
                                    i,
                                    i + 1,
                                  ),
                                );
                                n.selectRule([...prefix, i + 1]);
                              },
                      ),
                      IconButton(
                        key: ValueKey('add-child-$key'),
                        tooltip: l10n.cfgbAddChild,
                        icon: const Icon(AppIcons.addCircle, size: 18),
                        onPressed: () {
                          final children = jsonList(r, 'children').length;
                          n.edit((d) {
                            final id = DefinitionDraft.freeName(
                              'option',
                              d.allRuleIds(),
                            );
                            mutableList(
                              d.rule(path)!,
                              'children',
                            ).add(<String, Object?>{'id': id, 'code': ''});
                          });
                          n.selectRule([...path, children]);
                        },
                      ),
                      IconButton(
                        tooltip: l10n.remove,
                        icon: const Icon(AppIcons.delete, size: 18),
                        onPressed: () {
                          n.edit((d) {
                            d.ruleSiblings(path).removeAt(i);
                            if (prefix.isEmpty) {
                              dropEmpty(d.json, 'outputs');
                            } else {
                              dropEmpty(d.rule(prefix)!, 'children');
                            }
                          });
                          n.selectRule(null);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        walk(jsonList(r, 'children'), path);
      }
    }

    walk(d.outputs(), const []);
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.cfgbOutputRules),
        ...rows,
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('add-rule'),
              onPressed: () {
                final count = d.outputs().length;
                n.edit((d) {
                  final id = DefinitionDraft.freeName('line', d.allRuleIds());
                  mutableList(
                    d.json,
                    'outputs',
                  ).add(<String, Object?>{'id': id, 'code': ''});
                });
                n.selectRule([count]);
              },
              icon: const Icon(AppIcons.add),
              label: Text(l10n.cfgbAddRule),
            ),
          ),
      ],
    );
    final detail = selected == null
        ? Text(l10n.cfgbSelectRule)
        : RuleEditor(
            key: ValueKey('rule-${_rulePathKey(selected)}-${s.navigation}'),
            id: id,
            path: selected,
          );
    return MasterDetail(master: master, detail: detail, masterWidth: 420);
  }
}

String _jsonPath(List<int> rule) {
  final b = StringBuffer(
    r'$.outputs['
    '${rule.first}]',
  );
  for (final i in rule.skip(1)) {
    b.write('.children[$i]');
  }
  return b.toString();
}

String scopeLabel(AppLocalizations l10n, String s) => switch (s) {
  'group' => l10n.cfgbScopeGroup,
  'item' => l10n.cfgbScopeItem,
  _ => l10n.cfgbScopeProject,
};

/// The editor of one output rule.
class RuleEditor extends ConsumerWidget {
  const RuleEditor({super.key, required this.id, required this.path});
  final String id;
  final List<int> path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final r = d.rule(path);
    if (r == null) return const SizedBox.shrink();
    final top = path.length == 1;
    final jp = _jsonPath(path);
    final ctx = FormulaContext(d, d.ruleScope(path), inRule: true);
    void set(String key, Object? v) =>
        n.edit((d) => setProp(d.rule(path)!, key, v));
    String? err(String prop) {
      final e = s.errorsAt('$jp.$prop');
      return e.isEmpty ? null : e.first.message;
    }

    Widget formula(
      String prop,
      String label, {
      bool template = false,
      String? helper,
      int maxLines = 1,
    }) => PropBlock(
      child: FormulaField(
        key: ValueKey('$jp.$prop'),
        label: label,
        helper: helper,
        template: template,
        maxLines: maxLines,
        value: str(r[prop]) ?? '',
        context: ctx,
        enabled: !s.readOnly,
        serverProblems: s.formulaProblems('$jp.$prop'),
        onChanged: (v) => set(prop, v),
      ),
    );

    final codeMode = r.containsKey('code_template') ? 'template' : 'expr';
    final tables = d.itemTableNames();
    return Column(
      key: const ValueKey('rule-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          top
              ? l10n.cfgbRuleTitle(str(r['id']) ?? '')
              : l10n.cfgbChildRuleTitle(str(r['id']) ?? ''),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ProblemsBox(
          messages: [
            for (final e in s.errors)
              if (e.path == jp) e.message,
          ],
        ),
        PropRow(
          children: [
            PropText(
              key: const ValueKey('rule-id'),
              label: l10n.cfgbId,
              value: str(r['id']) ?? '',
              width: 200,
              monospace: true,
              errorText: err('id'),
              highlight: s.focusProperty == 'id',
              onChanged: (v) => n.edit((d) => d.rule(path)!['id'] = v),
            ),
            PropText(
              label: l10n.cfgbLabel,
              value: str(r['label']) ?? '',
              width: 260,
              onChanged: (v) => set('label', v),
            ),
          ],
        ),
        if (top)
          PropRow(
            children: [
              PropDropdown<String>(
                key: const ValueKey('rule-scope'),
                label: l10n.cfgbScope,
                value: str(r['scope']) ?? 'project',
                width: 180,
                items: {
                  for (final x in ['project', 'group', 'item'])
                    x: scopeLabel(l10n, x),
                },
                onChanged: (v) => n.edit((d) {
                  final x = d.rule(path)!;
                  setProp(x, 'scope', v == 'project' ? null : v);
                  if (v != 'item') x.remove('table');
                }),
              ),
              if (r['scope'] == 'item' && tables.length > 1)
                PropDropdown<String>(
                  label: l10n.cfgbItemTable,
                  value: str(r['table']),
                  allowNone: true,
                  width: 180,
                  items: {for (final t in tables) t: t},
                  onChanged: (v) => set('table', v),
                ),
            ],
          ),
        formula('when', l10n.cfgbWhen, helper: l10n.cfgbWhenHelp),
        formula('for_each', l10n.cfgbForEach, helper: l10n.cfgbForEachHelp),
        PropBlock(
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'expr', label: Text(l10n.cfgbCodeExpr)),
              ButtonSegment(
                value: 'template',
                label: Text(l10n.cfgbCodeTemplate),
              ),
            ],
            selected: {codeMode},
            onSelectionChanged: s.readOnly
                ? null
                : (sel) => n.edit((d) {
                    final x = d.rule(path)!;
                    if (sel.first == 'template') {
                      x.remove('code');
                      x['code_template'] = '';
                    } else {
                      x.remove('code_template');
                      x['code'] = '';
                    }
                  }),
          ),
        ),
        if (codeMode == 'template')
          formula(
            'code_template',
            l10n.cfgbCodeTemplate,
            template: true,
            helper: l10n.cfgbCodeTemplateHelp,
          )
        else
          formula('code', l10n.cfgbCode, helper: l10n.cfgbCodeHelp),
        formula('quantity', l10n.cfgbQuantity, helper: l10n.cfgbQuantityHelp),
        formula('description', l10n.cfgbDescriptionTemplate, template: true),
        formula('comment', l10n.cfgbCommentTemplate, template: true),
        formula(
          'section',
          l10n.cfgbSectionTemplate,
          template: true,
          helper: l10n.cfgbSectionTemplateHelp,
        ),
        PropSwitch(
          label: l10n.cfgbMergeIdentical,
          subtitle: l10n.cfgbMergeIdenticalHelp,
          value: r['merge_identical'] == true,
          onChanged: (v) => n.edit((d) {
            final x = d.rule(path)!;
            if (v) {
              x['merge_identical'] = true;
            } else if (x.containsKey('merge_identical')) {
              x['merge_identical'] = false;
            }
          }),
        ),
        if (!top) ...[
          formula(
            'percent_of_parent',
            l10n.cfgbPercentOfParent,
            helper: l10n.cfgbPercentOfParentHelp,
          ),
          PropRow(
            children: [
              PropDropdown<String>(
                label: l10n.cfgbPercentBase,
                value: str(r['percent_base']),
                allowNone: true,
                width: 260,
                items: {
                  'parent_list_unit_price': l10n.cfgbPercentBaseList,
                  'parent_net_unit_price': l10n.cfgbPercentBaseNet,
                },
                onChanged: (v) => set('percent_base', v),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Validations
// ---------------------------------------------------------------------------------------------

String severityLabel(AppLocalizations l10n, String s) => switch (s) {
  'error' => l10n.cfgbSeverityError,
  'info' => l10n.cfgbSeverityInfo,
  _ => l10n.cfgbSeverityWarning,
};

class ValidationsTab extends ConsumerWidget {
  const ValidationsTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final list = d.validations();
    final index = s.validationIndex != null && s.validationIndex! < list.length
        ? s.validationIndex
        : null;
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.cfgbValidations),
        EditableList(
          listKey: 'validations',
          titles: [for (final v in list) str(v['id']) ?? ''],
          subtitles: [
            for (final v in list)
              '${str(v['severity']) ?? ''} · ${str(v['when']) ?? ''}',
          ],
          selected: index,
          errorAt: (i) => s.errorsAt('\$.validations[$i]').isNotEmpty,
          onSelect: n.selectValidation,
          onReorder: (from, to) {
            n.edit(
              (d) => moveInList(mutableList(d.json, 'validations'), from, to),
            );
            n.selectValidation(to);
          },
          addLabel: l10n.cfgbAddValidation,
          onAdd: () {
            n.edit((d) {
              final ids = [for (final v in d.validations()) str(v['id']) ?? ''];
              mutableList(d.json, 'validations').add(<String, Object?>{
                'id': DefinitionDraft.freeName('check', ids),
                'when': '',
                'severity': 'warning',
                'message': '',
              });
            });
            n.selectValidation(list.length);
          },
          onRemove: (i) {
            n.edit((d) {
              mutableList(d.json, 'validations').removeAt(i);
              dropEmpty(d.json, 'validations');
            });
            n.selectValidation(null);
          },
        ),
      ],
    );
    final detail = index == null
        ? Text(l10n.cfgbSelectValidation)
        : _ValidationEditor(
            key: ValueKey('validation-$index-${s.navigation}'),
            id: id,
            index: index,
          );
    return MasterDetail(master: master, detail: detail);
  }
}

class _ValidationEditor extends ConsumerWidget {
  const _ValidationEditor({super.key, required this.id, required this.index});
  final String id;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final list = d.validations();
    if (index >= list.length) return const SizedBox.shrink();
    final v = list[index];
    final jp = '\$.validations[$index]';
    Json item(DefinitionDraft d) =>
        asJson(mutableList(d.json, 'validations')[index]);
    void set(String key, Object? x) => n.edit((d) => setProp(item(d), key, x));
    final scope = d.scopeOf(v['scope'], v['table']);
    final ctx = FormulaContext(d, scope);
    final tables = d.itemTableNames();
    final scopeFields = [
      for (final f in jsonList(d.readScope(scope), 'fields'))
        str(f['name']) ?? '',
      for (final c in jsonList(d.readScope(scope), 'computed'))
        str(c['name']) ?? '',
    ];
    String? err(String prop) {
      final e = s.errorsAt('$jp.$prop');
      return e.isEmpty ? null : e.first.message;
    }

    return Column(
      key: const ValueKey('validation-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.cfgbValidationTitle(str(v['id']) ?? ''),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ProblemsBox(
          messages: [
            for (final e in s.errors)
              if (e.path == jp) e.message,
          ],
        ),
        PropRow(
          children: [
            PropText(
              label: l10n.cfgbId,
              value: str(v['id']) ?? '',
              width: 200,
              monospace: true,
              errorText: err('id'),
              highlight: s.focusProperty == 'id',
              onChanged: (x) => n.edit((d) => item(d)['id'] = x),
            ),
            PropDropdown<String>(
              label: l10n.cfgbSeverity,
              value: str(v['severity']) ?? 'warning',
              width: 160,
              items: {
                for (final x in ['error', 'warning', 'info'])
                  x: severityLabel(l10n, x),
              },
              onChanged: (x) =>
                  n.edit((d) => item(d)['severity'] = x ?? 'warning'),
            ),
          ],
        ),
        PropRow(
          children: [
            PropDropdown<String>(
              label: l10n.cfgbScope,
              value: str(v['scope']) ?? 'project',
              width: 180,
              items: {
                for (final x in ['project', 'group', 'item'])
                  x: scopeLabel(l10n, x),
              },
              onChanged: (x) => n.edit((d) {
                final it = item(d);
                setProp(it, 'scope', x == 'project' ? null : x);
                if (x != 'item') it.remove('table');
              }),
            ),
            if (v['scope'] == 'item' && tables.length > 1)
              PropDropdown<String>(
                label: l10n.cfgbItemTable,
                value: str(v['table']),
                allowNone: true,
                width: 180,
                items: {for (final t in tables) t: t},
                onChanged: (x) => set('table', x),
              ),
            PropDropdown<String>(
              label: l10n.cfgbShownAt,
              value: str(v['field']),
              allowNone: true,
              width: 200,
              items: {for (final f in scopeFields) f: f},
              onChanged: (x) => set('field', x),
            ),
          ],
        ),
        PropBlock(
          child: FormulaField(
            key: ValueKey('$jp.when'),
            label: l10n.cfgbWhen,
            helper: l10n.cfgbValidationWhenHelp,
            value: str(v['when']) ?? '',
            context: ctx,
            enabled: !s.readOnly,
            serverProblems: s.formulaProblems('$jp.when'),
            onChanged: (x) => n.edit((d) => item(d)['when'] = x),
          ),
        ),
        PropBlock(
          child: FormulaField(
            key: ValueKey('$jp.message'),
            label: l10n.cfgbMessage,
            template: true,
            value: str(v['message']) ?? '',
            context: ctx,
            enabled: !s.readOnly,
            serverProblems: s.formulaProblems('$jp.message'),
            onChanged: (x) => n.edit((d) => item(d)['message'] = x),
          ),
        ),
        TranslationsEditor(
          value: v['translations'],
          plain: true,
          onChanged: (x) => set('translations', x),
        ),
      ],
    );
  }
}
