
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/file_export.dart';
import 'price_lists_api.dart';

/// Result of one file of a generation: [path] when it was written to a folder, [error] when it
/// failed (the other files carry on).
class GeneratedFile {
  const GeneratedFile(this.entry, {this.path, this.error, this.cancelled = false});
  final ExportPlanEntry entry;
  final String? path;
  final String? error;

  /// The person cancelled the platform's save mechanism (browser or share sheet).
  final bool cancelled;
  bool get ok => error == null && !cancelled;
}

/// Renders [entries] one after the other with [render] and saves each under [baseFolder] (default:
/// Downloads) at its server-given `relative_path` through [export]. A file that fails is recorded
/// with its error and does not stop the rest. [onProgress] is called before each file with the
/// number already done.
Future<List<GeneratedFile>> generateFiles({
  required List<ExportPlanEntry> entries,
  required Future<Uint8List> Function(ExportPlanEntry entry) render,
  required FileExport export,
  String? baseFolder,
  void Function(int done, ExportPlanEntry next)? onProgress,
}) async {
  final out = <GeneratedFile>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    onProgress?.call(i, e);
    try {
      final bytes = await render(e);
      final r = await export.save(e.relativePath, bytes, baseFolder: baseFolder);
      out.add(GeneratedFile(e, path: r.path, cancelled: !r.saved));
    } catch (err) {
      out.add(GeneratedFile(e, error: errorMessage(err)));
    }
  }
  return out;
}

/// The plan entries grouped zone > language > file, in plan order.
class PlanZone {
  PlanZone(this.zoneId, this.zoneCode);
  final String zoneId;
  final String zoneCode;
  final languages = <String, List<int>>{};
}

/// Groups entry indexes by zone and language, keeping the order of the plan.
List<PlanZone> groupPlan(List<ExportPlanEntry> plan) {
  final zones = <String, PlanZone>{};
  for (var i = 0; i < plan.length; i++) {
    final e = plan[i];
    zones
        .putIfAbsent(e.zoneId, () => PlanZone(e.zoneId, e.zoneCode))
        .languages
        .putIfAbsent(e.lang, () => [])
        .add(i);
  }
  return zones.values.toList();
}

/// Lets the person choose a folder; null when cancelled. Replaced in tests.
typedef FolderPicker = Future<String?> Function();

final folderPickerProvider = Provider<FolderPicker>(
  (_) => () => getDirectoryPath(),
);

/// Whether the platform can write into a chosen folder (desktop).
bool get canChooseFolder =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The Generate dialog: pick the format, see the files the export profiles produce (zone >
/// language > profile, all ticked), generate them into the Downloads folder (or a chosen one) and
/// see a summary.
class GenerateDialog extends ConsumerStatefulWidget {
  const GenerateDialog({super.key, required this.list});
  final PriceList list;

  @override
  ConsumerState<GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends ConsumerState<GenerateDialog> {
  RenderFormat _format = RenderFormat.pdf;
  List<ExportPlanEntry>? _plan;
  Map<String, String> _profileNames = const {};
  Object? _loadError;
  final _selected = <int>{};
  String? _folder;
  bool _running = false;
  int _done = 0;
  ExportPlanEntry? _current;
  List<GeneratedFile>? _results;
  String? _usedFolder;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    setState(() {
      _plan = null;
      _loadError = null;
    });
    try {
      final products = ref.read(apiProvider).products;
      final plan = await products.getExportPlan(
        id: widget.list.id,
        format: _format,
      );
      final exports = await products.listExports(id: widget.list.id);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _profileNames = {for (final e in exports) e.id: e.name};
        _selected
          ..clear()
          ..addAll(List.generate(plan.length, (i) => i));
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _chooseFolder() async {
    final f = await ref.read(folderPickerProvider)();
    if (f != null && mounted) setState(() => _folder = f);
  }

  Future<void> _generate() async {
    final plan = _plan!;
    final picked = [for (final i in _selected.toList()..sort()) plan[i]];
    final dio = ref.read(dioProvider);
    final export = ref.read(fileExportProvider);
    final downloads = await ref.read(downloadsFolderProvider)();
    setState(() {
      _running = true;
      _done = 0;
      _results = null;
    });
    final results = await generateFiles(
      entries: picked,
      export: export,
      baseFolder: _folder,
      render: (e) => renderPriceList(
        dio,
        widget.list.id,
        zoneId: e.zoneId,
        lang: e.lang,
        format: e.format.json ?? _format.json!,
        exportId: e.exportId,
      ),
      onProgress: (done, next) {
        if (mounted) {
          setState(() {
            _done = done;
            _current = next;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _results = results;
      _usedFolder = _folder ?? downloads;
    });
  }

  String _profileLabel(ExportPlanEntry e) {
    final l = context.l10n;
    final id = e.exportId;
    return id == null ? l.plWholeList : (_profileNames[id] ?? id);
  }

  void _toggle(Iterable<int> indexes, bool on) => setState(
    () => on ? _selected.addAll(indexes) : _selected.removeAll(indexes),
  );

  bool? _state(List<int> indexes) {
    final n = indexes.where(_selected.contains).length;
    if (n == 0) return false;
    return n == indexes.length ? true : null;
  }

  Widget _tree() {
    final plan = _plan!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final z in groupPlan(plan)) ...[
          CheckboxListTile(
            key: ValueKey('plgen-zone-${z.zoneCode}'),
            dense: true,
            tristate: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(z.zoneCode, style: theme.textTheme.titleSmall),
            value: _state([for (final v in z.languages.values) ...v]),
            onChanged: _running
                ? null
                : (v) => _toggle([for (final x in z.languages.values) ...x], v == true),
          ),
          for (final lang in z.languages.entries) ...[
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: CheckboxListTile(
                key: ValueKey('plgen-lang-${z.zoneCode}-${lang.key}'),
                dense: true,
                tristate: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(languageName(lang.key)),
                value: _state(lang.value),
                onChanged: _running ? null : (v) => _toggle(lang.value, v == true),
              ),
            ),
            for (final i in lang.value)
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: CheckboxListTile(
                  key: ValueKey('plgen-file-$i'),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_profileLabel(plan[i])),
                  subtitle: Text(
                    plan[i].relativePath,
                    style: theme.textTheme.bodySmall,
                  ),
                  value: _selected.contains(i),
                  onChanged: _running ? null : (v) => _toggle([i], v == true),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _summary() {
    final l = context.l10n;
    final results = _results!;
    final failed = results.where((r) => r.error != null).toList();
    final written = results.where((r) => r.ok).length;
    final folder = _usedFolder;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('plgen-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.plGenSummary(written, results.length),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (folder != null && written > 0)
          SelectableText(l.plGenTargetFolder(folder))
        else if (written > 0)
          Text(l.plGenSentToBrowser),
        for (final r in failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${r.entry.relativePath}: ${r.error}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = _plan;
    final done = _results != null;
    final folder = _folder;
    return AlertDialog(
      title: Text(l.plGenerate),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<RenderFormat>(
                key: const ValueKey('plgen-format'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: RenderFormat.pdf,
                    icon: const Icon(AppIcons.pictureAsPdf),
                    label: Text(l.plGeneratePdf),
                  ),
                  ButtonSegment(
                    value: RenderFormat.xlsx,
                    icon: const Icon(AppIcons.tableChart),
                    label: Text(l.plGenerateXlsx),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: _running
                    ? null
                    : (s) {
                        _format = s.first;
                        _results = null;
                        _loadPlan();
                      },
              ),
              const SizedBox(height: 8),
              if (canChooseFolder)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        folder == null ? l.plGenDownloads : l.plGenTargetFolder(folder),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('plgen-folder'),
                      onPressed: _running ? null : _chooseFolder,
                      child: Text(l.plGenChooseFolder),
                    ),
                  ],
                ),
              const Divider(),
              if (_loadError != null)
                Row(
                  children: [
                    Expanded(child: Text(errorMessage(_loadError!))),
                    TextButton(
                      key: const ValueKey('plgen-retry'),
                      onPressed: _loadPlan,
                      child: Text(l.retry),
                    ),
                  ],
                )
              else if (plan == null)
                const LinearProgressIndicator()
              else if (plan.isEmpty)
                Text(l.plGenNothing, key: const ValueKey('plgen-empty'))
              else ...[
                if (!done) _tree(),
                if (_running) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    key: const ValueKey('plgen-progress'),
                    value: _selected.isEmpty ? null : _done / _selected.length,
                  ),
                  Text(
                    l.plGenProgress(
                      _done + 1 > _selected.length ? _selected.length : _done + 1,
                      _selected.length,
                      _current?.relativePath ?? '',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (done) _summary(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (done && _usedFolder != null && _results!.any((r) => r.ok))
          TextButton(
            key: const ValueKey('plgen-open'),
            onPressed: () => ref.read(pathOpenerProvider)(_usedFolder!),
            child: Text(l.plGenOpenFolder),
          ),
        if (done)
          TextButton(
            key: const ValueKey('plgen-again'),
            onPressed: () => setState(() => _results = null),
            child: Text(l.plGenBack),
          ),
        TextButton(
          key: const ValueKey('plgen-close'),
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(l.close),
        ),
        if (!done)
          FilledButton(
            key: const ValueKey('plgen-go'),
            onPressed: _running || plan == null || _selected.isEmpty
                ? null
                : _generate,
            child: Text(l.plGenerate),
          ),
      ],
    );
  }
}
