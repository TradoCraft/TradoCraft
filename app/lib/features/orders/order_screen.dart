import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/order_widgets.dart';
import '../../shared/power_grid_field.dart';
import '../../shared/sales_hints.dart';
import '../delivery/order_deliveries.dart';
import '../production/order_production.dart';
import '../inventory/order_stock_panel.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

final _historyProvider = FutureProvider.autoDispose
    .family<List<PriorityChange>, String>(
      (ref, id) => ref.watch(apiProvider).sales.priorityHistory(id: id),
    );

final _requestsProvider = FutureProvider.autoDispose
    .family<List<PriorityRequest>, String>(
      (ref, id) => ref.watch(apiProvider).sales.listRequests(id: id),
    );

/// A sales order with its revisions: drafts are edited and sent to the customer, a sent revision is
/// confirmed (on the customer's behalf here, or by the customer in the portal) or replaced by a new
/// revision. Production can ask the salesperson a question about it from here.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Order? _order;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  bool _editing = false;
  final _qty = <int, TextEditingController>{};
  final _discount = <int, TextEditingController>{};
  final _desc = <int, TextEditingController>{};
  final _removed = <int>{};
  final _notes = TextEditingController();
  final _reference = TextEditingController();
  final _country = TextEditingController();
  String _purpose = 'installation';

  /// A specific power grid of the delivery country; null = any grid of that country.
  String? _gridId;

  SalesClient get _api => ref.read(apiProvider).sales;

  @override
  void initState() {
    super.initState();
    _load(() => _api.getOrder(id: widget.id));
  }

  @override
  void dispose() {
    _disposeEditors();
    _notes.dispose();
    _reference.dispose();
    _country.dispose();
    super.dispose();
  }

  void _disposeEditors() {
    for (final c in [..._qty.values, ..._discount.values, ..._desc.values]) {
      c.dispose();
    }
    _qty.clear();
    _discount.clear();
    _desc.clear();
    _removed.clear();
  }

  Future<void> _load(Future<Order> Function() call) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await call();
      if (mounted) _show(o);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bumped whenever an order is shown (loaded or saved) so the stock panel reloads: a saved draft
  /// can change quantities without changing the status or the revision number.
  int _stockReload = 0;

  void _show(Order o) {
    TabScope.reportTitle(context, o.order.number);
    TabScope.reportDirty(context, false);
    setState(() {
      _stockReload++;
      _order = o;
      _editing = false;
      _disposeEditors();
    });
    ref.invalidate(_historyProvider(widget.id));
    ref.invalidate(_requestsProvider(widget.id));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _close() {
    if (context.canPop()) {
      context.pop(_changed);
    } else {
      context.go('/orders');
    }
  }

  Future<void> _openRevision(int revision) {
    final current = _order!.order.currentRevision;
    return _load(
      () => revision == current
          ? _api.getOrder(id: widget.id)
          : _api.getOrderRevision(id: widget.id, revision: revision),
    );
  }

  void _startEditing() {
    final o = _order!;
    _disposeEditors();
    for (final line in o.lines) {
      _qty[line.position] = TextEditingController(text: number(line.quantity));
      _discount[line.position] = TextEditingController(
        text: number(line.lineDiscountPercent),
      );
      _desc[line.position] = TextEditingController(text: line.description);
    }
    _notes.text = o.notes;
    _reference.text = o.order.customerReference;
    _country.text = o.order.deliveryCountryCode ?? '';
    _purpose = o.order.purpose;
    _gridId = o.order.powerGridId;
    TabScope.reportDirty(context, true);
    setState(() => _editing = true);
  }

  /// The delivery country as typed, else the stored one (the server keeps it when none is sent).
  String _gridCountry(OrderSummary o) {
    final typed = _country.text.trim().toUpperCase();
    return typed.length == 2 ? typed : (o.deliveryCountryCode ?? '');
  }

  Future<void> _save() => _run(() async {
    final o = _order!;
    final lines = <OrderLineEdit>[];
    for (final line in o.lines) {
      if (_removed.contains(line.position)) continue;
      final qty = parseDecimalInput(_qty[line.position]!.text);
      if (qty == null) throw StateError(context.l10n.quantity);
      String? discount;
      if (line.pricingType != 'net') {
        final text = _discount[line.position]!.text;
        discount = text.trim().isEmpty ? '0' : parseDecimalInput(text);
        if (discount == null) throw StateError(context.l10n.lineDiscount);
      }
      lines.add(
        OrderLineEdit(
          position: line.position,
          quantity: qty,
          description: _desc[line.position]!.text.trim(),
          lineDiscountPercent: discount,
        ),
      );
    }
    final country = _country.text.trim().toUpperCase();
    if (country.isNotEmpty && country.length != 2) {
      throw StateError(context.l10n.deliveryCountryInvalid);
    }
    final saved = await _api.editOrder(
      id: widget.id,
      body: OrderEditInput(
        lines: lines,
        notes: _notes.text.trim(),
        customerReference: _reference.text.trim(),
        purpose: _purpose,
        deliveryCountryCode: country.isEmpty ? null : country,
        powerGridId: _purpose == 'stock' ? null : _gridId,
        // "Any grid" replacing a stored grid must be said explicitly: omitting keeps the stored one.
        clearPowerGrid:
            _purpose != 'stock' &&
                _gridId == null &&
                o.order.powerGridId != null
            ? true
            : null,
      ),
    );
    if (!mounted) return;
    _show(saved);
    _snack(context.l10n.orderSaved);
  });

  Future<bool> _confirmDialog(String title, String body) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 480, child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.send),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _send() async {
    final l = context.l10n;
    if (!await _confirmDialog(
      l.sendOrderConfirmation,
      l.sendOrderConfirmationHelp,
    )) {
      return;
    }
    await _run(() async {
      final o = await _api.sendOrder(id: widget.id);
      if (!mounted) return;
      _show(o);
      _snack(context.l10n.orderConfirmationQueued);
    });
  }

  Future<void> _newRevision() => _run(() async {
    _show(await _api.newRevision(id: widget.id));
  });

  Future<void> _confirmOnBehalf() async {
    final l = context.l10n;
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: l.confirmOnBehalf,
        help: l.confirmOnBehalfHelp,
        label: l.noteOptional,
        required: false,
      ),
    );
    if (note == null) return;
    Order? confirmed;
    await _run(() async {
      final o = await _api.confirm(
        id: widget.id,
        body: ConfirmOrderInput(
          revision: _order!.revision,
          note: note.isEmpty ? null : note,
        ),
      );
      if (!mounted) return;
      _show(o);
      _snack(context.l10n.orderConfirmedSnack);
      confirmed = o;
    });
    // The confirm call is the one place an order returns warnings and suggestions.
    final result = confirmed;
    if (result != null &&
        mounted &&
        (result.warnings.isNotEmpty || result.suggestions.isNotEmpty)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.hintsTitle),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SalesHints(
                warnings: result.warnings,
                suggestions: result.suggestions,
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cancelOrder() async {
    final l = context.l10n;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: l.cancelOrder,
        label: l.cancelReasonLabel,
        required: true,
      ),
    );
    if (reason == null) return;
    await _run(() async {
      _show(
        await _api.cancel(
          id: widget.id,
          body: CancelOrderInput(reason: reason),
        ),
      );
    });
  }

  Future<void> _changePriority() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _PriorityDialog(current: _order!.order.priority),
    );
    if (result == null) return;
    await _applyPriority(result.$1, result.$2, null);
  }

  Future<void> _applyPriority(
    String priority,
    String reason,
    String? requestId,
  ) => _run(() async {
    final o = await _api.changePriority(
      id: widget.id,
      body: PriorityInput(
        priority: priority,
        reason: reason,
        requestId: requestId,
      ),
    );
    if (!mounted) return;
    _show(o);
    _snack(context.l10n.priorityChangedSnack);
  });

  Future<void> _applyRequest(PriorityRequest r) {
    final l = context.l10n;
    final reason = r.message.trim().isEmpty
        ? l.priorityRequestLine(
            r.requestedByName,
            l.orderPriority(r.requestedPriority),
          )
        : r.message.trim();
    return _applyPriority(r.requestedPriority, reason, r.id);
  }

  Future<void> _dismissRequest(PriorityRequest r) async {
    final l = context.l10n;
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: l.dismissRequest,
        help: r.message,
        label: l.noteOptional,
        required: false,
      ),
    );
    if (note == null) return;
    await _run(() async {
      await _api.dismissRequest(
        id: widget.id,
        requestId: r.id,
        body: DismissRequestInput(note: note.isEmpty ? null : note),
      );
      ref.invalidate(_requestsProvider(widget.id));
      if (mounted) _snack(context.l10n.requestDismissedSnack);
    });
  }

  Future<void> _pdf() => _run(() async {
    final o = _order!;
    final bytes = await downloadBytes(
      ref.read(dioProvider),
      '/api/v1/orders/${o.order.id}/revisions/${o.revision}/pdf',
    );
    await Printing.layoutPdf(
      name: '${o.order.number}-r${o.revision}.pdf',
      onLayout: (_) async => Uint8List.fromList(bytes),
    );
  });

  Future<void> _ask(OrderSummary o) async {
    final l = context.l10n;
    final subject = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.questionToSales),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.questionToSalesHelp(o.salespersonName)),
              const SizedBox(height: 12),
              TextField(
                controller: subject,
                decoration: InputDecoration(labelText: l.subject),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                maxLines: 5,
                decoration: InputDecoration(labelText: l.question),
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
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.send),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    TicketDetail? t;
    final done = await runAction(
      context,
      () async => t = await ref
          .read(apiProvider)
          .helpdesk
          .productionQuestion(
            body: ProductionQuestionInput(
              orderId: o.id,
              subject: subject.text.trim(),
              body: body.text.trim(),
            ),
          ),
    );
    if (done && mounted) context.push('/helpdesk/${t!.ticket.id}');
  }

  Widget _actions(Order d, bool canWrite) {
    final l = context.l10n;
    final o = d.order;
    final isCurrent = d.revision == o.currentRevision;
    final open = !const [
      'cancelled',
      'ready_for_shipping',
      'partially_shipped',
      'shipped',
    ].contains(o.status);
    final busy = _busy;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : _pdf,
          icon: const Icon(AppIcons.pictureAsPdf),
          label: Text(l.pdf),
        ),
        if (canWrite && isCurrent && o.status == 'draft') ...[
          if (_editing) ...[
            FilledButton.icon(
              onPressed: busy ? null : _save,
              icon: const Icon(AppIcons.save),
              label: Text(l.save),
            ),
            TextButton(
              onPressed: busy ? null : () => _show(d),
              child: Text(l.cancel),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: busy ? null : _startEditing,
              icon: const Icon(AppIcons.edit),
              label: Text(l.edit),
            ),
            TutorialTarget(id: 'order-send', child: FilledButton.icon(
              onPressed: busy ? null : _send,
              icon: const Icon(AppIcons.forwardToInbox),
              label: Text(l.sendOrderConfirmation),
            )),
          ],
        ],
        if (canWrite && isCurrent && o.status == 'sent') ...[
          OutlinedButton.icon(
            onPressed: busy ? null : _newRevision,
            icon: const Icon(AppIcons.copy),
            label: Text(l.newRevision),
          ),
          TutorialTarget(id: 'order-confirm', child: FilledButton.icon(
            onPressed: busy ? null : _confirmOnBehalf,
            icon: const Icon(AppIcons.check),
            label: Text(l.confirmOnBehalf),
          )),
        ],
        if (canWrite && isCurrent && open && !_editing)
          OutlinedButton.icon(
            onPressed: busy ? null : _cancelOrder,
            icon: const Icon(AppIcons.cancel),
            label: Text(l.cancelOrder),
          ),
      ],
    );
  }

  Widget _revisions(Order d) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final current = d.order.currentRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.revisions, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final r in d.revisions)
              ChoiceChip(
                selected: r.revision == d.revision,
                label: Text(
                  '${l.revisionNumber(r.revision)} · ${l.orderStatus(r.status)}'
                  ' · ${money(r.total, currency: d.order.currency)}',
                ),
                onSelected: _busy || _editing
                    ? null
                    : (_) => _openRevision(r.revision),
              ),
          ],
        ),
        if (d.revision != current) ...[
          const SizedBox(height: 8),
          MaterialBanner(
            content: Text(l.revisionViewNotice(d.revision, current)),
            actions: [
              TextButton(
                onPressed: () => _openRevision(current),
                child: Text(l.backToCurrentRevision),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _confirmation(Order d) {
    final l = context.l10n;
    final via = switch (d.confirmedVia) {
      'staff' => l.confirmedViaStaff,
      'portal' => l.confirmedViaPortal,
      _ => d.confirmedVia ?? '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.confirmation, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          children: [
            InfoItem(l.confirmationDate, date(d.confirmedAt?.toLocal())),
            InfoItem(l.confirmedVia, via),
            InfoItem(
              l.confirmedRevision,
              d.confirmedRevision == null
                  ? ''
                  : l.revisionNumber(d.confirmedRevision!),
            ),
            if (d.confirmationNote.isNotEmpty)
              InfoItem(l.notes, d.confirmationNote),
          ],
        ),
      ],
    );
  }

  Widget _lines(Order d) {
    final l = context.l10n;
    final o = d.order;
    final editing = _editing;
    Widget field(TextEditingController c, double width, {bool right = false}) =>
        SizedBox(
          width: width,
          child: TextField(
            controller: c,
            textAlign: right ? TextAlign.right : TextAlign.start,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(l.code)),
          DataColumn(label: Text(l.description)),
          DataColumn(label: Text(l.quantity), numeric: true),
          if (editing) DataColumn(label: Text(l.lineDiscount), numeric: true),
          DataColumn(label: Text(l.netPrice), numeric: true),
          DataColumn(label: Text(l.total), numeric: true),
          if (editing) const DataColumn(label: SizedBox.shrink()),
        ],
        rows: [
          for (final line in d.lines)
            if (!_removed.contains(line.position))
              DataRow(
                cells: [
                  DataCell(Text(line.productCode)),
                  DataCell(
                    editing
                        ? field(_desc[line.position]!, 280)
                        : Text(line.description),
                  ),
                  DataCell(
                    editing
                        ? field(_qty[line.position]!, 90, right: true)
                        : Text('${number(line.quantity)} ${line.unit}'),
                  ),
                  if (editing)
                    DataCell(
                      line.pricingType == 'net'
                          ? Text(l.pricingNet)
                          : field(_discount[line.position]!, 70, right: true),
                    ),
                  DataCell(
                    Text(money(line.netUnitPrice, currency: o.currency)),
                  ),
                  DataCell(Text(money(line.lineTotal, currency: o.currency))),
                  if (editing)
                    DataCell(
                      IconButton(
                        tooltip: l.removeLine,
                        icon: const Icon(AppIcons.delete),
                        onPressed: () =>
                            setState(() => _removed.add(line.position)),
                      ),
                    ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _priority(Order d, bool canWrite) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final history = ref.watch(_historyProvider(widget.id));
    final requests = ref.watch(_requestsProvider(widget.id));
    final open = !const [
      'cancelled',
      'ready_for_shipping',
      'partially_shipped',
      'shipped',
    ].contains(d.order.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.priority, style: theme.textTheme.titleMedium),
            const SizedBox(width: 12),
            PriorityIndicator(d.order.priority),
            const Spacer(),
            if (canWrite && open)
              OutlinedButton.icon(
                onPressed: _busy ? null : _changePriority,
                icon: const Icon(AppIcons.flag),
                label: Text(l.changePriority),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l.priorityRequests, style: theme.textTheme.titleSmall),
        requests.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => list.isEmpty
              ? Text(l.noPriorityRequests)
              : Column(
                  children: [
                    for (final r in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.priorityRequestLine(
                            r.requestedByName,
                            l.orderPriority(r.requestedPriority),
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (r.message.isNotEmpty) r.message,
                            l.priorityRequestStatus(r.status),
                            if (r.resolutionNote.isNotEmpty) r.resolutionNote,
                          ].join(' · '),
                        ),
                        trailing: canWrite && r.status == 'open'
                            ? Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: _busy
                                        ? null
                                        : () => _applyRequest(r),
                                    child: Text(l.apply),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _dismissRequest(r),
                                    child: Text(l.dismiss),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Text(l.priorityHistory, style: theme.textTheme.titleSmall),
        history.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => list.isEmpty
              ? Text(l.noPriorityChanges)
              : Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.priorityChangeLine(
                            date(c.changedAt.toLocal()),
                            l.orderPriority(c.oldPriority),
                            l.orderPriority(c.newPriority),
                            c.changedByName,
                          ),
                        ),
                        subtitle: Text(c.reason),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = perms.contains('orders.write');
    final theme = Theme.of(context);
    final d = _order;
    if (d == null) {
      return Scaffold(
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Text(_error ?? ''),
        ),
      );
    }
    final o = d.order;
    const gap = SizedBox(height: 16);
    // The order row mirrors the latest revision; an older one shows its own totals.
    final rev = d.revisions.where((r) => r.revision == d.revision).firstOrNull;
    final subtotal = rev?.subtotal ?? o.subtotal;
    final total = rev?.total ?? o.total;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _close,
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                '${l.order} ${o.number}',
                style: theme.textTheme.headlineSmall,
              ),
              OrderStatusChip(o.status),
              PriorityIndicator(o.priority),
              Chip(
                label: Text(l.revisionNumber(d.revision)),
                visualDensity: VisualDensity.compact,
              ),
              OutlinedButton.icon(
                icon: const Icon(AppIcons.requestQuote),
                label: Text('${o.quotationNumber} rev. ${o.quotationRevision}'),
                onPressed: () => context.push('/quotations/${o.quotationId}'),
              ),
              if (perms.contains('helpdesk.write'))
                FilledButton.tonalIcon(
                  icon: const Icon(AppIcons.help),
                  label: Text(l.questionToSales),
                  onPressed: () => _ask(o),
                ),
              if (_loading || _busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          gap,
          _actions(d, canWrite),
          gap,
          Wrap(
            children: [
              InfoItem(l.customer, o.customerName),
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(right: 32, bottom: 8),
                  child: SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _reference,
                      decoration: InputDecoration(
                        labelText: l.customerReference,
                      ),
                    ),
                  ),
                )
              else
                InfoItem(l.customerReference, o.customerReference),
              if (_editing) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 32, bottom: 8),
                  child: SegmentedButton<String>(
                    key: const ValueKey('purpose'),
                    showSelectedIcon: false,
                    segments: [
                      for (final p in const ['installation', 'stock'])
                        ButtonSegment(value: p, label: Text(l.purposeName(p))),
                    ],
                    selected: {_purpose},
                    onSelectionChanged: (s) =>
                        setState(() => _purpose = s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 32, bottom: 8),
                  child: SizedBox(
                    width: 160,
                    child: TextField(
                      key: const ValueKey('deliveryCountry'),
                      controller: _country,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(2),
                        TextInputFormatter.withFunction(
                          (old, v) => v.copyWith(text: v.text.toUpperCase()),
                        ),
                      ],
                      decoration: InputDecoration(labelText: l.deliveryCountry),
                      // A grid belongs to one country.
                      onChanged: (_) => setState(() => _gridId = null),
                    ),
                  ),
                ),
                if (_purpose == 'installation')
                  Padding(
                    padding: const EdgeInsets.only(right: 32, bottom: 8),
                    child: PowerGridField(
                      country: _gridCountry(o),
                      selectedId: _gridId,
                      onChanged: (v) => setState(() => _gridId = v),
                    ),
                  ),
              ] else ...[
                InfoItem(l.purpose, l.purposeName(o.purpose)),
                InfoItem(l.deliveryCountry, o.deliveryCountryCode ?? ''),
              ],
              InfoItem(l.date, date(o.orderDate)),
              if (o.promisedDate != null)
                InfoItem(l.productionPromised, date(o.promisedDate)),
              InfoItem(l.salesperson, o.salespersonName),
              InfoItem(l.totalExclVat, money(subtotal, currency: o.currency)),
              InfoItem(l.vat, money(d.vatTotal, currency: o.currency)),
              InfoItem(l.totalInclVat, money(total, currency: o.currency)),
            ],
          ),
          if (o.status == 'cancelled' && d.cancelReason.isNotEmpty) ...[
            Text(
              l.cancelledReason(d.cancelReason),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            gap,
          ],
          if (d.confirmedAt != null) ...[_confirmation(d), gap],
          _revisions(d),
          gap,
          if (_editing)
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: l.notes),
            )
          else if (d.notes.isNotEmpty)
            Text(d.notes),
          gap,
          _lines(d),
          if (perms.contains('inventory.read') &&
              o.status != 'cancelled' &&
              d.revision == o.currentRevision) ...[
            gap,
            OrderStockPanel(
              orderId: o.id,
              revision: '${o.status}-${d.revision}-$_stockReload',
            ),
          ],
          if (perms.contains('production.read') &&
              d.revision == o.currentRevision &&
              !const ['draft', 'sent'].contains(o.status)) ...[
            gap,
            OrderProduction(
              orderId: o.id,
              orderStatus: o.status,
              onChanged: () {
                _changed = true;
                _load(() => _api.getOrder(id: widget.id));
              },
            ),
          ],
          if (perms.contains('delivery.read') &&
              d.revision == o.currentRevision &&
              !const ['draft', 'sent'].contains(o.status)) ...[
            gap,
            OrderDeliveries(
              orderId: o.id,
              orderStatus: o.status,
              onChanged: () {
                _changed = true;
                _load(() => _api.getOrder(id: widget.id));
              },
            ),
          ],
          gap,
          const Divider(),
          _priority(d, canWrite),
        ],
      ),
    );
  }
}

/// Asks for a line of text; [required] texts cannot be left empty. Pops the trimmed text.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.required,
    this.help,
  });
  final String title;
  final String label;
  final String? help;
  final bool required;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _text = TextEditingController();
  bool _missing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final help = widget.help;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (help != null && help.isNotEmpty) ...[
              Text(help),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _text,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _missing ? l.reasonRequired : null,
              ),
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
          onPressed: () {
            final text = _text.text.trim();
            if (widget.required && text.isEmpty) {
              setState(() => _missing = true);
              return;
            }
            Navigator.pop(context, text);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// New priority plus the reason that is kept in the history. Pops `(priority, reason)`.
class _PriorityDialog extends StatefulWidget {
  const _PriorityDialog({required this.current});
  final String current;

  @override
  State<_PriorityDialog> createState() => _PriorityDialogState();
}

class _PriorityDialogState extends State<_PriorityDialog> {
  static const _all = ['low', 'normal', 'expedite'];
  late String _priority = widget.current == 'expedite' ? 'normal' : 'expedite';
  final _reason = TextEditingController();
  bool _missing = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.changePriority),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: InputDecoration(labelText: l.newPriority),
              items: [
                for (final p in _all.where((p) => p != widget.current))
                  DropdownMenuItem(value: p, child: Text(l.orderPriority(p))),
              ],
              onChanged: (p) => setState(() => _priority = p ?? _priority),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l.reason,
                errorText: _missing ? l.reasonRequired : null,
              ),
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
          onPressed: () {
            final reason = _reason.text.trim();
            if (reason.isEmpty) {
              setState(() => _missing = true);
              return;
            }
            Navigator.pop(context, (_priority, reason));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
