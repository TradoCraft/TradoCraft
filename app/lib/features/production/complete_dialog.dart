import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import '../inventory/inventory_common.dart';
import '../planning/board_model.dart';
import '../tutorial/targets.dart';

/// What the planner fills in when a production order is completed: the output (quantity, place,
/// lot or serial numbers) and, per component, what was really used, scrapped and (for serial
/// components) which units went in. Pops the completed order.
class CompleteDialog extends ConsumerStatefulWidget {
  const CompleteDialog({super.key, required this.order});
  final ProductionOrder order;

  @override
  ConsumerState<CompleteDialog> createState() => _CompleteDialogState();
}

class _Actual {
  _Actual(ProductionComponent c)
    : consumed = TextEditingController(text: c.requiredQuantity),
      scrap = TextEditingController(text: '0');
  final TextEditingController consumed;
  final TextEditingController scrap;
  String? extraLocation;
  List<ProductionSerialCandidate> units = [];

  void dispose() {
    consumed.dispose();
    scrap.dispose();
  }
}

class _CompleteDialogState extends ConsumerState<CompleteDialog> {
  late final _quantity = TextEditingController(text: widget.order.quantity);
  final _lot = TextEditingController();
  final _serials = TextEditingController();
  final _note = TextEditingController();
  DateTime? _expiry;
  String? _location;
  late final Map<String, _Actual> _actuals = {
    for (final c in widget.order.components) c.id: _Actual(c),
  };
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _lot.dispose();
    _serials.dispose();
    _note.dispose();
    for (final a in _actuals.values) {
      a.dispose();
    }
    super.dispose();
  }

  Decimal _n(String text) =>
      Decimal.tryParse(parseDecimalInput(text) ?? '') ?? Decimal.zero;

  /// More is taken than the reservation holds: the rest needs a place to be taken from. Exact
  /// decimal arithmetic, so an exact fit never asks for an extra place.
  bool _needsExtra(ProductionComponent c) {
    final a = _actuals[c.id]!;
    return c.tracking != 'serial' &&
        _n(a.consumed.text) + _n(a.scrap.text) >
            (Decimal.tryParse(c.reservedQuantity) ?? Decimal.zero);
  }

  Future<void> _chooseUnits(ProductionComponent c) async {
    final a = _actuals[c.id]!;
    final chosen = await showDialog<List<ProductionSerialCandidate>>(
      context: context,
      builder: (_) => _UnitsDialog(
        orderId: widget.order.id,
        component: c,
        initial: a.units,
        count: _n(a.consumed.text).toBigInt().toInt(),
      ),
    );
    if (chosen != null) setState(() => a.units = chosen);
  }

  Future<void> _save() async {
    final l = context.l10n;
    final o = widget.order;
    final quantity = parseDecimalInput(_quantity.text);
    if (quantity == null || _location == null) {
      setState(
        () => _error = '${l.productionQuantityBuilt}, ${l.productionLocation}',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final done = await ref
          .read(apiProvider)
          .production
          .completeOrder(
            id: o.id,
            body: CompleteProductionInput(
              output: ProductionOutputInput(
                quantity: quantity,
                locationId: _location!,
                lotNumber: o.productTracking == 'lot' ? _lot.text.trim() : null,
                expiryDate: o.productTracking == 'lot' ? _expiry : null,
                serialNumbers: o.productTracking == 'serial'
                    ? [
                        for (final s in _serials.text.split('\n'))
                          if (s.trim().isNotEmpty) s.trim(),
                      ]
                    : null,
              ),
              components: [
                for (final c in o.components)
                  ProductionComponentActual(
                    componentId: c.id,
                    consumedQuantity: parseDecimalInput(
                      _actuals[c.id]!.consumed.text,
                    ),
                    scrapQuantity: c.tracking == 'serial'
                        ? null
                        : parseDecimalInput(_actuals[c.id]!.scrap.text),
                    extraLocationId: _needsExtra(c)
                        ? _actuals[c.id]!.extraLocation
                        : null,
                    serialUnitIds: c.tracking == 'serial'
                        ? [for (final u in _actuals[c.id]!.units) u.id]
                        : null,
                  ),
              ],
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final o = widget.order;
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text('${l.productionComplete} · ${o.number}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.productionOutput,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              TextField(
                key: const ValueKey('output-quantity'),
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${l.productionQuantityBuilt} (${o.unit})',
                ),
              ),
              LocationField(
                label: l.productionLocation,
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              if (o.productTracking == 'lot') ...[
                TextField(
                  key: const ValueKey('output-lot'),
                  controller: _lot,
                  decoration: InputDecoration(labelText: l.productionLot),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _expiry ?? dateOnly(DateTime.now()),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _expiry = dateOnly(d));
                      },
                      child: Text(
                        '${l.productionExpiry}: ${_expiry == null ? '—' : date(_expiry)}',
                      ),
                    ),
                  ],
                ),
              ],
              if (o.productTracking == 'serial')
                TextField(
                  key: const ValueKey('output-serials'),
                  controller: _serials,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: l.productionSerials),
                ),
              gap,
              Text(
                l.productionComponents,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final c in o.components)
                Padding(
                  key: ValueKey('actual-${c.id}'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.componentCode} · ${c.componentName}'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('consumed-${c.id}'),
                              controller: _actuals[c.id]!.consumed,
                              onChanged: (_) => setState(() {}),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${l.productionConsumed} (${c.unit})',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (c.tracking != 'serial')
                            Expanded(
                              child: TextField(
                                key: ValueKey('scrap-${c.id}'),
                                controller: _actuals[c.id]!.scrap,
                                onChanged: (_) => setState(() {}),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: l.productionScrap,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (c.tracking == 'serial')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: ValueKey('units-${c.id}'),
                            onPressed: () => _chooseUnits(c),
                            child: Text(
                              _actuals[c.id]!.units.isEmpty
                                  ? l.productionChooseSerials
                                  : _actuals[c.id]!.units
                                        .map((u) => u.serialNumber)
                                        .join(', '),
                            ),
                          ),
                        ),
                      if (_needsExtra(c))
                        LocationField(
                          key: ValueKey('extra-${c.id}'),
                          label: l.productionExtraFrom,
                          value: _actuals[c.id]!.extraLocation,
                          onChanged: (v) =>
                              setState(() => _actuals[c.id]!.extraLocation = v),
                        ),
                    ],
                  ),
                ),
              gap,
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l.notes),
              ),
              if (_error != null) ...[
                gap,
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TutorialTarget(id: 'production-complete-save', child: FilledButton(
          key: const ValueKey('complete-save'),
          onPressed: _saving ? null : _save,
          child: Text(l.productionComplete),
        )),
      ],
    );
  }
}

/// Picks the serial units of a serial-tracked component that were built in.
class _UnitsDialog extends ConsumerStatefulWidget {
  const _UnitsDialog({
    required this.orderId,
    required this.component,
    required this.initial,
    required this.count,
  });
  final String orderId;
  final ProductionComponent component;
  final List<ProductionSerialCandidate> initial;
  final int count;

  @override
  ConsumerState<_UnitsDialog> createState() => _UnitsDialogState();
}

class _UnitsDialogState extends ConsumerState<_UnitsDialog> {
  List<ProductionSerialCandidate>? _units;
  String? _error;
  late final Set<String> _picked = {for (final u in widget.initial) u.id};
  late final Map<String, ProductionSerialCandidate> _known = {
    for (final u in widget.initial) u.id: u,
  };

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .production
        .serialCandidates(id: widget.orderId, componentId: widget.component.id)
        .then((list) {
          if (mounted) {
            setState(() {
              _units = list;
              for (final u in list) {
                _known[u.id] = u;
              }
            });
          }
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = errorMessage(e));
        });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = _units;
    return AlertDialog(
      title: Text(l.productionSerialsNeeded(widget.count.toString())),
      content: SizedBox(
        width: 420,
        child: _error != null
            ? Text(_error!)
            : units == null
            ? const LinearProgressIndicator()
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final u in units)
                    CheckboxListTile(
                      key: ValueKey('unit-${u.id}'),
                      title: Text(u.serialNumber),
                      subtitle: Text(u.location),
                      value: _picked.contains(u.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(u.id);
                        } else {
                          _picked.remove(u.id);
                        }
                      }),
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
          key: const ValueKey('units-save'),
          onPressed: () => Navigator.pop(context, [
            for (final id in _picked)
              if (_known[id] != null) _known[id]!,
          ]),
          child: Text(l.save),
        ),
      ],
    );
  }
}
