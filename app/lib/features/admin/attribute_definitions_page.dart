import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'baseline_types_page.dart';

final attributeDefinitionsProvider =
    FutureProvider.autoDispose<List<AttributeDefinition>>(
      (ref) => ref.watch(apiProvider).products.listDefinitions(),
    );

/// Attribute definitions (ADR 0068): the admin-tunable fields that products (and later site
/// baseline items) can carry. List, create, edit (incl. select options), deactivate and delete;
/// the server refuses deleting a definition that is in use (409) and says to deactivate it.
class AttributeDefinitionsPage extends ConsumerWidget {
  const AttributeDefinitionsPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    AttributeDefinition? d,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AttributeDefinitionDialog(definition: d),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(attributeDefinitionsProvider);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AttributeDefinition d,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.attrDefDeleteConfirm(d.key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('attrdef-delete-confirm'),
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
      () => ref.read(apiProvider).products.deleteDefinition(id: d.id),
      success: l.attrDefDeleted,
    );
    if (ok && context.mounted) ref.invalidate(attributeDefinitionsProvider);
  }

  String _kindLabel(BuildContext context, DefinitionKind k) {
    final l = context.l10n;
    return switch (k) {
      DefinitionKind.number => l.attrKindNumber,
      DefinitionKind.range => l.attrKindRange,
      DefinitionKind.select => l.attrKindSelect,
      _ => l.attrKindText,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final defs = ref.watch(attributeDefinitionsProvider);
    final canWrite = can(ref, 'products.write');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.attrDefsTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canWrite)
              FilledButton.icon(
                key: const ValueKey('attrdef-new'),
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l.newAttrDef),
              ),
          ],
        ),
        const SizedBox(height: 8),
        defs.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                key: const ValueKey('attrdef-retry'),
                onPressed: () => ref.invalidate(attributeDefinitionsProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  key: const ValueKey('attrdef-empty'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l.attrDefsEmpty),
                )
              : Column(
                  children: [
                    for (final d in list)
                      ListTile(
                        key: ValueKey('attrdef-${d.key}'),
                        title: Text(d.label),
                        subtitle: Text(
                          [
                            d.key,
                            _kindLabel(context, d.kind),
                            if ((d.unit ?? '').isNotEmpty) d.unit!,
                            d.scope,
                            if (!d.active) l.inactive,
                          ].join(' · '),
                        ),
                        trailing: canWrite
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('attrdef-edit-${d.key}'),
                                    tooltip: l.edit,
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _edit(context, ref, d),
                                  ),
                                  IconButton(
                                    key: ValueKey('attrdef-del-${d.key}'),
                                    tooltip: l.delete,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(context, ref, d),
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

class _OptionRow {
  _OptionRow([String value = '', String label = ''])
    : value = TextEditingController(text: value),
      label = TextEditingController(text: label);
  final TextEditingController value;
  final TextEditingController label;
}

final _keyPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Create ([definition] null) or edit dialog of an attribute definition; pops true when saved.
/// Key, type and scope are fixed once created, because stored values refer to them.
class AttributeDefinitionDialog extends ConsumerStatefulWidget {
  const AttributeDefinitionDialog({super.key, this.definition});
  final AttributeDefinition? definition;

  @override
  ConsumerState<AttributeDefinitionDialog> createState() =>
      _AttributeDefinitionDialogState();
}

class _AttributeDefinitionDialogState
    extends ConsumerState<AttributeDefinitionDialog> {
  late final _key = TextEditingController(text: widget.definition?.key);
  late final _label = TextEditingController(text: widget.definition?.label);
  late final _unit = TextEditingController(text: widget.definition?.unit);
  late String _scope = widget.definition?.scope ?? 'product';
  late final _sort = TextEditingController(
    text: '${widget.definition?.sortOrder ?? 0}',
  );
  late DefinitionKind _kind = widget.definition?.kind ?? DefinitionKind.number;
  late bool _active = widget.definition?.active ?? true;
  late final List<_OptionRow> _options = [
    for (final o in widget.definition?.options ?? const <SelectOption>[])
      _OptionRow(o.value, o.label),
  ];
  bool _busy = false;
  String? _error;

  bool get _editing => widget.definition != null;
  bool get _hasUnit =>
      _kind == DefinitionKind.number || _kind == DefinitionKind.range;

  @override
  void dispose() {
    for (final c in [_key, _label, _unit, _sort]) {
      c.dispose();
    }
    for (final o in _options) {
      o.value.dispose();
      o.label.dispose();
    }
    super.dispose();
  }

  /// Mirrors the server rules; returns an error message or null.
  String? _check() {
    final l = context.l10n;
    if (!_keyPattern.hasMatch(_key.text.trim())) return l.attrKeyInvalid;
    if (_label.text.trim().isEmpty) return l.attrLabelRequired;
    if (int.tryParse(_sort.text.trim()) == null) return l.sortOrderInvalid;
    if (_kind == DefinitionKind.select) {
      if (_options.isEmpty) return l.attrSelectNeedsOptions;
      final seen = <String>{};
      for (final o in _options) {
        final v = o.value.text.trim();
        if (v.isEmpty || o.label.text.trim().isEmpty) return l.attrOptionBlank;
        if (!seen.add(v)) return l.attrOptionDuplicate;
      }
    }
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
    final unit = _unit.text.trim();
    final body = AttributeDefinitionInput(
      key: _key.text.trim(),
      label: _label.text.trim(),
      kind: _kind,
      unit: _hasUnit && unit.isNotEmpty ? unit : null,
      options: _kind == DefinitionKind.select
          ? [
              for (final o in _options)
                SelectOption(
                  value: o.value.text.trim(),
                  label: o.label.text.trim(),
                ),
            ]
          : null,
      scope: _scope,
      sortOrder: int.parse(_sort.text.trim()),
      active: _active,
    );
    final products = ref.read(apiProvider).products;
    final d = widget.definition;
    final ok = await runAction(context, () async {
      if (d == null) {
        await products.createDefinition(body: body);
      } else {
        await products.updateDefinition(id: d.id, body: body);
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
    final kinds = {
      DefinitionKind.number: l.attrKindNumber,
      DefinitionKind.range: l.attrKindRange,
      DefinitionKind.select: l.attrKindSelect,
      DefinitionKind.text: l.attrKindText,
    };
    // The scopes on offer: product and the baseline item types (none when they cannot be read).
    final types =
        ref.watch(baselineTypesProvider).value ?? const <BaselineItemType>[];
    return AlertDialog(
      title: Text(_editing ? l.editAttrDef : l.newAttrDef),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('attrdef-key'),
                controller: _key,
                enabled: !_editing,
                autofocus: !_editing,
                decoration: InputDecoration(labelText: l.attrKey),
              ),
              TextField(
                key: const ValueKey('attrdef-label'),
                controller: _label,
                decoration: InputDecoration(labelText: l.attrLabel),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DefinitionKind>(
                key: const ValueKey('attrdef-kind'),
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.type),
                items: [
                  for (final e in kinds.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _editing
                    ? null
                    : (v) => setState(() => _kind = v ?? _kind),
              ),
              if (_hasUnit)
                TextField(
                  key: const ValueKey('attrdef-unit'),
                  controller: _unit,
                  decoration: InputDecoration(labelText: l.unit),
                ),
              DropdownButtonFormField<String>(
                key: const ValueKey('attrdef-scope'),
                initialValue: _scope,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.attrScope),
                items: [
                  DropdownMenuItem(
                    value: 'product',
                    child: Text(l.attrScopeProduct),
                  ),
                  for (final t in types)
                    DropdownMenuItem(
                      value: t.code,
                      child: Text('${t.name} (${t.code})'),
                    ),
                  // A scope whose type is gone stays visible (and fixed) when editing.
                  if (_scope != 'product' &&
                      !types.any((t) => t.code == _scope))
                    DropdownMenuItem(value: _scope, child: Text(_scope)),
                ],
                // Stored values refer to the scope, so it is fixed once created.
                onChanged: _editing
                    ? null
                    : (v) => setState(() => _scope = v ?? _scope),
              ),
              TextField(
                key: const ValueKey('attrdef-sort'),
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.sortOrder),
              ),
              SwitchListTile(
                key: const ValueKey('attrdef-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_kind == DefinitionKind.select) ...[
                Text(
                  l.attrOptions,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final (i, o) in _options.indexed)
                  Row(
                    key: ObjectKey(o),
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey('attrdef-option-value-$i'),
                          controller: o.value,
                          decoration: InputDecoration(
                            labelText: l.attrOptionValue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: ValueKey('attrdef-option-label-$i'),
                          controller: o.label,
                          decoration: InputDecoration(
                            labelText: l.attrOptionLabel,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('attrdef-option-remove-$i'),
                        tooltip: l.remove,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _options.removeAt(i)),
                      ),
                    ],
                  ),
                TextButton.icon(
                  key: const ValueKey('attrdef-option-add'),
                  onPressed: () => setState(() => _options.add(_OptionRow())),
                  icon: const Icon(Icons.add),
                  label: Text(l.attrAddOption),
                ),
              ],
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
          key: const ValueKey('attrdef-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
