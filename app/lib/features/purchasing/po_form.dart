import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import 'goods_picker.dart';
import 'po_lines.dart';
import '../tutorial/targets.dart';

/// A date button with a clear action, used for the expected delivery date.
class PoDateField extends StatelessWidget {
  /// Shows [value] under [label]; [onChanged] gets the picked day or null when cleared.
  const PoDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /// Field caption.
  final String label;

  /// The current date, if any.
  final DateTime? value;

  /// Called with the new date.
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('po-expected-date'),
          icon: const Icon(AppIcons.calendarToday),
          label: Text(value == null ? label : '$label: ${date(value)}'),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 10),
            );
            if (d != null) onChanged(d);
          },
        ),
      ],
    );
  }
}

/// Opens the "new purchase order" dialog; resolves to the created draft or null.
Future<PurchaseOrderDetail?> showNewPurchaseOrderDialog(BuildContext context) =>
    showDialog<PurchaseOrderDetail>(
      context: context,
      builder: (_) => const _NewPoDialog(),
    );

class _NewPoDialog extends ConsumerStatefulWidget {
  const _NewPoDialog();

  @override
  ConsumerState<_NewPoDialog> createState() => _NewPoDialogState();
}

class _NewPoDialogState extends ConsumerState<_NewPoDialog> {
  Supplier? _supplier;
  List<SupplierProduct> _entries = const [];
  bool _loadingGoods = false;
  bool _clearedNotice = false;
  final _selection = GoodsSelection();
  DateTime? _expected;
  final _notes = TextEditingController();

  // Products that are not on the supplier's price list, added through the line editor.
  final _extra = <PoLineDraft>[];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    _selection.dispose();
    for (final d in _extra) {
      d.dispose();
    }
    super.dispose();
  }

  Map<String, SupplierProduct> get _prices => {
    for (final e in _entries) e.productId: e,
  };

  Future<void> _pickSupplier(Supplier s) async {
    final changed = _supplier != null && _supplier!.id != s.id;
    final hadChoice =
        _selection.hasAny || _extra.any((d) => d.productId != null);
    if (changed) {
      // A different supplier has a different price list: start the selection over.
      _selection.clear();
      for (final d in _extra) {
        d.dispose();
      }
      _extra.clear();
    }
    setState(() {
      _supplier = s;
      _entries = const [];
      _loadingGoods = true;
      _clearedNotice = changed && hadChoice;
    });
    try {
      final list = await ref
          .read(apiProvider)
          .purchasing
          .listSupplierProducts(id: s.id);
      if (mounted && _supplier?.id == s.id) {
        setState(() {
          _entries = list;
          _loadingGoods = false;
        });
      }
    } catch (_) {
      if (mounted && _supplier?.id == s.id) {
        setState(() => _loadingGoods = false);
      }
    }
  }

  void _goodsChanged() {
    setState(() {
      _error = null;
      _clearedNotice = false;
      // The supplier's lead time defaults the expected date when none is set.
      if (_expected == null) {
        for (final e in _entries) {
          if (_selection.isChosen(e.productId) && e.leadTimeDays > 0) {
            _expected = DateTime.now().add(Duration(days: e.leadTimeDays));
            break;
          }
        }
      }
    });
  }

  String _summary(AppLocalizations l) {
    var count = 0;
    var total = 0.0;
    var currency = _supplier?.currency ?? 'EUR';
    for (final e in _entries) {
      if (!_selection.isChosen(e.productId)) continue;
      count++;
      currency = e.currency;
      final q = double.parse(
        parseDecimalInput(_selection.qty(e.productId).text)!,
      );
      total += q * (double.tryParse(e.unitPrice) ?? 0);
    }
    for (final d in _extra) {
      final q = double.tryParse(parseDecimalInput(d.qty.text) ?? '');
      final p = double.tryParse(parseDecimalInput(d.price.text) ?? '');
      if (d.productId == null || q == null) continue;
      count++;
      total += q * (p ?? 0);
    }
    return l.purchGoodsSummary(
      count,
      money(total.toStringAsFixed(2), currency: currency),
    );
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_supplier == null) {
      setState(() => _error = l.purchPickSupplier);
      return;
    }
    final picked = selectedGoodsLines(_entries, _selection);
    final (lines, problem) = buildPoLines(l, [...picked, ..._extra]);
    for (final d in picked) {
      d.dispose();
    }
    if (lines == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final po = await ref
          .read(apiProvider)
          .purchasing
          .createOrder(
            body: NewPurchaseOrderInput(
              supplierId: _supplier!.id,
              expectedDeliveryDate: _expected,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              lines: lines,
            ),
          );
      if (mounted) Navigator.pop(context, po);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.purchNewOrder),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchPicker<Supplier>(
                key: const ValueKey('po-supplier'),
                label: l.purchSupplier,
                display: (s) => '${s.code} · ${s.name}',
                search: (q) async {
                  final all = await ref
                      .read(apiProvider)
                      .purchasing
                      .listSuppliers(activeOnly: true);
                  final n = q.toLowerCase();
                  return [
                    for (final s in all)
                      if ('${s.code} ${s.name}'.toLowerCase().contains(n)) s,
                  ];
                },
                onSelected: _pickSupplier,
              ),
              const SizedBox(height: 12),
              PoDateField(
                label: l.purchExpectedDate,
                value: _expected,
                onChanged: (d) => setState(() => _expected = d),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('po-notes'),
                controller: _notes,
                decoration: InputDecoration(labelText: l.notes),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Text(
                l.purchLines,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_supplier == null)
                Text(
                  l.purchGoodsPickSupplier,
                  key: const ValueKey('po-goods-pick-supplier'),
                )
              else if (_loadingGoods)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_clearedNotice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l.purchGoodsCleared,
                      key: const ValueKey('po-goods-cleared'),
                    ),
                  ),
                if (_entries.isNotEmpty) Text(l.purchGoodsHeader),
                SupplierGoodsPicker(
                  key: ValueKey('po-goods-${_supplier!.id}'),
                  entries: _entries,
                  selection: _selection,
                  onChanged: _goodsChanged,
                ),
                const SizedBox(height: 8),
                Text(
                  l.purchGoodsOther,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                PoLinesEditor(
                  lines: _extra,
                  prices: _prices,
                  onChanged: () => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
                Text(
                  _summary(l),
                  key: const ValueKey('po-goods-summary'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('po-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TutorialTarget(
          id: 'po-form-save',
          child: FilledButton(
            key: const ValueKey('po-save'),
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
