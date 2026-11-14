import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';

/// The statuses the list can be filtered on (the default is the work queue: open and requested).
const shippingRequestStatuses = ['open', 'requested', 'quoted', 'cancelled'];

/// Logistics work queue: quotations waiting for a shipping price. Logistics marks that carriers
/// were asked and enters the price, which lands on the quotation as its shipping line.
class ShippingPage extends ConsumerStatefulWidget {
  const ShippingPage({super.key});

  @override
  ConsumerState<ShippingPage> createState() => _ShippingPageState();
}

class _ShippingPageState extends ConsumerState<ShippingPage> {
  final _list = GlobalKey<EntityListState<ShippingRequest>>();
  String? _status;

  Future<void> _markRequested(ShippingRequest r) async {
    final input = await showDialog<MarkShippingRequestedInput>(
      context: context,
      builder: (_) => _RequestedDialog(request: r),
    );
    if (input == null || !mounted) return;
    final api = ref.read(apiProvider).sales;
    await runAction(
      context,
      () => api.markShippingRequested(id: r.id, body: input),
    );
    _list.currentState?.reload();
  }

  Future<void> _enterQuote(ShippingRequest r) async {
    final input = await showDialog<ShippingQuoteInput>(
      context: context,
      builder: (_) => _QuoteDialog(request: r),
    );
    if (input == null || !mounted) return;
    final api = ref.read(apiProvider).sales;
    await runAction(
      context,
      () => api.enterShippingQuote(id: r.id, body: input),
    );
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    return EntityList<ShippingRequest>(
      key: _list,
      title: l.shippingRequests,
      load: (q, offset, limit) async {
        final all = await api.sales.listShippingRequests(status: _status);
        // The endpoint is not paged or searchable: filter on number and customer here.
        final needle = q?.toLowerCase();
        final items = [
          for (final r in all)
            if (needle == null ||
                r.quotationNumber.toLowerCase().contains(needle) ||
                r.customerName.toLowerCase().contains(needle))
              r,
        ];
        return (items, items.length);
      },
      filters: DropdownButton<String?>(
        value: _status,
        hint: Text(l.shippingQueue),
        items: [
          DropdownMenuItem(value: null, child: Text(l.shippingQueue)),
          for (final s in shippingRequestStatuses)
            DropdownMenuItem(value: s, child: Text(l.shippingStatus(s))),
        ],
        onChanged: (s) {
          setState(() => _status = s);
          _list.currentState?.reload();
        },
      ),
      columns: [
        EntityColumn(
          l.quotation,
          (r) => '${r.quotationNumber}  rev. ${r.quotationRevision}',
          flex: 2,
        ),
        EntityColumn(l.customer, (r) => r.customerName, flex: 3),
        EntityColumn(l.deliveryCountry, (r) => r.deliveryCountryCode ?? ''),
        EntityColumn(
          l.status,
          (r) => l.shippingStatus(r.status),
          flex: 2,
          cell: (context, r) => _StatusChip(r.status),
        ),
        EntityColumn(l.carrier, (r) => r.carrier ?? '', flex: 2),
        EntityColumn(
          l.quotedAmount,
          (r) => r.quotedAmount == null
              ? ''
              : money(r.quotedAmount, currency: r.currency ?? 'EUR'),
          numeric: true,
          flex: 2,
        ),
        EntityColumn(
          l.requestedAt,
          (r) => r.requestedAt == null ? '' : date(r.requestedAt!.toLocal()),
        ),
        EntityColumn(
          '',
          (r) => '',
          flex: 3,
          cell: (context, r) => Wrap(
            spacing: 8,
            children: [
              if (r.status == 'open')
                OutlinedButton(
                  onPressed: () => _markRequested(r),
                  child: Text(l.markAsRequested),
                ),
              if (r.status == 'open' || r.status == 'requested')
                FilledButton.tonal(
                  onPressed: () => _enterQuote(r),
                  child: Text(l.enterQuote),
                ),
            ],
          ),
        ),
      ],
      onOpen: (r) async {
        await context.push<bool>('/quotations/${r.quotationId}');
        return true;
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(context.l10n.shippingStatus(status)),
      backgroundColor: switch (status) {
        'open' => scheme.tertiaryContainer,
        'quoted' => scheme.primaryContainer,
        'cancelled' => scheme.errorContainer,
        _ => null,
      },
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Asks which carriers were contacted (required) and an optional note.
class _RequestedDialog extends StatefulWidget {
  const _RequestedDialog({required this.request});
  final ShippingRequest request;

  @override
  State<_RequestedDialog> createState() => _RequestedDialogState();
}

class _RequestedDialogState extends State<_RequestedDialog> {
  late final _carrier = TextEditingController(text: widget.request.carrier);
  late final _notes = TextEditingController(text: widget.request.notes);
  bool _missing = false;

  @override
  void dispose() {
    _carrier.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.markAsRequested} · ${widget.request.quotationNumber}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _carrier,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.carrier,
                errorText: _missing ? l.carrierRequired : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: l.notes),
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
            final carrier = _carrier.text.trim();
            if (carrier.isEmpty) {
              setState(() => _missing = true);
              return;
            }
            final notes = _notes.text.trim();
            Navigator.pop(
              context,
              MarkShippingRequestedInput(
                carrier: carrier,
                notes: notes.isEmpty ? null : notes,
              ),
            );
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Asks for the quoted amount; the currency is the quotation's (the server rejects another one).
class _QuoteDialog extends StatefulWidget {
  const _QuoteDialog({required this.request});
  final ShippingRequest request;

  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  final _amount = TextEditingController();
  late final _currency = TextEditingController(text: widget.request.currency);
  late final _carrier = TextEditingController(text: widget.request.carrier);
  late final _notes = TextEditingController(text: widget.request.notes);
  bool _invalid = false;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _carrier.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.enterQuote} · ${widget.request.quotationNumber}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.amount,
                      errorText: _invalid ? l.amountRequired : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _currency,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: l.currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carrier,
              decoration: InputDecoration(labelText: l.carrier),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: l.notes),
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
            final amount = parseDecimalInput(_amount.text);
            if (amount == null) {
              setState(() => _invalid = true);
              return;
            }
            String? opt(TextEditingController c) =>
                c.text.trim().isEmpty ? null : c.text.trim();
            Navigator.pop(
              context,
              ShippingQuoteInput(
                amount: amount,
                currency: opt(_currency)?.toUpperCase(),
                carrier: opt(_carrier),
                notes: opt(_notes),
              ),
            );
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
