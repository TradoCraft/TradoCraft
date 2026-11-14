import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';

/// The states a delivery note can be filtered on.
const deliveryStatuses = ['planned', 'shipped', 'cancelled'];

/// Delivery notes of all orders. They are created from an order (see the order screen).
class DeliveriesPage extends ConsumerStatefulWidget {
  const DeliveriesPage({super.key});

  @override
  ConsumerState<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends ConsumerState<DeliveriesPage> {
  final _list = GlobalKey<EntityListState<DeliverySummary>>();
  String? _status = 'planned';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final admin =
        ref.watch(meProvider).value?.permissions.contains('delivery.admin') ??
        false;
    return EntityList<DeliverySummary>(
      key: _list,
      title: l.deliveries,
      load: (q, offset, limit) async {
        final page = await api.delivery.listNotes(
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
          for (final s in deliveryStatuses)
            DropdownMenuItem(value: s, child: Text(l.deliveryStatus(s))),
        ],
        onChanged: (s) {
          setState(() => _status = s);
          _list.currentState?.reload();
        },
      ),
      actions: [
        if (admin)
          IconButton(
            key: const ValueKey('delivery-settings'),
            tooltip: l.deliverySettingsTitle,
            icon: const Icon(AppIcons.settings),
            onPressed: () => context.push('/delivery/settings'),
          ),
      ],
      columns: [
        EntityColumn(l.number, (n) => n.number, flex: 2),
        EntityColumn(l.order, (n) => n.orderNumber, flex: 2),
        EntityColumn(l.customer, (n) => n.customerName, flex: 3),
        EntityColumn(
          l.deliveryPlannedDate,
          (n) => n.plannedDate == null
              ? l.deliveryNoDate
              : date(n.plannedDate) +
                    (n.plannedOnClosure ? ' · ${l.deliveryOnClosure}' : ''),
          flex: 3,
          cell: (context, n) => Row(
            children: [
              Flexible(
                child: Text(
                  n.plannedDate == null
                      ? l.deliveryNoDate
                      : date(n.plannedDate),
                ),
              ),
              if (n.plannedOnClosure) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: l.deliveryOnClosure,
                  child: Icon(
                    AppIcons.eventBusy,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        EntityColumn(l.carrier, (n) => n.carrier, flex: 2),
        EntityColumn(l.trackingNumber, (n) => n.trackingNumber, flex: 2),
        EntityColumn(l.status, (n) => l.deliveryStatus(n.status), flex: 2),
      ],
      locationOf: (n) => '/delivery/${n.id}',
      onOpen: (n) async =>
          await context.push<bool>('/delivery/${n.id}') ?? true,
    );
  }
}
