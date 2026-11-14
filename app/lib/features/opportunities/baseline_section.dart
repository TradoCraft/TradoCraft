import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../products/suitability_logic.dart';
import 'baseline_logic.dart';

final _baselineProvider = FutureProvider.autoDispose
    .family<List<BaselineItem>, String>(
      (ref, id) => ref.watch(apiProvider).crm.getBaseline(id: id),
    );

final _typesProvider = FutureProvider.autoDispose<List<BaselineItemType>>(
  (ref) => ref.watch(apiProvider).crm.listTypes(),
);

/// The definitions of one item type (scope = type code), inactive ones included; the form uses
/// the active ones, the summary shows every stored value.
final _scopeDefsProvider = FutureProvider.autoDispose
    .family<List<AttributeDefinition>, String>((ref, scope) async {
      final all = await ref
          .watch(apiProvider)
          .products
          .listDefinitions(scope: scope);
      return [
        for (final d in all)
          if (d.scope == scope) d,
      ];
    });

/// The site baseline of an opportunity (ADR 0068): what the customer already has at the site as a
/// tree (a group holds its bells). Items are added and edited with a form generated from the
/// admin-defined attributes of their type. Read-only without `opportunities.write`.
class BaselineSection extends ConsumerWidget {
  const BaselineSection({super.key, required this.opportunityId});
  final String opportunityId;

  void _refresh(WidgetRef ref) =>
      ref.invalidate(_baselineProvider(opportunityId));

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required List<BaselineItemType> types,
    required List<BaselineItem> tree,
    BaselineItem? item,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BaselineItemDialog(
        opportunityId: opportunityId,
        types: types,
        tree: tree,
        item: item,
      ),
    );
    if (saved == true) _refresh(ref);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BaselineItem item,
    String label,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.baselineDeleteConfirm(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('baseline-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    // A 409 (the item has children) is shown as the server's message.
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .crm
          .deleteItem(id: opportunityId, itemId: item.id),
      success: l.baselineDeleted,
    );
    if (ok) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canWrite = can(ref, 'opportunities.write');
    final tree = ref.watch(_baselineProvider(opportunityId));
    final types = ref.watch(_typesProvider);
    final typeList = types.value ?? const <BaselineItemType>[];
    final typeNames = {for (final t in typeList) t.code: t.name};
    final items = tree.value ?? const <BaselineItem>[];
    // Definitions per type present in the tree, for the one-line summaries.
    final defs = {
      for (final code in {for (final i in flattenBaseline(items)) i.typeCode})
        code: ref.watch(_scopeDefsProvider(code)).value ?? const [],
    };

    Widget node(BaselineItem item, int depth) {
      final typeName = typeNames[item.typeCode] ?? item.typeCode;
      final label = (item.name ?? '').isEmpty
          ? typeName
          : '$typeName · ${item.name}';
      final summary = summarizeValues(
        defs[item.typeCode] ?? const [],
        item.values,
      );
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 24.0 * depth),
            child: ListTile(
              key: ValueKey('baseline-item-${item.id}'),
              dense: true,
              title: Text(label),
              subtitle: summary.isEmpty ? null : Text(summary),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.quantity != 1) Text(l.baselineQty(item.quantity)),
                  if (canWrite) ...[
                    IconButton(
                      key: ValueKey('baseline-edit-${item.id}'),
                      tooltip: l.edit,
                      icon: const Icon(AppIcons.edit),
                      onPressed: () => _edit(
                        context,
                        ref,
                        types: typeList,
                        tree: items,
                        item: item,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('baseline-delete-${item.id}'),
                      tooltip: l.delete,
                      icon: const Icon(AppIcons.delete),
                      onPressed: () => _delete(context, ref, item, label),
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (final c in item.children) node(c, depth + 1),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.baselineTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (canWrite)
              FilledButton.tonalIcon(
                key: const ValueKey('baseline-add'),
                icon: const Icon(AppIcons.add),
                label: Text(l.baselineAdd),
                onPressed: !tree.hasValue || !types.hasValue
                    ? null
                    : () => _edit(context, ref, types: typeList, tree: items),
              ),
          ],
        ),
        if (tree.hasError || types.hasError)
          Row(
            children: [
              Expanded(child: Text(errorMessage(tree.error ?? types.error!))),
              TextButton(
                onPressed: () {
                  ref.invalidate(_baselineProvider(opportunityId));
                  ref.invalidate(_typesProvider);
                },
                child: Text(l.retry),
              ),
            ],
          )
        else if (!tree.hasValue)
          const LinearProgressIndicator()
        else if (items.isEmpty)
          Padding(
            key: const ValueKey('baseline-empty'),
            padding: const EdgeInsets.all(8),
            child: Text(l.baselineEmpty),
          )
        else
          for (final i in items) node(i, 0),
      ],
    );
  }
}

/// Handle through which the dialog reads the inputs of the generated fields.
class _FieldsHandle {
  Map<String, List<String>> Function() read = () => const {};
}

/// Create ([item] null) or edit dialog of a baseline item; pops true when saved. The type of an
/// existing item is fixed; the parent is limited to items of a type allowed as parent.
class BaselineItemDialog extends ConsumerStatefulWidget {
  const BaselineItemDialog({
    super.key,
    required this.opportunityId,
    required this.types,
    required this.tree,
    this.item,
  });
  final String opportunityId;
  final List<BaselineItemType> types;
  final List<BaselineItem> tree;
  final BaselineItem? item;

  @override
  ConsumerState<BaselineItemDialog> createState() => _BaselineItemDialogState();
}

class _BaselineItemDialogState extends ConsumerState<BaselineItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _quantity = TextEditingController(
    text: '${widget.item?.quantity ?? 1}',
  );
  final _handle = _FieldsHandle();
  late String? _type = widget.item?.typeCode;
  late String? _parent = widget.item?.parentId;
  Map<String, AttrError> _errors = {};
  String? _error;
  bool _busy = false;

  bool get _editing => widget.item != null;

  BaselineItemType? get _typeObj =>
      widget.types.where((t) => t.code == _type).firstOrNull;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  String _message(AttrError e) {
    final l = context.l10n;
    return switch (e) {
      AttrError.notNumber => l.attrEnterNumber,
      AttrError.rangeIncomplete => l.attrRangeIncomplete,
      AttrError.rangeOrder => l.attrRangeOrder,
      AttrError.notInOptions => l.attrNotInOptions,
    };
  }

  String _itemLabel(BaselineItem i) {
    final t = widget.types.where((t) => t.code == i.typeCode).firstOrNull;
    final typeName = t?.name ?? i.typeCode;
    return (i.name ?? '').isEmpty ? typeName : '$typeName · ${i.name}';
  }

  Future<void> _save(List<AttributeDefinition> active) async {
    final l = context.l10n;
    final type = _typeObj;
    if (type == null) {
      setState(() => _error = l.baselineTypeRequired);
      return;
    }
    final qty = int.tryParse(_quantity.text.trim());
    if (qty == null || qty < 1) {
      setState(() => _error = l.baselineQuantityInvalid);
      return;
    }
    if (_parent == null && !type.allowTopLevel) {
      setState(() => _error = l.baselineParentRequired);
      return;
    }
    final r = buildValues(
      defs: active,
      existing: widget.item?.values,
      raw: _handle.read(),
    );
    if (r.errors.isNotEmpty) {
      setState(() {
        _errors = r.errors;
        _error = null;
      });
      return;
    }
    setState(() {
      _errors = {};
      _error = null;
      _busy = true;
    });
    final name = _name.text.trim();
    final crm = ref.read(apiProvider).crm;
    try {
      final item = widget.item;
      if (item == null) {
        await crm.createItem(
          id: widget.opportunityId,
          body: BaselineItemInput(
            typeCode: type.code,
            name: name.isEmpty ? null : name,
            parentId: _parent,
            quantity: qty,
            values: r.values,
          ),
        );
      } else {
        await crm.updateItem(
          id: widget.opportunityId,
          itemId: item.id,
          body: BaselineItemUpdate(
            name: name.isEmpty ? null : name,
            parentId: _parent,
            quantity: qty,
            values: r.values,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
        });
      }
    }
  }

  Widget _parentField(BaselineItemType type) {
    final l = context.l10n;
    final candidates = parentCandidates(
      type,
      widget.tree,
      movingId: widget.item?.id,
    );
    final valid = candidates.any((c) => c.id == _parent);
    return KeyedSubtree(
      key: ValueKey('parent-for-${type.code}'),
      child: DropdownButtonFormField<String>(
        key: const ValueKey('baseline-parent'),
        initialValue: valid ? _parent : (type.allowTopLevel ? '' : null),
        isExpanded: true,
        decoration: InputDecoration(labelText: l.baselineParent),
        items: [
          if (type.allowTopLevel)
            DropdownMenuItem(value: '', child: Text(l.baselineTopLevel)),
          for (final c in candidates)
            DropdownMenuItem(value: c.id, child: Text(_itemLabel(c))),
        ],
        onChanged: (v) => _parent = (v == null || v.isEmpty) ? null : v,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final active = [
      for (final t in widget.types)
        if (t.active || t.code == widget.item?.typeCode) t,
    ];
    final type = _typeObj;
    final defsAsync = type == null
        ? null
        : ref.watch(_scopeDefsProvider(type.code));
    final activeDefs = [
      for (final d in defsAsync?.value ?? const <AttributeDefinition>[])
        if (d.active) d,
    ];
    return AlertDialog(
      title: Text(_editing ? l.baselineEditItem : l.baselineNewItem),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (active.isEmpty)
                Text(l.baselineNoTypes)
              else ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('baseline-type'),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.type),
                  items: [
                    for (final t in active)
                      DropdownMenuItem(value: t.code, child: Text(t.name)),
                  ],
                  onChanged: _editing
                      ? null
                      : (v) => setState(() {
                          _type = v;
                          _parent = null;
                          _errors = {};
                        }),
                ),
                if (type != null) _parentField(type),
                TextField(
                  key: const ValueKey('baseline-name'),
                  controller: _name,
                  decoration: InputDecoration(labelText: l.name),
                ),
                TextField(
                  key: const ValueKey('baseline-quantity'),
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.quantity),
                ),
                const SizedBox(height: 8),
                if (type != null && defsAsync!.isLoading)
                  const LinearProgressIndicator()
                else if (defsAsync?.hasError ?? false)
                  Text(errorMessage(defsAsync!.error!))
                else if (type != null && activeDefs.isEmpty)
                  Text(l.baselineNoFields)
                else if (type != null)
                  _Fields(
                    key: ValueKey('fields-${type.code}'),
                    defs: activeDefs,
                    stored: widget.item?.values,
                    handle: _handle,
                    errors: _errors,
                    message: _message,
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
          key: const ValueKey('baseline-save'),
          onPressed: _busy || active.isEmpty ? null : () => _save(activeDefs),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// One input per active definition of the item type (number with unit, range min/max, select
/// dropdown, text), like the suitability tab of a product.
class _Fields extends StatefulWidget {
  const _Fields({
    super.key,
    required this.defs,
    required this.stored,
    required this.handle,
    required this.errors,
    required this.message,
  });
  final List<AttributeDefinition> defs;
  final Object? stored;
  final _FieldsHandle handle;
  final Map<String, AttrError> errors;
  final String Function(AttrError) message;

  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  late final Map<String, List<TextEditingController>> _c = {};
  late final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    final raw = rawFromValues(widget.defs, widget.stored);
    for (final d in widget.defs) {
      final v = raw[d.key]!;
      if (d.kind == DefinitionKind.select) {
        _selected[d.key] = v.first;
      } else {
        _c[d.key] = [for (final t in v) TextEditingController(text: t)];
      }
    }
    widget.handle.read = () => {
      for (final d in widget.defs)
        d.key: d.kind == DefinitionKind.select
            ? [_selected[d.key] ?? '']
            : [for (final c in _c[d.key]!) c.text],
    };
  }

  @override
  void dispose() {
    for (final list in _c.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  static const _numberKeyboard = TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  );

  Widget _field(AttributeDefinition d) {
    final l = context.l10n;
    final err = widget.errors[d.key];
    final suffix = (d.unit ?? '').isEmpty ? null : d.unit;
    switch (d.kind) {
      case DefinitionKind.range:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('bl-attr-${d.key}-min'),
                controller: _c[d.key]![0],
                keyboardType: _numberKeyboard,
                decoration: InputDecoration(
                  labelText: '${d.label} ${l.attrMin}',
                  suffixText: suffix,
                  errorText: err == null ? null : widget.message(err),
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: ValueKey('bl-attr-${d.key}-max'),
                controller: _c[d.key]![1],
                keyboardType: _numberKeyboard,
                decoration: InputDecoration(
                  labelText: '${d.label} ${l.attrMax}',
                  suffixText: suffix,
                ),
              ),
            ),
          ],
        );
      case DefinitionKind.select:
        final current = _selected[d.key] ?? '';
        final known = d.options.any((o) => o.value == current);
        return DropdownButtonFormField<String>(
          key: ValueKey('bl-attr-${d.key}'),
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: d.label,
            errorText: err == null ? null : widget.message(err),
          ),
          items: [
            DropdownMenuItem(value: '', child: Text(l.none)),
            for (final o in d.options)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
            // A stored value that is no longer an option stays visible until changed.
            if (current.isNotEmpty && !known)
              DropdownMenuItem(value: current, child: Text(current)),
          ],
          onChanged: (v) => _selected[d.key] = v ?? '',
        );
      case DefinitionKind.number:
      case DefinitionKind.text:
      case DefinitionKind.$unknown:
        final isNumber = d.kind == DefinitionKind.number;
        return TextField(
          key: ValueKey('bl-attr-${d.key}'),
          controller: _c[d.key]![0],
          keyboardType: isNumber ? _numberKeyboard : TextInputType.text,
          decoration: InputDecoration(
            labelText: d.label,
            suffixText: isNumber ? suffix : null,
            errorText: err == null ? null : widget.message(err),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final d in widget.defs)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: _field(d)),
    ],
  );
}
