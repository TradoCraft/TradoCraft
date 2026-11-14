import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo_repository.dart';

/// The number of open to-dos on the plate of the user (root items, like the to-do page shows),
/// on the icon of the /todo destination. Red when at least one of them is overdue; hidden at zero
/// and when there is no to-do list for the user. See [todoBadgeSyncProvider] for the refreshing.
class TodoNavBadge extends ConsumerWidget {
  const TodoNavBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The previous numbers stay while a refresh is under way.
    final counts = ref.watch(todoCountsProvider).value;
    final open = counts?.open ?? 0;
    if (open <= 0) return child;
    final overdue = counts!.overdue > 0;
    final scheme = Theme.of(context).colorScheme;
    return Badge(
      key: const ValueKey('todo-nav-badge'),
      backgroundColor: overdue ? scheme.error : scheme.primary,
      textColor: overdue ? scheme.onError : scheme.onPrimary,
      label: Text('$open'),
      child: child,
    );
  }
}
