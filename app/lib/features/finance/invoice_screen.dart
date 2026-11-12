import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'invoice_form.dart';
import 'invoice_widgets.dart';
import '../tutorial/targets.dart';

/// A supplier invoice in a workspace tab: header, lines with the three-way match report per
/// line, an overall match banner, and the actions the status and the user's rights allow.
/// Drafts are editable.
class SupplierInvoiceScreen extends ConsumerStatefulWidget {
  /// Shows the supplier invoice with [id].
  const SupplierInvoiceScreen({super.key, required this.id});

  /// The supplier invoice to show.
  final String id;

  @override
  ConsumerState<SupplierInvoiceScreen> createState() =>
      _SupplierInvoiceScreenState();
}

class _SupplierInvoiceScreenState extends ConsumerState<SupplierInvoiceScreen> {
  InvoiceDetail? _inv;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  // Draft editing state; non-null `_lines` means the form is open.
  List<InvLineDraft>? _lines;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  final _number = TextEditingController();
  final _notes = TextEditingController();

  FinanceClient get _api => ref.read(apiProvider).finance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    for (final d in _lines ?? const <InvLineDraft>[]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inv = await _api.getInvoice(id: widget.id);
      if (mounted) _applyLoaded(inv);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyLoaded(InvoiceDetail inv) {
    TabScope.reportTitle(context, inv.invoiceNumber);
    setState(() => _inv = inv);
  }

  void _startEdit() {
    final inv = _inv!;
    for (final d in _lines ?? const <InvLineDraft>[]) {
      d.dispose();
    }
    setState(() {
      _lines = [for (final l in inv.lines) InvLineDraft.fromLine(l)];
      _invoiceDate = inv.invoiceDate;
      _dueDate = inv.dueDate;
      _number.text = inv.invoiceNumber;
      _notes.text = inv.notes;
    });
  }

  void _stopEdit() {
    final old = _lines;
    setState(() => _lines = null);
    for (final d in old ?? const <InvLineDraft>[]) {
      d.dispose();
    }
    TabScope.reportDirty(context, false);
  }

  void _dirty() {
    setState(() => _error = null);
    TabScope.reportDirty(context, true);
  }

  Future<void> _save() async {
    final l = context.l10n;
    final number = _number.text.trim();
    if (number.isEmpty || number.length > 64) {
      setState(() => _error = l.finNumberRequired);
      return;
    }
    final (lines, problem) = buildInvoiceLines(l, _lines!);
    if (lines == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inv = await _api.updateInvoice(
        id: widget.id,
        body: UpdateInvoiceInput(
          invoiceNumber: number,
          invoiceDate: _invoiceDate,
          dueDate: _dueDate,
          notes: _notes.text.trim(),
          lines: lines,
        ),
      );
      if (!mounted) return;
      _applyLoaded(inv);
      _stopEdit();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs a lifecycle call; conflicts (409/422) are shown in the banner.
  Future<void> _transition(Future<InvoiceDetail> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inv = await call();
      if (mounted) _applyLoaded(inv);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a mandatory free-text reason; null when cancelled.
  Future<String?> _askReason({
    required String title,
    required String label,
    String? help,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title, label: label, help: help),
  );

  Future<void> _approve() async {
    final l = context.l10n;
    String? override;
    if (!_inv!.matchReport.matched) {
      override = await _askReason(
        title: l.finOverrideTitle,
        label: l.finOverrideReason,
        help: l.finOverrideHelp,
      );
      if (override == null) return;
    }
    await _transition(
      () => _api.approveInvoice(
        id: widget.id,
        body: ApproveInvoiceInput(overrideReason: override),
      ),
    );
  }

  Future<void> _dispute() async {
    final l = context.l10n;
    final reason = await _askReason(
      title: l.finDispute,
      label: l.finDisputeReason,
    );
    if (reason == null) return;
    await _transition(
      () => _api.disputeInvoice(
        id: widget.id,
        body: DisputeInvoiceInput(reason: reason),
      ),
    );
  }

  Future<void> _markPaid() async {
    final result = await showDialog<(DateTime, String)>(
      context: context,
      builder: (_) => const _MarkPaidDialog(),
    );
    if (result == null) return;
    await _transition(
      () => _api.markPaid(
        id: widget.id,
        body: MarkPaidInput(paidAt: result.$1, paymentReference: result.$2),
      ),
    );
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final number = _inv!.invoiceNumber;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.finDeleteDraft),
        content: Text(l.finDeleteConfirm(number)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('inv-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.deleteInvoice(id: widget.id);
      if (!mounted) return;
      TabScope.reportDirty(context, false);
      context.canPop() ? context.pop() : context.go('/finance');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The status actions available to the user.
  List<Widget> _actions(InvoiceDetail s) {
    final l = context.l10n;
    final canWrite = can(ref, 'finance.write');
    final canApprove = can(ref, 'finance.approve');
    final st = s.status;
    final open = st == 'draft' || st == 'matched';
    return [
      if (st == 'draft' && canWrite)
        OutlinedButton.icon(
          key: const ValueKey('inv-edit'),
          onPressed: _busy ? null : _startEdit,
          icon: const Icon(AppIcons.edit),
          label: Text(l.edit),
        ),
      if (open && canWrite)
        OutlinedButton(
          key: const ValueKey('inv-submit-match'),
          onPressed: _busy
              ? null
              : () => _transition(() => _api.submitMatch(id: widget.id)),
          child: Text(l.finSubmitMatch),
        ),
      if (open && canApprove)
        TutorialTarget(id: 'inv-approve', child: FilledButton(
          key: const ValueKey('inv-approve'),
          onPressed: _busy ? null : _approve,
          child: Text(l.finApprove),
        )),
      if (st == 'approved' && canApprove)
        TutorialTarget(id: 'inv-mark-paid', child: FilledButton(
          key: const ValueKey('inv-mark-paid'),
          onPressed: _busy ? null : _markPaid,
          child: Text(l.finMarkPaid),
        )),
      if ((open || st == 'approved') && canWrite)
        TutorialTarget(id: 'inv-dispute', child: TextButton(
          key: const ValueKey('inv-dispute'),
          onPressed: _busy ? null : _dispute,
          child: Text(l.finDispute),
        )),
      if ((st == 'disputed' || st == 'matched') && canWrite)
        TextButton(
          key: const ValueKey('inv-reopen'),
          onPressed: _busy
              ? null
              : () => _transition(() => _api.reopenInvoice(id: widget.id)),
          child: Text(l.finReopen),
        ),
      if (st == 'draft' && canWrite)
        TextButton(
          key: const ValueKey('inv-delete'),
          onPressed: _busy ? null : _delete,
          child: Text(l.finDeleteDraft),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _inv;
    if (s == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? ''),
            TextButton(onPressed: _load, child: Text(l.retry)),
          ],
        ),
      );
    }
    final editing = _lines != null;
    final report = s.matchReport;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              s.invoiceNumber,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            InvoiceStatusChip(status: s.status),
            if (!editing) ..._actions(s),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          MaterialBanner(
            key: const ValueKey('inv-banner'),
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: Text(l.close),
              ),
            ],
          ),
        if (_loading || _busy) const LinearProgressIndicator(),
        Wrap(
          children: [
            InfoItem(l.finInternalNumber, s.number),
            InfoItem(l.purchSupplier, s.supplierName),
            if (!editing) ...[
              InfoItem(l.finInvoiceDate, date(s.invoiceDate)),
              InfoItem(l.finDueDate, date(s.dueDate)),
            ],
            InfoItem(l.currency, s.currency),
            InfoItem(l.finNetTotal, money(s.netTotal, currency: s.currency)),
            InfoItem(l.vat, money(s.vatTotal, currency: s.currency)),
            InfoItem(
              l.finGrossTotal,
              money(s.grossTotal, currency: s.currency),
            ),
            if (!editing && s.notes.isNotEmpty) InfoItem(l.notes, s.notes),
            if (s.disputeReason.isNotEmpty)
              InfoItem(l.finDisputeReasonShown, s.disputeReason),
            if (s.overrideReason.isNotEmpty)
              InfoItem(l.finOverrideShown, s.overrideReason),
            if (s.paidAt != null) InfoItem(l.finPaidOn, date(s.paidAt)),
            if (s.paymentReference.isNotEmpty)
              InfoItem(l.finPaymentReference, s.paymentReference),
          ],
        ),
        if (s.purchaseOrderId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('inv-open-po'),
              onPressed: () =>
                  context.push('/purchase-orders/${s.purchaseOrderId}'),
              child: Text(
                '${l.finPurchaseOrder} ${s.purchaseOrderNumber ?? ''}'.trim(),
              ),
            ),
          ),
        if (editing) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('inv-edit-number'),
            controller: _number,
            decoration: InputDecoration(labelText: l.finInvoiceNumber),
            onChanged: (_) => _dirty(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              InvoiceDateField(
                label: l.finInvoiceDate,
                value: _invoiceDate,
                onChanged: (d) {
                  setState(() => _invoiceDate = d);
                  _dirty();
                },
              ),
              InvoiceDateField(
                label: l.finDueDate,
                value: _dueDate,
                onChanged: (d) {
                  setState(() => _dueDate = d);
                  _dirty();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('inv-edit-notes'),
            controller: _notes,
            decoration: InputDecoration(labelText: l.notes),
            maxLines: 2,
            onChanged: (_) => _dirty(),
          ),
        ],
        const Divider(height: 32),
        if (!editing && s.lines.isNotEmpty) _MatchBanner(report: report),
        Text(l.purchLines, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (editing) ...[
          InvoiceLinesEditor(lines: _lines!, onChanged: _dirty),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                key: const ValueKey('inv-edit-save'),
                onPressed: _busy ? null : _save,
                child: Text(l.save),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('inv-edit-cancel'),
                onPressed: _busy ? null : _stopEdit,
                child: Text(l.cancel),
              ),
            ],
          ),
        ] else
          _LinesTable(invoice: s),
      ],
    );
  }
}

/// The overall result of the match: 'matches' or 'does not match', with the tolerances.
class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.report});
  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok = report.matched;
    final color = ok ? Colors.green : Colors.orange;
    return TutorialTarget(id: 'inv-match-banner', child: Container(
      key: const ValueKey('inv-match-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: color.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? l.finMatches : l.finNotMatches,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color.shade800,
                  ),
                ),
                Text(
                  l.finTolerances(
                    number(report.quantityTolerancePct),
                    number(report.priceTolerancePct),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.invoice});
  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final byLine = {
      for (final m in invoice.matchReport.lines) m.invoiceLineId: m,
    };
    final cur = invoice.currency;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMaxHeight: double.infinity,
        dataRowMinHeight: 48,
        columns: [
          const DataColumn(label: Text('#')),
          DataColumn(label: Text(l.description)),
          DataColumn(label: Text(l.quantity), numeric: true),
          DataColumn(label: Text(l.unitPrice), numeric: true),
          DataColumn(label: Text(l.vatPercent), numeric: true),
          DataColumn(label: Text(l.purchLineTotal), numeric: true),
          DataColumn(label: Text(l.finMatchColumn)),
        ],
        rows: [
          for (final line in invoice.lines)
            DataRow(
              key: ValueKey('inv-line-${line.lineNumber}'),
              cells: [
                DataCell(Text('${line.lineNumber}')),
                DataCell(Text(line.description)),
                DataCell(Text(number(line.quantity))),
                DataCell(Text(money(line.unitPrice, currency: cur))),
                DataCell(Text(number(line.vatRate))),
                DataCell(Text(money(line.lineNet, currency: cur))),
                DataCell(
                  _MatchCell(
                    n: line.lineNumber,
                    match: byLine[line.id],
                    currency: cur,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The match result of one line: status chip, the numbers behind it and every issue.
class _MatchCell extends StatelessWidget {
  const _MatchCell({
    required this.n,
    required this.match,
    required this.currency,
  });
  final int n;
  final LineMatch? match;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final m = match;
    if (m == null) return const SizedBox.shrink();
    final l = context.l10n;
    final parts = <String>[
      if (m.orderedQuantity != null)
        '${l.finOrdered}: ${number(m.orderedQuantity)}',
      if (m.receivedQuantity != null)
        '${l.purchQtyReceived}: ${number(m.receivedQuantity)}',
      if (m.invoicedQuantity != null)
        '${l.finInvoiced}: ${number(m.invoicedQuantity)}',
      if (m.poUnitPrice != null)
        '${l.finOrderPrice}: ${money(m.poUnitPrice, currency: currency)}',
      '${l.finInvoicePrice}: ${money(m.invoiceUnitPrice, currency: currency)}',
      if (m.priceVariancePct != null)
        '${l.finVariance}: ${number(m.priceVariancePct)} %',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LineStatusChip(status: m.status, chipKey: ValueKey('inv-match-$n')),
          Text(parts.join(' · '), key: ValueKey('inv-match-numbers-$n')),
          if (m.issues.isNotEmpty)
            Text(
              m.issues.map((i) => lineStatusLabel(l, i)).join(', '),
              key: ValueKey('inv-match-issues-$n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog();

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  DateTime _paid = DateTime.now();
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.finMarkPaid),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InvoiceDateField(
            label: l.finPaymentDate,
            value: _paid,
            onChanged: (d) => setState(() => _paid = d!),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('inv-payment-reference'),
            controller: _ref,
            decoration: InputDecoration(labelText: l.finPaymentReference),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('inv-paid-ok'),
          onPressed: () => Navigator.pop(context, (_paid, _ref.text.trim())),
          child: Text(l.finMarkPaid),
        ),
      ],
    );
  }
}

/// A dialog asking for a mandatory free-text reason; pops with the trimmed text.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.label, this.help});

  final String title;
  final String label;
  final String? help;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctl = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.help != null) ...[
            Text(widget.help!),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('inv-reason'),
            controller: _ctl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _problem,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('inv-reason-ok'),
          onPressed: () {
            final r = _ctl.text.trim();
            if (r.isEmpty) {
              setState(() => _problem = l.finReasonRequired);
              return;
            }
            Navigator.pop(context, r);
          },
          child: Text(widget.title),
        ),
      ],
    );
  }
}
