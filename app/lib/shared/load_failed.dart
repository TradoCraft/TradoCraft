import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/api.dart';
import '../features/todo/todo_quick_add.dart';
import '../features/todo/todo_repository.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// What a detail screen shows when its record could not be loaded: a clear "not found" state when
/// the record is gone ([notFound], HTTP 404; a to-do link can outlive its record), otherwise the
/// error. Always with a way out: back to where the user came from, or [leaveTo] (the section
/// list) when nothing is left to go back to. Inside a workspace tab that closes the tab.
class LoadFailedView extends ConsumerWidget {
  const LoadFailedView({
    super.key,
    required this.message,
    required this.leaveTo,
    this.notFound = false,
    this.todoKind,
    this.todoId,
  });

  /// The error sentence (`errorMessage`).
  final String message;

  /// The section list to go to when there is no screen to go back to, e.g. `/orders`.
  final String leaveTo;

  /// The record does not exist (any more) or is not available to the user.
  final bool notFound;

  /// The kind and id of the record. With [notFound], the caller's to-dos that still link to it are
  /// looked up and one button offers to remove that link.
  final TodoLinkKind? todoKind;
  final String? todoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: ValueKey(notFound ? 'record-not-found' : 'record-load-failed'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notFound)
              Icon(
                AppIcons.searchOff,
                size: 48,
                color: theme.colorScheme.outline,
              ),
            if (notFound)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.recordNotFound,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: notFound
                    ? theme.textTheme.bodySmall
                    : TextStyle(color: theme.colorScheme.error),
              ),
            ),
            if (notFound &&
                todoKind != null &&
                todoId != null &&
                canUseTodo(ref))
              _RemoveLinkButton(kind: todoKind!, id: todoId!),
            OutlinedButton.icon(
              key: const ValueKey('record-back'),
              icon: const Icon(AppIcons.arrowBack),
              label: Text(MaterialLocalizations.of(context).backButtonTooltip),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(leaveTo),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Remove link from my to-dos": shown only while the caller has to-dos linked to the missing
/// record. Clears the link of all of them, then looks again (and so disappears).
class _RemoveLinkButton extends ConsumerStatefulWidget {
  const _RemoveLinkButton({required this.kind, required this.id});

  final TodoLinkKind kind;
  final String id;

  @override
  ConsumerState<_RemoveLinkButton> createState() => _RemoveLinkButtonState();
}

class _RemoveLinkButtonState extends ConsumerState<_RemoveLinkButton> {
  bool _busy = false;

  Future<void> _remove(List<TodoItem> items) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await ref.read(todoRepositoryProvider).clearLinks(items);
      ref.invalidate(todoItemsProvider);
      ref.invalidate(objectTodosProvider);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
    ref.invalidate(linkedTodosProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref
        .watch(linkedTodosProvider((kind: widget.kind, id: widget.id)))
        .value;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.tonalIcon(
        key: const ValueKey('record-remove-todo-link'),
        icon: const Icon(AppIcons.linkOff),
        label: Text(context.l10n.todoRemoveLink),
        onPressed: _busy ? null : () => _remove(items),
      ),
    );
  }
}
