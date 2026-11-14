import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import 'offline_queue.dart';
import '../../../shared/app_icons.dart';

final _stamp = DateFormat('dd/MM HH:mm');

/// "Offline: data from 07/11 09:12", shown above data that comes from the local copy.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key, required this.savedAt});
  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('offline-note'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(AppIcons.cloudOff, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.offlineDataFrom(_stamp.format(savedAt.toLocal())),
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the technician that a change was kept on the device.
void showQueuedSnack(BuildContext context) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(context.l10n.offlineQueuedMessage)));

String opLabel(QueuedOp o, AppLocalizations l) => switch (o.type) {
  OpType.start => l.offlineOpStart,
  OpType.taskDone =>
    o.payload['done'] == true ? l.offlineOpTaskDone : l.offlineOpTaskUndone,
  OpType.taskAdd => l.offlineOpTaskAdd,
  OpType.workLog => l.offlineOpWorkLog,
  OpType.partAdd => l.offlineOpPart,
  OpType.complete => l.offlineOpComplete,
  OpType.decline => l.offlineOpDecline,
  OpType.signature => l.offlineOpSignature,
  OpType.photo => l.offlineOpPhoto,
};

/// "N changes waiting to sync", for the jobs page (all jobs) and the job screen ([jobId]).
/// Hidden when nothing is waiting. Tap to see the list.
class PendingSyncBanner extends ConsumerWidget {
  const PendingSyncBanner({super.key, this.jobId});
  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(offlineQueueProvider);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final ops = jobId == null ? queue.ops : queue.forJob(jobId!);
        if (ops.isEmpty) return const SizedBox.shrink();
        final l = context.l10n;
        final scheme = Theme.of(context).colorScheme;
        final failed = ops.where((o) => o.failed).length;
        final color = failed > 0
            ? scheme.errorContainer
            : scheme.tertiaryContainer;
        final onColor = failed > 0
            ? scheme.onErrorContainer
            : scheme.onTertiaryContainer;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            key: const ValueKey('pending-sync-banner'),
            color: color,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showSyncQueue(context, jobId: jobId),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    queue.running
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: onColor,
                            ),
                          )
                        : Icon(
                            failed > 0
                                ? AppIcons.syncProblem
                                : AppIcons.cloudUpload,
                            size: 20,
                            color: onColor,
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          l.offlineWaiting(ops.length),
                          if (failed > 0) l.offlineFailedCount(failed),
                        ].join(' · '),
                        style: TextStyle(color: onColor),
                      ),
                    ),
                    Icon(AppIcons.chevronRight, color: onColor),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSyncQueue(BuildContext context, {String? jobId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SyncQueueSheet(jobId: jobId),
    );

/// The waiting changes, oldest first. Failed ones show the server's message and can be tried
/// again or discarded.
class SyncQueueSheet extends ConsumerWidget {
  const SyncQueueSheet({super.key, this.jobId});
  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(offlineQueueProvider);
    final l = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final ops = jobId == null ? queue.ops : queue.forJob(jobId!);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.offlineQueueTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.icon(
                        icon: const Icon(AppIcons.sync),
                        label: Text(l.offlineSyncNow),
                        onPressed: queue.running || ops.isEmpty
                            ? null
                            : () => unawaited(queue.process(force: true)),
                      ),
                    ],
                  ),
                ),
                if (ops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.offlineAllSynced),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in ops)
                          _OpTile(op: o, queue: queue, showJob: jobId == null),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OpTile extends StatelessWidget {
  const _OpTile({required this.op, required this.queue, required this.showJob});
  final QueuedOp op;
  final OfflineQueue queue;
  final bool showJob;

  Future<void> _discard(BuildContext context) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(l.offlineDiscardQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.offlineDiscard),
          ),
        ],
      ),
    );
    if (ok == true) await queue.discard(op.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[
      if (op.detail.isNotEmpty) op.detail,
      if (showJob && op.jobLabel.isNotEmpty) op.jobLabel,
      _stamp.format(op.createdAt.toLocal()),
    ];
    return ListTile(
      key: ValueKey('queued-${op.id}'),
      isThreeLine: op.failed,
      leading: Icon(
        op.failed ? AppIcons.error : AppIcons.schedule,
        color: op.failed ? scheme.error : null,
      ),
      title: Text(opLabel(op, l)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lines.join(' · ')),
          if (op.failed) ...[
            Text(l.offlineRejected, style: TextStyle(color: scheme.error)),
            if (op.lastError != null && op.lastError!.isNotEmpty)
              Text(
                l.offlineLastError(op.lastError!),
                style: TextStyle(color: scheme.error),
              ),
          ] else if (op.attempts > 0 && op.lastError != null)
            Text(
              '${l.offlineAttempts(op.attempts)} · ${l.offlineLastError(op.lastError!)}',
            ),
        ],
      ),
      trailing: op.failed
          ? Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => unawaited(queue.retry(op.id)),
                  child: Text(l.offlineRetry),
                ),
                TextButton(
                  onPressed: () => _discard(context),
                  child: Text(l.offlineDiscard),
                ),
              ],
            )
          : null,
    );
  }
}

/// Starts the periodic retry and the retry when the app comes back to the front. Put it once
/// around the signed-in part of the app. Without a connectivity plugin: a request that fails
/// without an answer is what tells us we are offline.
class OfflineSyncHost extends ConsumerStatefulWidget {
  const OfflineSyncHost({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 30),
  });
  final Widget child;
  final Duration interval;

  @override
  ConsumerState<OfflineSyncHost> createState() => _OfflineSyncHostState();
}

class _OfflineSyncHostState extends ConsumerState<OfflineSyncHost>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _sync());
    // The queue is read from disk now, and a first run follows once it is.
    scheduleMicrotask(_sync);
  }

  void _sync() {
    if (mounted) unawaited(ref.read(offlineQueueProvider).process());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
