import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import 'report_draft.dart';
import 'report_result_view.dart';
import 'reports_page.dart';

/// The words for a summary (or "show the value" when null).
String summaryLabel(AppLocalizations l, ReportSummary? s) => switch (s) {
  null => l.crSummaryNone,
  ReportSummary.count => l.crSumCount,
  ReportSummary.sum => l.crSumSum,
  ReportSummary.avg => l.crSumAvg,
  ReportSummary.min => l.crSumMin,
  ReportSummary.max => l.crSumMax,
  _ => s.json ?? '',
};

/// The words for a filter operator.
String operatorLabel(AppLocalizations l, ReportOp op) => switch (op) {
  ReportOp.eq => l.crOpEq,
  ReportOp.ne => l.crOpNe,
  ReportOp.gt => l.crOpGt,
  ReportOp.gte => l.crOpGte,
  ReportOp.lt => l.crOpLt,
  ReportOp.lte => l.crOpLte,
  ReportOp.contains => l.crOpContains,
  ReportOp.startsWith => l.crOpStartsWith,
  ReportOp.valueIn => l.crOpIn,
  ReportOp.isNull => l.crOpIsNull,
  ReportOp.notNull => l.crOpNotNull,
  _ => op.json ?? '',
};

/// The words for a date bucket.
String bucketLabel(AppLocalizations l, ReportBucket? b) => switch (b) {
  null => l.crBucketNone,
  ReportBucket.day => l.crBucketDay,
  ReportBucket.month => l.crBucketMonth,
  ReportBucket.year => l.crBucketYear,
  _ => b.json ?? '',
};

/// The words for a chart kind.
String chartKindLabel(AppLocalizations l, ReportChartKind? k) => switch (k) {
  null => l.crChartNone,
  ReportChartKind.bar => l.crChartBar,
  ReportChartKind.line => l.crChartLine,
  ReportChartKind.pie => l.crChartPie,
  _ => k.json ?? '',
};

/// The words for a relative date token.
String relativeLabel(AppLocalizations l, String token) => switch (token) {
  'today' => l.crRelToday,
  'yesterday' => l.crRelYesterday,
  'this_week' => l.crRelThisWeek,
  'last_week' => l.crRelLastWeek,
  'this_month' => l.crRelThisMonth,
  'last_month' => l.crRelLastMonth,
  'this_quarter' => l.crRelThisQuarter,
  'last_quarter' => l.crRelLastQuarter,
  'this_year' => l.crRelThisYear,
  'last_year' => l.crRelLastYear,
  'last_n_days' => l.crRelLastNDays,
  'next_n_days' => l.crRelNextNDays,
  _ => token,
};

bool _isDate(ReportFieldType? t) =>
    t == ReportFieldType.date || t == ReportFieldType.datetime;

/// [keys] without repeats (the first of each key stays), so a dropdown never has two items
/// with the same value.
List<OutputKey> _uniqueKeys(List<OutputKey> keys) {
  final seen = <String>{};
  return [
    for (final k in keys)
      if (seen.add(k.key)) k,
  ];
}

/// Builds a report, or changes the one with [id]: what it is about, its columns, filters,
/// grouping and chart, with a preview of the result and the choice to share it.
class ReportBuilderPage extends ConsumerStatefulWidget {
  const ReportBuilderPage({super.key, this.id});

  /// The saved report to change, or null to build a new one.
  final String? id;

  @override
  ConsumerState<ReportBuilderPage> createState() => _ReportBuilderPageState();
}

class _ReportBuilderPageState extends ConsumerState<ReportBuilderPage> {
  ReportCatalog? _catalog;
  ReportDraft? _draft;
  Object? _loadError;
  ReportRunResult? _preview;
  Object? _previewError;
  bool _busy = false;
  bool _saving = false;

  /// Counts draft changes; a preview that was requested at an older revision is dropped.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider).reports;
    setState(() => _loadError = null);
    try {
      final catalog = await api.reportsCatalog();
      ReportDraft draft;
      if (widget.id != null) {
        draft = ReportDraft.from(await api.reportsGet(id: widget.id!));
      } else if (catalog.objects.isNotEmpty) {
        draft = ReportDraft(object: catalog.objects.first.name);
      } else {
        throw StateError('no objects');
      }
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _draft = draft;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  // --- edits -------------------------------------------------------------------------------

  void _edit(VoidCallback change) => setState(() {
    change();
    _normalize();
  });

  /// Keeps the draft consistent: summaries that fit the field and the grouping, no chart or sort
  /// that points at something that is gone.
  void _normalize() {
    final catalog = _catalog!;
    final d = _draft!;
    final names = d.included;
    final fields = catalog.fieldsOf(names).map((f) => f.name).toSet();
    d.columns.removeWhere((c) => !fields.contains(c.field));
    d.filters.removeWhere((f) => !fields.contains(f.field));
    d.groups.removeWhere((g) => !fields.contains(g.field));
    for (final c in d.columns) {
      final f = catalog.field(c.field);
      if (f == null) continue;
      final allowed = summariesFor(f, grouped: d.grouped);
      if (!allowed.contains(c.summary)) c.summary = allowed.first;
    }
    for (final f in d.filters) {
      final field = catalog.field(f.field);
      if (field == null) continue;
      if (!operatorsFor(field.type).contains(f.op)) {
        f.op = operatorsFor(field.type).first;
      }
      if (!_isDate(field.type) || !relativeAllowedFor(f.op)) f.relative = null;
    }
    for (final g in d.groups) {
      if (!_isDate(catalog.field(g.field)?.type)) g.bucket = null;
    }
    final keys = d.outputKeys(catalog).map((k) => k.key).toSet();
    d.sorts.removeWhere((s) => !keys.contains(s.column));
    final groupKeys = d.groupKeys(catalog).map((k) => k.key).toList();
    final summaryKeys = d.summaryKeys(catalog).map((k) => k.key).toList();
    if (!d.grouped || summaryKeys.isEmpty) {
      d.chartKind = null;
    }
    if (d.chartKind != null) {
      if (!groupKeys.contains(d.chartX)) d.chartX = groupKeys.first;
      if (!summaryKeys.contains(d.chartY)) d.chartY = summaryKeys.first;
    }
    _revision++;
    _preview = null;
    _previewError = null;
  }

  void _changeObject(String name) => _edit(() {
    final d = _draft!;
    d.object = name;
    d.joins.clear();
    d.columns.clear();
    d.filters.clear();
    d.groups.clear();
    d.sorts.clear();
    d.chartKind = null;
  });

  ReportCatalogField _firstField({
    bool groupable = false,
    bool filterable = false,
  }) {
    final all = _catalog!.fieldsOf(_draft!.included);
    return all.firstWhere(
      (f) =>
          (!groupable || (!f.countOnly && f.type != ReportFieldType.number)) &&
          (!filterable || !f.countOnly),
      orElse: () => all.first,
    );
  }

  // --- actions -----------------------------------------------------------------------------

  Future<void> _run() async {
    final l = context.l10n;
    final d = _draft!;
    if (d.columns.isEmpty) {
      setState(() {
        _preview = null;
        _previewError = l.crNeedColumn;
      });
      return;
    }
    if (d.hasInvalidRelative) {
      setState(() {
        _preview = null;
        _previewError = l.crRelativeDaysInvalid;
      });
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _previewError = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .reports
          .reportsRunDefinition(
            body: ReportRunRequest(
              definition: d.toDefinition(_catalog!),
              limit: 50,
            ),
          );
      if (mounted && revision == _revision) setState(() => _preview = r);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _preview = null;
          _previewError = errorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _saving) return;
    final l = context.l10n;
    final d = _draft!;
    final messenger = ScaffoldMessenger.of(context);
    // A new message replaces the one still showing instead of queueing behind it.
    if (d.name.trim().isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.crNeedName)));
      return;
    }
    if (d.columns.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.crNeedColumn)));
      return;
    }
    if (d.hasInvalidRelative) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.crRelativeDaysInvalid)));
      return;
    }
    final input = SavedReportInput(
      name: d.name.trim(),
      description: d.description.trim(),
      shared: d.shared,
      definition: d.toDefinition(_catalog!),
    );
    final api = ref.read(apiProvider).reports;
    SavedReport? saved;
    setState(() => _saving = true);
    final bool ok;
    try {
      ok = await runAction(context, () async {
        saved = widget.id == null
            ? await api.reportsCreate(body: input)
            : await api.reportsUpdate(id: widget.id!, body: input);
      }, success: l.crSaved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (ok && saved != null && mounted) {
      ref.invalidate(savedReportsProvider);
      context.go('/reports/${saved!.id}');
    }
  }

  // --- building blocks ---------------------------------------------------------------------

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
    Key? key,
  }) {
    final shown = items.any((i) => i.$1 == value) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: key,
          isExpanded: true,
          isDense: true,
          value: shown,
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.$1,
                child: Text(i.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }

  String _fieldTitle(ReportCatalogField f) {
    final multi = _draft!.joins.isNotEmpty;
    if (!multi) return f.label;
    final object = _catalog!.objectNamed(f.name.split('.').first)?.label ?? '';
    return '$object: ${f.label}';
  }

  Widget _fieldDropdown({
    required String label,
    required String value,
    required List<ReportCatalogField> fields,
    required ValueChanged<String> onChanged,
    Key? key,
  }) => _dropdown<String>(
    key: key,
    label: label,
    value: value,
    items: [for (final f in fields) (f.name, _fieldTitle(f))],
    onChanged: onChanged,
  );

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _row(
    List<Widget> children, {
    required VoidCallback onRemove,
    Key? key,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final c in children) ...[
          Expanded(child: c),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: context.l10n.remove,
          onPressed: onRemove,
          icon: const Icon(AppIcons.close),
        ),
      ],
    ),
  );

  Widget _filterValue(DraftFilter f, ReportCatalogField? field) {
    final l = context.l10n;
    if (f.op == ReportOp.isNull || f.op == ReportOp.notNull) {
      return const SizedBox.shrink();
    }
    final type = field?.type;
    // A list of values is typed, whatever the type of the field.
    if (f.op == ReportOp.valueIn) return _plainValue(f, type);
    if (type == ReportFieldType.valueBool) {
      return _dropdown<String>(
        label: l.crValue,
        value: f.value.isEmpty ? 'true' : f.value,
        items: [('true', l.yes), ('false', l.no)],
        onChanged: (v) => _edit(() => f.value = v),
      );
    }
    if (_isDate(type)) {
      final picker = _datePicker(f);
      if (!relativeAllowedFor(f.op)) return picker;
      final relative = f.relative != null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dropdown<bool>(
            key: ObjectKey('mode-${identityHashCode(f)}'),
            label: l.crDateMode,
            value: relative,
            items: [(false, l.crDateFixed), (true, l.crDateRelative)],
            onChanged: (v) => _edit(() => f.relative = v ? 'today' : null),
          ),
          const SizedBox(height: 8),
          if (!relative)
            picker
          else ...[
            _dropdown<String>(
              label: l.crRelativePeriod,
              value: f.relative!,
              items: [for (final t in relativeTokens) (t, relativeLabel(l, t))],
              onChanged: (v) => _edit(() => f.relative = v),
            ),
            if (f.relativeNeedsDays) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: ObjectKey(f),
                initialValue: f.days,
                decoration: InputDecoration(
                  labelText: l.crRelativeDays,
                  errorText: f.relativeInvalid ? l.crRelativeDaysInvalid : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => setState(() {
                  f.days = v;
                  _revision++;
                  _preview = null;
                  _previewError = null;
                }),
              ),
            ],
          ],
        ],
      );
    }
    return _plainValue(f, type);
  }

  Widget _datePicker(DraftFilter f) {
    final l = context.l10n;
    {
      return OutlinedButton.icon(
        icon: const Icon(AppIcons.calendarToday),
        label: Text(f.value.isEmpty ? l.crValue : f.value),
        onPressed: () async {
          final now = DateTime.now();
          final initial = DateTime.tryParse(f.value) ?? now;
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked == null || !mounted) return;
          String two(int n) => n.toString().padLeft(2, '0');
          _edit(
            () => f.value =
                '${picked.year}-${two(picked.month)}-${two(picked.day)}',
          );
        },
      );
    }
  }

  Widget _plainValue(DraftFilter f, ReportFieldType? type) {
    final l = context.l10n;
    return TextFormField(
      key: ValueKey('${identityHashCode(f)}-${f.field}'),
      initialValue: f.value,
      decoration: InputDecoration(
        labelText: l.crValue,
        hintText: f.op == ReportOp.valueIn ? l.crValueListHint : null,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: type == ReportFieldType.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      // The value is read when the report runs; the preview is stale from here on.
      onChanged: (v) {
        f.value = v;
        _revision++;
        if (_preview != null || _previewError != null) {
          setState(() {
            _preview = null;
            _previewError = null;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = _draft;
    final catalog = _catalog;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.go(
                  widget.id == null ? '/reports' : '/reports/${widget.id}',
                ),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                widget.id == null ? l.crNew : l.edit,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          if (_loadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage(_loadError!)),
                TextButton(onPressed: _load, child: Text(l.retry)),
              ],
            )
          else if (d == null || catalog == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: _form(d, catalog),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(ReportDraft d, ReportCatalog catalog) {
    final l = context.l10n;
    final fields = catalog.fieldsOf(d.included);
    final groupable = [
      for (final f in fields)
        if (!f.countOnly && f.type != ReportFieldType.number) f,
    ];
    final filterable = [
      for (final f in fields)
        if (!f.countOnly) f,
    ];
    final outputs = _uniqueKeys(d.outputKeys(catalog));
    final joinable = catalog.joinable(d.included);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('report-name'),
          initialValue: d.name,
          decoration: InputDecoration(
            labelText: l.name,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => d.name = v,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: d.description,
          decoration: InputDecoration(
            labelText: l.description,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => d.description = v,
        ),
        SwitchListTile(
          key: const ValueKey('report-shared'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.crShare),
          value: d.shared,
          onChanged: (v) => setState(() => d.shared = v),
        ),
        _section(l.crObject, [
          _dropdown<String>(
            key: const ValueKey('report-object'),
            label: l.crObject,
            value: d.object,
            items: [for (final o in catalog.objects) (o.name, o.label)],
            onChanged: _changeObject,
          ),
          if (d.joins.isNotEmpty || joinable.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final j in d.joins)
                  InputChip(
                    label: Text(catalog.objectNamed(j)?.label ?? j),
                    onDeleted: () => _edit(() => d.joins.remove(j)),
                  ),
                for (final o in joinable)
                  ActionChip(
                    key: ValueKey('join-${o.name}'),
                    avatar: const Icon(AppIcons.add, size: 16),
                    label: Text('${l.crJoin}: ${o.label}'),
                    onPressed: () => _edit(() => d.joins.add(o.name)),
                  ),
              ],
            ),
          ],
        ]),
        _section(l.crGroupBy, [
          for (var i = 0; i < d.groups.length; i++)
            _row(key: ValueKey('group-$i'), [
              _fieldDropdown(
                label: l.crField,
                value: d.groups[i].field,
                fields: groupable,
                onChanged: (v) => _edit(() => d.groups[i].field = v),
              ),
              if (_isDate(catalog.field(d.groups[i].field)?.type))
                _dropdown<ReportBucket?>(
                  label: l.crBucketNone,
                  value: d.groups[i].bucket,
                  items: [
                    for (final b in <ReportBucket?>[
                      null,
                      ReportBucket.day,
                      ReportBucket.month,
                      ReportBucket.year,
                    ])
                      (b, bucketLabel(l, b)),
                  ],
                  onChanged: (v) => _edit(() => d.groups[i].bucket = v),
                ),
            ], onRemove: () => _edit(() => d.groups.removeAt(i))),
          if (d.groups.length < 3 && groupable.isNotEmpty)
            TextButton.icon(
              key: const ValueKey('add-group'),
              icon: const Icon(AppIcons.add),
              label: Text(l.crAddGrouping),
              onPressed: () => _edit(
                () =>
                    d.groups.add(DraftGroup(_firstField(groupable: true).name)),
              ),
            ),
        ]),
        _section(l.crColumns, [
          for (var i = 0; i < d.columns.length; i++)
            _row(key: ValueKey('column-$i'), [
              _fieldDropdown(
                label: l.crField,
                value: d.columns[i].field,
                fields: fields,
                onChanged: (v) => _edit(() => d.columns[i].field = v),
              ),
              _dropdown<ReportSummary?>(
                label: l.crSummary,
                value: d.columns[i].summary,
                items: [
                  for (final s in summariesFor(
                    catalog.field(d.columns[i].field) ?? fields.first,
                    grouped: d.grouped,
                  ))
                    (s, summaryLabel(l, s)),
                ],
                onChanged: (v) => _edit(() => d.columns[i].summary = v),
              ),
            ], onRemove: () => _edit(() => d.columns.removeAt(i))),
          TextButton.icon(
            key: const ValueKey('add-column'),
            icon: const Icon(AppIcons.add),
            label: Text(l.crAddColumn),
            onPressed: () => _edit(() {
              final taken = d.outputKeys(catalog).map((k) => k.key).toSet();
              DraftColumn? pick;
              for (final f in fields) {
                for (final s in summariesFor(f, grouped: d.grouped)) {
                  final key = s == null ? f.name : '${f.name}:${s.json}';
                  if (!taken.contains(key)) {
                    pick = DraftColumn(f.name, s);
                    break;
                  }
                }
                if (pick != null) break;
              }
              if (pick == null) {
                final f = _firstField();
                pick = DraftColumn(
                  f.name,
                  summariesFor(f, grouped: d.grouped).first,
                );
              }
              d.columns.add(pick);
            }),
          ),
        ]),
        _section(l.crFilters, [
          for (var i = 0; i < d.filters.length; i++)
            _row(key: ValueKey('filter-$i'), [
              _fieldDropdown(
                label: l.crField,
                value: d.filters[i].field,
                fields: filterable,
                onChanged: (v) => _edit(() {
                  d.filters[i].field = v;
                  d.filters[i].value = '';
                  d.filters[i].relative = null;
                }),
              ),
              _dropdown<ReportOp>(
                label: l.crFilters,
                value: d.filters[i].op,
                items: [
                  for (final op in operatorsFor(
                    catalog.field(d.filters[i].field)?.type ??
                        ReportFieldType.text,
                  ))
                    (op, operatorLabel(l, op)),
                ],
                onChanged: (v) => _edit(() => d.filters[i].op = v),
              ),
              _filterValue(d.filters[i], catalog.field(d.filters[i].field)),
            ], onRemove: () => _edit(() => d.filters.removeAt(i))),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: const ValueKey('add-filter'),
                icon: const Icon(AppIcons.add),
                label: Text(l.crAddFilter),
                onPressed: () => _edit(() {
                  final f = _firstField(filterable: true);
                  d.filters.add(
                    DraftFilter(f.name, operatorsFor(f.type).first),
                  );
                }),
              ),
              if (d.filters.length > 1)
                SegmentedButton<ReportLogic>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ReportLogic.and,
                      label: Text(l.crMatchAll),
                    ),
                    ButtonSegment(
                      value: ReportLogic.or,
                      label: Text(l.crMatchAny),
                    ),
                  ],
                  selected: {d.logic},
                  onSelectionChanged: (s) => _edit(() => d.logic = s.first),
                ),
            ],
          ),
        ]),
        _section(l.crSort, [
          for (var i = 0; i < d.sorts.length; i++)
            _row(key: ValueKey('sort-$i'), [
              _dropdown<String>(
                label: l.crSort,
                value: d.sorts[i].column,
                items: [
                  for (final k in outputs)
                    (
                      k.key,
                      k.key.contains(':')
                          ? '${k.label} (${k.key.split(':').last})'
                          : k.label,
                    ),
                ],
                onChanged: (v) => _edit(() => d.sorts[i].column = v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l.crDescending),
                value: d.sorts[i].descending,
                onChanged: (v) =>
                    _edit(() => d.sorts[i].descending = v ?? false),
              ),
            ], onRemove: () => _edit(() => d.sorts.removeAt(i))),
          if (d.sorts.length < 5 &&
              outputs.any((k) => !d.sorts.any((s) => s.column == k.key)))
            TextButton.icon(
              key: const ValueKey('add-sort'),
              icon: const Icon(AppIcons.add),
              label: Text(l.crAddSort),
              onPressed: () => _edit(() {
                final used = d.sorts.map((s) => s.column).toSet();
                d.sorts.add(
                  DraftSort(
                    outputs.firstWhere((k) => !used.contains(k.key)).key,
                  ),
                );
              }),
            ),
        ]),
        if (d.grouped && d.summaryKeys(catalog).isNotEmpty)
          _section(l.crChart, [
            _dropdown<ReportChartKind?>(
              key: const ValueKey('chart-kind'),
              label: l.crChart,
              value: d.chartKind,
              items: [
                for (final k in <ReportChartKind?>[
                  null,
                  ReportChartKind.bar,
                  ReportChartKind.line,
                  ReportChartKind.pie,
                ])
                  (k, chartKindLabel(l, k)),
              ],
              onChanged: (v) => _edit(() => d.chartKind = v),
            ),
            if (d.chartKind != null) ...[
              const SizedBox(height: 8),
              _dropdown<String?>(
                label: l.crChartX,
                value: d.chartX,
                items: [
                  for (final k in _uniqueKeys(d.groupKeys(catalog)))
                    (k.key, k.label),
                ],
                onChanged: (v) => _edit(() => d.chartX = v),
              ),
              const SizedBox(height: 8),
              _dropdown<String?>(
                label: l.crChartY,
                value: d.chartY,
                items: [
                  for (final k in _uniqueKeys(d.summaryKeys(catalog)))
                    (k.key, '${k.label} (${k.key.split(':').last})'),
                ],
                onChanged: (v) => _edit(() => d.chartY = v),
              ),
            ],
          ]),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('run-report'),
              icon: const Icon(AppIcons.playArrow),
              label: Text(l.crRun),
              onPressed: _busy ? null : _run,
            ),
            FilledButton.icon(
              key: const ValueKey('save-report'),
              icon: const Icon(AppIcons.save),
              label: Text(l.save),
              onPressed: _busy || _saving ? null : _save,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_previewError != null)
          Text(
            errorMessage(_previewError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_preview != null) ReportResultView(result: _preview!),
      ],
    );
  }
}
