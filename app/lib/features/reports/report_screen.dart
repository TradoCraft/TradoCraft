import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/csv_transfer.dart';
import 'report_result_view.dart';
import 'reports_page.dart';

/// Rows fetched per request.
const reportPageSize = 100;

/// An export error from a binary download: the server's message is in the body, as bytes.
String exportErrorMessage(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is List<int>) {
      try {
        final j = jsonDecode(utf8.decode(d));
        if (j is Map && j['message'] is String) return j['message'] as String;
      } catch (_) {}
    }
  }
  return errorMessage(e);
}

/// File name for an export of a report: letters and digits only.
String reportFileBase(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'report' : s;
}

/// The `as_of` query value (`YYYY-MM-DD`) for a date the server returned.
String asOfParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The export URL of a saved report. `asOf` is the day of the result on screen: the file then
/// resolves relative dates like the table did, even after midnight. Omitted without a result.
String exportPath(String id, String format, DateTime? asOf) =>
    '/api/v1/custom-reports/$id/export?format=$format'
    '${asOf == null ? '' : '&as_of=${asOfParam(asOf)}'}';

/// Runs a saved report and shows it, with CSV and PDF export.
class SavedReportScreen extends ConsumerStatefulWidget {
  const SavedReportScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<SavedReportScreen> createState() => _SavedReportScreenState();
}

class _SavedReportScreenState extends ConsumerState<SavedReportScreen> {
  SavedReport? _report;
  ReportRunResult? _result;
  Object? _error;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider).reports;
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final report = await api.reportsGet(id: widget.id);
      if (!mounted) return;
      setState(() => _report = report);
      final result = await api.reportsRun(
        id: widget.id,
        limit: reportPageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _more() async {
    final current = _result;
    if (current == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ref
          .read(apiProvider)
          .reports
          .reportsRun(
            id: widget.id,
            limit: reportPageSize,
            offset: current.rows.length,
            // The day the first page resolved relative dates against: one run, one range.
            asOf: asOfParam(current.asOf),
          );
      if (!mounted) return;
      setState(() {
        _result = ReportRunResult(
          asOf: current.asOf,
          columns: current.columns,
          rows: [...current.rows, ...next.rows],
          total: next.total,
          chart: current.chart,
          totals: current.totals,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _export(String format) async {
    final report = _report;
    if (report == null) return;
    final messenger = ScaffoldMessenger.of(context);
    // Read before awaiting: the screen may be gone when the download finishes.
    final saveCsv = ref.read(csvSaverProvider);
    final dio = ref.read(dioProvider);
    try {
      final bytes = Uint8List.fromList(
        await downloadBytes(dio, exportPath(widget.id, format, _result?.asOf)),
      );
      final base = reportFileBase(report.name);
      if (format == 'pdf') {
        await Printing.layoutPdf(
          name: '$base.pdf',
          onLayout: (_) async => bytes,
        );
      } else {
        await saveCsv('$base.csv', bytes);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(exportErrorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.crDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.crDelete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).reports.reportsDelete(id: widget.id),
      success: l.crDeleted,
    );
    if (ok && mounted) {
      ref.invalidate(savedReportsProvider);
      context.go('/reports');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final report = _report;
    final canChange =
        report != null &&
        (report.mine || can(ref, 'users.admin')) &&
        can(ref, 'reports.write');
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.go('/reports'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                report?.name ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (report != null)
                Chip(
                  avatar: Icon(
                    report.shared ? AppIcons.people : AppIcons.lock,
                    size: 16,
                  ),
                  label: Text(report.shared ? l.crShared : l.crPrivate),
                ),
              if (report != null)
                OutlinedButton.icon(
                  key: const ValueKey('export-csv'),
                  icon: const Icon(AppIcons.fileDownload),
                  label: Text(l.crExportCsv),
                  onPressed: () => _export('csv'),
                ),
              if (report != null)
                OutlinedButton.icon(
                  key: const ValueKey('export-pdf'),
                  icon: const Icon(AppIcons.pictureAsPdf),
                  label: Text(l.crExportPdf),
                  onPressed: () => _export('pdf'),
                ),
              if (canChange)
                OutlinedButton.icon(
                  key: const ValueKey('edit-report'),
                  icon: const Icon(AppIcons.edit),
                  label: Text(l.edit),
                  onPressed: () => context.go('/reports/${widget.id}/edit'),
                ),
              if (canChange)
                OutlinedButton.icon(
                  key: const ValueKey('delete-report'),
                  icon: const Icon(AppIcons.delete),
                  label: Text(l.crDelete),
                  onPressed: _delete,
                ),
            ],
          ),
          if (report != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (report.description.isNotEmpty) report.description,
                l.crOwnedBy(report.ownerName),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage(_error!)),
                TextButton(onPressed: _load, child: Text(l.retry)),
              ],
            )
          else if (_result == null)
            const Center(child: CircularProgressIndicator())
          else
            ReportResultView(
              result: _result!,
              onLoadMore: _more,
              loadingMore: _loadingMore,
            ),
        ],
      ),
    );
  }
}
