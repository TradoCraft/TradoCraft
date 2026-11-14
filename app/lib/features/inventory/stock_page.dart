import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../tutorial/targets.dart';
import 'inventory_common.dart';
import 'move_dialogs.dart';
import '../../shared/app_icons.dart';

/// Stock overview: one row per product with on hand, reserved and available, filterable by
/// warehouse, with shortcuts to receive, issue and transfer.
class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _list = GlobalKey<EntityListState<ProductStock>>();
  String? _warehouse;
  bool _inStock = false;
  bool _below = false;

  void _reload() => _list.currentState?.reload();

  Future<bool> _move(MoveKind kind) async =>
      await showMoveDialog(context, kind) == true;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final canWrite = hasPermission(ref, 'inventory.write');
    final warehouses = ref.watch(warehousesProvider).value ?? const [];
    return EntityList<ProductStock>(
      key: _list,
      title: l.stockTitle,
      load: (q, offset, limit) async {
        final page = await api.inventory.listProductStock(
          q: q,
          warehouseId: _warehouse,
          inStock: _inStock ? true : null,
          belowReorder: _below ? true : null,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      filters: DropdownButton<String?>(
        value: _warehouse,
        hint: Text(l.stockAllWarehouses),
        items: [
          DropdownMenuItem(value: null, child: Text(l.stockAllWarehouses)),
          for (final w in warehouses)
            DropdownMenuItem(value: w.id, child: Text('${w.code} · ${w.name}')),
        ],
        onChanged: (v) {
          setState(() => _warehouse = v);
          _reload();
        },
      ),
      moreFilters: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: Text(l.stockOnlyInStock),
            selected: _inStock,
            onSelected: (v) {
              setState(() => _inStock = v);
              _reload();
            },
          ),
          FilterChip(
            label: Text(l.stockBelowReorder),
            selected: _below,
            onSelected: (v) {
              setState(() => _below = v);
              _reload();
            },
          ),
        ],
      ),
      actions: [
        if (canWrite) ...[
          OutlinedButton.icon(
            icon: const Icon(AppIcons.moveToInbox),
            label: Text(l.stockReceive),
            onPressed: () async {
              if (await _move(MoveKind.receive)) _reload();
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.outbox),
            label: Text(l.stockIssue),
            onPressed: () async {
              if (await _move(MoveKind.issue)) _reload();
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.swapHoriz),
            label: Text(l.stockTransfer),
            onPressed: () async {
              if (await _move(MoveKind.transfer)) _reload();
            },
          ),
        ],
        OutlinedButton.icon(
          icon: const Icon(AppIcons.factCheck),
          label: Text(l.stockCounts),
          onPressed: () => context.push('/stock/counts'),
        ),
        TutorialTarget(
          id: 'stock-warehouses',
          child: OutlinedButton.icon(
            icon: const Icon(AppIcons.warehouse),
            label: Text(l.stockWarehouses),
            onPressed: () => context.push('/stock/warehouses'),
          ),
        ),
      ],
      columns: [
        EntityColumn(l.code, (p) => p.code),
        EntityColumn(l.name, (p) => p.name, flex: 3),
        EntityColumn(
          l.stockOnHand,
          (p) => '${number(p.onHand)} ${p.unit}',
          numeric: true,
        ),
        EntityColumn(l.stockReserved, (p) => number(p.reserved), numeric: true),
        EntityColumn(
          l.stockAvailable,
          (p) => number(p.available),
          numeric: true,
          cell: (context, p) => Text(
            number(p.available),
            style: p.belowReorder
                ? TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  )
                : null,
          ),
        ),
        EntityColumn(l.stockInVans, (p) => number(p.inVans), numeric: true),
        EntityColumn(
          l.stockReorderMin,
          (p) => p.reorderMin == null ? '' : number(p.reorderMin),
          numeric: true,
        ),
      ],
      locationOf: (p) => '/stock/products/${p.productId}',
      onOpen: (p) async =>
          await context.push<bool>('/stock/products/${p.productId}') ?? true,
    );
  }
}
