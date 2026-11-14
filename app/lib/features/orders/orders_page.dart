import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../shared/order_widgets.dart';

/// The order states the list can be filtered on.
const orderStatuses = [
  'draft',
  'sent',
  'confirmed',
  'in_planning',
  'planned',
  'in_production',
  'ready_for_shipping',
  'partially_shipped',
  'shipped',
  'cancelled',
];

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final _list = GlobalKey<EntityListState<OrderSummary>>();
  String? _status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    return EntityList<OrderSummary>(
      key: _list,
      title: l.orders,
      load: (q, offset, limit) async {
        final page = await api.sales.listOrders(
          q: q,
          status: _status,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      filters: DropdownButton<String?>(
        value: _status,
        hint: Text(l.allStatuses),
        items: [
          DropdownMenuItem(value: null, child: Text(l.allStatuses)),
          for (final s in orderStatuses)
            DropdownMenuItem(value: s, child: Text(l.orderStatus(s))),
        ],
        onChanged: (s) {
          setState(() => _status = s);
          _list.currentState?.reload();
        },
      ),
      columns: [
        EntityColumn(
          l.number,
          (o) => '${o.number}  r${o.currentRevision}',
          flex: 2,
        ),
        EntityColumn(l.customer, (o) => o.customerName, flex: 3),
        EntityColumn(l.customerReference, (o) => o.customerReference, flex: 2),
        EntityColumn(
          l.quotation,
          (o) => '${o.quotationNumber} rev. ${o.quotationRevision}',
          flex: 2,
        ),
        EntityColumn(
          l.status,
          (o) => l.orderStatus(o.status),
          flex: 2,
          cell: (context, o) => OrderStatusChip(o.status),
        ),
        EntityColumn(
          l.priority,
          (o) => l.orderPriority(o.priority),
          cell: (context, o) => PriorityIndicator(o.priority),
        ),
        EntityColumn(l.date, (o) => date(o.orderDate)),
        EntityColumn(l.salesperson, (o) => o.salespersonName, flex: 2),
        EntityColumn(
          l.totalExclVat,
          (o) => money(o.subtotal, currency: o.currency),
          numeric: true,
          flex: 2,
        ),
      ],
      locationOf: (o) => '/orders/${o.id}',
      onOpen: (o) async => await context.push<bool>('/orders/${o.id}') ?? true,
    );
  }
}
