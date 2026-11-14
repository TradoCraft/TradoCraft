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

/// Price history per zone. Prices are never edited: a new price starts on a date.
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
                  builder: (_) => _NewPrice(product: product),
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
                  ],
                  rows: [
                    for (final p in list)
                      DataRow(
                        cells: [
                          DataCell(Text(p.zoneCode)),
                          DataCell(Text(date(p.validFrom))),
                          DataCell(Text(money(p.unitPrice))),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NewPrice extends ConsumerStatefulWidget {
  const _NewPrice({required this.product});
  final Product product;

  @override
  ConsumerState<_NewPrice> createState() => _NewPriceState();
}

class _NewPriceState extends ConsumerState<_NewPrice> {
  final _price = TextEditingController();
  String? _zoneId;
  DateTime _from = DateTime.now();
  String? _error;

  Future<void> _save() async {
    final price = parseDecimalInput(_price.text);
    if (_zoneId == null || price == null) {
      setState(() => _error = context.l10n.chooseZonePrice);
      return;
    }
    try {
      await ref
          .read(apiProvider)
          .products
          .addProductPrice(
            id: widget.product.id,
            body: ZonePriceInput(
              zoneId: _zoneId!,
              unitPrice: price,
              validFrom: _from,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(priceZonesProvider).value ?? const [];
    return AlertDialog(
      title: Text(context.l10n.newPrice),
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
            onChanged: (v) => setState(() => _zoneId = v),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TutorialTarget(id: 'price-form-save', child: FilledButton(onPressed: _save, child: Text(context.l10n.save))),
      ],
    );
  }
}
