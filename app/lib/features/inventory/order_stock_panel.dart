import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import 'inventory_common.dart';

/// Availability (available to promise) of every line of an order, with reservation of stock once
/// the order is confirmed. Shown on the order screen to people who may read inventory.
class OrderStockPanel extends ConsumerStatefulWidget {
  const OrderStockPanel({super.key, required this.orderId, this.revision});

  final String orderId;

  /// Changes when the order changes (so the panel reloads).
  final Object? revision;

  @override
  ConsumerState<OrderStockPanel> createState() => _OrderStockPanelState();
}

class _OrderStockPanelState extends ConsumerState<OrderStockPanel> {
  OrderAvailability? _a;
  String? _error;
  bool _busy = false;

  /// The last reload failed, so what is shown may not match the stock any more.
  bool _stale = false;

  TradocraftApi get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderStockPanel old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId || old.revision != widget.revision) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final a = await _api.inventory.orderAvailability(id: widget.orderId);
      if (mounted) {
        setState(() {
          _a = a;
          _error = null;
          _stale = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _stale = true;
        });
      }
    }
  }

  Future<void> _set(LineAvailability line, String quantity) async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => _api.inventory.setReservation(
        id: line.orderLineId,
        body: ReserveInput(quantity: quantity),
      ),
    );
    if (ok) await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final canWrite = hasPermission(ref, 'inventory.write');
    final a = _a;
    if (a == null) {
      return _error == null
          ? const SizedBox.shrink()
          : _refreshError(theme, l.retry);
    }
    final stocked = a.lines.where((x) => x.state != 'not_stocked').toList();
    if (stocked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.orderStockTitle, style: theme.textTheme.titleMedium),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        if (_stale && _error != null) _refreshError(theme, l.retry),
        if (!a.reservable && a.orderStatus != 'cancelled')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.orderStockReserveHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final line in stocked)
          ListTile(
            key: ValueKey('stock-${line.orderLineId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text('${line.position}'),
            title: Text('${line.productCode} · ${line.description}'),
            subtitle: Text(
              '${l.stockOnHand}: ${number(line.onHand)} · '
              '${l.stockReserved}: ${number(line.reservedTotal)} · '
              '${l.stockAvailable}: ${number(line.available)}'
              '${_isZero(line.expired) ? '' : ' · ${l.stockExpiredQty(number(line.expired))}'}'
              '${_isZero(line.reserved) ? '' : ' · ${l.orderStockThisLine(number(line.reserved))}'}'
              '${_isZero(line.shortfall) ? '' : ' · ${l.stockShortBy(number(line.shortfall))}'}',
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StockStateChip(line.state),
                if (canWrite && a.reservable) ...[
                  if (line.state != 'reserved')
                    OutlinedButton(
                      onPressed: _busy || _stale
                          ? null
                          : () => _set(line, _fill(line)),
                      child: Text(l.orderStockReserve),
                    ),
                  if (!_isZero(line.reserved))
                    TextButton(
                      // Releasing never depends on the figures, so it stays possible.
                      onPressed: _busy ? null : () => _set(line, '0'),
                      child: Text(l.orderStockRelease),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// The failed reload, with a retry. Controls that depend on the figures stay disabled until a
  /// reload succeeds.
  Widget _refreshError(ThemeData theme, String retryLabel) => Row(
    children: [
      Expanded(
        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ),
      TextButton(onPressed: _busy ? null : _load, child: Text(retryLabel)),
    ],
  );

  /// The quantity to ask for when reserving: what the line still needs, as far as stock allows.
  /// Both figures are in the stock unit of the product (the ordered quantity of the line may be in
  /// another unit), and what was already shipped is no longer needed.
  String _fill(LineAvailability line) {
    final needed =
        Decimal.parse(line.orderedStock) - Decimal.parse(line.consumed);
    final remaining = needed > Decimal.zero ? needed : Decimal.zero;
    final reserved = Decimal.parse(line.reserved);
    final free = Decimal.parse(line.available);
    final extra = free > Decimal.zero ? free : Decimal.zero;
    final want = reserved + extra;
    return (want > remaining ? remaining : want).toString();
  }
}

bool _isZero(String v) => (Decimal.tryParse(v) ?? Decimal.zero) == Decimal.zero;
