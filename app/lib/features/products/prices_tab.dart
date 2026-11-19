import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/format.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

final _pricesProvider = FutureProvider.autoDispose
    .family<List<ZonePriceEntry>, String>(
      (ref, productId) =>
          ref.watch(apiProvider).products.listProductPrices(id: productId),
    );

/// Whether a price has not started yet: only such a price can be corrected or deleted. Prices
/// that are or were in effect are history; a change is a new price from a date.
bool isPlanned(ZonePriceEntry p, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);
  final from = DateTime(p.validFrom.year, p.validFrom.month, p.validFrom.day);
  return from.isAfter(today);
}

/// Price history per zone. Prices in effect are never edited: a new price starts on a date. A
/// planned price (starting after today) can be corrected or deleted.
class PricesTab extends ConsumerWidget {
  const PricesTab({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prices = ref.watch(_pricesProvider(product.id));
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('prices.write') ??
        false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: TutorialTarget(id: 'price-new', child: FilledButton.tonalIcon(
              icon: Icon(AppIcons.add),
              label: Text(context.l10n.newPrice),
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (_) => _PriceDialog(product: product),
                );
                if (added == true) ref.invalidate(_pricesProvider(product.id));
              },
            )),
          ),
        prices.when(
          loading: () => LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(context.l10n.noPrices),
                )
              : DataTable(
                  columns: [
                    DataColumn(label: Text(context.l10n.zone)),
                    DataColumn(label: Text(context.l10n.validFrom)),
                    DataColumn(
                      label: Text(context.l10n.unitPrice),
                      numeric: true,
                    ),
                    if (canWrite) const DataColumn(label: SizedBox.shrink()),
                  ],
                  rows: [
                    for (final p in list)
                      DataRow(
                        cells: [
                          DataCell(Text(p.zoneCode)),
                          DataCell(Text(date(p.validFrom))),
                          DataCell(Text(money(p.unitPrice))),
                          if (canWrite)
                            DataCell(
                              isPlanned(p)
                                  ? IconButton(
                                      key: ValueKey('price-correct-${p.id}'),
                                      tooltip: context.l10n.correctPrice,
                                      icon: Icon(AppIcons.edit),
                                      onPressed: () async {
                                        final changed = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => _PriceDialog(
                                            product: product,
                                            existing: p,
                                          ),
                                        );
                                        if (changed == true) {
                                          ref.invalidate(
                                            _pricesProvider(product.id),
                                          );
                                        }
                                      },
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Adds a price, or corrects or deletes a planned one (`existing`).
class _PriceDialog extends ConsumerStatefulWidget {
  const _PriceDialog({required this.product, this.existing});
  final Product product;
  final ZonePriceEntry? existing;

  @override
  ConsumerState<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends ConsumerState<_PriceDialog> {
  late final _price = TextEditingController(
    text: widget.existing == null ? '' : number(widget.existing!.unitPrice),
  );
  late String? _zoneId = widget.existing?.zoneId;
  late DateTime _from = widget.existing?.validFrom ?? DateTime.now();
  String? _error;

  Future<void> _delete() async {
    final e = widget.existing!;
    try {
      await ref
          .read(apiProvider)
          .products
          .deleteProductPrice(id: widget.product.id, priceId: e.id);
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      setState(() => _error = errorMessage(err));
    }
  }

  Future<void> _save() async {
    final price = parseDecimalInput(_price.text);
    if (_zoneId == null || price == null) {
      setState(() => _error = context.l10n.chooseZonePrice);
      return;
    }
    final existing = widget.existing;
    try {
      final products = ref.read(apiProvider).products;
      if (existing == null) {
        await products.addProductPrice(
          id: widget.product.id,
          body: ZonePriceInput(
            zoneId: _zoneId!,
            unitPrice: price,
            validFrom: _from,
          ),
        );
      } else {
        await products.correctProductPrice(
          id: widget.product.id,
          priceId: existing.id,
          body: ZonePriceCorrection(unitPrice: price, validFrom: _from),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(priceZonesProvider).value ?? const [];
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? context.l10n.newPrice
            : context.l10n.correctPrice,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _zoneId,
            decoration: InputDecoration(labelText: context.l10n.zone),
            items: [
              for (final z in zones)
                DropdownMenuItem(
                  value: z.id,
                  child: Text('${z.code} – ${z.name}'),
                ),
            ],
            // The zone of a planned price stays; only its price and date can be corrected.
            onChanged: widget.existing != null
                ? null
                : (v) => setState(() => _zoneId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            decoration: InputDecoration(
              labelText: context.l10n.unitPriceExclVat,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.validFromDate(date(_from))),
            trailing: const Icon(AppIcons.calendarToday),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _from,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _from = d);
            },
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const ValueKey('price-delete'),
            onPressed: _delete,
            child: Text(context.l10n.delete),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TutorialTarget(id: 'price-form-save', child: FilledButton(onPressed: _save, child: Text(context.l10n.save))),
      ],
    );
  }
}
