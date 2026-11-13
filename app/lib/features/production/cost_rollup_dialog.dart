import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';

/// The cost of building a quantity of a product from its active BOM and routing, through every
/// level of subassemblies. For users who may see cost (`inventory.cost`).
class CostRollupDialog extends ConsumerStatefulWidget {
  const CostRollupDialog({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<CostRollupDialog> createState() => _CostRollupDialogState();
}

class _CostRollupDialogState extends ConsumerState<CostRollupDialog> {
  final _quantity = TextEditingController(text: '1');
  ProductionCostRollup? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    final q = parseDecimalInput(_quantity.text);
    if (q == null) return;
    try {
      final r = await ref
          .read(apiProvider)
          .production
          .productionCostRollup(id: widget.product.id, quantity: q);
      if (mounted) {
        setState(() {
          _result = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = null;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = _result;
    final theme = Theme.of(context);
    String eur(String v) => money(v, currency: r?.currency ?? 'EUR');
    return AlertDialog(
      title: Text('${l.productionCostRollup} · ${widget.product.code}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.productionCostRollupHint,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      key: const ValueKey('rollup-quantity'),
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l.quantity,
                        suffixText: widget.product.unit,
                      ),
                      onSubmitted: (_) => _calculate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const ValueKey('rollup-calculate'),
                    onPressed: _calculate,
                    child: Text(l.productionCostCalculate),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              if (r != null) ...[
                _line(
                  l.productionCostMaterial,
                  eur(r.materialCost),
                  key: 'rollup-material',
                ),
                _line(
                  l.productionCostLabour,
                  eur(r.labourCost),
                  key: 'rollup-labour',
                ),
                _line(
                  l.total,
                  eur(r.totalCost),
                  key: 'rollup-total',
                  bold: true,
                ),
                _line(
                  l.productionCostPerUnit,
                  eur(r.unitCost),
                  key: 'rollup-unit',
                ),
                const Divider(),
                for (final lv in r.levels)
                  Padding(
                    padding: EdgeInsets.only(left: lv.level * 20.0, top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${lv.productCode} · ${number(lv.quantity)} ${lv.unit}',
                          ),
                        ),
                        Text(
                          '${eur(lv.materialCost)} + ${eur(lv.labourCost)} (${minutesText(lv.minutes)})',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (r.gaps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.productionCostIncomplete,
                    style: theme.textTheme.labelMedium,
                  ),
                  for (final g in r.gaps)
                    Text(
                      g.kind == 'standard_cost'
                          ? l.productionCostGapProduct(g.code)
                          : l.productionCostGapWorkCentre(g.code),
                      key: ValueKey('gap-${g.kind}-${g.code}'),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }

  Widget _line(String label, String value, {String? key, bool bold = false}) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold)
        : null;
    return Padding(
      key: key == null ? null : ValueKey(key),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
