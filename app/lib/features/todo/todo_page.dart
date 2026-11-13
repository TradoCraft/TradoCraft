import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'todo_repository.dart';

/// A root item with the sub-items the list holds for it.
class TodoNode {
  const TodoNode(this.item, this.children);

  final TodoItem item;
  final List<TodoItem> children;

  bool get hasOpenChildren => children.any((c) => !c.done);
}

/// Builds the tree from the flat list (ordered by parent, then position). An item whose parent is
/// not in the list (for example a finished sub-item of an open parent, under the "done" filter) is
/// shown as a root.
List<TodoNode> buildTodoTree(List<TodoItem> items) {
  final ids = {for (final i in items) i.id};
  final kids = <String, List<TodoItem>>{};
  final roots = <TodoItem>[];
  for (final i in items) {
    final p = i.parentId;
    if (p != null && ids.contains(p)) {
      kids.putIfAbsent(p, () => []).add(i);
    } else {
      roots.add(i);
    }
  }
  return [for (final r in roots) TodoNode(r, kids[r.id] ?? const [])];
}

/// My to-dos: a tree of items with sub-items. Add, complete, reopen, delete, reorder, due date.
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final filter = ref.watch(todoFilterProvider);
    final items = ref.watch(todoItemsProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.todoTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              FilledButton.icon(
                key: const ValueKey('todo-add'),
                icon: const Icon(AppIcons.add),
                label: Text(l.todoAdd),
                onPressed: () => _add(context, ref),
              ),
              SegmentedButton<TodoFilter>(
                key: const ValueKey('todo-filter'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: TodoFilter.open,
                    label: Text(l.todoFilterOpen),
                  ),
                  ButtonSegment(
                    value: TodoFilter.done,
                    label: Text(l.todoFilterDone),
                  ),
                  ButtonSegment(
                    value: TodoFilter.all,
                    label: Text(l.todoFilterAll),
                  ),
                ],
                selected: {filter},
                onSelectionChanged: (s) =>
                    ref.read(todoFilterProvider.notifier).set(s.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Column(
              children: [
                Text(errorMessage(e)),
                TextButton(
                  onPressed: () => ref.invalidate(todoItemsProvider),
                  child: Text(l.retry),
                ),
              ],
            ),
            data: (list) {
              final tree = buildTodoTree(list);
              if (tree.isEmpty) {
                return Padding(
                  key: const ValueKey('todo-empty'),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    filter == TodoFilter.done ? l.todoEmptyDone : l.todoEmpty,
                  ),
                );
              }
              return _RootList(tree: tree);
            },
          ),
        ],
      ),
    );
  }
}

/// Runs [action] and reloads the list; a failure is shown to the person.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
  }
  if (!context.mounted) return;
  ref.invalidate(todoItemsProvider);
}

Future<void> _add(
  BuildContext context,
  WidgetRef ref, {
  TodoItem? parent,
}) async {
  final input = await showDialog<_NewTodo>(
    context: context,
    builder: (_) => _AddDialog(sub: parent != null),
  );
  if (input == null || !context.mounted) return;
  await _run(
    context,
    ref,
    () => ref
        .read(todoRepositoryProvider)
        .add(title: input.title, parentId: parent?.id, dueDate: input.due),
  );
}

/// Completes or reopens. Completing an item with open sub-items asks first.
Future<void> _toggle(
  BuildContext context,
  WidgetRef ref,
  TodoItem item, {
  bool hasOpenChildren = false,
}) async {
  final repo = ref.read(todoRepositoryProvider);
  if (item.done) {
    await _run(context, ref, () => repo.reopen(item.id));
    return;
  }
  if (hasOpenChildren && !await _confirmCompleteAll(context, item)) return;
  if (!context.mounted) return;
  await _run(context, ref, () async {
    try {
      await repo.complete(item.id, completeChildren: hasOpenChildren);
    } catch (e) {
      // Sub-items the list does not show (a filter) are still open on the server: ask, then retry.
      if (errorCode(e) != 'open_sub_items') rethrow;
      if (!context.mounted || !await _confirmCompleteAll(context, item)) return;
      await repo.complete(item.id, completeChildren: true);
    }
  });
}

Future<bool> _confirmCompleteAll(BuildContext context, TodoItem item) async {
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
          key: const ValueKey('todo-complete-all'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.todoCompleteAll),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> _delete(BuildContext context, WidgetRef ref, TodoItem item) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(l.todoDeleteConfirm(item.title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('todo-confirm-delete'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await _run(
    context,
    ref,
    () => ref.read(todoRepositoryProvider).delete(item.id),
  );
}

Future<void> _setDue(BuildContext context, WidgetRef ref, TodoItem item) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: item.dueDate ?? now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 10),
  );
  if (picked == null || !context.mounted) return;
  await _run(
    context,
    ref,
    () => ref
        .read(todoRepositoryProvider)
        .update(item.id, TodoPatch(dueDate: picked)),
  );
}

/// The root items, reorderable by dragging their handle.
class _RootList extends ConsumerWidget {
  const _RootList({required this.tree});

  final List<TodoNode> tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tree.length,
      onReorderItem: (from, to) {
        final order = [...tree];
        order.insert(to, order.removeAt(from));
        final ids = [
          for (final n in order)
            if (n.item.parentId == null) n.item.id,
        ];
        _run(
          context,
          ref,
          () => ref.read(todoRepositoryProvider).reorder(null, ids),
        );
      },
      itemBuilder: (context, i) => _RootTile(
        key: ValueKey('todo-${tree[i].item.id}'),
        index: i,
        node: tree[i],
      ),
    );
  }
}

class _RootTile extends ConsumerWidget {
  const _RootTile({super.key, required this.index, required this.node});

  final int index;
  final TodoNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final item = node.item;
    // Only a real root item is reordered among the roots and takes sub-items. A sub-item shown as a
    // root (a filter hid its parent) has neither.
    final isRoot = item.parentId == null;
    final handle = ReorderableDragStartListener(
      index: index,
      child: Tooltip(
        message: l.todoReorder,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(AppIcons.dragHandle),
        ),
      ),
    );
    final check = _DoneBox(
      item: item,
      onChanged: () =>
          _toggle(context, ref, item, hasOpenChildren: node.hasOpenChildren),
    );
    final actions = [
      _ItemMenu(item: item, canAddSub: isRoot),
      if (isRoot) handle,
    ];
    if (node.children.isEmpty) {
      return Card(
        child: ListTile(
          leading: check,
          title: _Title(item),
          subtitle: _Details(item),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
        ),
      );
    }
    final done = node.children.where((c) => c.done).length;
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('todo-expand-${item.id}'),
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: check,
        title: Row(
          children: [
            Expanded(child: _Title(item)),
            ...actions,
          ],
        ),
        subtitle: _Details(
          item,
          extra: l.todoSubProgress(done, node.children.length),
        ),
        childrenPadding: const EdgeInsets.only(left: 24),
        children: [_ChildList(parent: item, children: node.children)],
      ),
    );
  }
}

class _ChildList extends ConsumerWidget {
  const _ChildList({required this.parent, required this.children});

  final TodoItem parent;
  final List<TodoItem> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: children.length,
      onReorderItem: (from, to) {
        final order = [...children];
        order.insert(to, order.removeAt(from));
        _run(
          context,
          ref,
          () => ref.read(todoRepositoryProvider).reorder(parent.id, [
            for (final c in order) c.id,
          ]),
        );
      },
      itemBuilder: (context, i) {
        final c = children[i];
        return ListTile(
          key: ValueKey('todo-${c.id}'),
          dense: true,
          leading: _DoneBox(item: c, onChanged: () => _toggle(context, ref, c)),
          title: _Title(c),
          subtitle: _Details(c),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ItemMenu(item: c, canAddSub: false),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(AppIcons.dragHandle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DoneBox extends StatelessWidget {
  const _DoneBox({required this.item, required this.onChanged});

  final TodoItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Checkbox(
    key: ValueKey('todo-check-${item.id}'),
    value: item.done,
    onChanged: (_) => onChanged(),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.item);

  final TodoItem item;

  @override
  Widget build(BuildContext context) => Text(
    item.title,
    style: item.done
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null,
  );
}

/// Due date, who handed the item over, and the link: shown under the title.
class _Details extends StatelessWidget {
  const _Details(this.item, {this.extra});

  final TodoItem item;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final due = item.dueDate;
    final today = DateTime.now();
    final overdue =
        due != null &&
        !item.done &&
        DateTime(
          due.year,
          due.month,
          due.day,
        ).isBefore(DateTime(today.year, today.month, today.day));
    final parts = <Widget>[
      if (due != null)
        Text(
          overdue
              ? '${l.todoOverdue} · ${l.todoDue(date(due))}'
              : l.todoDue(date(due)),
          key: ValueKey('todo-due-${item.id}'),
          style: overdue ? TextStyle(color: scheme.error) : null,
        ),
      if (!item.mine) Text(l.todoFromOwner(item.ownerName)),
      if (extra != null) Text(extra!),
      if (item.linkKind != null)
        // Jumping to the record comes with the next step; for now the chip only names it.
        Chip(
          key: ValueKey('todo-link-${item.id}'),
          avatar: const Icon(AppIcons.link, size: 16),
          label: Text(item.linkLabel ?? l.todoLinkedItem),
          visualDensity: VisualDensity.compact,
        ),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

enum _Action { addSub, setDue, clearDue, reopen, delete }

class _ItemMenu extends ConsumerWidget {
  const _ItemMenu({required this.item, required this.canAddSub});

  final TodoItem item;
  final bool canAddSub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return PopupMenuButton<_Action>(
      key: ValueKey('todo-menu-${item.id}'),
      onSelected: (a) async {
        switch (a) {
          case _Action.addSub:
            await _add(context, ref, parent: item);
          case _Action.setDue:
            await _setDue(context, ref, item);
          case _Action.clearDue:
            await _run(
              context,
              ref,
              () => ref
                  .read(todoRepositoryProvider)
                  .update(item.id, const TodoPatch(clearDueDate: true)),
            );
          case _Action.reopen:
            await _toggle(context, ref, item);
          case _Action.delete:
            await _delete(context, ref, item);
        }
      },
      itemBuilder: (_) => [
        if (canAddSub)
          PopupMenuItem(
            key: ValueKey('todo-add-sub-${item.id}'),
            value: _Action.addSub,
            child: Text(l.todoAddSub),
          ),
        PopupMenuItem(value: _Action.setDue, child: Text(l.todoSetDue)),
        if (item.dueDate != null)
          PopupMenuItem(value: _Action.clearDue, child: Text(l.todoClearDue)),
        if (item.done)
          PopupMenuItem(value: _Action.reopen, child: Text(l.todoReopen)),
        // Only the owner deletes an item.
        if (item.mine)
          PopupMenuItem(
            key: ValueKey('todo-delete-${item.id}'),
            value: _Action.delete,
            child: Text(l.delete),
          ),
      ],
    );
  }
}

class _NewTodo {
  const _NewTodo(this.title, this.due);

  final String title;
  final DateTime? due;
}

class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.sub});

  final bool sub;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _title = TextEditingController();
  DateTime? _due;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => _due = d);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, _NewTodo(title, _due));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.sub ? l.todoAddSub : l.todoAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('todo-title-field'),
            controller: _title,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(labelText: l.todoWhat),
            onSubmitted: (_) => _submit(),
          ),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('todo-due-button'),
                icon: const Icon(AppIcons.event),
                label: Text(_due == null ? l.todoSetDue : date(_due)),
                onPressed: _pickDue,
              ),
              if (_due != null)
                IconButton(
                  tooltip: l.todoClearDue,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => setState(() => _due = null),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('todo-dialog-save'),
          onPressed: _submit,
          child: Text(l.add),
        ),
      ],
    );
  }
}
