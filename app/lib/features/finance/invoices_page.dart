import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import 'invoice_form.dart';
import 'invoice_widgets.dart';

/// The supplier invoices list of the Finance section: paged on the server, with status chips,
/// a supplier filter and a search on the invoice number.
class SupplierInvoicesList extends ConsumerStatefulWidget {
  /// Creates the list.
  const SupplierInvoicesList({super.key});

  @override
  ConsumerState<SupplierInvoicesList> createState() =>
      _SupplierInvoicesListState();
}

class _SupplierInvoicesListState extends ConsumerState<SupplierInvoicesList> {
  final _list = GlobalKey<EntityListState<InvoiceSummary>>();
  String? _status;
  String? _supplierId;
  List<Supplier> _suppliers = const [];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final s = await ref.read(apiProvider).purchasing.listSuppliers();
      if (mounted) setState(() => _suppliers = s);
    } catch (_) {
      // The supplier filter just stays empty; the list reports its own errors.
    }
  }

  Future<(List<InvoiceSummary>, int)> _load(
    String? q,
    int offset,
    int limit,
  ) async {
    final page = await ref
        .read(apiProvider)
        .finance
        .listInvoices(
          status: _status,
          supplierId: _supplierId,
          q: q,
          limit: limit,
          offset: offset,
        );
    return (page.items, page.total);
  }

  void _reload() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => _list.currentState?.reload(),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'finance.write');
    return EntityList<InvoiceSummary>(
      key: _list,
      title: l.finSupplierInvoices,
      emptyText: l.finNoInvoices,
      load: _load,
      columns: [
        EntityColumn(l.finInvoiceNumber, (i) => i.invoiceNumber, flex: 2),
        EntityColumn(l.purchSupplier, (i) => i.supplierName, flex: 3),
        EntityColumn(
          l.status,
          (i) => invoiceStatusLabel(l, i.status),
          cell: (_, i) => Align(
            alignment: Alignment.centerLeft,
            child: InvoiceStatusChip(status: i.status),
          ),
          flex: 2,
        ),
        EntityColumn(l.finInvoiceDate, (i) => date(i.invoiceDate)),
        EntityColumn(l.finDueDate, (i) => date(i.dueDate)),
        EntityColumn(
          l.total,
          (i) => money(i.grossTotal, currency: i.currency),
          numeric: true,
        ),
      ],
      filters: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final s in [null, ...invoiceStatuses])
            FilterChip(
              key: ValueKey('inv-filter-${s ?? 'all'}'),
              label: Text(s == null ? l.all : invoiceStatusLabel(l, s)),
              selected: _status == s,
              onSelected: (_) {
                setState(() => _status = s);
                _reload();
              },
            ),
        ],
      ),
      moreFilters: DropdownButton<String?>(
        key: const ValueKey('inv-filter-supplier'),
        value: _suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
        items: [
          DropdownMenuItem(value: null, child: Text(l.purchAllSuppliers)),
          for (final s in _suppliers)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (v) {
          setState(() => _supplierId = v);
          _reload();
        },
      ),
      createLabel: l.finNewInvoice,
      onCreate: canWrite
          ? () async {
              final created = await showNewInvoiceDialog(context);
              if (created != null && context.mounted) {
                context.push('/supplier-invoices/${created.id}');
              }
              return created != null;
            }
          : null,
      locationOf: (i) => '/supplier-invoices/${i.id}',
      onOpen: (i) async {
        await context.push('/supplier-invoices/${i.id}');
        return null;
      },
    );
  }
}
