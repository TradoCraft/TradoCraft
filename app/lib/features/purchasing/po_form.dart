import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
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
  Map<String, SupplierProduct> _prices = {};
  DateTime? _expected;
  final _notes = TextEditingController();
  final _lines = <PoLineDraft>[PoLineDraft()];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    for (final d in _lines) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pickSupplier(Supplier s) async {
    setState(() {
      _supplier = s;
      _prices = {};
    });
    try {
      final list = await ref
          .read(apiProvider)
          .purchasing
          .listSupplierProducts(id: s.id);
      if (mounted && _supplier?.id == s.id) {
        setState(() => _prices = {for (final p in list) p.productId: p});
      }
    } catch (_) {
      // Without a price list the lines are simply not pre-filled.
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_supplier == null) {
      setState(() => _error = l.purchPickSupplier);
      return;
    }
    final (lines, problem) = buildPoLines(l, _lines);
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
              PoLinesEditor(
                lines: _lines,
                prices: _prices,
                onChanged: () => setState(() => _error = null),
                onPriceDefaults: (e) {
                  // The supplier's lead time defaults the expected date when none is set.
                  if (_expected == null && e.leadTimeDays > 0) {
                    setState(
                      () => _expected = DateTime.now().add(
                        Duration(days: e.leadTimeDays),
                      ),
                    );
                  }
                },
              ),
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
        TutorialTarget(id: 'po-form-save', child: FilledButton(
          key: const ValueKey('po-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        )),
      ],
    );
  }
}
