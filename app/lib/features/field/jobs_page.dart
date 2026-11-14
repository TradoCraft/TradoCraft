import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show OpenInTab;
import '../../l10n/l10n.dart';
import 'job_form.dart';
import 'offline/job_cache.dart';
import 'offline/offline_queue.dart';
import 'offline/offline_ui.dart';
import '../../shared/app_icons.dart';

final _day = DateFormat('EEE dd/MM');
final _time = DateFormat('HH:mm');

/// Short text for an appointment: "Mon 09/11 07:00–11:00".
String whenText(Job j, AppLocalizations l) {
  final s = j.scheduledStart?.toLocal();
  if (s == null) return l.notScheduled;
  final e = j.scheduledEnd?.toLocal();
  return '${_day.format(s)} ${_time.format(s)}${e == null ? '' : '–${_time.format(e)}'}';
}

/// A technician's day: their jobs in the order of the appointments. Planners see every job and can
/// filter it and create new ones.
class JobsPage extends ConsumerStatefulWidget {
  const JobsPage({super.key});

  @override
  ConsumerState<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends ConsumerState<JobsPage> {
  Future<List<Job>>? _jobs;
  bool _activeOnly = true;
  String _technician = 'all';

  /// Set when the list comes from the local copy because the server cannot be reached.
  DateTime? _offlineAt;
  StreamSubscription<AppliedOp>? _applied;

  @override
  void initState() {
    super.initState();
    _applied = ref.read(offlineQueueProvider).applied.listen((_) {
      // A change was synced: the task counts may have moved.
      if (mounted && _jobs != null) {
        _reload(
          (ref.read(meProvider).value?.permissions ?? const []).contains(
            'field.plan',
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _applied?.cancel();
    super.dispose();
  }

  Future<List<Job>> _fetch(bool planner) async {
    final field = ref.read(apiProvider).field;
    final cache = ref.read(jobCacheProvider);
    if (planner) {
      _offlineAt = null;
      return field.listJobs(
        status: _activeOnly ? 'active' : null,
        technician: _technician == 'all' ? null : _technician,
      );
    }
    // A technician's jobs are kept on the device, so the day can be read without signal.
    try {
      final jobs = await field.listMyJobs();
      _offlineAt = null;
      unawaited(_keep(cache, jobs));
      return jobs;
    } catch (e) {
      if (isNetworkError(e)) {
        final cached = await cache.loadList();
        if (cached != null) {
          _offlineAt = cached.savedAt;
          return cached.jobs;
        }
      }
      rethrow;
    }
  }

  /// Saves the list and the details of the open jobs, one after the other, for offline use.
  Future<void> _keep(JobCache cache, List<Job> jobs) async {
    try {
      await cache.saveList(jobs);
      final field = ref.read(apiProvider).field;
      for (final j
          in jobs
              .where((j) => j.status == 'planned' || j.status == 'in_progress')
              .take(20)) {
        if (!mounted) return;
        await cache.saveDetail(await field.getJob(id: j.id));
      }
    } catch (_) {
      // Best effort: the copy is a convenience.
    }
  }

  void _reload(bool planner) => setState(() => _jobs = _fetch(planner));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final planner = perms.contains('field.plan');
    _jobs ??= _fetch(planner);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(planner ? l.jobs : l.myJobs),
        actions: [
          TextButton.icon(
            icon: const Icon(AppIcons.eventRepeat),
            label: Text(l.contracts),
            onPressed: () => context.push('/jobs/contracts'),
          ),
          if (planner)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.newJob),
                onPressed: () async {
                  final d = await showJobForm(context);
                  if (d != null && context.mounted) {
                    context.push('/jobs/${d.job.id}');
                    _reload(planner);
                  }
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (planner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: Text(l.openJobsOnly),
                    selected: _activeOnly,
                    onSelected: (v) {
                      _activeOnly = v;
                      _reload(planner);
                    },
                  ),
                  DropdownButton<String>(
                    value: _technician,
                    items: [
                      DropdownMenuItem(value: 'all', child: Text(l.all)),
                      DropdownMenuItem(
                        value: 'none',
                        child: Text(l.noTechnicians),
                      ),
                      DropdownMenuItem(value: 'me', child: Text(l.myJobs)),
                    ],
                    onChanged: (v) {
                      _technician = v!;
                      _reload(planner);
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                if (_offlineAt != null) ...[
                  OfflineNote(savedAt: _offlineAt!),
                  const SizedBox(height: 8),
                ],
                const PendingSyncBanner(),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Job>>(
              future: _jobs,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(child: Text(errorMessage(s.error!)));
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final jobs = s.data!;
                if (jobs.isEmpty) return Center(child: Text(l.noJobsAssigned));
                return RefreshIndicator(
                  onRefresh: () async => _reload(planner),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final j in jobs)
                        OpenInTab(
                          location: '/jobs/${j.id}',
                          child: Card(
                            child: ListTile(
                              isThreeLine: true,
                              onTap: () async {
                                await context.push<bool>('/jobs/${j.id}');
                                if (mounted) _reload(planner);
                              },
                              title: Text('${j.title} · ${j.customerName}'),
                              subtitle: Text(
                                [
                                  whenText(j, l),
                                  if (j.address.isNotEmpty) j.address,
                                  if (j.tasksTotal > 0)
                                    l.tasksProgress(
                                      '${j.tasksDone}',
                                      '${j.tasksTotal}',
                                    ),
                                  if (planner)
                                    j.technicians.isEmpty
                                        ? l.noTechnicians
                                        : j.technicians
                                              .map((t) => t.displayName)
                                              .join(', '),
                                ].join('\n'),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Chip(
                                    label: Text(l.jobStatus(j.status)),
                                    backgroundColor: j.status == 'in_progress'
                                        ? theme.colorScheme.tertiaryContainer
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Text(
                                    l.jobKind(j.kind),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
