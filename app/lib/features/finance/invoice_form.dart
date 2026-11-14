import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import 'invoice_widgets.dart';
import '../tutorial/targets.dart';

/// A date button with an optional clear action.
class InvoiceDateField extends StatelessWidget {
  /// Shows [value] under [label]; [onChanged] gets the picked day (or null when cleared).
  const InvoiceDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = false,
  });

  /// Field caption.
  final String label;

  /// The current date, if any.
  final DateTime? value;

  /// Called with the new date.
  final ValueChanged<DateTime?> onChanged;

  /// Whether a clear button is shown while a date is set.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          icon: const Icon(AppIcons.calendarToday),
          label: Text(value == null ? label : '$label: ${date(value)}'),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
            );
            if (d != null) onChanged(d);
          },
        ),
        if (clearable && value != null)
          IconButton(
            icon: const Icon(AppIcons.close),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

/// Opens the "new supplier invoice" dialog; resolves to the created draft or null.
///
/// [supplierId] and [supplierName] (and optionally [orderId] and [orderNumber]) prefill the form,
/// for example from the purchase order screen.
Future<InvoiceDetail?> showNewInvoiceDialog(
  BuildContext context, {
  String? supplierId,
  String? supplierName,
  String? orderId,
  String? orderNumber,
}) => showDialog<InvoiceDetail>(
  context: context,
  builder: (_) => _NewInvoiceDialog(
    supplier: supplierId == null ? null : (supplierId, supplierName ?? ''),
    order: orderId == null ? null : (orderId, orderNumber ?? ''),
  ),
);

class _NewInvoiceDialog extends ConsumerStatefulWidget {
  const _NewInvoiceDialog({this.supplier, this.order});

  final (String, String)? supplier;
  final (String, String)? order;

  @override
  ConsumerState<_NewInvoiceDialog> createState() => _NewInvoiceDialogState();
}

class _NewInvoiceDialogState extends ConsumerState<_NewInvoiceDialog> {
  (String, String)? _supplier;
  String? _orderId;
  List<(String, String)> _orders = const [];
  final _number = TextEditingController();
  final _notes = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  final _lines = <InvLineDraft>[InvLineDraft()];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _orderId = widget.order?.$1;
    if (_supplier != null) _loadOrders(_supplier!.$1);
  }

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    for (final d in _lines) {
      d.dispose();
    }
    super.dispose();
  }

  /// The orders of the supplier that have goods received (partially or fully).
  Future<void> _loadOrders(String supplierId) async {
    final client = ref.read(apiProvider).purchasing;
    final found = <(String, String)>[];
    try {
      for (final status in const ['partially_received', 'received']) {
        final list = await client.listOrders(
          supplierId: supplierId,
          status: status,
        );
        for (final o in list) {
          if (!found.any((f) => f.$1 == o.id)) found.add((o.id, o.number));
        }
      }
    } catch (_) {
      // Without the list the invoice can still be entered without an order.
    }
    final seed = widget.order;
    if (seed != null && !found.any((o) => o.$1 == seed.$1)) found.add(seed);
    if (mounted && _supplier?.$1 == supplierId) {
      setState(() => _orders = found);
    }
  }

  void _pickSupplier((String, String) s) {
    setState(() {
      _supplier = s;
      _orderId = null;
      _orders = const [];
    });
    _loadOrders(s.$1);
  }

  Future<void> _save() async {
    final l = context.l10n;
    final number = _number.text.trim();
    if (number.isEmpty || number.length > 64) {
      setState(() => _error = l.finNumberRequired);
      return;
    }
    if (_supplier == null) {
      setState(() => _error = l.purchPickSupplier);
      return;
    }
    List<InvoiceLineInput>? lines;
    if (_orderId == null) {
      final (built, problem) = buildInvoiceLines(l, _lines);
      if (built == null) {
        setState(() => _error = problem);
        return;
      }
      lines = built;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiProvider)
          .finance
          .createInvoice(
            body: NewInvoiceInput(
              supplierId: _supplier!.$1,
              purchaseOrderId: _orderId,
              invoiceNumber: number,
              invoiceDate: _invoiceDate,
              dueDate: _dueDate,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              lines: lines,
            ),
          );
      if (mounted) Navigator.pop(context, created);
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
    final locked = widget.supplier != null;
    return AlertDialog(
      title: Text(l.finNewInvoice),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked)
                InputDecorator(
                  decoration: InputDecoration(labelText: l.purchSupplier),
                  child: Text(
                    _supplier!.$2,
                    key: const ValueKey('inv-supplier-fixed'),
                  ),
                )
              else
                SearchPicker<(String, String)>(
                  key: const ValueKey('inv-supplier'),
                  label: l.purchSupplier,
                  display: (s) => s.$2,
                  search: (q) async {
                    final all = await ref
                        .read(apiProvider)
                        .purchasing
                        .listSuppliers(activeOnly: true);
                    final n = q.toLowerCase();
                    return [
                      for (final s in all)
                        if ('${s.code} ${s.name}'.toLowerCase().contains(n))
                          (s.id, '${s.code} · ${s.name}'),
                    ];
                  },
                  onSelected: _pickSupplier,
                ),
              const SizedBox(height: 12),
              if (_supplier != null)
                InputDecorator(
                  decoration: InputDecoration(labelText: l.finOrderOptional),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      key: const ValueKey('inv-order'),
                      isExpanded: true,
                      isDense: true,
                      value: _orders.any((o) => o.$1 == _orderId)
                          ? _orderId
                          : null,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l.finNoOrder),
                        ),
                        for (final o in _orders)
                          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                      ],
                      onChanged: (v) => setState(() => _orderId = v),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('inv-number'),
                controller: _number,
                decoration: InputDecoration(labelText: l.finInvoiceNumber),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  KeyedSubtree(
                    key: const ValueKey('inv-date'),
                    child: InvoiceDateField(
                      label: l.finInvoiceDate,
                      value: _invoiceDate,
                      onChanged: (d) => setState(() => _invoiceDate = d!),
                    ),
                  ),
                  KeyedSubtree(
                    key: const ValueKey('inv-due'),
                    child: InvoiceDateField(
                      label: l.finDueDate,
                      value: _dueDate,
                      clearable: true,
                      onChanged: (d) => setState(() => _dueDate = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('inv-notes'),
                controller: _notes,
                decoration: InputDecoration(labelText: l.notes),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              if (_orderId != null)
                Text(
                  l.finOrderPrefillHint,
                  key: const ValueKey('inv-prefill-hint'),
                )
              else ...[
                Text(
                  l.purchLines,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                InvoiceLinesEditor(
                  lines: _lines,
                  onChanged: () => setState(() => _error = null),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('inv-error'),
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
        TutorialTarget(id: 'inv-form-save', child: FilledButton(
          key: const ValueKey('inv-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        )),
      ],
    );
  }
}
