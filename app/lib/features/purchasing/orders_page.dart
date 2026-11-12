import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import 'po_form.dart';
import 'po_lines.dart';

/// Purchase order statuses in lifecycle order, used by the filter chips.
const poStatuses = [
  'draft',
  'approved',
  'sent',
  'partially_received',
  'received',
  'cancelled',
];

/// The purchase orders list of the Purchasing section: search, status and supplier filters.
class PurchaseOrdersList extends ConsumerStatefulWidget {
  /// Creates the list.
  const PurchaseOrdersList({super.key});

  @override
  ConsumerState<PurchaseOrdersList> createState() => _PurchaseOrdersListState();
}

class _PurchaseOrdersListState extends ConsumerState<PurchaseOrdersList> {
  final _list = GlobalKey<EntityListState<PurchaseOrderSummary>>();
  String? _status;
  String? _supplierId;
  List<Supplier> _suppliers = const [];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final s = await ref.read(apiProvider).purchasing.listSuppliers();
      if (mounted) setState(() => _suppliers = s);
    } catch (_) {
      // The supplier filter just stays empty; the list reports its own errors.
    }
  }

  /// The API returns every (filtered) order, so search and paging happen here.
  Future<(List<PurchaseOrderSummary>, int)> _load(
    String? q,
    int offset,
    int limit,
  ) async {
    final all = await ref
        .read(apiProvider)
        .purchasing
        .listOrders(status: _status, supplierId: _supplierId);
    final needle = q?.toLowerCase();
    final hits = needle == null
        ? all
        : [
            for (final o in all)
              if ('${o.number} ${o.supplierName}'.toLowerCase().contains(
                needle,
              ))
                o,
          ];
    final end = (offset + limit).clamp(0, hits.length);
    return (hits.sublist(offset.clamp(0, end), end), hits.length);
  }

  void _reload() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => _list.currentState?.reload(),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'purchasing.write');
    return EntityList<PurchaseOrderSummary>(
      key: _list,
      title: l.purchOrders,
      emptyText: l.purchNoOrders,
      load: _load,
      columns: [
        EntityColumn(l.purchOrderNumber, (o) => o.number),
        EntityColumn(l.purchSupplier, (o) => o.supplierName, flex: 3),
        EntityColumn(
          l.status,
          (o) => poStatusLabel(l, o.status),
          cell: (_, o) => Align(
            alignment: Alignment.centerLeft,
            child: PoStatusChip(status: o.status),
          ),
          flex: 2,
        ),
        EntityColumn(l.purchOrderDate, (o) => date(o.orderDate)),
        EntityColumn(l.purchExpectedDate, (o) => date(o.expectedDeliveryDate)),
        EntityColumn(
          l.total,
          (o) => money(o.total, currency: o.currency),
          numeric: true,
        ),
      ],
      filters: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final s in [null, ...poStatuses])
            FilterChip(
              key: ValueKey('po-filter-${s ?? 'all'}'),
              label: Text(s == null ? l.all : poStatusLabel(l, s)),
              selected: _status == s,
              onSelected: (_) {
                setState(() => _status = s);
                _reload();
              },
            ),
        ],
      ),
      moreFilters: DropdownButton<String?>(
        key: const ValueKey('po-filter-supplier'),
        value: _suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
        items: [
          DropdownMenuItem(value: null, child: Text(l.purchAllSuppliers)),
          for (final s in _suppliers)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (v) {
          setState(() => _supplierId = v);
          _reload();
        },
      ),
      createTargetId: 'po-create',
      createLabel: l.purchNewOrder,
      onCreate: canWrite
          ? () async {
              final created = await showNewPurchaseOrderDialog(context);
              if (created != null && context.mounted) {
                context.push('/purchase-orders/${created.id}');
              }
              return created != null;
            }
          : null,
      locationOf: (o) => '/purchase-orders/${o.id}',
      onOpen: (o) async {
        await context.push('/purchase-orders/${o.id}');
        return null;
      },
    );
  }
}
