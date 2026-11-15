import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/search_picker.dart';
import 'price_list_generate.dart';
import 'price_list_groups.dart';
import 'price_list_zones_exports.dart';
import 'price_lists_api.dart';

/// The editor of one price list: group tree, products, and generation of the PDF and Excel file.
class PriceListEditorPage extends ConsumerWidget {
  const PriceListEditorPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final list = ref.watch(priceListProvider(id));
    final groups = ref.watch(priceListGroupsProvider(id));
    final items = ref.watch(priceListItemsProvider(id));
    final canWrite = can(ref, 'price_lists.write');
    final failure = list.error ?? groups.error ?? items.error;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(errorMessage(failure))),
            TextButton(
              key: const ValueKey('ple-retry'),
              onPressed: () {
                ref.invalidate(priceListProvider(id));
                ref.invalidate(priceListGroupsProvider(id));
                ref.invalidate(priceListItemsProvider(id));
              },
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    if (!list.hasValue || !groups.hasValue || !items.hasValue) {
      return const Align(
        alignment: Alignment.topCenter,
        child: LinearProgressIndicator(),
      );
    }
    final pl = list.requireValue;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('ple-back'),
              tooltip: l.plBack,
              icon: const Icon(AppIcons.arrowBack),
              onPressed: () => context.go('/price-lists'),
            ),
            Expanded(
              child: Text(
                '${pl.code}  ${pl.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _GeneratePanel(list: pl),
        const SizedBox(height: 12),
        ZonesPanel(list: pl, canWrite: canWrite),
        const SizedBox(height: 12),
        PriceListGroupsPanel(
          list: pl,
          groups: groups.requireValue,
          canWrite: canWrite,
        ),
        const SizedBox(height: 12),
        ExportsPanel(list: pl, groups: groups.requireValue, canWrite: canWrite),
        const SizedBox(height: 12),
        _ItemsPanel(
          list: pl,
          groups: groups.requireValue,
          items: items.requireValue,
          canWrite: canWrite,
        ),
      ],
    );
  }
}

/// The Generate button: opens the dialog that plans and writes the files.
class _GeneratePanel extends StatelessWidget {
  const _GeneratePanel({required this.list});
  final PriceList list;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        key: const ValueKey('ple-generate'),
        onPressed: list.zones.isEmpty
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) => GenerateDialog(list: list),
              ),
        icon: const Icon(AppIcons.fileDownload),
        label: Text(l.plGenerate),
      ),
    );
  }
}

/// The products of the list in print order, with add, edit and remove.
class _ItemsPanel extends ConsumerStatefulWidget {
  const _ItemsPanel({
    required this.list,
    required this.groups,
    required this.items,
    required this.canWrite,
  });

  final PriceList list;
  final List<PriceListGroup> groups;
  final List<PriceListItem> items;
  final bool canWrite;

  @override
  ConsumerState<_ItemsPanel> createState() => _ItemsPanelState();
}

class _ItemsPanelState extends ConsumerState<_ItemsPanel> {
  String? _targetGroup;

  String get _lang => widget.list.publishedLanguages.first;

  void _refresh() {
    ref.invalidate(priceListItemsProvider(widget.list.id));
    ref.invalidate(priceListProvider(widget.list.id));
  }

  Future<void> _add(Product p, String groupId) async {
    final ok = await runAction(
      context,
      () async => ref
          .read(apiProvider)
          .products
          .createItem(
            id: widget.list.id,
            body: PriceListItemInput(productId: p.id, groupId: groupId),
          ),
    );
    if (ok && mounted) _refresh();
  }

  Future<void> _edit(PriceListItem it) async {
    final changed = await showDialog<PriceListItemUpdate>(
      context: context,
      builder: (_) => ItemDialog(
        item: it,
        groups: widget.groups,
        languages: widget.list.publishedLanguages,
      ),
    );
    if (changed == null || !mounted) return;
    final ok = await runAction(
      context,
      () async => ref
          .read(apiProvider)
          .products
          .updateItem(id: widget.list.id, itemId: it.id, body: changed),
      success: context.l10n.saved,
    );
    if (ok && mounted) _refresh();
  }

  Future<void> _remove(PriceListItem it) async {
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .products
          .deleteItem(id: widget.list.id, itemId: it.id),
    );
    if (ok && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final nodes = flattenGroups(widget.groups);
    final order = {for (var i = 0; i < nodes.length; i++) nodes[i].group.id: i};
    final byId = {for (final n in nodes) n.group.id: n.group};
    final sorted = [...widget.items]
      ..sort((a, b) {
        final c = (order[a.groupId] ?? 1 << 30).compareTo(
          order[b.groupId] ?? 1 << 30,
        );
        if (c != 0) return c;
        final k = compareSortKeys(a.sortKey, b.sortKey);
        return k != 0 ? k : a.productCode.compareTo(b.productCode);
      });
    final target = byId.containsKey(_targetGroup)
        ? _targetGroup
        : (nodes.isEmpty ? null : nodes.first.group.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.plItems, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.plNotPrintedNote, style: Theme.of(context).textTheme.bodySmall),
            if (widget.canWrite && target != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('pli-target'),
                      initialValue: target,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.plGroup),
                      items: [
                        for (final n in nodes)
                          DropdownMenuItem(
                            value: n.group.id,
                            child: Text(
                              '${'  ' * n.depth}${groupTitle(n.group, _lang)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _targetGroup = v),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: SearchPicker<Product>(
                      label: l.plAddProduct,
                      clearOnSelect: true,
                      display: (p) => '${p.code} · ${p.name}',
                      search: (q) async => (await ref
                              .read(apiProvider)
                              .products
                              .listProducts(q: q, active: true, limit: 20))
                          .items,
                      onSelected: (p) => _add(p, target),
                    ),
                  ),
                ],
              ),
            ] else if (widget.canWrite && nodes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.plNoGroups),
              ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              Text(l.plNoItems)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: [
                    DataColumn(label: Text(l.product)),
                    DataColumn(label: Text(l.plGroup)),
                    DataColumn(label: Text(l.plSortKey)),
                    DataColumn(label: Text('${l.plNet} / ${l.plIndicative}')),
                    const DataColumn(label: SizedBox.shrink()),
                  ],
                  rows: [
                    for (final it in sorted)
                      DataRow(
                        key: ValueKey('pli-${it.productCode}'),
                        cells: [
                          DataCell(
                            Text(
                              '${it.productCode} · ${it.description[_lang] ?? it.productName}',
                            ),
                          ),
                          DataCell(Text(
                            byId[it.groupId] == null
                                ? '—'
                                : groupTitle(byId[it.groupId]!, _lang),
                          )),
                          DataCell(Text(it.sortKey)),
                          DataCell(Text([
                            if (it.priceOnRequest) l.plPriceOnRequest,
                            if (it.net) l.plNet,
                            if (it.indicative) l.plIndicative,
                            if (it.hidden) '${l.plHidden} (${l.plNotPrinted})',
                          ].join(', '))),
                          DataCell(
                            widget.canWrite
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: ValueKey('pli-edit-${it.productCode}'),
                                        tooltip: l.edit,
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _edit(it),
                                      ),
                                      IconButton(
                                        key: ValueKey('pli-del-${it.productCode}'),
                                        tooltip: l.remove,
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _remove(it),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final _sortKeyPattern = RegExp(r'^[A-Za-z0-9]+(\.[A-Za-z0-9]+)*$');

/// Group, sort key, the four flags and a description per language of one item.
class ItemDialog extends StatefulWidget {
  const ItemDialog({
    super.key,
    required this.item,
    required this.groups,
    required this.languages,
  });

  final PriceListItem item;
  final List<PriceListGroup> groups;
  final List<String> languages;

  @override
  State<ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late String _group = widget.item.groupId;
  late final _key = TextEditingController(text: widget.item.sortKey);
  late bool _onRequest = widget.item.priceOnRequest;
  late bool _net = widget.item.net;
  late bool _indicative = widget.item.indicative;
  late bool _hidden = widget.item.hidden;
  late final Map<String, TextEditingController> _desc = {
    for (final c in widget.languages)
      c: TextEditingController(text: widget.item.description[c] ?? ''),
  };
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    for (final c in _desc.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final key = _key.text.trim();
    if (key.isNotEmpty && !_sortKeyPattern.hasMatch(key)) {
      setState(() => _error = context.l10n.plSortKeyInvalid);
      return;
    }
    Navigator.pop<PriceListItemUpdate>(
      context,
      PriceListItemUpdate(
        groupId: _group,
        sortKey: key,
        priceOnRequest: _onRequest,
        net: _net,
        indicative: _indicative,
        hidden: _hidden,
        description: {
          // Descriptions in languages the list does not use are kept.
          ...widget.item.description,
          for (final e in _desc.entries) e.key: e.value.text.trim(),
        }..removeWhere((_, v) => v.isEmpty),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final nodes = flattenGroups(widget.groups);
    final lang = widget.languages.first;
    Widget flag(String key, String label, bool v, ValueChanged<bool> on) =>
        SwitchListTile(
          key: ValueKey(key),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: v,
          onChanged: (x) => setState(() => on(x)),
        );
    return AlertDialog(
      title: Text('${widget.item.productCode} · ${widget.item.productName}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('pli-group'),
                initialValue: _group,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.plGroup),
                items: [
                  for (final n in nodes)
                    DropdownMenuItem(
                      value: n.group.id,
                      child: Text(
                        '${'  ' * n.depth}${groupTitle(n.group, lang)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _group = v ?? _group),
              ),
              TextField(
                key: const ValueKey('pli-sort-key'),
                controller: _key,
                decoration: InputDecoration(labelText: l.plSortKey),
              ),
              flag('pli-on-request', l.plPriceOnRequest, _onRequest,
                  (v) => _onRequest = v),
              flag('pli-net', l.plNet, _net, (v) => _net = v),
              flag('pli-indicative', l.plIndicative, _indicative,
                  (v) => _indicative = v),
              flag('pli-hidden', l.plHidden, _hidden, (v) => _hidden = v),
              for (final e in _desc.entries)
                TextField(
                  key: ValueKey('pli-desc-${e.key}'),
                  controller: e.value,
                  decoration: InputDecoration(
                    labelText:
                        '${l.plDescriptionOverride} (${languageName(e.key)})',
                  ),
                ),
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
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pli-ok'),
          onPressed: _ok,
          child: Text(l.save),
        ),
      ],
    );
  }
}
