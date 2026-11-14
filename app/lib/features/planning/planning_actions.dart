import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'planning_adapter.dart';

/// Checking and saving a schedule, shared by the board drop and the schedule dialog.
class PlanningActions {
  PlanningActions(
    this.api, {
    required this.technicianNames,
    required this.skillNames,
  });

  final TradocraftApi api;
  final Map<String, String> technicianNames;
  final Map<String, String> skillNames;

  /// The conflicts of a placement, without changing anything.
  Future<List<Conflict>> check(
    String jobId,
    List<String> technicians,
    DateTime start,
    DateTime end,
  ) async {
    final r = await api.planning.scheduleJob(
      id: jobId,
      dryRun: true,
      body: ScheduleInput(
        scheduledStart: start.toUtc(),
        scheduledEnd: end.toUtc(),
        technicianIds: technicians,
      ),
    );
    return r.conflicts;
  }

  /// Saves the schedule. When the check finds errors the planner is asked first; returns whether
  /// the job was scheduled.
  Future<bool> save(
    BuildContext context,
    String jobId,
    List<String> technicians,
    DateTime start,
    DateTime end,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = context.l10n;
    try {
      final conflicts = await check(jobId, technicians, start, end);
      var force = false;
      if (hasErrors(conflicts)) {
        if (!context.mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.planningConfirmTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.planningConfirmBody),
                const SizedBox(height: 8),
                for (final c in conflicts)
                  Text('• ${conflictText(l, c, technicianNames, skillNames)}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.planningScheduleAnyway),
              ),
            ],
          ),
        );
        if (ok != true) return false;
        force = true;
      }
      await api.planning.scheduleJob(
        id: jobId,
        force: force ? true : null,
        body: ScheduleInput(
          scheduledStart: start.toUtc(),
          scheduledEnd: end.toUtc(),
          technicianIds: technicians,
        ),
      );
      messenger?.showSnackBar(SnackBar(content: Text(l.planningScheduled)));
      return true;
    } on DioException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
      return false;
    }
  }
}
