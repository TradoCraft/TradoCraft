import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/csv_transfer.dart';
import '../products/suitability_logic.dart';
import 'baseline_logic.dart';
import 'matches_panel.dart';

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

/// Opens the saved site's baseline without leaving the current screen.
Future<void> showSiteBaseline(
  BuildContext context, {
  required String opportunityId,
}) {
  // The opportunity may still be open underneath this screen.
  ProviderScope.containerOf(
    context,
    listen: false,
  ).invalidate(_baselineProvider(opportunityId));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      semanticLabel: dialogContext.l10n.baselineTitle,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: BaselineSection(opportunityId: opportunityId),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.l10n.close),
        ),
      ],
    ),
  );
}

/// The site baseline of an opportunity (ADR 0068): what the customer already has at the site as a
/// tree (a group holds its bells). Items are added and edited with a form generated from the
/// admin-defined attributes of their type. Read-only without `opportunities.write`.
class BaselineSection extends ConsumerWidget {
  const BaselineSection({super.key, required this.opportunityId});
  final String opportunityId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(_baselineProvider(opportunityId));
    ref.invalidate(productMatchesProvider);
  }

  /// Picks a tower configurator export, previews it with a dry run and imports it on confirm.
  Future<void> _importTower(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final PickedFile? file;
    try {
      file = await ref.read(jsonPickerProvider)();
    } catch (_) {
      // The picker or reading the chosen file failed (permissions, a file that vanished).
      messenger.showSnackBar(
        SnackBar(content: Text(l.baselineImportReadFailed)),
      );
      return;
    }
    if (file == null || !context.mounted) return;
    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(file.bytes));
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(l.baselineImportBadFile)));
      return;
    }
    final crm = ref.read(apiProvider).crm;
    final BaselineImportReport preview;
    try {
      preview = await crm.importBaseline(
        id: opportunityId,
        body: doc,
        dryRun: true,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TowerImportDialog(
        preview: preview,
        run: () => crm.importBaseline(
          id: opportunityId,
          body: doc,
          dryRun: false,
          sourceId: preview.sourceId,
        ),
      ),
    );
    if (done == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.baselineImportDone)));
      // The screen may have been closed while the import ran: then there is nothing to refresh.
      if (context.mounted) _refresh(ref);
    }
  }

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
    if (saved == true && context.mounted) _refresh(ref);
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
    final container = ProviderScope.containerOf(context, listen: false);
    // A 409 (the item has children) is shown as the server's message.
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .crm
          .deleteItem(id: opportunityId, itemId: item.id),
      success: l.baselineDeleted,
    );
    if (!ok) return;
    if (context.mounted) {
      _refresh(ref);
    } else {
      container.invalidate(productMatchesProvider);
    }
  }

  /// Edits one attribute of an item in place; pops true when saved.
  Future<void> _quickEdit(
    BuildContext context,
    WidgetRef ref,
    BaselineItem item,
    AttributeDefinition def,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BaselineQuickEditDialog(
        opportunityId: opportunityId,
        item: item,
        def: def,
      ),
    );
    if (saved == true && context.mounted) _refresh(ref);
  }

  /// One chip per active attribute of the item: the value, tap to change it; an attribute without
  /// a value is flagged "unknown - set" (the matcher judges it as unknown until it is filled in).
  /// Stored values of attributes that are no longer active are shown but not editable.
  Widget? _valueChips(
    BuildContext context,
    WidgetRef ref,
    BaselineItem item,
    List<AttributeDefinition> itemDefs,
  ) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final stored = item.values is Map ? item.values as Map : const {};
    final chips = <Widget>[
      for (final d in itemDefs)
        if (d.active)
          stored[d.key] == null
              ? ActionChip(
                  key: ValueKey('baseline-chip-${item.id}-${d.key}'),
                  avatar: Icon(
                    AppIcons.edit,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  backgroundColor: scheme.errorContainer,
                  label: Text(
                    l.baselineUnknownSet(d.label),
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                  onPressed: () => _quickEdit(context, ref, item, d),
                )
              : ActionChip(
                  key: ValueKey('baseline-chip-${item.id}-${d.key}'),
                  label: Text(
                    '${d.label} ${describeValue(d, stored[d.key], yes: l.yes, no: l.no)}',
                  ),
                  onPressed: () => _quickEdit(context, ref, item, d),
                )
        else if (stored[d.key] != null)
          Chip(
            label: Text(
              '${d.label} ${describeValue(d, stored[d.key], yes: l.yes, no: l.no)}',
            ),
          ),
    ];
    // Stored values without a (known) definition stay visible, read-only.
    final known = {for (final d in itemDefs) d.key};
    for (final e in stored.entries) {
      if (e.value == null || known.contains(e.key)) continue;
      chips.add(
        Chip(
          key: ValueKey('baseline-undefined-${item.id}-${e.key}'),
          label: Text('${e.key}: ${e.value}'),
        ),
      );
    }
    if (chips.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canWrite = can(ref, 'opportunities.write');
    final canSuggest = can(ref, 'products.read');
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

    Widget node(BaselineItem item, int depth, double width) {
      final typeName = typeNames[item.typeCode] ?? item.typeCode;
      final label = (item.name ?? '').isEmpty
          ? typeName
          : '$typeName · ${item.name}';
      final itemDefs = defs[item.typeCode] ?? const <AttributeDefinition>[];
      final summary = summarizeValues(
        itemDefs,
        item.values,
        yes: l.yes,
        no: l.no,
      );
      final values = canWrite
          ? _valueChips(context, ref, item, itemDefs)
          : (summary.isEmpty ? null : Text(summary));
      final actions = <Widget>[
        if (item.quantity != 1) Text(l.baselineQty(item.quantity)),
        if (canSuggest)
          IconButton(
            key: ValueKey('baseline-suggest-${item.id}'),
            tooltip: l.matchesSuggest,
            icon: const Icon(AppIcons.search),
            onPressed: () => showSuggestedProducts(
              context,
              opportunityId: opportunityId,
              itemId: item.id,
              itemLabel: label,
            ),
          ),
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
      ];
      final indentation = depth * (width < 400 ? 12.0 : 24.0);
      final compact = width - indentation < 320;
      return Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(start: indentation),
            child: ListTile(
              key: ValueKey('baseline-item-${item.id}'),
              dense: true,
              title: Text(
                item.importSource == null
                    ? label
                    : '$label · ${l.baselineImported}',
              ),
              subtitle: compact && actions.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ?values,
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ],
                    )
                  : values,
              trailing: compact || actions.isEmpty
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
          for (final c in item.children) node(c, depth + 1, width),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final title = Text(
              l.baselineTitle,
              style: Theme.of(context).textTheme.titleMedium,
            );
            if (!canWrite) return title;
            final importButton = OutlinedButton.icon(
              key: const ValueKey('baseline-import-tower'),
              icon: const Icon(AppIcons.fileUpload),
              label: Text(l.baselineImportTower),
              onPressed: () => _importTower(context, ref),
            );
            final addButton = FilledButton.tonalIcon(
              key: const ValueKey('baseline-add'),
              icon: const Icon(AppIcons.add),
              label: Text(l.baselineAdd),
              onPressed: !tree.hasValue || !types.hasValue
                  ? null
                  : () => _edit(context, ref, types: typeList, tree: items),
            );
            // Title and both buttons fit on one line from about this width; on a narrow screen
            // the buttons wrap onto their own line below the title.
            if (box.maxWidth >= 560) {
              return Row(
                children: [
                  Expanded(child: title),
                  importButton,
                  const SizedBox(width: 8),
                  addButton,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [importButton, addButton],
                ),
              ],
            );
          },
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
          LayoutBuilder(
            builder: (_, box) => Column(
              children: [for (final i in items) node(i, 0, box.maxWidth)],
            ),
          ),
      ],
    );
  }
}

/// What an import would do (from its dry run), with Confirm and Cancel. The real import runs
/// here; the dialog cannot be left while it runs. Pops true when the import went through.
class _TowerImportDialog extends StatefulWidget {
  const _TowerImportDialog({required this.preview, required this.run});
  final BaselineImportReport preview;
  final Future<BaselineImportReport> Function() run;

  @override
  State<_TowerImportDialog> createState() => _TowerImportDialogState();
}

class _TowerImportDialogState extends State<_TowerImportDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.run();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = widget.preview;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.baselineImportTitle),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.baselineImportCreates(
                    p.created.bellGroup,
                    p.created.bell,
                    p.created.clockDial,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  p.replaced > 0
                      ? l.baselineImportReplaces(p.replaced)
                      : l.baselineImportFresh,
                ),
                if (p.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.baselineImportWarnings,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final w in p.warnings)
                    Text(
                      l.baselineImportWarning(w.bell ?? '', w.field, w.message),
                    ),
                ],
                if (p.unmappedFields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.baselineImportUnmapped,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    [
                      for (final u in p.unmappedFields)
                        l.baselineImportUnmappedRow(u.field, u.count),
                    ].join(', '),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('baseline-import-cancel'),
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('baseline-import-confirm'),
            onPressed: _busy ? null : _confirm,
            child: Text(l.baselineImportConfirm),
          ),
        ],
      ),
    );
  }
}

/// Sets one attribute of an existing item without the full item dialog: the same input as the
/// form, the other values, name, parent and quantity are sent back unchanged. Pops true when saved.
/// Reusable wherever a baseline item is shown (for example a quotation view of the baseline).
class BaselineQuickEditDialog extends ConsumerStatefulWidget {
  const BaselineQuickEditDialog({
    super.key,
    required this.opportunityId,
    required this.item,
    required this.def,
  });
  final String opportunityId;
  final BaselineItem item;
  final AttributeDefinition def;

  @override
  ConsumerState<BaselineQuickEditDialog> createState() =>
      _BaselineQuickEditDialogState();
}

class _BaselineQuickEditDialogState
    extends ConsumerState<BaselineQuickEditDialog> {
  final _handle = _FieldsHandle();
  Map<String, AttrError> _errors = {};
  String? _error;
  bool _busy = false;

  String _message(AttrError e) {
    final l = context.l10n;
    return switch (e) {
      AttrError.notNumber => l.attrEnterNumber,
      AttrError.rangeIncomplete => l.attrRangeIncomplete,
      AttrError.rangeOrder => l.attrRangeOrder,
      AttrError.notInOptions => l.attrNotInOptions,
    };
  }

  Future<void> _save() async {
    final item = widget.item;
    final r = buildValues(
      defs: [widget.def],
      existing: item.values,
      raw: _handle.read(),
    );
    if (r.errors.isNotEmpty) {
      setState(() => _errors = r.errors);
      return;
    }
    setState(() {
      _errors = {};
      _error = null;
      _busy = true;
    });
    try {
      await ref
          .read(apiProvider)
          .crm
          .updateItem(
            id: widget.opportunityId,
            itemId: item.id,
            body: BaselineItemUpdate(
              name: item.name,
              parentId: item.parentId,
              quantity: item.quantity,
              values: r.values,
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // A route pop must not close the dialog while the save is under way.
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.def.label),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Fields(
                  defs: [widget.def],
                  stored: widget.item.values,
                  handle: _handle,
                  errors: _errors,
                  message: _message,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
            key: const ValueKey('baseline-quick-save'),
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ],
      ),
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
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      if (d.kind == DefinitionKind.select || d.kind == DefinitionKind.boolean) {
        _selected[d.key] = v.first;
      } else {
        _c[d.key] = [for (final t in v) TextEditingController(text: t)];
      }
    }
    widget.handle.read = () => {
      for (final d in widget.defs)
        d.key: _selected.containsKey(d.key)
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
      case DefinitionKind.boolean:
        return DropdownButtonFormField<String>(
          key: ValueKey('bl-attr-${d.key}'),
          initialValue: _selected[d.key] ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: d.label,
            errorText: err == null ? null : widget.message(err),
          ),
          items: [
            DropdownMenuItem(value: '', child: Text(l.none)),
            DropdownMenuItem(value: 'true', child: Text(l.yes)),
            DropdownMenuItem(value: 'false', child: Text(l.no)),
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
