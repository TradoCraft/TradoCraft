import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'csv_transfer.dart';

enum _Phase { idle, checking, preview, errors, importing, done }

/// Imports a CSV file: choose a file, dry run, preview (counts or row errors), import.
/// Pops `true` when records were written. Shared by the customers and products lists.
class CsvImportDialog extends ConsumerStatefulWidget {
  const CsvImportDialog({
    super.key,
    required this.entity,
    required this.importer,
    this.onImported,
  });

  /// Plural name of what is imported, for the title ("customers").
  final String entity;
  final CsvImporter importer;

  /// Runs once the real import has written records, even if the dialog was dismissed while it
  /// was in flight. Never called for a failed import or one that wrote nothing.
  final VoidCallback? onImported;

  @override
  ConsumerState<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends ConsumerState<CsvImportDialog> {
  static const _maxErrors = 100;

  _Phase _phase = _Phase.idle;
  String? _fileName;
  String? _csv;
  String? _problem;
  ImportReport? _report;

  bool get _busy => _phase == _Phase.checking || _phase == _Phase.importing;

  Future<void> _choose() async {
    if (_busy) return;
    final l = context.l10n;
    PickedCsv? file;
    try {
      file = await ref.read(csvPickerProvider)();
    } catch (_) {
      _fail(l.csvReadFailed);
      return;
    }
    if (file == null || !mounted) return;
    String text;
    try {
      text = decodeCsv(file.bytes);
    } on FormatException {
      _fail(l.csvNotUtf8, name: file.name);
      return;
    }
    if (text.trim().isEmpty) {
      _fail(l.csvEmptyFile, name: file.name);
      return;
    }
    setState(() {
      _fileName = file!.name;
      _csv = text;
      _problem = null;
      _report = null;
      _phase = _Phase.checking;
    });
    try {
      final r = await widget.importer(text, dryRun: true);
      if (!mounted) return;
      setState(() {
        _report = r;
        _phase = r.errors.isEmpty ? _Phase.preview : _Phase.errors;
      });
    } catch (e) {
      _fail(errorMessage(e), name: file.name);
    }
  }

  void _fail(String message, {String? name}) {
    if (!mounted) return;
    setState(() {
      _fileName = name ?? _fileName;
      _csv = null;
      _report = null;
      _problem = message;
      _phase = _Phase.idle;
    });
  }

  Future<void> _import() async {
    final csv = _csv;
    if (_phase != _Phase.preview || csv == null) return;
    setState(() => _phase = _Phase.importing);
    try {
      final r = await widget.importer(csv, dryRun: false);
      // Tied to completion of the write, not to the dialog still being on screen.
      if (r.errors.isEmpty && (r.created + r.updated) > 0) {
        widget.onImported?.call();
      }
      if (!mounted) return;
      setState(() {
        _report = r;
        _phase = r.errors.isEmpty ? _Phase.done : _Phase.errors;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = errorMessage(e);
        _phase = _Phase.preview;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final done = _phase == _Phase.done;
    final r = _report;
    final changed = done && r != null && (r.created + r.updated) > 0;
    return AlertDialog(
      title: Text(l.csvImportTitle(widget.entity)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_phase == _Phase.idle || _phase == _Phase.checking)
                Text(l.csvImportHelp),
              if (_fileName != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(AppIcons.attachFile, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _fileName!,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (_phase == _Phase.checking || _phase == _Phase.importing)
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _phase == _Phase.checking
                          ? l.csvChecking
                          : l.csvImporting,
                    ),
                  ],
                ),
              if (_problem != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (r != null && (_phase == _Phase.preview || done)) ...[
                Text(
                  done ? l.csvDone : l.csvPreview,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _Counts(report: r, done: done),
              ],
              if (r != null && _phase == _Phase.errors) _Errors(report: r),
            ],
          ),
        ),
      ),
      actions: [
        if (_phase == _Phase.idle ||
            _phase == _Phase.errors ||
            _phase == _Phase.preview)
          TextButton.icon(
            icon: const Icon(AppIcons.fileUpload),
            label: Text(
              _csv == null && _phase != _Phase.errors
                  ? l.csvChooseFile
                  : l.csvChooseOther,
            ),
            onPressed: _busy ? null : _choose,
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, changed),
          child: Text(done ? l.close : l.cancel),
        ),
        if (!done)
          FilledButton(
            onPressed: _phase == _Phase.preview ? _import : null,
            child: Text(l.csvImportAction),
          ),
      ],
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.report, required this.done});
  final ImportReport report;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget row(String label, int n) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$n', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
    return Column(
      children: [
        row(done ? l.csvCreated : l.csvToCreate, report.created),
        row(done ? l.csvUpdated : l.csvToUpdate, report.updated),
        row(l.csvUnchanged, report.unchanged),
      ],
    );
  }
}

class _Errors extends StatelessWidget {
  const _Errors({required this.report});
  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final shown = report.errors.take(_CsvImportDialogState._maxErrors).toList();
    final more = report.errors.length - shown.length;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(AppIcons.error, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.csvErrorsFound(report.errors.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in shown)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.message),
                  subtitle: Text(
                    e.column == null
                        ? l.csvErrorRow(e.row)
                        : l.csvErrorRowColumn(e.row, e.column!),
                  ),
                ),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.csvAndMore(more)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
