import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import '../shared/format.dart';
import '../shared/order_widgets.dart';
import 'portal_state.dart';
import '../shared/app_icons.dart';

/// The customer's orders: the latest revision that was sent to them.
class PortalOrdersPage extends ConsumerWidget {
  const PortalOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final orders = ref.watch(portalOrdersProvider);
    return orders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(portalError(e))),
      data: (list) => list.isEmpty
          ? Center(child: Text(l.noOrdersYet))
          : RefreshIndicator(
              onRefresh: () async => ref.refresh(portalOrdersProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l.myOrders,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final o in list)
                    Card(
                      child: ListTile(
                        onTap: () => context.go('/orders/${o.id}'),
                        title: Text(
                          '${o.number}  ·  ${l.revisionNumber(o.revision)}',
                        ),
                        subtitle: Text(
                          [
                            if (o.customerReference.isNotEmpty)
                              o.customerReference,
                            date(o.orderDate),
                            money(o.total, currency: o.currency),
                            if (o.openPriorityRequests > 0)
                              l.openPriorityRequests(o.openPriorityRequests),
                          ].join('  ·  '),
                        ),
                        trailing: OrderStatusChip(o.status, portal: true),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// One order with its lines and totals; the customer can confirm it or ask for another priority.
class PortalOrderPage extends ConsumerStatefulWidget {
  const PortalOrderPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<PortalOrderPage> createState() => _PortalOrderPageState();
}

class _PortalOrderPageState extends ConsumerState<PortalOrderPage> {
  final _message = TextEditingController();
  String _priority = 'expedite';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(PortalOrder o) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.confirmOrder),
        content: Text(l.confirmOrderHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.confirmOrder),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await ref
          .read(portalApiProvider)
          .confirmPortalOrder(
            id: widget.id,
            body: ConfirmPortalOrder(revision: o.revision),
          );
      ref.invalidate(portalOrderProvider(widget.id));
      ref.invalidate(portalOrdersProvider);
      if (mounted) _snack(context.l10n.orderConfirmedThanks);
    });
  }

  Future<void> _requestPriority() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = context.l10n.reasonRequired);
      return;
    }
    await _run(() async {
      await ref
          .read(portalApiProvider)
          .requestPortalOrderPriority(
            id: widget.id,
            body: NewPriorityRequest(priority: _priority, message: message),
          );
      _message.clear();
      ref.invalidate(portalOrderProvider(widget.id));
      ref.invalidate(portalOrdersProvider);
      if (mounted) _snack(context.l10n.priorityRequestSent);
    });
  }

  String _whyNot(PortalOrder o) {
    final l = context.l10n;
    if (o.confirmedAt != null || o.status == 'confirmed') {
      return l.orderAlreadyConfirmed(date(o.confirmedAt?.toLocal()));
    }
    if (o.status == 'sent') return l.cannotConfirmNewer;
    return l.cannotConfirmOther;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final detail = ref.watch(portalOrderProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(portalError(e))),
      data: (d) {
        final o = d.order;
        final canAsk = !const [
          'cancelled',
          'ready_for_shipping',
          'partially_shipped',
          'shipped',
        ].contains(o.status);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.go('/orders'),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Expanded(
                  child: Text(
                    '${o.number}  ·  ${l.revisionNumber(o.revision)}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                OrderStatusChip(o.status, portal: true),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 32,
              children: [
                if (o.customerReference.isNotEmpty)
                  _Item(l.customerReference, o.customerReference),
                _Item(l.date, date(o.orderDate)),
                _Item(l.totalExclVat, money(o.subtotal, currency: o.currency)),
                _Item(l.vat, money(o.vatTotal, currency: o.currency)),
                _Item(l.totalInclVat, money(o.total, currency: o.currency)),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(l.code)),
                  DataColumn(label: Text(l.description)),
                  DataColumn(label: Text(l.quantity), numeric: true),
                  DataColumn(label: Text(l.netPrice), numeric: true),
                  DataColumn(label: Text(l.total), numeric: true),
                ],
                rows: [
                  for (final line in d.lines)
                    DataRow(
                      cells: [
                        DataCell(Text(line.productCode)),
                        DataCell(Text(line.description)),
                        DataCell(Text('${number(line.quantity)} ${line.unit}')),
                        DataCell(
                          Text(money(line.netUnitPrice, currency: o.currency)),
                        ),
                        DataCell(
                          Text(money(line.lineTotal, currency: o.currency)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 32),
            if (o.canConfirm) ...[
              Text(l.confirmOrderHelp),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _confirm(o),
                  icon: const Icon(AppIcons.check),
                  label: Text(l.confirmOrder),
                ),
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(AppIcons.check),
                  label: Text(l.confirmOrder),
                ),
              ),
              const SizedBox(height: 8),
              Text(_whyNot(o)),
            ],
            if (canAsk) ...[
              const Divider(height: 32),
              Text(l.requestPriorityChange, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l.priorityRequestHelp),
              if (o.openPriorityRequests > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.openPriorityRequests(o.openPriorityRequests)),
                ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'expedite',
                    label: Text(l.requestMoreUrgent),
                  ),
                  ButtonSegment(value: 'low', label: Text(l.requestLessUrgent)),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: l.message),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _busy ? null : _requestPriority,
                  child: Text(l.requestPriorityChange),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Text(value.isEmpty ? '—' : value),
      ],
    );
  }
}
