import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';

/// The production orders of a sales order, and a button that releases what is still to be built.
/// Shown on the order screen to people who may read production.
class OrderProduction extends ConsumerStatefulWidget {
  const OrderProduction({
    super.key,
    required this.orderId,
    required this.orderStatus,
    this.onChanged,
  });

  final String orderId;
  final String orderStatus;

  /// Called after a release or after coming back from a production order: the order's status and
  /// promised date follow production, so the order screen reloads.
  final VoidCallback? onChanged;

  @override
  ConsumerState<OrderProduction> createState() => _OrderProductionState();
}

class _OrderProductionState extends ConsumerState<OrderProduction> {
  List<ProductionSummary>? _orders;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderProduction old) {
    super.didUpdateWidget(old);
    if (old.orderStatus != widget.orderStatus) _load();
  }

  Future<void> _load() async {
    try {
      final page = await ref
          .read(apiProvider)
          .production
          .listOrders(orderId: widget.orderId, limit: 100);
      if (mounted) {
        setState(() {
          _orders = page.items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  /// Releases every manufactured line of this order that production orders do not cover yet.
  Future<void> _release() async {
    final l = context.l10n;
    setState(() => _busy = true);
    var released = 0;
    try {
      final api = ref.read(apiProvider).production;
      final todo = (await api.toRelease())
          .where((t) => t.orderId == widget.orderId)
          .toList();
      if (todo.isEmpty) {
        if (mounted) _snack(l.productionNothingToRelease);
      } else {
        for (final t in todo) {
          await api.release(
            body: ReleaseProductionInput(
              orderId: t.orderId,
              orderLineId: t.orderLineId,
            ),
          );
          released++;
        }
        if (mounted) _snack(l.productionReleased);
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e), error: true);
    } finally {
      // Lines released before a failure still changed the order: show them.
      if (released > 0 && mounted) {
        await _load();
        widget.onChanged?.call();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canRelease =
        perms.contains('production.write') &&
        const [
          'confirmed',
          'in_planning',
          'planned',
          'in_production',
        ].contains(widget.orderStatus);
    final orders = _orders;
    return Column(
      key: const ValueKey('order-production'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.productionOrdersOfOrder,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (canRelease)
              OutlinedButton.icon(
                key: const ValueKey('release-order'),
                onPressed: _busy ? null : _release,
                icon: const Icon(AppIcons.outbox),
                label: Text(l.productionRelease),
              ),
          ],
        ),
        if (_error != null)
          Text(_error!)
        else if (orders == null)
          const LinearProgressIndicator()
        else
          for (final p in orders)
            ListTile(
              key: ValueKey('production-${p.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                p.shortComponents > 0
                    ? AppIcons.warningAmber
                    : AppIcons.precisionManufacturing,
              ),
              title: Text(
                '${p.number} · ${p.productCode} · ${number(p.quantity)} ${p.unit}',
              ),
              subtitle: Text(
                [
                  l.productionStatus(p.status),
                  if (p.plannedReadyDate != null) date(p.plannedReadyDate),
                  if (p.divisionName != null) p.divisionName!,
                ].join(' · '),
              ),
              onTap: () async {
                await context.push<bool>('/production/${p.id}');
                if (!mounted) return;
                _load();
                widget.onChanged?.call();
              },
            ),
      ],
    );
  }
}
