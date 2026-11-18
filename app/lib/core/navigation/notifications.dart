import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../app/worker_ui.dart';
import '../../app/workspace.dart';
import '../../features/todo/todo_repository.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

enum NotificationSeverity { info, warning }

/// A text that is translated when shown. A future server feed hands over its own text with
/// [AppNotification.literal].
typedef NotificationText = String Function(AppLocalizations l);

/// One entry of the notifications centre.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.icon,
    required this.location,
    this.subtitle,
    this.severity = NotificationSeverity.info,
  });

  /// An entry whose texts are already final (from a server feed).
  AppNotification.literal({
    required this.id,
    required String title,
    required this.icon,
    required this.location,
    String? subtitle,
    this.severity = NotificationSeverity.info,
  }) : title = ((_) => title),
       subtitle = subtitle == null ? null : ((_) => subtitle);

  final String id;
  final NotificationText title;
  final NotificationText? subtitle;
  final IconData icon;
  final NotificationSeverity severity;

  /// Where tapping the entry goes.
  final String location;
}

/// What needs the user's attention, gathered on the client from what the app already knows:
/// the to-do counts and, for administrators, the background worker. Empty when there is nothing.
/// A server-side feed can be added here later without touching the bell.
final notificationsProvider = Provider.autoDispose<List<AppNotification>>((
  ref,
) {
  final todo = ref.watch(todoCountsProvider).value;
  final worker = ref.watch(workerStatusProvider).value;
  return [
    if (todo != null && todo.overdue > 0)
      AppNotification(
        id: 'todo-overdue',
        title: (l) => l.notificationsOverdueTodos(todo.overdue),
        icon: AppIcons.checklist,
        severity: NotificationSeverity.warning,
        location: '/todo',
      ),
    if (todo != null && todo.open > todo.overdue)
      AppNotification(
        id: 'todo-pending',
        title: (l) => l.notificationsOpenTodos(todo.open - todo.overdue),
        subtitle: todo.dueToday > 0
            ? (l) => l.notificationsTodosDueToday(todo.dueToday)
            : null,
        icon: AppIcons.checklist,
        location: '/todo',
      ),
    if (worker != null &&
        (worker.state == WorkerState.down ||
            worker.state == WorkerState.neverSeen))
      AppNotification(
        id: 'worker',
        title: (l) => worker.state == WorkerState.down
            ? l.notificationsWorkerDown
            : l.notificationsWorkerNeverSeen,
        subtitle: (l) => l.notificationsWorkerSubtitle,
        icon: AppIcons.warningAmber,
        severity: NotificationSeverity.warning,
        location: '/admin',
      ),
  ];
});

/// The bell with the number of notifications (no badge at zero); opens the list.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final bell = const Icon(Icons.notifications_outlined);
    return PopupMenuButton<String>(
      key: const ValueKey('notifications-button'),
      tooltip: l.notificationsTooltip,
      icon: items.isEmpty
          ? bell
          : Badge(
              key: const ValueKey('notifications-badge'),
              backgroundColor: scheme.error,
              textColor: scheme.onError,
              label: Text('${items.length}'),
              child: bell,
            ),
      onSelected: (location) {
        ref.read(workspaceProvider.notifier).focusHome();
        context.go(location);
      },
      itemBuilder: (_) => [
        if (items.isEmpty)
          PopupMenuItem<String>(
            key: const ValueKey('notifications-empty'),
            enabled: false,
            child: Text(l.notificationsEmpty),
          ),
        for (final n in items)
          PopupMenuItem<String>(
            key: ValueKey('notification-${n.id}'),
            value: n.location,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                n.icon,
                color: n.severity == NotificationSeverity.warning
                    ? scheme.error
                    : null,
              ),
              title: Text(n.title(l)),
              subtitle: n.subtitle == null ? null : Text(n.subtitle!(l)),
            ),
          ),
      ],
    );
  }
}
