import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/actions.dart';
import '../../../shared/app_icons.dart';
import 'imports_api.dart';
import 'job_widgets.dart';

/// How often the history and the detail of a job refresh while a job is queued or running.
const historyRefresh = Duration(seconds: 3);

/// The runs of the company, newest first.
class JobHistory extends ConsumerStatefulWidget {
  const JobHistory({super.key});

  @override
  ConsumerState<JobHistory> createState() => _JobHistoryState();
}

class _JobHistoryState extends ConsumerState<JobHistory> {
  // How many pages are shown: page `i` holds the jobs from offset `i * importJobsPageSize`.
  int _pages = 1;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Asks the loaded pages again.
  void _refresh() {
    for (var i = 0; i < _pages; i++) {
      ref.invalidate(importJobsProvider(i * importJobsPageSize));
    }
  }

  /// While a listed job is queued or running, asks again soon.
  void _follow(List<ImportJob> jobs) {
    if (!jobs.any(jobIsActive)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(historyRefresh, () {
      _timer = null;
      if (mounted) _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pages = [
      for (var i = 0; i < _pages; i++)
        ref.watch(importJobsProvider(i * importJobsPageSize)),
    ];
    // The previous data of a page stays on screen while a refresh is under way; the pages are
    // shown up to the first one that has nothing yet.
    final jobs = <ImportJob>[];
    var total = 0;
    AsyncValue<ImportJobPage>? pending;
    for (final p in pages) {
      final v = p.value;
      if (v == null) {
        pending = p;
        break;
      }
      jobs.addAll(v.items);
      total = v.total;
    }
    final first = pages.first.value;
    // Follow the jobs only once everything shown has settled: a page that is loading would be
    // asked again over its own request.
    if (first != null && pending == null && !pages.any((p) => p.isLoading)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(jobs);
      });
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.impHistory,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              key: const ValueKey('imp-history-refresh'),
              tooltip: l.impRefresh,
              icon: const Icon(AppIcons.refresh),
              onPressed: _refresh,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (first == null && pending!.hasError)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                errorMessage(pending.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                key: const ValueKey('imp-history-retry'),
                onPressed: _refresh,
                child: Text(l.retry),
              ),
            ],
          )
        else if (first == null)
          const LinearProgressIndicator()
        else if (jobs.isEmpty && pending == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.impHistoryEmpty),
          )
        else ...[
          for (final j in jobs) _JobTile(job: j),
          if (pending != null && pending.hasError)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  errorMessage(pending.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  key: const ValueKey('imp-history-retry'),
                  onPressed: _refresh,
                  child: Text(l.retry),
                ),
              ],
            )
          else if (pending != null)
            const LinearProgressIndicator()
          else if (total > jobs.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('imp-history-more'),
                  onPressed: () => setState(() => _pages++),
                  child: Text(l.loadMore),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final counts = job.status == 'done' && job.errorCount == 0
        ? (job.dryRun
              ? l.impCountsPlanned(job.created, job.updated, job.unchanged)
              : l.impCountsDone(job.created, job.updated, job.unchanged))
        : null;
    return Card(
      key: ValueKey('imp-job-${job.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showJobDetail(context, job.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.filename,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  entityLabel(l, job.entity),
                  job.dryRun ? l.impDryRun : l.impApplied,
                  formatWhen(context, job.createdAt),
                  if (job.requestedByName != null)
                    l.impJobBy(job.requestedByName!),
                ].join(' · '),
                style: muted,
              ),
              const SizedBox(height: 6),
              JobStatusChip(job: job),
              if (counts != null) Text(counts, style: muted),
              if (jobIsActive(job) && job.totalRows > 0) ...[
                const SizedBox(height: 6),
                JobProgress(job: job),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showJobDetail(BuildContext context, String id) => showDialog<void>(
  context: context,
  builder: (_) => _JobDetail(id: id),
);

/// One run in full: where it comes from, its progress or counts, the failure message, the
/// errors with the download of the report, and Cancel while it is queued.
class _JobDetail extends ConsumerStatefulWidget {
  const _JobDetail({required this.id});
  final String id;

  @override
  ConsumerState<_JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends ConsumerState<_JobDetail> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _follow(ImportJob job) {
    if (!jobIsActive(job)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(historyRefresh, () {
      _timer = null;
      if (mounted) ref.invalidate(importJobProvider(widget.id));
    });
  }

  Future<void> _cancel() async {
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).imports.cancelImportJob(id: widget.id),
    );
    // A 409 means the worker took it meanwhile; either way show what the job is now.
    if (!mounted) return;
    ref.invalidate(importJobProvider(widget.id));
    if (ok) ref.invalidate(importJobsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(importJobProvider(widget.id));
    final job = async.value;
    // Follow only a settled value: while a refresh is loading it would be asked again over it.
    if (job != null && !async.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(job);
      });
    }
    Widget row(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          );
    return AlertDialog(
      title: Text(l.impJobDetails),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: job == null
              ? (async.hasError
                    ? Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(errorMessage(async.error!)),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(importJobProvider(widget.id)),
                            child: Text(l.retry),
                          ),
                        ],
                      )
                    : const LinearProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.filename,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    row(l.impEntity, entityLabel(l, job.entity)),
                    row(l.impSheet, job.sheet),
                    row(l.status, job.dryRun ? l.impDryRun : l.impApplied),
                    if (job.requestedByName != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(l.impJobBy(job.requestedByName!)),
                      ),
                    row(l.date, formatWhen(context, job.createdAt)),
                    const SizedBox(height: 12),
                    JobOutcome(
                      job: job,
                      planned: job.dryRun,
                      onCancel: _cancel,
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
