import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../app/shortcuts/registry.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'current_context.dart';
import 'todo_repository.dart';

/// Whether the user may use to-dos: holds `todo.use`. The server removes the permission when the
/// module is off, so this covers "module on" as well.
bool canUseTodo(WidgetRef ref) => can(ref, 'todo.use');

/// Asks for a new to-do and creates it. Reachable from the to-do page, the account menu and the
/// New to-do shortcut, from any screen.
///
/// Without [parent] the dialog offers "Link to current screen": [target] when given (the record of
/// a detail screen's own button), else the record on screen now (`currentContextProvider`), on by
/// default. A sub-item ([parent]) is never linked on its own. Returns the created item, or null
/// when cancelled or failed (the failure is shown in a snack bar).
Future<TodoItem?> showTodoQuickAdd(
  BuildContext context,
  WidgetRef ref, {
  TodoItem? parent,
  LinkTarget? target,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = context.l10n;
  final offered = parent != null
      ? null
      : target ?? ref.read(currentContextProvider).target;
  final input = await showDialog<_NewTodo>(
    context: context,
    builder: (_) => _QuickAddDialog(sub: parent != null, target: offered),
  );
  if (input == null) return null;
  final link = input.link;
  try {
    final item = await ref
        .read(todoRepositoryProvider)
        .add(
          title: input.title,
          parentId: parent?.id,
          dueDate: input.due,
          linkKind: link?.kind,
          linkId: link?.id,
          linkLabel: link?.label,
          linkLocation: link?.location,
        );
    ref.invalidate(todoItemsProvider);
    ref.invalidate(objectTodosProvider);
    messenger?.showSnackBar(SnackBar(content: Text(l.todoAdded)));
    return item;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    return null;
  }
}

/// The link the dialog was saved with.
class _Link {
  const _Link(this.kind, this.id, this.label, this.location);
  final TodoLinkKind kind;
  final String id;
  final String label;
  final String location;
}

class _NewTodo {
  const _NewTodo(this.title, this.due, this.link);

  final String title;
  final DateTime? due;
  final _Link? link;
}

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog({required this.sub, required this.target});

  final bool sub;
  final LinkTarget? target;

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  final _title = TextEditingController();
  DateTime? _due;

  // On by default when there is something to link to.
  late bool _link = widget.target != null;

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
    final t = widget.target;
    _Link? link;
    if (_link && t != null) {
      link = _Link(
        t.ref.kind,
        t.ref.id,
        t.label ?? t.ref.info.label(context.l10n),
        t.location,
      );
    }
    Navigator.pop(context, _NewTodo(title, _due, link));
  }

  Widget _linkSwitch(BuildContext context) {
    final l = context.l10n;
    final t = widget.target;
    final kind = t?.ref.info.label(l);
    return SwitchListTile(
      key: const ValueKey('todo-link-switch'),
      contentPadding: EdgeInsets.zero,
      value: _link && t != null,
      onChanged: t == null ? null : (v) => setState(() => _link = v),
      secondary: Icon(t?.ref.info.icon ?? AppIcons.linkOff),
      title: Text(l.todoLinkToScreen),
      subtitle: Text(
        key: const ValueKey('todo-link-hint'),
        t == null
            ? l.todoLinkNotAvailable
            : t.label == null
            ? kind!
            : '$kind · ${t.label}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // A dialog is modal for shortcuts: nothing behind it fires (the observer on the navigator
    // already blocks them; this scope makes the dialog's layer explicit).
    return ShortcutScope(
      layer: ShortcutLayer.dialog,
      actions: const {},
      child: AlertDialog(
        title: Text(widget.sub ? l.todoAddSub : l.todoAdd),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
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
                if (!widget.sub) _linkSwitch(context),
              ],
            ),
          ),
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
      ),
    );
  }
}
