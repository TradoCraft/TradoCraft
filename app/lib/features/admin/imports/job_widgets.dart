import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/csv_transfer.dart';
import 'imports_api.dart';

/// Pieces that show an import job: its status, progress, counts and errors. Used by the check
/// and import steps of the wizard, the history and the detail of a job.

/// The label of the status of [j]; "done with N errors" is told apart from a clean "done".
String jobStatusLabel(AppLocalizations l, ImportJob j) => switch (j.status) {
  'queued' => l.impStatusQueued,
  'running' => l.impStatusRunning,
  'done' when j.errorCount > 0 => l.impStatusDoneErrors(j.errorCount),
  'done' => l.impStatusDone,
  'failed' => l.impStatusFailed,
  'cancelled' => l.impStatusCancelled,
  _ => j.status,
};

/// The name of the entity of a job or a menu entry.
String entityLabel(AppLocalizations l, String key) => switch (key) {
  'customers' => l.customers,
  'products' => l.products,
  _ => key,
};

String formatWhen(BuildContext context, DateTime t) =>
    DateFormat.yMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(t.toLocal());

/// An icon, a colour and a word per state, so the state does not rest on colour alone.
class JobStatusChip extends StatelessWidget {
  const JobStatusChip({super.key, required this.job});
  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (job.status) {
      'queued' => (AppIcons.schedule, scheme.onSurfaceVariant),
      'running' => (AppIcons.sync, scheme.primary),
      'done' when job.errorCount > 0 => (
        AppIcons.warningAmber,
        scheme.tertiary,
      ),
      'done' => (AppIcons.checkCircle, scheme.primary),
      'failed' => (AppIcons.error, scheme.error),
      _ => (AppIcons.cancel, scheme.onSurfaceVariant),
    };
    final label = jobStatusLabel(context.l10n, job);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String phaseLabel(AppLocalizations l, ImportJob j) => switch (j.phase) {
  'reading' => l.impPhaseReading,
  'validating' => l.impPhaseValidating,
  'writing' => l.impPhaseWriting,
  _ => jobStatusLabel(l, j),
};

/// Phase and progress bar of a job that is queued or running.
class JobProgress extends StatelessWidget {
  const JobProgress({super.key, required this.job});
  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final known = job.totalRows > 0;
    final text = [
      phaseLabel(l, job),
      if (known) l.impProgress(job.processedRows, job.totalRows),
    ].join(', ');
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: known
                  ? (job.processedRows / job.totalRows).clamp(0.0, 1.0)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Created, updated and unchanged: planned for a check, done for an import.
class JobCounts extends StatelessWidget {
  const JobCounts({super.key, required this.job, required this.planned});
  final ImportJob job;
  final bool planned;

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
        row(planned ? l.csvToCreate : l.csvCreated, job.created),
        row(planned ? l.csvToUpdate : l.csvUpdated, job.updated),
        row(l.csvUnchanged, job.unchanged),
      ],
    );
  }
}

/// Saves the error report of a job as CSV through the file saver.
Future<void> downloadErrorReport(
  BuildContext context,
  WidgetRef ref,
  ImportJob job,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final dio = ref.read(dioProvider);
  final saver = ref.read(csvSaverProvider);
  final name = 'import-errors-${job.id.split('-').first}.csv';
  try {
    final bytes = await downloadImportErrors(dio, job.id);
    final saved = await saver(name, bytes);
    if (saved) {
      messenger.showSnackBar(SnackBar(content: Text(l.csvExported(name))));
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.csvExportFailed(errorMessage(e)))),
    );
  }
}

/// The problems of a job (the server keeps the first 100 with the job), the total, and the
/// download of the full report.
class JobErrors extends ConsumerWidget {
  const JobErrors({super.key, required this.job});
  final ImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final shown = job.errors.take(100).toList();
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
                  l.csvErrorsFound(job.errorCount),
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
            ],
          ),
        ),
        if (job.errorCount > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.impErrorsTotal(shown.length, job.errorCount)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('imp-download-errors'),
          onPressed: () => downloadErrorReport(context, ref, job),
          icon: const Icon(AppIcons.fileDownload),
          label: Text(l.impDownloadErrors),
        ),
      ],
    );
  }
}

/// What a job shows by status: progress while it runs, the failure message, the errors of a
/// finished run, or its counts. [planned] = a check (nothing was written).
class JobOutcome extends StatelessWidget {
  const JobOutcome({
    super.key,
    required this.job,
    required this.planned,
    this.onCancel,
  });
  final ImportJob job;
  final bool planned;

  /// Offered while the job is queued.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JobStatusChip(job: job),
        const SizedBox(height: 8),
        if (jobIsActive(job)) ...[
          JobProgress(job: job),
          if (job.status == 'queued' && onCancel != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('imp-cancel-job'),
              onPressed: onCancel,
              icon: const Icon(AppIcons.cancel),
              label: Text(l.impCancelJob),
            ),
          ],
        ] else if (job.status == 'failed')
          Semantics(
            liveRegion: true,
            child: Text(
              job.message ?? l.impStatusFailed,
              style: TextStyle(color: scheme.error),
            ),
          )
        else if (job.status == 'done' && job.errorCount > 0)
          JobErrors(job: job)
        else if (job.status == 'done') ...[
          if (planned) Text(l.impCheckClean) else Text(l.csvDone),
          const SizedBox(height: 8),
          JobCounts(job: job, planned: planned),
        ],
      ],
    );
  }
}
