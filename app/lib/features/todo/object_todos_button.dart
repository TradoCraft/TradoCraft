import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'current_context.dart';
import 'link_kinds.dart';
import 'todo_quick_add.dart';
import 'todo_repository.dart';

/// "To-dos for this record" in the header of a detail screen: a small button with the number of
/// the caller's own open to-dos linked to the record. It opens a sheet that lists them (complete
/// one, add one that is already linked to the record). Hidden for a user without `todo.use`, which
/// the server also takes away when the module is off. The count and the list are the caller's own
/// items only (ADR 0061: a to-do is private to its owner and assignee).
class ObjectTodosButton extends ConsumerWidget {
  const ObjectTodosButton({
    super.key,
    required this.kind,
    required this.id,
    this.label,
  });

  /// The kind of the record.
  final TodoLinkKind kind;

  /// The id of the record.
  final String id;

  /// What the screen calls the record (a quotation number); stored with a to-do made from here.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = linkKindInfo(kind);
    if (info == null || !canUseTodo(ref)) return const SizedBox.shrink();
    final l = context.l10n;
    final count =
        ref.watch(objectTodosProvider((kind: kind, id: id))).value?.length ?? 0;
    return IconButton(
      key: const ValueKey('object-todos-button'),
      tooltip: count == 0 ? l.todoForObject : l.todoForObjectCount(count),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ObjectTodosSheet(
          target: LinkTarget(LinkRef(info, id), label: label),
        ),
      ),
      icon: Badge(
        key: const ValueKey('object-todos-badge'),
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(AppIcons.checklist),
      ),
    );
  }
}

class _ObjectTodosSheet extends ConsumerWidget {
  const _ObjectTodosSheet({required this.target});

  final LinkTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final items = ref.watch(
      objectTodosProvider((kind: target.ref.kind, id: target.ref.id)),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(target.ref.info.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target.label ?? target.ref.info.label(l),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('object-todos-add'),
                  icon: const Icon(AppIcons.add),
                  label: Text(l.shortcutNewTodo),
                  onPressed: () =>
                      showTodoQuickAdd(context, ref, target: target),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(errorMessage(e)),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        key: const ValueKey('object-todos-empty'),
                        padding: const EdgeInsets.all(16),
                        child: Text(l.todoForObjectEmpty),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final i in list) _Row(item: i, target: target),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.item, required this.target});

  final TodoItem item;
  final LinkTarget target;

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(todoRepositoryProvider);
    try {
      try {
        await repo.complete(item.id);
      } catch (e) {
        // Sub-items that are not linked to this record are open too: ask before completing them.
        if (errorCode(e) != 'open_sub_items') rethrow;
        if (!context.mounted || !await _confirm(context)) return;
        await repo.complete(item.id, completeChildren: true);
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
    ref.invalidate(objectTodosProvider);
    ref.invalidate(todoItemsProvider);
  }

  Future<bool> _confirm(BuildContext context) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.todoCompleteAllTitle),
        content: Text(l.todoCompleteAllBody(item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.todoCompleteAll),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final due = item.dueDate;
    return CheckboxListTile(
      key: ValueKey('object-todo-${item.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: item.done,
      onChanged: item.done ? null : (_) => _complete(context, ref),
      title: Text(item.title),
      subtitle: due == null ? null : Text(l.todoDue(date(due))),
    );
  }
}
