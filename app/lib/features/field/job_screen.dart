import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart' show date;
import '../../shared/photos.dart';
import 'job_extras.dart';
import 'job_form.dart';
import 'jobs_page.dart' show whenText;
import 'offline/job_cache.dart';
import 'offline/offline_queue.dart';
import 'offline/offline_ui.dart';
import 'offline/pending_overlay.dart';
import 'work_log_dialog.dart';
import '../../shared/app_icons.dart';
import '../../shared/load_failed.dart';
import '../todo/object_todos_button.dart';

final _stamp = DateFormat('dd/MM HH:mm');

/// One job, as the technician needs it on site: where to go, what to do, the checklist, time
/// and photos. Planners can also edit, cancel and reopen it.
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  /// The job as the server last told us (or the local copy); queued changes are laid over it
  /// when it is shown.
  JobDetail? _d;
  String? _error;
  bool _missing = false;
  bool _busy = false;

  /// Set while what is shown comes from the local copy because the server cannot be reached.
  DateTime? _offlineAt;
  StreamSubscription<AppliedOp>? _applied;
  final _newTask = TextEditingController();

  FieldClient get _field => ref.read(apiProvider).field;
  OfflineQueue get _queue => ref.read(offlineQueueProvider);
  String get _label => _d == null ? '' : '${_d!.job.number} ${_d!.job.title}';

  @override
  void initState() {
    super.initState();
    _applied = _queue.applied.listen(_onApplied);
    _load();
  }

  @override
  void dispose() {
    _applied?.cancel();
    _newTask.dispose();
    super.dispose();
  }

  void _setDetail(JobDetail d) {
    if (!mounted) return;
    setState(() {
      _d = d;
      _offlineAt = null;
      _error = null;
    });
    unawaited(ref.read(jobCacheProvider).saveDetail(d).catchError((_) {}));
  }

  /// A queued change reached the server: show the job as it answered.
  void _onApplied(AppliedOp a) {
    if (a.op.jobId != widget.id || !mounted) return;
    final m = a.detail;
    if (m != null) {
      try {
        _setDetail(JobDetail.fromJson(m));
        return;
      } catch (_) {}
    }
    _load();
  }

  Future<void> _load() async {
    try {
      _setDetail(await _field.getJob(id: widget.id));
    } catch (e) {
      if (!mounted) return;
      if (isNetworkError(e)) {
        if (_d != null) {
          setState(() => _offlineAt ??= DateTime.now());
          return;
        }
        final cached = await ref.read(jobCacheProvider).loadDetail(widget.id);
        if (cached != null && mounted) {
          setState(() {
            _d = cached.detail;
            _offlineAt = cached.savedAt;
          });
          return;
        }
      }
      if (mounted && _d == null) {
        setState(() {
          _error = errorMessage(e);
          _missing = errorStatus(e) == 404;
        });
      }
    }
  }

  /// Sends a technician write; with no connection it goes into the offline queue instead.
  /// Returns true when it was sent now, false when it was queued, null when it failed (the
  /// server's message is shown).
  Future<bool?> _write(
    OpType type, {
    required Future<JobDetail> Function() online,
    Map<String, Object?> payload = const {},
    String? id,
    String? entityId,
    Uint8List? data,
  }) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final d = await submitWrite(
        _queue,
        type: type,
        jobId: widget.id,
        jobLabel: _label,
        online: online,
        payload: payload,
        id: id,
        entityId: entityId,
        data: data,
      );
      if (d != null) {
        _setDetail(d);
        return true;
      }
      messenger.showSnackBar(SnackBar(content: Text(l.offlineQueuedMessage)));
      return false;
    } on QueueFullException {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.offlineTooLarge),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return null;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<JobDetail> Function() action) async {
    setState(() => _busy = true);
    JobDetail? d;
    final ok = await runAction(context, () async => d = await action());
    if (mounted) setState(() => _busy = false);
    if (ok && d != null && mounted) _setDetail(d!);
  }

  Future<void> _complete() async {
    final l = context.l10n;
    final view = _view(_d!);
    final notes = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CompleteDialog(done: view.job.tasksDone, total: view.job.tasksTotal),
    );
    if (notes == null || notes.isEmpty || !mounted) return;
    final sent = await _write(
      OpType.complete,
      payload: {'notes': notes},
      online: () => _field.completeJob(
        id: widget.id,
        body: CompleteInput(notes: notes),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saved)));
    }
  }

  /// The server's job with the waiting changes applied, so the work shows at once.
  JobDetail _view(JobDetail d) => applyPending(
    d,
    _queue.forJob(widget.id),
    userName: ref.read(meProvider).value?.displayName ?? '',
  );

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(url)));
      }
    }
  }

  Future<void> _addPhotos(List<PickedPhoto> photos) async {
    final dio = ref.read(dioProvider);
    for (final p in photos) {
      final id = newClientId();
      final ok = await _write(
        OpType.photo,
        id: id,
        payload: {'filename': p.filename, 'caption': ''},
        data: p.bytes,
        online: () async {
          final res = await uploadPhoto(
            dio,
            '/api/v1/field/jobs/${widget.id}/photos',
            p,
            clientId: id,
          );
          return JobDetail.fromJson(
            Map<String, dynamic>.from(res.data! as Map),
          );
        },
      );
      if (ok == null) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        body: _error != null
            ? LoadFailedView(
                message: _error!,
                leaveTo: '/jobs',
                notFound: _missing,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final queue = ref.watch(offlineQueueProvider);
    // Rebuild whenever something is queued, sent or fails.
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) => _body(context, _view(_d!)),
    );
  }

  Widget _body(BuildContext context, JobDetail d) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final queued = _queue.forJob(widget.id);
    final pending = pendingIds(queued);
    final addedOffline = {
      for (final o in queued)
        if (o.type == OpType.taskAdd) o.id,
    };
    final photosWaiting = queued.where((o) => o.type == OpType.photo).length;
    final j = d.job;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final planner = perms.contains('field.plan');
    final canWork = planner || perms.contains('field.work');
    final open = j.status == 'planned' || j.status == 'in_progress';

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () =>
                    context.canPop() ? context.pop(true) : context.go('/jobs'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Expanded(
                child: Text(
                  '${j.number}  ${j.title}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              ObjectTodosButton(
                kind: TodoLinkKind.job,
                id: j.id,
                label: j.number,
              ),
              IconButton(
                tooltip: l.offlineReload,
                onPressed: _load,
                icon: const Icon(AppIcons.refresh),
              ),
              Chip(label: Text(l.jobStatus(j.status))),
            ],
          ),
          if (_offlineAt != null) ...[
            OfflineNote(savedAt: _offlineAt!),
            const SizedBox(height: 8),
          ],
          PendingSyncBanner(jobId: widget.id),
          Text(
            '${j.customerName} · ${l.jobKind(j.kind)} · ${whenText(j, l)}',
            style: theme.textTheme.bodyMedium,
          ),
          if (j.contractNumber != null)
            Text(
              [
                l.contractLabel(j.contractNumber!),
                if (j.dueDate != null) l.dueOnDate(date(j.dueDate)),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          // Where to go
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.siteAddress, style: theme.textTheme.labelMedium),
                  if (j.siteName.isNotEmpty) Text(j.siteName),
                  SelectableText(j.address.isEmpty ? '—' : j.address),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (j.mapsUrl != null)
                        FilledButton.tonalIcon(
                          icon: const Icon(AppIcons.directions),
                          label: Text(l.navigate),
                          onPressed: () => _open(j.mapsUrl!),
                        ),
                      for (final p in d.contactPhones)
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.call),
                          label: Text(
                            '${j.contactName ?? l.onSiteContact} · ${p.number}',
                          ),
                          onPressed: () =>
                              _open('tel:${p.number.replaceAll(' ', '')}'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (j.instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.instructions, style: theme.textTheme.titleSmall),
            SelectableText(j.instructions),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canWork && j.status == 'planned')
                FilledButton.icon(
                  icon: const Icon(AppIcons.playArrow),
                  label: Text(l.startJob),
                  onPressed: _busy
                      ? null
                      : () => _write(
                          OpType.start,
                          online: () => _field.startJob(id: widget.id),
                        ),
                ),
              if (canWork && open)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.timer),
                  label: Text(l.logWork),
                  onPressed: _busy
                      ? null
                      : () async {
                          final r = await showWorkLogDialog(
                            context,
                            widget.id,
                            jobLabel: _label,
                          );
                          if (r != null) _setDetail(r);
                        },
                ),
              if (canWork && open)
                FilledButton.icon(
                  icon: const Icon(AppIcons.checkCircle),
                  label: Text(l.completeJob),
                  onPressed: _busy ? null : _complete,
                ),
              if (planner && open)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.edit),
                  label: Text(l.editJob),
                  onPressed: () async {
                    final r = await showJobForm(context, detail: d);
                    if (r != null) _setDetail(r);
                  },
                ),
              if (planner && open)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.cancel),
                  label: Text(l.cancelJob),
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await askText(
                            context,
                            title: l.cancelJob,
                            label: l.notes,
                          );
                          if (reason == null) return;
                          await _run(
                            () => _field.cancelJob(
                              id: widget.id,
                              body: ReasonInput(reason: reason),
                            ),
                          );
                        },
                ),
              if (planner && !open)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.undo),
                  label: Text(l.reopenJob),
                  onPressed: _busy
                      ? null
                      : () => _run(() => _field.reopenJob(id: widget.id)),
                ),
            ],
          ),
          if (j.completionNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.completionNotes, style: theme.textTheme.labelMedium),
            SelectableText(j.completionNotes),
          ],
          const Divider(height: 32),
          // The checklist
          Row(
            children: [
              Text(l.tasks, style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(l.tasksProgress('${j.tasksDone}', '${j.tasksTotal}')),
            ],
          ),
          for (final t in d.tasks)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: t.done,
              title: Text(
                t.description,
                style: t.done
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
              subtitle: t.done && t.doneByName != null
                  ? Text(t.doneByName!)
                  : null,
              secondary: pending.contains(t.id)
                  ? Tooltip(
                      message: l.offlinePendingSync,
                      child: const Icon(AppIcons.cloudUpload, size: 18),
                    )
                  : null,
              // A task added offline has no id on the server yet: tick it after it is synced.
              onChanged:
                  canWork && open && !_busy && !addedOffline.contains(t.id)
                  ? (v) => _write(
                      OpType.taskDone,
                      entityId: t.id,
                      payload: {
                        'done': v ?? false,
                        'description': t.description,
                      },
                      online: () => _field.setJobTaskDone(
                        id: widget.id,
                        taskId: t.id,
                        body: DoneInput(done: v ?? false),
                      ),
                    )
                  : null,
            ),
          if (canWork && open)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTask,
                    decoration: InputDecoration(labelText: l.addTask),
                    onSubmitted: (_) => _submitTask(),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.add,
                  onPressed: _submitTask,
                  icon: const Icon(AppIcons.add),
                ),
              ],
            ),
          const Divider(height: 32),
          // Time
          Row(
            children: [
              Text(l.workLogs, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                l.timeTotals(
                  minutesText(d.workMinutes),
                  minutesText(d.travelMinutes),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          for (final w in d.workLogs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                w.kind == 'travel' ? AppIcons.directionsCar : AppIcons.build,
                size: 20,
              ),
              trailing: pending.contains(w.id)
                  ? Tooltip(
                      message: l.offlinePendingSync,
                      child: const Icon(AppIcons.cloudUpload, size: 18),
                    )
                  : null,
              title: Text(
                '${minutesText(w.minutes)}${w.notes.isEmpty ? '' : ' — ${w.notes}'}',
              ),
              subtitle: Text(
                '${w.userName} · ${_stamp.format(w.startedAt.toLocal())}',
              ),
            ),
          const Divider(height: 32),
          JobExtras(
            detail: d,
            canWork: canWork,
            planner: planner,
            pending: pending,
            onChanged: _setDetail,
          ),
          const Divider(height: 32),
          PhotoGallery(
            photos: [
              for (final p in d.photos)
                PhotoItem(id: p.id, caption: p.caption, by: p.uploaderName),
            ],
            dio: ref.watch(dioProvider),
            pathFor: (id) => '/api/v1/field/jobs/${widget.id}/photos/$id',
            onAdd: canWork && j.status != 'cancelled' ? _addPhotos : null,
          ),
          if (photosWaiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(AppIcons.cloudUpload, size: 18),
                  const SizedBox(width: 6),
                  Text(l.offlinePhotosWaiting(photosWaiting)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submitTask() {
    final text = _newTask.text.trim();
    if (text.isEmpty) return;
    _newTask.clear();
    final id = newClientId();
    _write(
      OpType.taskAdd,
      id: id,
      payload: {'description': text},
      online: () => _field.addJobTask(
        id: widget.id,
        body: TaskInput(description: text, clientId: id),
      ),
    );
  }
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({required this.done, required this.total});
  final int done;
  final int total;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.completeJob),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unticked tasks are allowed, but the technician should say why in the report.
            if (widget.done < widget.total)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.tasksProgress('${widget.done}', '${widget.total}'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _notes,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: l.completionNotes),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _notes.text.trim()),
          child: Text(l.completeJob),
        ),
      ],
    );
  }
}
