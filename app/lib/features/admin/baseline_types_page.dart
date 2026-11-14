import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';

final baselineTypesProvider =
    FutureProvider.autoDispose<List<BaselineItemType>>(
      (ref) => ref.watch(apiProvider).crm.listTypes(),
    );

/// Baseline item types (ADR 0068): the kinds of things that can be recorded at a customer's site
/// (clock dial, bell group, bell) and where they may be placed. List, create, edit, deactivate and
/// delete; the server refuses deleting a type that is in use (409) and says to deactivate it.
class BaselineTypesPage extends ConsumerWidget {
  const BaselineTypesPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<BaselineItemType> all, [
    BaselineItemType? t,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BaselineTypeDialog(type: t, all: all),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(baselineTypesProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BaselineItemType t,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.baselineTypeDeleteConfirm(t.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('bltype-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    // A 409 (in use) is shown as the server's message: "... deactivate it instead".
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).crm.deleteType(id: t.id),
      success: l.baselineTypeDeleted,
    );
    if (ok && context.mounted) ref.invalidate(baselineTypesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final types = ref.watch(baselineTypesProvider);
    final canWrite = can(ref, 'products.write');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.baselineTypesTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canWrite && types.hasValue)
              FilledButton.icon(
                key: const ValueKey('bltype-new'),
                onPressed: () => _edit(context, ref, types.requireValue),
                icon: const Icon(Icons.add),
                label: Text(l.newBaselineType),
              ),
          ],
        ),
        const SizedBox(height: 8),
        types.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                onPressed: () => ref.invalidate(baselineTypesProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  key: const ValueKey('bltype-empty'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l.baselineTypesEmpty),
                )
              : Column(
                  children: [
                    for (final t in list)
                      ListTile(
                        key: ValueKey('bltype-${t.code}'),
                        title: Text(t.name),
                        subtitle: Text(
                          [
                            t.code,
                            if (t.allowedParentCodes.isNotEmpty)
                              '${l.baselineTypeParents}: ${t.allowedParentCodes.join(', ')}',
                            if (t.allowTopLevel) l.baselineTopLevel,
                            if (!t.active) l.inactive,
                          ].join(' · '),
                        ),
                        trailing: canWrite
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('bltype-edit-${t.code}'),
                                    tooltip: l.edit,
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () =>
                                        _edit(context, ref, list, t),
                                  ),
                                  IconButton(
                                    key: ValueKey('bltype-del-${t.code}'),
                                    tooltip: l.delete,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(context, ref, t),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

final _codePattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Create ([type] null) or edit dialog of a baseline item type; pops true when saved. The code is
/// fixed once created, because items and attribute definitions refer to it.
class BaselineTypeDialog extends ConsumerStatefulWidget {
  const BaselineTypeDialog({super.key, this.type, required this.all});
  final BaselineItemType? type;

  /// All existing types, the candidates for the allowed parents.
  final List<BaselineItemType> all;

  @override
  ConsumerState<BaselineTypeDialog> createState() => _BaselineTypeDialogState();
}

class _BaselineTypeDialogState extends ConsumerState<BaselineTypeDialog> {
  late final _code = TextEditingController(text: widget.type?.code);
  late final _name = TextEditingController(text: widget.type?.name);
  late final _sort = TextEditingController(
    text: '${widget.type?.sortOrder ?? 0}',
  );
  late final Set<String> _parents = {...?widget.type?.allowedParentCodes};
  late bool _top = widget.type?.allowTopLevel ?? true;
  late bool _active = widget.type?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.type != null;

  @override
  void dispose() {
    for (final c in [_code, _name, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mirrors the server rules; returns an error message or null.
  String? _check() {
    final l = context.l10n;
    if (!_editing && !_codePattern.hasMatch(_code.text.trim())) {
      return l.baselineTypeCodeInvalid;
    }
    if (_name.text.trim().isEmpty) return l.baselineTypeNameRequired;
    if (int.tryParse(_sort.text.trim()) == null) return l.sortOrderInvalid;
    if (_parents.isEmpty && !_top) return l.baselineTypePlacement;
    return null;
  }

  Future<void> _save() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final parents = _parents.toList()..sort();
    final crm = ref.read(apiProvider).crm;
    final t = widget.type;
    final ok = await runAction(context, () async {
      if (t == null) {
        await crm.createType(
          body: BaselineItemTypeInput(
            code: _code.text.trim(),
            name: _name.text.trim(),
            allowedParentCodes: parents,
            allowTopLevel: _top,
            sortOrder: int.parse(_sort.text.trim()),
            active: _active,
          ),
        );
      } else {
        await crm.updateType(
          id: t.id,
          body: BaselineItemTypeUpdate(
            name: _name.text.trim(),
            allowedParentCodes: parents,
            allowTopLevel: _top,
            sortOrder: int.parse(_sort.text.trim()),
            active: _active,
          ),
        );
      }
    }, success: context.l10n.saved);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final candidates = [
      for (final t in widget.all)
        if (t.code != widget.type?.code) t,
    ];
    return AlertDialog(
      title: Text(_editing ? l.editBaselineType : l.newBaselineType),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('bltype-code'),
                controller: _code,
                enabled: !_editing,
                autofocus: !_editing,
                decoration: InputDecoration(labelText: l.code),
              ),
              TextField(
                key: const ValueKey('bltype-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              const SizedBox(height: 12),
              Text(
                l.baselineTypeParents,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in candidates)
                    FilterChip(
                      key: ValueKey('bltype-parent-${t.code}'),
                      label: Text(t.name),
                      selected: _parents.contains(t.code),
                      onSelected: (v) => setState(() {
                        v ? _parents.add(t.code) : _parents.remove(t.code);
                      }),
                    ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('bltype-top'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.baselineTypeTopLevel),
                value: _top,
                onChanged: (v) => setState(() => _top = v),
              ),
              TextField(
                key: const ValueKey('bltype-sort'),
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.sortOrder),
              ),
              SwitchListTile(
                key: const ValueKey('bltype-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('bltype-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
