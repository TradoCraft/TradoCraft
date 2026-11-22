import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/decimal_field.dart';
import '../../shared/format.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../tutorial/controller.dart';
import '../tutorial/targets.dart';

final _pricesProvider = FutureProvider.autoDispose
    .family<List<ZonePriceEntry>, String>(
      (ref, productId) =>
          ref.watch(apiProvider).products.listProductPrices(id: productId),
    );

/// Whether a price has not started yet: only such a price can be corrected or deleted. Prices
/// that are or were in effect are history; a change is a new price from a date.
bool isPlanned(ZonePriceEntry p, {DateTime? now}) {
  final start = p.validFrom;
  final from = DateTime.utc(start.year, start.month, start.day);
  return from.isAfter(businessToday(now));
}

/// Computes a zone's default price from [basePrice] using [multiplier] and optional [rounding] step.
String? computeZonePrice(
  String? basePrice, {
  String? multiplier,
  String? rounding,
}) {
  if (basePrice == null || multiplier == null) return null;
  final base = Decimal.tryParse(basePrice);
  final mult = Decimal.tryParse(multiplier);
  if (base == null || mult == null || mult <= Decimal.zero) return null;
  var raw = base * mult;
  final step = rounding == null || rounding == 'none'
      ? null
      : Decimal.tryParse(rounding);
  if (step != null && step > Decimal.zero) {
    final quotient = (raw / step).toDouble().round();
    raw = step * Decimal.fromInt(quotient);
    return raw.toStringAsFixed(2);
  }
  final s = raw.toStringAsFixed(4);
  if (s.endsWith('00')) return raw.toStringAsFixed(2);
  return s;
}

/// Price history per zone. Prices in effect are never edited: a new price starts on a date. A
/// planned price (starting after today) can be corrected or deleted.
class PricesTab extends ConsumerWidget {
  const PricesTab({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tutorialAssistCompletedProvider, (_, completed) {
      if (completed?.missionId == 'prices' &&
          (completed?.stepId == 'priceExport' ||
              completed?.stepId == 'priceHome')) {
        ref.invalidate(_pricesProvider(product.id));
      }
    });
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
            child: TutorialTarget(
              id: 'price-new',
              child: FilledButton.tonalIcon(
                icon: Icon(AppIcons.add),
                label: Text(context.l10n.newPrice),
                onPressed: () async {
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (_) => _MultiZonePriceDialog(product: product),
                  );
                  if (added == true) {
                    ref.invalidate(_pricesProvider(product.id));
                  }
                },
              ),
            ),
          ),
        prices.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
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
                          DataCell(
                            Text(
                              date(p.validFrom),
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              money(p.unitPrice),
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
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

/// Multi-zone table dialog for entering prices across all zones at once.
class _MultiZonePriceDialog extends ConsumerStatefulWidget {
  const _MultiZonePriceDialog({required this.product});
  final Product product;

  @override
  ConsumerState<_MultiZonePriceDialog> createState() =>
      _MultiZonePriceDialogState();
}

class _MultiZonePriceDialogState extends ConsumerState<_MultiZonePriceDialog> {
  final Map<String, DecimalInputController> _controllers = {};
  final Set<String> _overridden = {};
  DateTime _from = DateTime.now();
  bool _programmatic = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  DecimalInputController _controllerFor(
    PriceZone zone,
    List<PriceZone> zones,
  ) {
    return _controllers.putIfAbsent(zone.id, () {
      final c = DecimalInputController();
      c.addListener(() {
        if (_programmatic) return;
        if (zones.isNotEmpty && zone.id == zones.first.id) {
          _recomputeFromFirst(zones);
        } else {
          if (!_overridden.contains(zone.id)) {
            setState(() => _overridden.add(zone.id));
          }
        }
      });
      return c;
    });
  }

  void _recomputeFromFirst(List<PriceZone> zones, {bool forceAll = false}) {
    if (zones.isEmpty) return;
    final first = zones.first;
    final baseDecimal = _controllers[first.id]?.decimal;
    _programmatic = true;
    try {
      for (var i = 1; i < zones.length; i++) {
        final z = zones[i];
        if (z.defaultMultiplier == null) continue;
        if (!forceAll && _overridden.contains(z.id)) continue;
        final c = _controllers[z.id];
        if (c == null) continue;
        final computed = computeZonePrice(
          baseDecimal,
          multiplier: z.defaultMultiplier,
          rounding: z.defaultRounding,
        );
        c.text = computed == null ? '' : editableDecimal(computed);
      }
      if (forceAll) _overridden.clear();
    } finally {
      _programmatic = false;
    }
    if (mounted) setState(() {});
  }

  void _resetZone(PriceZone zone, List<PriceZone> zones) {
    if (zones.isEmpty) return;
    final baseDecimal = _controllers[zones.first.id]?.decimal;
    final computed = computeZonePrice(
      baseDecimal,
      multiplier: zone.defaultMultiplier,
      rounding: zone.defaultRounding,
    );
    _programmatic = true;
    try {
      _overridden.remove(zone.id);
      _controllers[zone.id]?.text = computed == null
          ? ''
          : editableDecimal(computed);
    } finally {
      _programmatic = false;
    }
    setState(() {});
  }

  Future<void> _save(List<PriceZone> zones) async {
    final l = context.l10n;
    final entries = <(PriceZone, String)>[];
    for (final z in zones) {
      final c = _controllers[z.id];
      if (c == null || c.text.trim().isEmpty) continue;
      final dec = c.decimal;
      if (dec == null) {
        setState(() => _error = l.chooseZonePrice);
        return;
      }
      entries.add((z, dec));
    }
    if (entries.isEmpty) {
      setState(() => _error = l.enterAtLeastOnePrice);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final products = ref.read(apiProvider).products;
      for (final (z, price) in entries) {
        await products.addProductPrice(
          id: widget.product.id,
          body: ZonePriceInput(
            zoneId: z.id,
            unitPrice: price,
            validFrom: _from,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  String _formulaLabel(AppLocalizations l, PriceZone z, bool isFirst) {
    if (isFirst) return l.baseZone;
    if (z.defaultMultiplier == null) return '—';
    final mult = '× ${number(z.defaultMultiplier)}';
    final round = z.defaultRounding != null && z.defaultRounding != 'none'
        ? ' (${z.defaultRounding})'
        : '';
    return '$mult$round';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final zonesAsync = ref.watch(priceZonesProvider);
    final zones = zonesAsync.value ?? const <PriceZone>[];

    // Ensure controllers exist for all zones.
    for (final z in zones) {
      _controllerFor(z, zones);
    }

    return AlertDialog(
      title: Text(l.newPrice),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.validFromDate(date(_from))),
                trailing: const Icon(AppIcons.calendarToday),
                onTap: _saving
                    ? null
                    : () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _from,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _from = d);
                      },
              ),
              const Divider(height: 16),
              if (zonesAsync.isLoading)
                const LinearProgressIndicator()
              else if (zones.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.noPriceZones),
                )
              else
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.4),
                    2: FixedColumnWidth(160),
                    3: FixedColumnWidth(44),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l.zone,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l.formula,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l.unitPriceExclVat,
                            style: theme.textTheme.labelMedium,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox.shrink(),
                      ],
                    ),
                    for (var i = 0; i < zones.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${zones[i].code} – ${zones[i].name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Text(
                              _formulaLabel(l, zones[i], i == 0),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: DecimalField(
                              key: ValueKey('zone-price-${zones[i].code}'),
                              controller: _controllers[zones[i].id]!,
                              autofocus: i == 0,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          if (i > 0 &&
                              zones[i].defaultMultiplier != null &&
                              _overridden.contains(zones[i].id))
                            IconButton(
                              key: ValueKey('zone-reset-${zones[i].code}'),
                              tooltip: l.resetToFormula,
                              icon: const Icon(AppIcons.refresh, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              onPressed: _saving
                                  ? null
                                  : () => _resetZone(zones[i], zones),
                            )
                          else
                            const SizedBox(width: 40, height: 40),
                        ],
                      ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_overridden.isNotEmpty)
          TextButton(
            onPressed: _saving
                ? null
                : () => _recomputeFromFirst(zones, forceAll: true),
            child: Text(l.applyFormulas),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('multi-price-save'),
          onPressed: _saving || zones.isEmpty ? null : () => _save(zones),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Corrects or deletes a single planned price (`existing`).
class _PriceDialog extends ConsumerStatefulWidget {
  const _PriceDialog({required this.product, required this.existing});
  final Product product;
  final ZonePriceEntry existing;

  @override
  ConsumerState<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends ConsumerState<_PriceDialog> {
  late final _price = DecimalInputController(
    text: editableDecimal(widget.existing.unitPrice),
  );
  late DateTime _from = widget.existing.validFrom;
  String? _error;

  Future<void> _delete() async {
    try {
      await ref
          .read(apiProvider)
          .products
          .deleteProductPrice(
            id: widget.product.id,
            priceId: widget.existing.id,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      setState(() => _error = errorMessage(err));
    }
  }

  Future<void> _save() async {
    final price = _price.decimal;
    if (price == null) {
      setState(() => _error = context.l10n.chooseZonePrice);
      return;
    }
    try {
      await ref
          .read(apiProvider)
          .products
          .correctProductPrice(
            id: widget.product.id,
            priceId: widget.existing.id,
            body: ZonePriceCorrection(unitPrice: price, validFrom: _from),
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
      title: Text(context.l10n.correctPrice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: widget.existing.zoneId,
            decoration: InputDecoration(labelText: context.l10n.zone),
            items: [
              for (final z in zones)
                DropdownMenuItem(
                  value: z.id,
                  child: Text('${z.code} – ${z.name}'),
                ),
            ],
            onChanged: null,
          ),
          const SizedBox(height: 12),
          DecimalField(
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
          key: const ValueKey('price-delete'),
          onPressed: _delete,
          child: Text(context.l10n.delete),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(context.l10n.save)),
      ],
    );
  }
}
