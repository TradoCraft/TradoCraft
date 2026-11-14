import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';

/// Order statuses in which goods can be delivered.
const deliverableOrderStatuses = [
  'confirmed',
  'ready_for_shipping',
  'partially_shipped',
];

/// The delivery notes of an order, and a button to plan the next one. Shown on the order screen
/// to people who may read deliveries.
class OrderDeliveries extends ConsumerStatefulWidget {
  const OrderDeliveries({
    super.key,
    required this.orderId,
    required this.orderStatus,
    this.onChanged,
  });

  final String orderId;
  final String orderStatus;

  /// Called when a delivery was opened and the user came back: the order may have changed (its
  /// status follows what was shipped), so its screen and list refresh.
  final VoidCallback? onChanged;

  @override
  ConsumerState<OrderDeliveries> createState() => _OrderDeliveriesState();
}

class _OrderDeliveriesState extends ConsumerState<OrderDeliveries> {
  List<DeliverySummary>? _notes;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderDeliveries old) {
    super.didUpdateWidget(old);
    if (old.orderStatus != widget.orderStatus) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(apiProvider)
          .delivery
          .listForOrder(id: widget.orderId);
      if (mounted) {
        setState(() {
          _notes = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _afterReturn() {
    if (!mounted) return;
    _load();
    widget.onChanged?.call();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(apiProvider)
          .delivery
          .createNote(id: widget.orderId, body: const CreateDeliveryInput());
      if (!mounted) return;
      await context.push<bool>('/delivery/${note.id}');
      _afterReturn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canPlan =
        perms.contains('delivery.write') &&
        deliverableOrderStatuses.contains(widget.orderStatus);
    final notes = _notes;
    return Column(
      key: const ValueKey('order-deliveries'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.deliveries, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (canPlan)
              OutlinedButton.icon(
                key: const ValueKey('new-delivery'),
                onPressed: _busy ? null : _create,
                icon: const Icon(AppIcons.add),
                label: Text(l.deliveryNew),
              ),
          ],
        ),
        if (_error != null)
          Text(_error!)
        else if (notes == null)
          const LinearProgressIndicator()
        else
          for (final n in notes)
            ListTile(
              key: ValueKey('delivery-${n.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                n.plannedOnClosure ? AppIcons.eventBusy : AppIcons.outbox,
              ),
              title: Text('${n.number} · ${l.deliveryStatus(n.status)}'),
              subtitle: Text(
                [
                  n.plannedDate == null
                      ? l.deliveryNoDate
                      : date(n.plannedDate),
                  if (n.trackingNumber.isNotEmpty) n.trackingNumber,
                ].join(' · '),
              ),
              onTap: () async {
                await context.push<bool>('/delivery/${n.id}');
                _afterReturn();
              },
            ),
      ],
    );
  }
}
