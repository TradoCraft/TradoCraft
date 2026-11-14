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

const _pageSize = 50;
// The API returns at most 200 rows per request.
const _maxLimit = 200;

/// The runs of the company, newest first.
class JobHistory extends ConsumerStatefulWidget {
  const JobHistory({super.key});

  @override
  ConsumerState<JobHistory> createState() => _JobHistoryState();
}

class _JobHistoryState extends ConsumerState<JobHistory> {
  int _limit = _pageSize;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// While a listed job is queued or running, asks again soon.
  void _follow(ImportJobPage page) {
    if (!page.items.any(jobIsActive)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(historyRefresh, () {
      _timer = null;
      if (mounted) ref.invalidate(importJobsProvider(_limit));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(importJobsProvider(_limit));
    // The previous page stays on screen while a refresh is under way.
    final page = async.value;
    if (page != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(page);
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
              onPressed: () => ref.invalidate(importJobsProvider(_limit)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (page == null && async.hasError)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                errorMessage(async.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                key: const ValueKey('imp-history-retry'),
                onPressed: () => ref.invalidate(importJobsProvider(_limit)),
                child: Text(l.retry),
              ),
            ],
          )
        else if (page == null)
          const LinearProgressIndicator()
        else if (page.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.impHistoryEmpty),
          )
        else ...[
          for (final j in page.items) _JobTile(job: j),
          if (page.total > page.items.length && _limit < _maxLimit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('imp-history-more'),
                  onPressed: () => setState(
                    () => _limit = (_limit + _pageSize).clamp(0, _maxLimit),
                  ),
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
    if (job != null) {
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
