import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/csv_transfer.dart' show shareCsvFile;
import '../definition.dart';
import '../runner_screen.dart';
import '../runner_state.dart';
import '../widgets/field_widgets.dart';
import '../widgets/panels.dart';
import 'common.dart';
import 'draft.dart';
import 'editor_state.dart';

// ---------------------------------------------------------------------------------------------
// JSON files
// ---------------------------------------------------------------------------------------------

typedef PickedFile = ({String name, Uint8List bytes});

/// Lets the person choose a JSON file; null when cancelled. Replaced in tests.
final jsonPickerProvider = Provider<Future<PickedFile?> Function()>(
  (_) => () async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  },
);

/// Saves or shares a JSON file; false when cancelled. Replaced in tests.
final jsonSaverProvider = Provider<Future<bool> Function(String, Uint8List)>(
  (_) => (filename, bytes) async {
    final file = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: filename,
    );
    if (kIsWeb) {
      await file.saveTo(filename);
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return shareCsvFile(file, filename);
      default:
        final target = await getSaveLocation(suggestedName: filename);
        if (target == null) return false;
        await file.saveTo(target.path);
        return true;
    }
  },
);

/// Reads a chosen file as an export (`{format, model, definition}`) or a bare definition.
/// Returns the definition, or throws a [FormatException].
Object? definitionFromFile(Uint8List bytes) {
  final v = jsonDecode(utf8.decode(bytes));
  if (v is! Map) throw const FormatException('not a JSON object');
  if (v.containsKey('definition')) return v['definition'];
  if (v.containsKey('name') || v.containsKey('project')) return v;
  throw const FormatException('no definition in this file');
}

// ---------------------------------------------------------------------------------------------
// General
// ---------------------------------------------------------------------------------------------

/// Name, description and translations of the definition, and the layout sections of the form.
class GeneralTab extends ConsumerWidget {
  const GeneralTab({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final n = ref.read(revisionEditorProvider(id).notifier);
    final d = s.draft!;
    final l10n = context.l10n;
    final sections = d.sections();
    final readOnly = s.readOnly;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProblemsBox(
          messages: [
            for (final e in s.errors)
              if (locate(e.path).tab == EditorTab.general)
                '${e.path}: ${e.message}',
          ],
        ),
        PropBlock(
          child: PropText(
            label: l10n.name,
            value: d.name,
            highlight: s.focusProperty == 'name',
            onChanged: (v) => n.edit((d) => d.json['name'] = v),
          ),
        ),
        PropBlock(
          child: PropText(
            label: l10n.description,
            value: str(d.json['description']) ?? '',
            maxLines: 4,
            onChanged: (v) => n.edit((d) => setProp(d.json, 'description', v)),
          ),
        ),
        TranslationsEditor(
          value: d.json['translations'],
          onChanged: (v) => n.edit((d) => setProp(d.json, 'translations', v)),
        ),
        const Divider(height: 32),
        SectionTitle(l10n.cfgbLayoutSections),
        Text(
          l10n.cfgbLayoutSectionsHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final (i, sec) in sections.indexed)
          Padding(
            key: ValueKey('section-$i'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                PropText(
                  label: l10n.name,
                  value: str(sec['name']) ?? '',
                  width: 180,
                  monospace: true,
                  onChanged: (v) => n.edit(
                    (d) =>
                        asJson(mutableList(d.json, 'sections')[i])['name'] = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PropText(
                    label: l10n.cfgbLabel,
                    value: str(sec['label']) ?? '',
                    onChanged: (v) => n.edit(
                      (d) =>
                          asJson(mutableList(d.json, 'sections')[i])['label'] =
                              v,
                    ),
                  ),
                ),
                if (!readOnly) ...[
                  IconButton(
                    tooltip: l10n.cfgbMoveUp,
                    icon: const Icon(AppIcons.arrowUpward, size: 18),
                    onPressed: i == 0
                        ? null
                        : () => n.edit(
                            (d) => moveInList(
                              mutableList(d.json, 'sections'),
                              i,
                              i - 1,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: l10n.remove,
                    icon: const Icon(AppIcons.delete, size: 18),
                    onPressed: () => n.edit((d) {
                      mutableList(d.json, 'sections').removeAt(i);
                      dropEmpty(d.json, 'sections');
                    }),
                  ),
                ],
              ],
            ),
          ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => n.edit((d) {
                final names = [
                  for (final x in d.sections()) str(x['name']) ?? '',
                ];
                mutableList(d.json, 'sections').add(<String, Object?>{
                  'name': DefinitionDraft.freeName('section', names),
                  'label': '',
                });
              }),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.cfgbAddSection),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Import / export
// ---------------------------------------------------------------------------------------------

/// Export to a JSON file, import a file into this draft, and the definition as raw JSON.
class TransferTab extends ConsumerStatefulWidget {
  const TransferTab({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TransferTab> createState() => _TransferTabState();
}

class _TransferTabState extends ConsumerState<TransferTab> {
  final _json = TextEditingController();
  int _shownVersion = -1;
  String? _jsonError;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final s = ref.read(revisionEditorProvider(widget.id));
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ex = await ref
          .read(apiProvider)
          .configurator
          .exportRevision(id: widget.id);
      // The definition as it is in the editor, unsaved changes included.
      final doc = {
        ...ex.toJson(),
        'model': ex.model.toJson(),
        'definition': s.draft!.toJson(),
      };
      final name =
          '${ex.model.code.toLowerCase()}-r${s.revision!.revision}.json';
      final saved = await ref.read(jsonSaverProvider)(
        name,
        Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(doc)),
        ),
      );
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.cfgbExported(name))),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _import() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final f = await ref.read(jsonPickerProvider)();
    if (f == null) return;
    try {
      final def = definitionFromFile(f.bytes);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.cfgbImportReplace(f.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.cfgbReplace),
            ),
          ],
        ),
      );
      if (ok != true) return;
      ref
          .read(revisionEditorProvider(widget.id).notifier)
          .replaceDefinition(def);
      messenger.showSnackBar(SnackBar(content: Text(l10n.cfgbImported)));
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.cfgbImportFailed(e.message))),
      );
    }
  }

  void _apply() {
    try {
      final v = jsonDecode(_json.text);
      if (v is! Map) throw const FormatException('not a JSON object');
      ref.read(revisionEditorProvider(widget.id).notifier).replaceDefinition(v);
      setState(() => _jsonError = null);
    } on FormatException catch (e) {
      setState(() => _jsonError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(revisionEditorProvider(widget.id));
    final l10n = context.l10n;
    if (_shownVersion != s.version) {
      _shownVersion = s.version;
      _json.text = const JsonEncoder.withIndent('  ').convert(s.draft!.json);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('export-json'),
              onPressed: _export,
              icon: const Icon(AppIcons.fileDownload),
              label: Text(l10n.cfgbExportJson),
            ),
            if (!s.readOnly)
              FilledButton.tonalIcon(
                key: const ValueKey('import-json'),
                onPressed: _import,
                icon: const Icon(AppIcons.fileUpload),
                label: Text(l10n.cfgbImportJson),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle(
          l10n.cfgbRawJson,
          trailing: s.readOnly
              ? null
              : TextButton(onPressed: _apply, child: Text(l10n.cfgbApply)),
        ),
        TextField(
          key: const ValueKey('raw-json'),
          controller: _json,
          readOnly: s.readOnly,
          minLines: 12,
          maxLines: 40,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _jsonError,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Test: the runner against the saved draft
// ---------------------------------------------------------------------------------------------

/// The runner's form and panels against the saved revision, with inputs kept here only (nothing
/// is saved as a configuration). Unsaved changes of the editor need a save first.
class TestTab extends ConsumerStatefulWidget {
  const TestTab({super.key, required this.id});
  final String id;

  /// Pause after a change before evaluating (shorter in tests).
  static Duration debounce = const Duration(milliseconds: 300);

  @override
  ConsumerState<TestTab> createState() => _TestTabState();
}

class _TestTabState extends ConsumerState<TestTab>
    with SingleTickerProviderStateMixin
    implements RunnerActions {
  late final _tabs = TabController(length: 3, vsync: this);
  final _focus = FieldFocus();
  CfgDefinition? _def;
  int _defVersion = -1;
  RunnerInputs _inputs = const RunnerInputs();
  Evaluation? _evaluation;
  String? _error;
  bool _evaluating = false;
  Map<String, String> _units = const {};
  List<int>? _selected;
  Timer? _timer;
  int _seq = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// (Re)starts from the saved definition: the required rows, then one evaluation.
  void _reset(EditorState s) {
    final def = CfgDefinition(s.revision!.definition);
    var inputs = const RunnerInputs();
    for (final t in def.itemTables) {
      final n = t.initialRows;
      for (var i = 0; i < n; i++) {
        inputs = inputs.addRow(t.name);
      }
    }
    _def = def;
    _inputs = inputs;
    _evaluation = null;
    _selected = null;
    Future.microtask(_evaluate);
  }

  void _changed(RunnerInputs inputs) {
    setState(() => _inputs = inputs);
    _timer?.cancel();
    _timer = Timer(TestTab.debounce, _evaluate);
  }

  Future<void> _evaluate() async {
    if (!mounted) return;
    final seq = ++_seq;
    setState(() => _evaluating = true);
    try {
      final e = await ref
          .read(apiProvider)
          .configurator
          .evaluateRevision(
            id: widget.id,
            body: _inputs.toApi(),
            language: Localizations.localeOf(context).languageCode,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _evaluation = e;
        _error = null;
        _evaluating = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = errorMessage(e);
        _evaluating = false;
      });
    }
  }

  EvalIndex get _index => EvalIndex(_evaluation);

  @override
  void setValue(FieldRef ref, Object? value) =>
      _changed(_inputs.set(ref, value));

  @override
  void addRow(String table, [InputRow initial = const {}]) =>
      _changed(_inputs.addRow(table, initial));

  @override
  void duplicateRow(String table, int row) =>
      _changed(_inputs.duplicateRow(table, row));

  @override
  void deleteRow(String table, int row) =>
      _changed(_inputs.deleteRow(table, row));

  @override
  void bulkSet(
    String table,
    String name,
    Object? value, {
    Iterable<int>? rows,
  }) => _changed(_inputs.bulkSet(table, name, value, rows: rows));

  @override
  void pin(FieldRef ref, Object? value) {
    final current = _index[ref];
    final calculated = current?.calculated ?? current?.value;
    if (calculated != null && sameValue(value, calculated)) {
      _changed(_inputs.unpin(ref));
    } else {
      _changed(_inputs.pin(ref.pin(value, calculated)));
    }
  }

  @override
  void unpin(FieldRef ref) => _changed(_inputs.unpin(ref));

  @override
  void setDisplayUnit(String key, String unit) =>
      setState(() => _units = {..._units, key: unit});

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(revisionEditorProvider(widget.id));
    final n = ref.read(revisionEditorProvider(widget.id).notifier);
    final l10n = context.l10n;
    // The saved definition changed (a save or an activation): start again.
    final savedVersion = s.revision!.updatedAt.microsecondsSinceEpoch;
    if (_defVersion != savedVersion) {
      _defVersion = savedVersion;
      _reset(s);
    }
    final def = _def!;
    final view = RunnerView(
      definition: def,
      inputs: _inputs,
      index: _index,
      actions: this,
      displayUnits: _units,
      focus: _focus,
    );
    final lines = _evaluation?.lines ?? const <Line>[];
    final issues = _evaluation?.issues ?? const <Issue>[];
    final selected = _selected == null ? null : lineAt(lines, _selected!);
    final panels = Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '${l10n.cfgIssues} (${issues.length})'),
            Tab(text: l10n.cfgLines),
            Tab(text: l10n.cfgWhy),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              IssuesPanel(
                issues: issues,
                onTap: (i) {
                  final r = FieldRef.ofIssue(i);
                  if (r != null) _focus.focus(r);
                },
              ),
              LinesPanel(
                lines: lines,
                selected: _selected,
                onSelect: (p) {
                  setState(() => _selected = p);
                  _tabs.animateTo(2);
                },
              ),
              WhyPanel(line: selected),
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.dirty || s.errors.isNotEmpty)
          MaterialBanner(
            leading: const Icon(AppIcons.info),
            content: Text(
              s.errors.isNotEmpty
                  ? l10n.cfgbTestNeedsValid
                  : l10n.cfgbTestUnsaved,
            ),
            actions: [
              if (s.dirty && !s.readOnly)
                TextButton(
                  onPressed: s.busy ? null : n.save,
                  child: Text(l10n.save),
                ),
              const SizedBox.shrink(),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cfgbTestHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('test-reset'),
                onPressed: () => setState(() => _reset(s)),
                icon: const Icon(AppIcons.refresh),
                label: Text(l10n.cfgbTestReset),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: _evaluating
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox.shrink(),
        ),
        if (_error != null)
          Container(
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(8),
            child: Text(l10n.cfgEvalFailed(_error!)),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 1000
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: RunnerForm(view: view)),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 420, child: panels),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(flex: 3, child: RunnerForm(view: view)),
                      const Divider(height: 1),
                      Expanded(flex: 2, child: panels),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
