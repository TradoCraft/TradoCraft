import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/file_export.dart';
import '../../shared/search_picker.dart';
import 'invoice_form.dart';

const customerBillingPath = '/api/v1/customer-invoices';

typedef BillingJson = Map<String, dynamic>;

String billingDay(DateTime value) => value.toIso8601String().split('T').first;

Future<BillingJson> billingObject(
  Future<Response<BillingJson>> response,
) async => (await response).data!;

String _requestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _billingPageProvider = FutureProvider.autoDispose
    .family<List<BillingJson>, int>((ref, offset) async {
      final response = await ref
          .watch(dioProvider)
          .get<List<dynamic>>(
            customerBillingPath,
            queryParameters: {'limit': 50, 'offset': offset},
          );
      return response.data!.cast<BillingJson>();
    });

class CustomerBillingPage extends ConsumerStatefulWidget {
  const CustomerBillingPage({super.key});

  @override
  ConsumerState<CustomerBillingPage> createState() =>
      _CustomerBillingPageState();
}

class _CustomerBillingPageState extends ConsumerState<CustomerBillingPage> {
  int _offset = 0;

  Future<void> _open({String? id, bool legacy = false}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => legacy
          ? const _LegacyInvoiceDialog()
          : id == null
          ? const _NewBillingDraft()
          : _BillingDetail(id: id),
    );
    if (mounted) ref.invalidate(_billingPageProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final page = ref.watch(_billingPageProvider(_offset));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (can(ref, 'billing.write'))
                FilledButton(
                  onPressed: () => _open(),
                  child: Text(l.cbNewInvoice),
                ),
              if (can(ref, 'billing.post'))
                OutlinedButton(
                  onPressed: () => _open(legacy: true),
                  child: Text(l.cbRegisterLegacy),
                ),
              OutlinedButton(
                onPressed: () => ref.invalidate(_billingPageProvider),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
        Expanded(
          child: page.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(errorMessage(error))),
            data: (documents) => ListView(
              children: [
                if (documents.isEmpty) Center(child: Text(l.cbNoDocuments)),
                for (final document in documents)
                  ListTile(
                    title: Text(
                      '${document['number'] ?? l.cbDraft} · ${document['customer_name']}',
                    ),
                    subtitle: Text(
                      '${_kind(l, document)} · ${document['document_date']}',
                    ),
                    trailing: Text(
                      '${document['gross_total']} ${document['currency']}',
                    ),
                    onTap: () => _open(id: document['id'] as String),
                  ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).previousPageTooltip,
              onPressed: _offset > 0
                  ? () => setState(() => _offset -= 50)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).nextPageTooltip,
              onPressed: page.value?.length == 50
                  ? () => setState(() => _offset += 50)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

String _kind(AppLocalizations l, BillingJson summary) =>
    summary['is_legacy'] == true
    ? l.cbLegacyInvoice
    : summary['kind'] == 'invoice'
    ? l.cbInvoice
    : l.cbCredit;

class _BillingDetail extends ConsumerStatefulWidget {
  const _BillingDetail({required this.id});

  final String id;

  @override
  ConsumerState<_BillingDetail> createState() => _BillingDetailState();
}

class _BillingDetailState extends ConsumerState<_BillingDetail> {
  BillingJson? _detail;
  String? _error;
  bool _busy = true;

  String get _path => '$customerBillingPath/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => _run(() async {
    _detail = await billingObject(ref.read(dioProvider).get(_path));
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = errorMessage(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() => _run(() async {
    _detail = await billingObject(ref.read(dioProvider).post('$_path/post'));
  });

  Future<void> _discard() => _run(() async {
    await ref.read(dioProvider).delete(_path);
    if (mounted) Navigator.of(context).pop();
  });

  Future<void> _pdf(String number) => _run(() async {
    final bytes = await downloadBytes(ref.read(dioProvider), '$_path/pdf');
    if (!mounted) return;
    await saveExport(context, ref, '$number.pdf', Uint8List.fromList(bytes));
  });

  Future<void> _credit() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _NewBillingDraft(invoice: _detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final detail = _detail;
    final summary = detail?['document'] as BillingJson?;
    final posted = summary?['status'] == 'posted';
    return AlertDialog(
      title: Text(
        summary == null
            ? l.cbCustomerInvoices
            : '${_kind(l, summary)} · ${summary['number'] ?? l.cbDraft}',
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (summary != null) ...[
                Text(
                  '${summary['customer_name']} · ${summary['document_date']}',
                ),
                if (summary['source_invoice_number'] != null)
                  Text('${l.cbOriginal}: ${summary['source_invoice_number']}'),
                if ((summary['reason'] as String).isNotEmpty)
                  Text(summary['reason'] as String),
                for (final line
                    in (detail!['lines'] as List).cast<BillingJson>())
                  ListTile(
                    title: Text(
                      '${line['product_code']} · ${line['description']}',
                    ),
                    subtitle: Text('${line['quantity']} ${line['unit']}'),
                    trailing: Text(
                      '${line['gross_total']} ${summary['currency']}',
                    ),
                  ),
                Text(
                  '${l.cbTotal}: ${summary['gross_total']} ${summary['currency']}',
                ),
                if (detail['rebate_progress'] case {
                  'message': final String message,
                })
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        if (summary == null && !_busy)
          OutlinedButton(onPressed: _load, child: Text(l.retry)),
        if (summary != null && !posted && can(ref, 'billing.write'))
          TextButton(
            onPressed: _busy ? null : _discard,
            child: Text(l.cbDiscard),
          ),
        if (summary != null && !posted && can(ref, 'billing.post'))
          FilledButton(onPressed: _busy ? null : _post, child: Text(l.cbPost)),
        if (summary != null && posted && summary['is_legacy'] != true)
          OutlinedButton(
            onPressed: _busy ? null : () => _pdf(summary['number'] as String),
            child: const Text('PDF'),
          ),
        if (summary != null &&
            posted &&
            summary['kind'] == 'invoice' &&
            can(ref, 'billing.write'))
          FilledButton(
            onPressed: _busy ? null : _credit,
            child: Text(l.cbNewCredit),
          ),
      ],
    );
  }
}

class _NewBillingDraft extends ConsumerStatefulWidget {
  const _NewBillingDraft({this.invoice});

  final BillingJson? invoice;

  @override
  ConsumerState<_NewBillingDraft> createState() => _NewBillingDraftState();
}

class _NewBillingDraftState extends ConsumerState<_NewBillingDraft> {
  final _request = _requestId();
  final _reason = TextEditingController();
  final _amounts = <String, String>{};
  final _creditNet = <String, String>{};
  DeliveryNote? _delivery;
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  bool get _credit => widget.invoice != null;

  @override
  void initState() {
    super.initState();
    if (_credit) {
      for (final line
          in (widget.invoice!['lines'] as List).cast<BillingJson>()) {
        _amounts[line['id'] as String] =
            (line['creditable_quantity'] ?? line['quantity']).toString();
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _selectDelivery(DeliverySummary summary) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await ref.read(apiProvider).delivery.getNote(id: summary.id);
      if (!mounted) return;
      _amounts
        ..clear()
        ..addEntries(
          note.lines.map((line) => MapEntry(line.id, line.quantity)),
        );
      _delivery = note;
    } catch (error) {
      _error = errorMessage(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lineId = _credit ? 'invoice_line_id' : 'delivery_line_id';
      final body = <String, dynamic>{
        'request_id': _request,
        'document_date': billingDay(_date),
        'lines': [
          for (final line in _amounts.entries)
            if (line.value.trim().isNotEmpty &&
                double.tryParse(line.value.replaceAll(',', '.')) != 0)
              {
                lineId: line.key,
                'quantity': line.value.trim().replaceAll(',', '.'),
                if (_creditNet[line.key] case final value?
                    when value.isNotEmpty)
                  'net_total': value,
              },
        ],
        if (_credit) ...{
          'invoice_id': (widget.invoice!['document'] as BillingJson)['id'],
          'reason': _reason.text.trim(),
        } else
          'delivery_note_id': _delivery!.id,
      };
      await ref
          .read(dioProvider)
          .post(
            _credit ? '$customerBillingPath/credits' : customerBillingPath,
            data: body,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _quantity(String id, String title, String unit) => TextFormField(
    key: ValueKey(id),
    initialValue: _amounts[id],
    enabled: !_busy,
    decoration: InputDecoration(labelText: '$title ($unit)'),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (value) => _amounts[id] = value,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(_credit ? l.cbNewCredit : l.cbNewInvoice),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_credit)
                SearchPicker<DeliverySummary>(
                  label: l.cbShippedDelivery,
                  search: (q) async =>
                      (await ref
                              .read(apiProvider)
                              .delivery
                              .listNotes(status: 'shipped', q: q, limit: 20))
                          .items,
                  display: (delivery) =>
                      '${delivery.number} · ${delivery.customerName}',
                  enabled: !_busy,
                  onSelected: _selectDelivery,
                ),
              InvoiceDateField(
                label: l.cbDate,
                value: _date,
                onChanged: (date) => setState(() => _date = date ?? _date),
              ),
              if (_credit)
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l.cbCreditReason),
                ),
              if (_credit)
                for (final line
                    in (widget.invoice!['lines'] as List).cast<BillingJson>())
                  Column(
                    key: ValueKey(line['id']),
                    children: [
                      _quantity(
                        line['id'] as String,
                        line['description'] as String,
                        line['unit'] as String,
                      ),
                      TextFormField(
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: l.cbNet,
                          hintText: line['creditable_net_total']?.toString(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) => _creditNet[line['id'] as String] =
                            value.trim().replaceAll(',', '.'),
                      ),
                    ],
                  )
              else if (_delivery case final delivery?)
                for (final line in delivery.lines)
                  _quantity(line.id, line.productName, line.unit),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy || (!_credit && _delivery == null) ? null : _save,
          child: Text(l.cbSaveDraft),
        ),
      ],
    );
  }
}

class _LegacyInvoiceDialog extends ConsumerStatefulWidget {
  const _LegacyInvoiceDialog();

  @override
  ConsumerState<_LegacyInvoiceDialog> createState() =>
      _LegacyInvoiceDialogState();
}

class _LegacyInvoiceDialogState extends ConsumerState<_LegacyInvoiceDialog> {
  Customer? _customer;
  DateTime _date = DateTime.now();
  final _header = <String, String>{'currency': 'EUR', 'vat_regime': 'domestic'};
  final _lines = <BillingJson>[
    {'included_in_turnover': false},
  ];
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '$customerBillingPath/legacy',
            data: {
              ..._header,
              'customer_id': _customer!.id,
              'document_date': billingDay(_date),
              'lines': _lines,
            },
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    BillingJson target,
    String key,
    String label, {
    bool decimal = false,
  }) => TextFormField(
    initialValue: target[key] as String?,
    enabled: !_busy,
    decoration: InputDecoration(labelText: label),
    keyboardType: decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    onChanged: (value) => target[key] = decimal
        ? value.trim().replaceAll(',', '.')
        : value.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.cbRegisterLegacy),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchPicker<Customer>(
                label: l.customers,
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .crm
                            .listCustomers(q: q, limit: 20))
                        .items,
                display: (customer) => '${customer.code} · ${customer.name}',
                onSelected: (customer) => setState(() => _customer = customer),
                enabled: !_busy,
              ),
              InvoiceDateField(
                label: l.cbDate,
                value: _date,
                onChanged: (date) => setState(() => _date = date ?? _date),
              ),
              _field(_header, 'number', l.cbOriginal),
              _field(_header, 'evidence_reference', l.cbEvidence),
              _field(_header, 'currency', l.cbCurrency),
              DropdownButtonFormField<String>(
                initialValue: _header['vat_regime'],
                decoration: InputDecoration(labelText: l.cbVatRegime),
                items: [
                  DropdownMenuItem(
                    value: 'domestic',
                    child: Text(l.cbDomestic),
                  ),
                  DropdownMenuItem(
                    value: 'domestic_reverse_charge',
                    child: Text(l.cbReverseCharge),
                  ),
                  DropdownMenuItem(value: 'intra_eu', child: Text(l.cbIntraEu)),
                  DropdownMenuItem(
                    value: 'outside_eu',
                    child: Text(l.cbOutsideEu),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => _header['vat_regime'] = value!,
              ),
              for (final line in _lines)
                KeyedSubtree(
                  key: ObjectKey(line),
                  child: Column(
                    children: [
                      const Divider(),
                      _field(line, 'product_code', l.cbProductCode),
                      _field(line, 'description', l.cbDescription),
                      _field(line, 'unit', l.cbUnit),
                      _field(line, 'quantity', l.cbQuantity, decimal: true),
                      _field(line, 'net_total', l.cbNet, decimal: true),
                      _field(line, 'vat_rate', l.cbVatRate, decimal: true),
                      _field(line, 'vat_total', l.cbVatTotal, decimal: true),
                      DropdownButtonFormField<bool>(
                        initialValue: line['included_in_turnover'] as bool?,
                        decoration: InputDecoration(labelText: l.cbEligible),
                        items: [
                          DropdownMenuItem(value: true, child: Text(l.yes)),
                          DropdownMenuItem(value: false, child: Text(l.no)),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => line['included_in_turnover'] = value,
                              ),
                      ),
                      if (_lines.length > 1)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _lines.remove(line)),
                          child: Text(l.cbRemoveLine),
                        ),
                    ],
                  ),
                ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _lines.add({})),
                child: Text(l.cbAddLine),
              ),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  _customer == null ||
                  _lines.any((line) => line['included_in_turnover'] == null)
              ? null
              : _save,
          child: Text(l.cbRegisterLegacy),
        ),
      ],
    );
  }
}
