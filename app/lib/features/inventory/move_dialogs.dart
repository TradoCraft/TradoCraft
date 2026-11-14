import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import '../../shared/photos.dart' show newClientId;
import '../../shared/search_picker.dart';
import 'inventory_common.dart';
import '../../shared/app_icons.dart';

enum MoveKind { receive, issue, transfer }

/// Receive, issue or transfer stock. Returns true when a move was posted (or a retry of it).
///
/// The move id is chosen once when the dialog opens, so pressing the button again after a lost
/// answer repeats the same move instead of posting a second one.
Future<bool?> showMoveDialog(
  BuildContext context,
  MoveKind kind, {
  Product? product,
  String? locationId,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      MoveDialog(kind: kind, product: product, locationId: locationId),
);

const _receiveReasons = ['manual_receipt', 'return'];
const _issueReasons = ['consumption', 'shipment', 'scrap', 'repair_use'];
const _transferReasons = ['transfer', 'van_replenishment'];

class MoveDialog extends ConsumerStatefulWidget {
  const MoveDialog({
    super.key,
    required this.kind,
    this.product,
    this.locationId,
  });
  final MoveKind kind;
  final Product? product;
  final String? locationId;

  @override
  ConsumerState<MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends ConsumerState<MoveDialog> {
  final _id = newClientId();
  final _qty = TextEditingController();
  final _lotNumber = TextEditingController();
  final _serial = TextEditingController();
  final _note = TextEditingController();
  Product? _product;
  String? _from, _to;
  String? _uom, _lotId, _serialUnitId, _customerId;
  DateTime? _expiry;
  late String _reason = switch (widget.kind) {
    MoveKind.receive => _receiveReasons.first,
    MoveKind.issue => _issueReasons.first,
    MoveKind.transfer => _transferReasons.first,
  };
  List<Lot> _lots = [];
  List<String> _uoms = [];
  String? _error;
  bool _busy = false;

  /// Counts product selections, so answers to an earlier selection are ignored.
  int _selection = 0;

  /// A request went out and its outcome is unknown (no answer, or a server error): the move may
  /// have been posted. The form is locked and only the same request can be repeated, so the
  /// retry carries the same id and content; to change anything the dialog is closed and reopened.
  bool _unresolved = false;

  TradocraftApi get _api => ref.read(apiProvider);
  bool get _receive => widget.kind == MoveKind.receive;
  bool get _issue => widget.kind == MoveKind.issue;
  bool get _serialTracked => _product?.tracking == 'serial';
  bool get _lotTracked => _product?.tracking == 'lot';

  @override
  void initState() {
    super.initState();
    if (_receive) {
      _to = widget.locationId;
    } else {
      _from = widget.locationId;
    }
    if (widget.product != null) _setProduct(widget.product!);
  }

  @override
  void dispose() {
    _qty.dispose();
    _lotNumber.dispose();
    _serial.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _setProduct(Product p) async {
    final selection = ++_selection;
    bool current() => mounted && selection == _selection;
    setState(() {
      _product = p;
      _uom = null;
      _lotId = null;
      _serialUnitId = null;
      _lots = [];
      _uoms = [p.unit];
    });
    try {
      if (p.tracking == 'lot' && !_receive) {
        final lots = await _api.inventory.listLots(
          productId: p.id,
          inStock: true,
        );
        if (current()) setState(() => _lots = lots);
      }
      final own = await _api.inventory.productUoms(id: p.id);
      final all = await _api.inventory.listUoms();
      final category = all.where((u) => u.code == p.unit).firstOrNull?.category;
      final codes = {
        p.unit,
        ...own.map((u) => u.uomCode),
        // Pieces, sets and boxes do not convert into each other by themselves: only the
        // conversions of the product are offered for the category `unit`.
        if (category != null && category != 'unit')
          ...all.where((u) => u.category == category).map((u) => u.code),
      };
      if (current()) setState(() => _uoms = codes.toList());
    } catch (_) {
      // Other units are a convenience; the stock unit always works.
    }
  }

  String get _title => switch (widget.kind) {
    MoveKind.receive => context.l10n.stockReceive,
    MoveKind.issue => context.l10n.stockIssue,
    MoveKind.transfer => context.l10n.stockTransfer,
  };

  Future<void> _submit() async {
    final l = context.l10n;
    final p = _product;
    final quantity = _serialTracked ? '1' : parseDecimalInput(_qty.text);
    if (p == null || quantity == null) {
      setState(() => _error = l.stockProductQuantityRequired);
      return;
    }
    final uom = _uom == p.unit ? null : _uom;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = _api.inventory;
      if (_receive) {
        await api.receive(
          body: ReceiptInput(
            id: _id,
            productId: p.id,
            locationId: _to ?? '',
            quantity: quantity,
            uom: uom,
            lotNumber: _lotTracked ? _lotNumber.text.trim() : null,
            expiryDate: _lotTracked ? _expiry : null,
            serialNumber: _serialTracked ? _serial.text.trim() : null,
            reason: _reason,
            note: note,
          ),
        );
      } else if (_issue) {
        await api.issue(
          body: IssueInput(
            id: _id,
            productId: p.id,
            locationId: _from ?? '',
            quantity: quantity,
            uom: uom,
            lotId: _lotId,
            serialUnitId: _serialUnitId,
            reason: _reason,
            customerId: _customerId,
            note: note,
          ),
        );
      } else {
        await api.transfer(
          body: TransferInput(
            id: _id,
            productId: p.id,
            fromLocationId: _from ?? '',
            toLocationId: _to ?? '',
            quantity: quantity,
            uom: uom,
            lotId: _lotId,
            serialUnitId: _serialUnitId,
            reason: _reason,
            note: note,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
          // A refusal (4xx) means nothing was posted and the form can be corrected. Anything
          // else may have been posted, so only the same request may be repeated.
          _unresolved =
              e is! DioException ||
              (e.response?.statusCode ?? 500) >= 500 ||
              e.response?.statusCode == 408;
        });
      }
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (d != null) setState(() => _expiry = d);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12);
    final reasons = switch (widget.kind) {
      MoveKind.receive => _receiveReasons,
      MoveKind.issue => _issueReasons,
      MoveKind.transfer => _transferReasons,
    };
    final p = _product;
    return AlertDialog(
      title: Text(p == null ? _title : '$_title · ${p.code}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: ExcludeFocus(
            excluding: _unresolved,
            child: IgnorePointer(
              ignoring: _unresolved,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.product == null)
                    SearchPicker<Product>(
                      label: l.product,
                      display: (p) => '${p.code} · ${p.name}',
                      search: (q) async =>
                          (await _api.products.listProducts(
                                q: q,
                                limit: 20,
                                active: true,
                              )).items
                              .where((p) => p.productType != 'service')
                              .toList(),
                      onSelected: _setProduct,
                    ),
                  if (widget.product == null) gap,
                  if (!_receive)
                    LocationField(
                      label: l.stockFrom,
                      value: _from,
                      onChanged: (v) => setState(() => _from = v),
                    ),
                  if (!_receive) gap,
                  if (!_issue)
                    LocationField(
                      label: _receive ? l.stockLocation : l.stockTo,
                      value: _to,
                      onChanged: (v) => setState(() => _to = v),
                    ),
                  if (!_issue) gap,
                  if (p != null && _lotTracked && _receive) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lotNumber,
                            decoration: InputDecoration(
                              labelText: l.stockLotNumber,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.eventOutlined),
                          label: Text(
                            _expiry == null ? l.stockExpiry : date(_expiry),
                          ),
                          onPressed: _pickExpiry,
                        ),
                      ],
                    ),
                    gap,
                  ],
                  if (p != null && _lotTracked && !_receive) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _lotId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.stockLot),
                      items: [
                        for (final lot in _lots)
                          DropdownMenuItem(
                            value: lot.id,
                            child: Text(
                              '${lot.lotNumber} · ${number(lot.onHand)}'
                              '${lot.expiryDate == null ? '' : ' · ${date(lot.expiryDate)}'}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _lotId = v),
                    ),
                    gap,
                  ],
                  if (p != null && _serialTracked && _receive) ...[
                    TextField(
                      controller: _serial,
                      decoration: InputDecoration(labelText: l.serialNumber),
                    ),
                    gap,
                  ],
                  if (p != null && _serialTracked && !_receive) ...[
                    SearchPicker<SerialUnit>(
                      // A new product starts with an empty picker, like `_serialUnitId`.
                      key: ValueKey('serial-${p.id}'),
                      label: l.serialNumber,
                      display: (s) => s.serialNumber,
                      search: (q) async => (await _api.engineering.listSerials(
                        productId: p.id,
                        q: q,
                        status: 'in_stock',
                        limit: 20,
                      )).items,
                      onSelected: (s) => _serialUnitId = s.id,
                    ),
                    gap,
                  ],
                  if (p != null && !_serialTracked)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qty,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(labelText: l.quantity),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_uoms.length),
                            initialValue: _uom ?? p.unit,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: l.unit),
                            items: [
                              for (final u in _uoms)
                                DropdownMenuItem(value: u, child: Text(u)),
                            ],
                            onChanged: (v) => setState(() => _uom = v),
                          ),
                        ),
                      ],
                    ),
                  gap,
                  DropdownButtonFormField<String>(
                    initialValue: _reason,
                    decoration: InputDecoration(labelText: l.reason),
                    items: [
                      for (final r in reasons)
                        DropdownMenuItem(
                          value: r,
                          child: Text(l.stockReason(r)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _reason = v!),
                  ),
                  if (_issue && _reason == 'shipment' && _serialTracked) ...[
                    gap,
                    SearchPicker<Customer>(
                      label: l.customer,
                      display: (c) => '${c.code} · ${c.name}',
                      search: (q) async =>
                          (await _api.crm.listCustomers(q: q, limit: 20)).items,
                      onSelected: (c) => _customerId = c.id,
                    ),
                  ],
                  gap,
                  TextField(
                    controller: _note,
                    decoration: InputDecoration(labelText: l.stockNote),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_title)),
      ],
    );
  }
}

/// Corrects the stock of a product at a location (inventory administrators).
Future<bool?> showAdjustDialog(
  BuildContext context, {
  required Product product,
  String? locationId,
}) => showDialog<bool>(
  context: context,
  builder: (_) => AdjustDialog(product: product, locationId: locationId),
);

class AdjustDialog extends ConsumerStatefulWidget {
  const AdjustDialog({super.key, required this.product, this.locationId});
  final Product product;
  final String? locationId;

  @override
  ConsumerState<AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<AdjustDialog> {
  final _id = newClientId();
  final _value = TextEditingController();
  final _lotNumber = TextEditingController();
  final _note = TextEditingController();
  late String? _location = widget.locationId;
  String? _lotId;
  bool _setTo = true;
  List<Lot> _lots = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.product.tracking == 'lot') {
      ref
          .read(apiProvider)
          .inventory
          .listLots(productId: widget.product.id)
          .then((l) {
            if (mounted) setState(() => _lots = l);
          })
          .catchError((_) {});
    }
  }

  Future<void> _submit() async {
    final value = parseDecimalInput(_value.text);
    if (value == null || _location == null || _note.text.trim().isEmpty) {
      setState(() => _error = context.l10n.stockAdjustRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .inventory
          .adjust(
            body: AdjustmentInput(
              id: _id,
              productId: widget.product.id,
              locationId: _location!,
              lotId: _lotId,
              lotNumber: _lotId == null && _lotNumber.text.trim().isNotEmpty
                  ? _lotNumber.text.trim()
                  : null,
              newQuantity: _setTo ? value : null,
              delta: _setTo ? null : value,
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, true);
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
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text('${l.stockAdjust} · ${widget.product.code}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocationField(
                label: l.stockLocation,
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              gap,
              if (widget.product.tracking == 'lot') ...[
                DropdownButtonFormField<String?>(
                  initialValue: _lotId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.stockLot),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.stockNewLot),
                    ),
                    for (final lot in _lots)
                      DropdownMenuItem<String?>(
                        value: lot.id,
                        child: Text(lot.lotNumber),
                      ),
                  ],
                  onChanged: (v) => setState(() => _lotId = v),
                ),
                if (_lotId == null)
                  TextField(
                    controller: _lotNumber,
                    decoration: InputDecoration(labelText: l.stockLotNumber),
                  ),
                gap,
              ],
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(l.stockNewQuantity)),
                  ButtonSegment(value: false, label: Text(l.stockChangeBy)),
                ],
                selected: {_setTo},
                onSelectionChanged: (s) => setState(() => _setTo = s.first),
              ),
              gap,
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: _setTo ? l.stockNewQuantity : l.stockChangeBy,
                  suffixText: widget.product.unit,
                ),
              ),
              gap,
              TextField(
                controller: _note,
                decoration: InputDecoration(labelText: l.stockAdjustReason),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
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
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l.stockAdjust),
        ),
      ],
    );
  }
}
