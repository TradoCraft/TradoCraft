import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/power_text.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'voltage_range.dart';

final _suppliesProvider = FutureProvider.autoDispose
    .family<List<PowerSupply>, String>(
      (ref, productId) => ref
          .watch(apiProvider)
          .products
          .getProductPowerSupplies(id: productId),
    );

/// The power supplies a product accepts (none = not electrical) and a check against a country's
/// grids. Read-only without `products.write`.
class PowerTab extends ConsumerWidget {
  const PowerTab({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplies = ref.watch(_suppliesProvider(product.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        supplies.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => _SupplyEditor(product: product, initial: list),
        ),
        const SizedBox(height: 24),
        _CompatibilityCheck(product: product),
      ],
    );
  }
}

class _Row {
  _Row({
    this.current = 'ac',
    String voltage = '',
    this.phases = 1,
    this.frequency,
    String tolerance = '10',
    String min = '',
    String max = '',
  }) : voltage = TextEditingController(text: voltage),
       tolerance = TextEditingController(text: tolerance),
       min = TextEditingController(text: min),
       max = TextEditingController(text: max);

  factory _Row.from(PowerSupply s) => _Row(
    current: s.currentType,
    voltage: '${s.voltageV}',
    phases: s.phases ?? 1,
    frequency: s.frequencyHz,
    tolerance: '${s.tolerancePct}',
    min: s.voltageMinV == null ? '' : '${s.voltageMinV}',
    max: s.voltageMaxV == null ? '' : '${s.voltageMaxV}',
  );

  String current;
  final TextEditingController voltage;
  int phases;

  /// 50 or 60; null = both.
  int? frequency;
  final TextEditingController tolerance;

  /// Optional explicit voltage range (both or neither).
  final TextEditingController min;
  final TextEditingController max;

  /// Inline validation message of this row, if any.
  String? error;

  bool get isAc => current == 'ac';
}

class _SupplyEditor extends ConsumerStatefulWidget {
  const _SupplyEditor({required this.product, required this.initial});
  final Product product;
  final List<PowerSupply> initial;

  @override
  ConsumerState<_SupplyEditor> createState() => _SupplyEditorState();
}

class _SupplyEditorState extends ConsumerState<_SupplyEditor> {
  late final List<_Row> _rows = widget.initial.map(_Row.from).toList();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.voltage.dispose();
      r.tolerance.dispose();
      r.min.dispose();
      r.max.dispose();
    }
    super.dispose();
  }

  /// Mirrors the API validation; returns the bodies or sets [_error].
  List<PowerSupplyInput>? _validate() {
    final l = context.l10n;
    final out = <PowerSupplyInput>[];
    final seen = <String>{};
    var rowInvalid = false;
    for (final r in _rows) {
      r.error = null;
      final v = int.tryParse(r.voltage.text.trim());
      if (v == null || v <= 0) {
        _error = l.powerVoltageInvalid;
        return null;
      }
      final t = int.tryParse(r.tolerance.text.trim());
      if (t == null || t < 0 || t > 50) {
        _error = l.powerToleranceInvalid;
        return null;
      }
      final range = checkVoltageRange(
        nominal: v,
        min: r.min.text,
        max: r.max.text,
      );
      if (range.error != null) {
        r.error = switch (range.error!) {
          VoltageRangeError.incomplete => l.powerBoundsIncomplete,
          VoltageRangeError.invalid => l.powerBoundsInvalid,
          VoltageRangeError.order => l.powerBoundsOrder,
          VoltageRangeError.nominalOutside => l.powerBoundsNominal,
        };
        rowInvalid = true;
        continue;
      }
      final phases = r.isAc ? r.phases : null;
      final freq = r.isAc ? r.frequency : null;
      if (!seen.add('${r.current}/$v/$phases/$freq')) {
        _error = l.powerSupplyDuplicate;
        return null;
      }
      out.add(
        PowerSupplyInput(
          currentType: r.current,
          voltageV: v,
          phases: phases,
          frequencyHz: freq,
          tolerancePct: t,
          voltageMinV: range.min,
          voltageMaxV: range.max,
        ),
      );
    }
    if (rowInvalid) return null;
    return out;
  }

  Future<void> _save() async {
    _error = null;
    final body = _validate();
    setState(() {});
    if (body == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .products
          .replaceProductPowerSupplies(id: widget.product.id, body: body);
      ref.invalidate(_suppliesProvider(widget.product.id));
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'products.write');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.powerNotElectrical),
          ),
        for (final (i, r) in _rows.indexed)
          Padding(
            key: ObjectKey(r),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dropdown<String>(
                      key: ValueKey('current-$i'),
                      width: 120,
                      label: l.currentType,
                      value: r.current,
                      items: {'ac': l.currentAc, 'dc': l.currentDc},
                      onChanged: canWrite
                          ? (v) => setState(() => r.current = v!)
                          : null,
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('voltage-$i'),
                        controller: r.voltage,
                        enabled: canWrite,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(labelText: l.voltageV),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('vmin-$i'),
                        controller: r.min,
                        enabled: canWrite,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l.powerVoltageMin,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('vmax-$i'),
                        controller: r.max,
                        enabled: canWrite,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l.powerVoltageMax,
                        ),
                      ),
                    ),
                    if (r.isAc) ...[
                      _dropdown<int>(
                        key: ValueKey('phases-$i'),
                        width: 100,
                        label: l.phases,
                        value: r.phases,
                        items: const {1: '1', 3: '3'},
                        onChanged: canWrite
                            ? (v) => setState(() => r.phases = v!)
                            : null,
                      ),
                      _dropdown<int?>(
                        key: ValueKey('frequency-$i'),
                        width: 150,
                        label: l.frequencyHz,
                        value: r.frequency,
                        items: {null: l.frequencyBoth, 50: '50', 60: '60'},
                        onChanged: canWrite
                            ? (v) => setState(() => r.frequency = v)
                            : null,
                      ),
                    ],
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('tolerance-$i'),
                        controller: r.tolerance,
                        enabled: canWrite,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(labelText: l.tolerancePct),
                      ),
                    ),
                    if (canWrite)
                      IconButton(
                        key: ValueKey('remove-$i'),
                        tooltip: l.remove,
                        icon: const Icon(AppIcons.delete),
                        onPressed: () => setState(() => _rows.removeAt(i)),
                      ),
                  ],
                ),
                if (r.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      r.error!,
                      key: ValueKey('vrow-error-$i'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.powerBoundsHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (canWrite)
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.powerAddSupply),
                onPressed: () => setState(() => _rows.add(_Row())),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l.save),
              ),
            ],
          ),
      ],
    );
  }

  Widget _dropdown<T>({
    required Key key,
    required double width,
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?>? onChanged,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    ),
  );
}

class _CompatibilityCheck extends ConsumerStatefulWidget {
  const _CompatibilityCheck({required this.product});
  final Product product;

  @override
  ConsumerState<_CompatibilityCheck> createState() =>
      _CompatibilityCheckState();
}

class _CompatibilityCheckState extends ConsumerState<_CompatibilityCheck> {
  final _country = TextEditingController();
  String? _gridId;
  PowerCompatibilityReport? _report;
  String? _error;

  @override
  void dispose() {
    _country.dispose();
    super.dispose();
  }

  String get _code => _country.text.trim().toUpperCase();

  Future<void> _check() async {
    if (_code.length != 2) {
      setState(() {
        _report = null;
        _error = context.l10n.deliveryCountryInvalid;
      });
      return;
    }
    try {
      final r = await ref
          .read(apiProvider)
          .products
          .getProductPowerCompatibility(
            id: widget.product.id,
            country: _code,
            gridId: _gridId,
          );
      if (mounted) {
        setState(() {
          _report = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _report = null;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final grids = _code.length == 2
        ? (ref.watch(powerGridsProvider(_code)).value ?? const <PowerGrid>[])
              .where((g) => g.active)
              .toList()
        : const <PowerGrid>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.powerCheckTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(l.powerCheckHelp),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: const ValueKey('check-country'),
                    controller: _country,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(2),
                      TextInputFormatter.withFunction(
                        (old, v) => v.copyWith(text: v.text.toUpperCase()),
                      ),
                    ],
                    decoration: InputDecoration(labelText: l.country),
                    onChanged: (_) => setState(() => _gridId = null),
                  ),
                ),
                if (grids.isNotEmpty)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('check-grid-$_code-${grids.length}'),
                      initialValue: _gridId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.powerGrid),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l.powerAnyGrid),
                        ),
                        for (final g in grids)
                          DropdownMenuItem<String?>(
                            value: g.id,
                            child: Text(
                              powerProfileText(
                                voltage: g.voltageV,
                                phases: g.phases,
                                frequency: g.frequencyHz,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _gridId = v),
                    ),
                  ),
                FilledButton(onPressed: _check, child: Text(l.powerCheck)),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_report != null) _result(context, _report!),
          ],
        ),
      ),
    );
  }

  Widget _result(BuildContext context, PowerCompatibilityReport r) {
    final l = context.l10n;
    final country = r.countryCode;
    String profiles(Iterable<String> p) => powerProfilesText(p);
    final (text, icon, ok) = switch (r.status) {
      PowerStatus.compatible => (
        l.powerResultCompatible(country),
        AppIcons.checkCircle,
        true,
      ),
      PowerStatus.incompatible => (
        l.powerResultIncompatible(
          country,
          profiles(
            r.supported.map(
              (s) => powerProfileText(
                current: s.currentType,
                voltage: s.voltageV,
                phases: s.phases,
                frequency: s.frequencyHz,
                tolerance: s.tolerancePct,
              ),
            ),
          ),
          profiles(
            r.available.map(
              (g) => powerProfileText(
                voltage: g.voltageV,
                phases: g.phases,
                frequency: g.frequencyHz,
              ),
            ),
          ),
        ),
        AppIcons.error,
        false,
      ),
      PowerStatus.needsExternalSupply => (
        l.powerResultExternal,
        AppIcons.info,
        true,
      ),
      PowerStatus.notApplicable => (
        l.powerResultNotApplicable,
        AppIcons.info,
        true,
      ),
      _ => (l.powerResultUnknown(country), AppIcons.help, false),
    };
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        key: const ValueKey('check-result'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ok ? scheme.primary : scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.powerStatus(r.status.json ?? ''),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
