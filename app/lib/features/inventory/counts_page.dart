import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import 'inventory_common.dart';
import '../../shared/app_icons.dart';

/// Stock counts: start one for a warehouse or location, count, then post the differences.
class CountsPage extends ConsumerStatefulWidget {
  const CountsPage({super.key});

  @override
  ConsumerState<CountsPage> createState() => _CountsPageState();
}

class _CountsPageState extends ConsumerState<CountsPage> {
  final _list = GlobalKey<EntityListState<Count>>();
  String? _status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final canWrite = hasPermission(ref, 'inventory.write');
    return EntityList<Count>(
      key: _list,
      title: l.stockCounts,
      // Searching and paging happen on the server, so older counts stay reachable.
      load: (q, offset, limit) async {
        final page = await api.inventory.listCounts(
          status: _status,
          q: q,
          limit: limit,
          offset: offset,
        );
        return (page.items, page.total);
      },
      filters: DropdownButton<String?>(
        value: _status,
        hint: Text(l.allStatuses),
        items: [
          DropdownMenuItem(value: null, child: Text(l.allStatuses)),
          for (final s in const ['counting', 'posted', 'cancelled'])
            DropdownMenuItem(value: s, child: Text(l.countStatus(s))),
        ],
        onChanged: (s) {
          setState(() => _status = s);
          _list.currentState?.reload();
        },
      ),
      columns: [
        EntityColumn(l.number, (c) => c.number, flex: 2),
        EntityColumn(
          l.stockWarehouses,
          (c) => c.locationCode == null
              ? c.warehouseCode
              : '${c.warehouseCode}/${c.locationCode}',
          flex: 2,
        ),
        EntityColumn(l.status, (c) => l.countStatus(c.status)),
        EntityColumn(
          l.countProgress,
          (c) => '${c.countedCount} / ${c.lineCount}',
          numeric: true,
        ),
        EntityColumn(l.date, (c) => date(c.createdAt)),
        EntityColumn(l.countedBy, (c) => c.createdByName, flex: 2),
      ],
      createLabel: l.countNew,
      onCreate: canWrite
          ? () async {
              final created = await showDialog<String>(
                context: context,
                builder: (_) => const _NewCountDialog(),
              );
              if (created != null && context.mounted) {
                await context.push<bool>('/stock/counts/$created');
                return true;
              }
              return false;
            }
          : null,
      locationOf: (c) => '/stock/counts/${c.id}',
      onOpen: (c) async =>
          await context.push<bool>('/stock/counts/${c.id}') ?? true,
    );
  }
}

class _NewCountDialog extends ConsumerStatefulWidget {
  const _NewCountDialog();

  @override
  ConsumerState<_NewCountDialog> createState() => _NewCountDialogState();
}

class _NewCountDialogState extends ConsumerState<_NewCountDialog> {
  String? _warehouse, _location, _productId;
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _create() async {
    if (_warehouse == null) {
      setState(() => _error = context.l10n.countWarehouseRequired);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await ref
          .read(apiProvider)
          .inventory
          .createCount(
            body: CountInput(
              warehouseId: _warehouse!,
              locationId: _location,
              productId: _productId,
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, d.count.id);
    } catch (e) {
      setState(() {
        _error = errorMessage(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final warehouses = (ref.watch(warehousesProvider).value ?? const [])
        .where((w) => w.active)
        .toList();
    final selected = warehouses.where((w) => w.id == _warehouse).firstOrNull;
    return AlertDialog(
      title: Text(l.countNew),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _warehouse,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.stockWarehouse),
              items: [
                for (final w in warehouses)
                  DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.code} · ${w.name}'),
                  ),
              ],
              onChanged: (v) => setState(() {
                _warehouse = v;
                _location = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey(_warehouse),
              initialValue: _location,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.stockLocation),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.countWholeWarehouse),
                ),
                for (final loc in selected?.locations ?? const <Location>[])
                  DropdownMenuItem<String?>(
                    value: loc.id,
                    child: Text(loc.code),
                  ),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
            const SizedBox(height: 12),
            SearchPicker<Product>(
              label: l.countOneProduct,
              display: (p) => '${p.code} · ${p.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .products
                          .listProducts(q: q, limit: 20))
                      .items
                      .where(
                        (p) =>
                            p.productType != 'service' &&
                            p.tracking != 'serial',
                      )
                      .toList(),
              onSelected: (p) => _productId = p.id,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.stockNote),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(l.countStart),
        ),
      ],
    );
  }
}

/// One count: enter the counted quantity per line, add stock that was not expected, then post
/// (inventory administrators) or cancel.
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  CountDetail? _d;
  final _controllers = <String, TextEditingController>{};
  String? _error;
  bool _busy = false;
  bool _changed = false;

  TradocraftApi get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _show(CountDetail d) {
    _d = d;
    for (final line in d.lines) {
      final text = line.countedQuantity == null
          ? ''
          : number(line.countedQuantity);
      final c = _controllers.putIfAbsent(
        line.id,
        () => TextEditingController(),
      );
      if (c.text.isEmpty || d.count.status != 'counting') c.text = text;
    }
  }

  Future<void> _load() async {
    try {
      final d = await _api.inventory.getCount(id: widget.id);
      if (mounted) setState(() => _show(d));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _run(Future<CountDetail> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await action();
      _changed = true;
      if (mounted) setState(() => _show(d));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends every typed quantity (also the cleared ones) to the server.
  Future<void> _save() async {
    final entries = <CountEntry>[];
    for (final line in _d!.lines) {
      final text = _controllers[line.id]?.text.trim() ?? '';
      final value = text.isEmpty ? null : parseDecimalInput(text);
      if (text.isNotEmpty && value == null) {
        setState(() => _error = context.l10n.countInvalidQuantity);
        return;
      }
      entries.add(CountEntry(lineId: line.id, countedQuantity: value));
    }
    await _run(
      () => _api.inventory.enterCounts(
        id: widget.id,
        body: CountEntries(entries: entries),
      ),
    );
  }

  Future<void> _post() async {
    await _save();
    if (_error != null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.countPost),
        content: Text(context.l10n.countPostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.countPost),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.inventory.postCount(id: widget.id));
  }

  Future<void> _addLine() async {
    final added = await showDialog<CountEntry>(
      context: context,
      builder: (_) => _AddLineDialog(count: _d!.count),
    );
    if (added == null) return;
    await _save();
    if (_error != null) return;
    await _run(
      () => _api.inventory.enterCounts(
        id: widget.id,
        body: CountEntries(entries: [added]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final d = _d;
    final canWrite = hasPermission(ref, 'inventory.write');
    final canAdmin = hasPermission(ref, 'inventory.admin');
    if (d == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    final c = d.count;
    final open = c.status == 'counting';
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.canPop()
                    ? context.pop(_changed)
                    : context.go('/stock/counts'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(c.number, style: theme.textTheme.headlineSmall),
              Chip(
                label: Text(l.countStatus(c.status)),
                visualDensity: VisualDensity.compact,
              ),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              InfoItem(
                l.stockWarehouse,
                c.locationCode == null
                    ? c.warehouseCode
                    : '${c.warehouseCode}/${c.locationCode}',
              ),
              InfoItem(l.countProgress, '${c.countedCount} / ${c.lineCount}'),
              InfoItem(l.countedBy, c.createdByName),
              InfoItem(l.date, date(c.createdAt)),
              if (c.note.isNotEmpty) InfoItem(l.stockNote, c.note),
            ],
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (open)
            Card(
              key: const ValueKey('count-warning'),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  AppIcons.warningAmber,
                  color: theme.colorScheme.onErrorContainer,
                ),
                title: Text(
                  l.countOverwriteWarning,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          if (c.status == 'posted' && d.movedDuringCount > 0)
            Card(
              key: const ValueKey('count-moved'),
              child: ListTile(
                leading: const Icon(AppIcons.info),
                title: Text(l.countMovedDuring(d.movedDuringCount)),
              ),
            ),
          if (open && canWrite)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(AppIcons.save),
                  label: Text(l.save),
                  onPressed: _busy ? null : _save,
                ),
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.add),
                  label: Text(l.countAddLine),
                  onPressed: _busy ? null : _addLine,
                ),
                if (canAdmin)
                  FilledButton.tonalIcon(
                    icon: const Icon(AppIcons.checkCircle),
                    label: Text(l.countPost),
                    onPressed: _busy ? null : _post,
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _api.inventory.cancelCount(id: widget.id),
                        ),
                  child: Text(l.countCancel),
                ),
              ],
            ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(l.product, style: theme.textTheme.labelLarge),
              ),
              Expanded(
                flex: 2,
                child: Text(l.stockLocation, style: theme.textTheme.labelLarge),
              ),
              Expanded(
                child: Text(l.stockLot, style: theme.textTheme.labelLarge),
              ),
              Expanded(
                child: Text(
                  l.countExpected,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  l.countCounted,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  l.countDifference,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          for (final line in d.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                key: ValueKey(line.id),
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('${line.productCode} · ${line.productName}'),
                  ),
                  Expanded(flex: 2, child: Text(line.location)),
                  Expanded(child: Text(line.lotNumber ?? '')),
                  Expanded(
                    child: Text(
                      '${number(line.expectedQuantity)} ${line.unit}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: open && canWrite
                        ? TextField(
                            controller: _controllers[line.id],
                            onChanged: (_) => setState(() {}),
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(isDense: true),
                          )
                        : Text(
                            number(line.countedQuantity),
                            textAlign: TextAlign.end,
                          ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Tooltip(
                      message: line.quantityAtPost == null
                          ? ''
                          : l.countStockAtPost(number(line.quantityAtPost)),
                      child: Text(
                        _difference(line),
                        textAlign: TextAlign.end,
                        style: TextStyle(color: _differenceColor(theme, line)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Counted minus expected, as the count screen shows it while typing.
  String _difference(CountLine line) {
    final counted = parseDecimalInput(_controllers[line.id]?.text ?? '');
    final c = counted == null ? null : Decimal.tryParse(counted);
    final expected = Decimal.tryParse(line.expectedQuantity);
    if (c == null || expected == null) return '';
    final diff = c - expected;
    if (diff == Decimal.zero) return '0';
    return '${diff > Decimal.zero ? '+' : ''}${number(diff.toString())}';
  }

  Color? _differenceColor(ThemeData theme, CountLine line) {
    final text = _difference(line);
    if (text.isEmpty || text == '0') return null;
    return text.startsWith('+')
        ? Colors.green.shade700
        : theme.colorScheme.error;
  }
}

class _AddLineDialog extends ConsumerStatefulWidget {
  const _AddLineDialog({required this.count});
  final Count count;

  @override
  ConsumerState<_AddLineDialog> createState() => _AddLineDialogState();
}

class _AddLineDialogState extends ConsumerState<_AddLineDialog> {
  Product? _product;
  String? _location;
  final _qty = TextEditingController();
  final _lot = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final warehouse = (ref.watch(warehousesProvider).value ?? const [])
        .where((w) => w.id == widget.count.warehouseId)
        .firstOrNull;
    final locations = [
      for (final loc in warehouse?.locations ?? const <Location>[])
        if (loc.active &&
            (widget.count.locationId == null ||
                loc.id == widget.count.locationId))
          loc,
    ];
    return AlertDialog(
      title: Text(l.countAddLine),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPicker<Product>(
              label: l.product,
              display: (p) => '${p.code} · ${p.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .products
                          .listProducts(q: q, limit: 20))
                      .items
                      .where(
                        (p) =>
                            p.productType != 'service' &&
                            p.tracking != 'serial' &&
                            // A count of one product only takes lines of that product.
                            (widget.count.productId == null ||
                                p.id == widget.count.productId),
                      )
                      .toList(),
              onSelected: (p) => setState(() => _product = p),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _location,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.stockLocation),
              items: [
                for (final loc in locations)
                  DropdownMenuItem(value: loc.id, child: Text(loc.code)),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
            if (_product?.tracking == 'lot') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _lot,
                decoration: InputDecoration(labelText: l.stockLotNumber),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l.countCounted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            final q = parseDecimalInput(_qty.text);
            if (_product == null || _location == null || q == null) return;
            Navigator.pop(
              context,
              CountEntry(
                productId: _product!.id,
                locationId: _location,
                lotNumber: _lot.text.trim().isEmpty ? null : _lot.text.trim(),
                countedQuantity: q,
              ),
            );
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
