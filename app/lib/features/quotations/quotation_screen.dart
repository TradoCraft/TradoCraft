import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/sales_hints.dart';
import '../../shared/options_chooser.dart';
import '../../shared/sub_item_chooser.dart';
import '../../shared/power_grid_field.dart';
import '../../shared/remark_history.dart';
import '../../shared/search_picker.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

/// An editable line of a draft. Prices are never computed here: they come from
/// the server's pricing preview, matched by position.
class _Line {
  _Line(
    this.product, {
    String quantity = '1',
    String discount = '0',
    String price = '',
    this.description,
    String? productionRemark,
    String customerRemark = '',
    this.section,
    this.comment,
    this.parent,
    this.percentOfParent,
    this.percentBase,
  }) : quantity = TextEditingController(text: quantity),
       discount = TextEditingController(text: discount),
       price = TextEditingController(text: price),
       // A new line starts with the product's default production remark.
       productionRemark = TextEditingController(
         text: productionRemark ?? product.defaultProductionRemark ?? '',
       ),
       customerRemark = TextEditingController(text: customerRemark);

  final Product product;
  final TextEditingController quantity;
  final TextEditingController discount;

  /// Confirmed price of an indicative product; empty while unconfirmed.
  final TextEditingController price;
  final String? description;

  /// Internal remark for production (never printed for the customer) and the remark printed under
  /// the description.
  final TextEditingController productionRemark;
  final TextEditingController customerRemark;

  /// The structure of a configured quotation, kept as it was loaded so that previews and saves
  /// send it back: section heading, comment, parent line and percent-of-parent pricing.
  final String? section;
  final String? comment;
  final _Line? parent;
  final String? percentOfParent;
  final PercentBase? percentBase;

  bool isDescendantOf(_Line other) {
    for (var p = parent; p != null; p = p.parent) {
      if (p == other) return true;
    }
    return false;
  }

  /// Depth below a top-level line: 0 for a normal line, 1 for an option of it, and so on.
  int get level => parent == null ? 0 : parent!.level + 1;

  bool get isNet => product.pricingType == 'net';
  bool get isIndicative => product.pricingType == 'indicative';

  /// Priced as a percentage of its parent: the server derives the price, so it is not editable
  /// and never sent as a unit price (even for an indicative product).
  bool get isPercent => percentOfParent != null;

  /// Whether the user confirms this line's price: indicative and not derived from the parent.
  bool get hasConfirmablePrice => isIndicative && !isPercent;

  /// Section heading (a child line inherits its parent's) and comment, so that the same product
  /// in several sections can be told apart; null when there is neither.
  String? get sectionAndComment {
    String? section;
    for (_Line? l = this; l != null && section == null; l = l.parent) {
      final s = l.section?.trim();
      if (s != null && s.isNotEmpty) section = s;
    }
    final parts = [
      ?section,
      if (comment?.trim().isNotEmpty ?? false) comment!.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  void dispose() {
    quantity.dispose();
    discount.dispose();
    price.dispose();
    productionRemark.dispose();
    customerRemark.dispose();
  }
}

/// The editable lines of a saved draft, keeping sections, comments and the parent and
/// percent-of-parent structure of configured quotations (lines without a product, such as the
/// shipping line, are kept by the server and left out).
List<_Line> _linesFromQuotation(
  List<QuotationLine> lines,
  Map<String, Product> products,
) {
  final byPosition = <int, _Line>{};
  final out = <_Line>[];
  for (final l in lines) {
    if (l.productId == null) continue;
    final parent = l.parentPosition == null
        ? null
        : byPosition[l.parentPosition];
    final line = _Line(
      products[l.productId]!,
      quantity: number(l.quantity),
      discount: number(l.lineDiscountPercent),
      price:
          l.pricingType == 'indicative' &&
              l.priceConfirmed &&
              (parent == null || l.percentOfParent == null)
          ? number(l.listUnitPrice)
          : '',
      description: l.description,
      productionRemark: l.productionRemark,
      customerRemark: l.customerRemark ?? '',
      section: l.section,
      comment: l.comment,
      parent: parent,
      percentOfParent: parent == null ? null : l.percentOfParent,
      percentBase: parent == null || l.percentBase == null
          ? null
          : PercentBase.fromJson(l.percentBase!),
    );
    byPosition[l.position] = line;
    out.add(line);
  }
  return out;
}

/// Create, edit (drafts), view and process a quotation.
class QuotationScreen extends ConsumerStatefulWidget {
  const QuotationScreen({
    super.key,
    this.id,
    this.customerId,
    this.opportunityId,
  });

  final String? id;

  /// Pre-selects the customer and opportunity of a new quotation.
  final String? customerId;
  final String? opportunityId;

  @override
  ConsumerState<QuotationScreen> createState() => _QuotationPageState();
}

class _QuotationPageState extends ConsumerState<QuotationScreen> {
  late String? _id = widget.id;
  Quotation? _q;
  Customer? _customer;
  late String? _opportunityId = widget.opportunityId;
  List<Opportunity> _opportunities = [];

  /// Price list date; null = the quote date (today for a new quotation).
  DateTime? _priceDate;
  final List<_Line> _lines = [];
  final _notes = TextEditingController();

  /// `installation` or `stock`; only editable while the quotation is a draft.
  String _purpose = 'installation';

  /// Delivery country (2 letters); empty = the customer's country, which the server fills in.
  final _country = TextEditingController();

  /// A specific power grid of the delivery country; null = any grid of that country.
  String? _gridId;
  PricingPreview? _preview;
  String? _previewError;
  Timer? _debounce;
  int _previewSeq = 0;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  TradocraftApi get _api => ref.read(apiProvider);
  bool get _editable => _id == null || _q?.status == QuotationStatus.draft;

  @override
  void initState() {
    super.initState();
    if (_id != null) {
      _load();
    } else if (widget.customerId != null) {
      _api.crm
          .getCustomer(id: widget.customerId!)
          .then(
            _selectCustomer,
            onError: (Object e) {
              if (mounted) setState(() => _error = errorMessage(e));
            },
          );
    }
  }

  /// Selects a customer and loads their open opportunities.
  Future<void> _selectCustomer(Customer c) async {
    setState(() => _customer = c);
    _refreshPreview();
    // Linking an opportunity is optional: without access to opportunities, quoting still works.
    final opportunities = await _api.crm
        .listOpportunities(customerId: c.id, open: true, limit: 100)
        .then((p) => p.items, onError: (Object _) => <Opportunity>[]);
    if (!mounted) return;
    setState(() {
      _opportunities = opportunities;
      if (!_opportunities.any((o) => o.id == _opportunityId)) {
        _opportunityId = null;
      }
    });
  }

  /// The same screen object is reused for another quotation when its `id` changes (a tab that
  /// navigates from one quotation to the next, a revision replacing its predecessor): start over
  /// with the new one instead of showing the old lines under the new id.
  @override
  void didUpdateWidget(QuotationScreen old) {
    super.didUpdateWidget(old);
    if (widget.id == old.id || widget.id == _id) return;
    _debounce?.cancel();
    _previewSeq++;
    setState(() {
      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      _id = widget.id;
      _q = null;
      _customer = null;
      _opportunities = [];
      _opportunityId = widget.opportunityId;
      _priceDate = null;
      _notes.clear();
      _country.clear();
      _gridId = null;
      _purpose = 'installation';
      _preview = null;
      _previewError = null;
      _error = null;
      _changed = false;
    });
    _setDirty(false);
    if (_id != null) _load();
  }

  bool _wasActive = true;

  /// Prices may have changed elsewhere (a price entered in another tab) while this tab was in
  /// the background: reprice the draft when the tab is shown again.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TabScope.activeOf(context);
    if (active && !_wasActive && _customer != null && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshPreview();
      });
    }
    _wasActive = active;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _notes.dispose();
    _country.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = await _api.sales.getQuotation(id: _id!);
      _apply(q);
      if (q.status == QuotationStatus.draft) {
        final customer = await _api.crm.getCustomer(id: q.customerId);
        final ids = q.lines.map((l) => l.productId).whereType<String>().toSet();
        final products = {
          for (final id in ids) id: await _api.products.getProduct(id: id),
        };
        _opportunityId = q.opportunityId;
        await _selectCustomer(customer);
        setState(() {
          for (final l in _lines) {
            l.dispose();
          }
          _lines
            ..clear()
            ..addAll(_linesFromQuotation(q.lines, products));
          _notes.text = q.notes;
          _priceDate = q.priceDate;
          _purpose = q.purpose;
          _country.text = q.deliveryCountryCode ?? '';
          _gridId = q.powerGridId;
        });
        _refreshPreview();
      }
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Removes a line and its sub-lines (an option cannot stay without its parent).
  void _removeLine(_Line l) {
    for (final c in _lines.where((c) => c.parent == l).toList()) {
      _removeLine(c);
    }
    _lines.remove(l);
    l.dispose();
  }

  /// Shows the loaded or saved quotation and clears the unsaved-edits mark.
  void _apply(Quotation q) {
    if (!mounted) return;
    TabScope.reportTitle(context, q.number);
    setState(() {
      _q = q;
      _id = q.id;
      _error = null;
    });
    // Loaded or saved: what is on screen is what the server has.
    _setDirty(false);
  }

  /// Unsaved edits: a tab asks before it closes while this is true.
  void _setDirty(bool dirty) {
    TabScope.reportDirty(context, dirty);
  }

  /// Builds the line inputs; returns null (and sets an error) if a field is invalid.
  List<QuotationLineInput>? _lineInputs() {
    final inputs = <QuotationLineInput>[];
    for (final (i, l) in _lines.indexed) {
      final qty = parseDecimalInput(l.quantity.text);
      final disc = parseDecimalInput(
        l.discount.text.isEmpty ? '0' : l.discount.text,
      );
      final price = l.hasConfirmablePrice && l.price.text.trim().isNotEmpty
          ? parseDecimalInput(l.price.text)
          : null;
      if (qty == null ||
          disc == null ||
          (l.hasConfirmablePrice &&
              l.price.text.trim().isNotEmpty &&
              price == null)) {
        _previewError = context.l10n.enterValidNumbersLine(i + 1);
        return null;
      }
      final parent = l.parent == null ? -1 : _lines.indexOf(l.parent!);
      inputs.add(
        QuotationLineInput(
          productId: l.product.id,
          quantity: qty,
          lineDiscountPercent: disc,
          description: l.description,
          unitPrice: price,
          productionRemark: l.productionRemark.text.trim(),
          customerRemark: l.customerRemark.text.trim(),
          section: l.section,
          comment: l.comment,
          parentPosition: parent < 0 ? null : parent + 1,
          percentOfParent: parent < 0 ? null : l.percentOfParent,
          percentBase: parent < 0 ? null : l.percentBase,
        ),
      );
    }
    return inputs;
  }

  /// The delivery country as typed: null when empty (the server defaults it) or incomplete.
  String? get _countryOrNull {
    final c = _country.text.trim().toUpperCase();
    return c.length == 2 ? c : null;
  }

  void _onEdited() {
    _setDirty(true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    final customer = _customer;
    _previewError = null;
    final inputs = _lineInputs();
    if (customer == null || inputs == null || inputs.isEmpty) {
      setState(() => _preview = null);
      return;
    }
    final seq = ++_previewSeq;
    try {
      final p = await _api.sales.preview(
        body: PricingPreviewInput(
          customerId: customer.id,
          quoteDate: _q?.quoteDate,
          priceDate: _priceDate,
          purpose: _purpose,
          deliveryCountryCode: _countryOrNull,
          powerGridId: _purpose == 'stock' ? null : _gridId,
          // The saved draft, so that its quoted shipping cost is part of the totals.
          quotationId: _editable ? _id : null,
          lines: inputs,
        ),
      );
      if (mounted && seq == _previewSeq) setState(() => _preview = p);
    } catch (e) {
      if (mounted && seq == _previewSeq) {
        setState(() {
          _preview = null;
          _previewError = errorMessage(e);
        });
      }
    }
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
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final inputs = _lineInputs();
    if (_customer == null || inputs == null || inputs.isEmpty) {
      throw context.l10n.chooseCustomerAndLine;
    }
    final country = _country.text.trim();
    if (country.isNotEmpty && country.length != 2) {
      throw context.l10n.deliveryCountryInvalid;
    }
    final body = QuotationInput(
      customerId: _customer!.id,
      opportunityId: _opportunityId,
      priceDate: _priceDate,
      purpose: _purpose,
      deliveryCountryCode: _countryOrNull,
      powerGridId: _purpose == 'stock' ? null : _gridId,
      // "Any grid" replacing a stored grid must be said explicitly: omitting keeps the stored one.
      clearPowerGrid:
          _purpose != 'stock' && _gridId == null && _q?.powerGridId != null
          ? true
          : null,
      notes: _notes.text,
      lines: inputs,
    );
    final q = _id == null
        ? await _api.sales.createQuotation(body: body)
        : await _api.sales.updateQuotation(id: _id!, body: body);
    _apply(q);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.savedNumber(q.number))),
      );
    }
  });

  Future<void> _transition(Future<Quotation> Function(String id) call) =>
      _run(() async => _apply(await call(_id!)));

  /// Sends the draft. While the shipping cost is still to be quoted the server answers 409; people
  /// who may override that (logistics) are offered "send anyway", others see the message.
  Future<void> _send(bool canOverride) => _run(() async {
    try {
      _apply(await _api.sales.sendQuotation(id: _id!));
    } on DioException catch (e) {
      if (e.response?.statusCode != 409 ||
          !canOverride ||
          _q?.shippingStatus != 'pending') {
        rethrow;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.sendAnyway),
          content: Text(context.l10n.sendAnywayHelp(errorMessage(e))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.sendAnyway),
            ),
          ],
        ),
      );
      if (ok != true) rethrow;
      _apply(await _api.sales.sendQuotation(id: _id!, overrideShipping: true));
    }
  });

  /// Turns this sent or accepted revision into a sales order and opens it.
  Future<void> _convert() async {
    final reference = await askText(
      context,
      title: context.l10n.convertToOrder,
      label: context.l10n.customerReference,
    );
    if (reference == null) return;
    await _run(() async {
      final order = await _api.sales.convert(
        id: _id!,
        body: ConvertInput(
          customerReference: reference.trim().isEmpty ? null : reference.trim(),
        ),
      );
      if (mounted) context.pushReplacement('/orders/${order.order.id}');
    });
  }

  /// Shows what today's prices would change, then lets the user keep or update the prices.
  Future<void> _revise() async {
    final pricing = await showDialog<RevisionPricing>(
      context: context,
      builder: (_) => RevisionDialog(quotation: _q!),
    );
    if (pricing == null) return;
    await _run(() async {
      final rev = await _api.sales.reviseQuotation(
        id: _id!,
        body: ReviseInput(pricing: pricing),
      );
      if (mounted) context.pushReplacement('/quotations/${rev.id}');
    });
  }

  Future<void> _pickPriceDate() async {
    final d = await showDatePicker(
      context: context,
      helpText: context.l10n.priceListValidOn,
      initialDate: _priceDate ?? _q?.quoteDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() => _priceDate = d);
    _setDirty(true);
    _refreshPreview();
  }

  Future<void> _pdf() => _run(() async {
    final q = _q!;
    final bytes = await downloadBytes(
      ref.read(dioProvider),
      '/api/v1/quotations/${q.id}/pdf',
    );
    await Printing.layoutPdf(
      name: '${q.number}-r${q.revision}.pdf',
      onLayout: (_) async => Uint8List.fromList(bytes),
    );
  });

  void _close() {
    if (context.canPop()) {
      context.pop(_changed);
    } else {
      context.go('/quotations');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('quotations.write') ??
        false;
    final theme = Theme.of(context);
    final q = _q;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      onPressed: _close,
                      icon: const Icon(AppIcons.arrowBack),
                    ),
                    Text(
                      q == null
                          ? context.l10n.newQuotation
                          : '${q.number}  rev. ${q.revision}',
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (q != null)
                      Chip(
                        label: Text(
                          context.l10n.quotationStatus(q.status.json ?? ''),
                        ),
                      ),
                    if (_busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ..._actions(canWrite),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                if (q != null) ..._shippingBanner(q),
                if (_editable && canWrite)
                  ..._editor(theme)
                else if (q != null)
                  ..._readOnly(q, theme),
              ],
            ),
    );
  }

  List<Widget> _actions(bool canWrite) {
    final q = _q;
    if (!canWrite) {
      return [
        if (q != null)
          OutlinedButton.icon(
            onPressed: _pdf,
            icon: const Icon(AppIcons.pictureAsPdf),
            label: const Text('PDF'),
          ),
      ];
    }
    final s = q?.status;
    return [
      if (_editable)
        TutorialTarget(id: 'quotation-save', child: FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(AppIcons.save),
          label: Text(context.l10n.saveDraft),
        )),
      if (q != null)
        TutorialTarget(id: 'quotation-pdf', child: OutlinedButton.icon(
          onPressed: _busy ? null : _pdf,
          icon: const Icon(AppIcons.pictureAsPdf),
          label: const Text('PDF'),
        )),
      if (s == QuotationStatus.draft)
        TutorialTarget(id: 'quotation-send', child: OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _send(canWrite && can(ref, 'shipping.manage')),
          icon: const Icon(AppIcons.send),
          label: Text(context.l10n.markAsSent),
        )),
      if (s == QuotationStatus.sent) ...[
        TutorialTarget(id: 'quotation-accept', child: OutlinedButton(
          onPressed: _busy
              ? null
              : () => _transition((id) => _api.sales.acceptQuotation(id: id)),
          child: Text(context.l10n.accepted),
        )),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _transition((id) => _api.sales.rejectQuotation(id: id)),
          child: Text(context.l10n.rejected),
        ),
      ],
      if (s == QuotationStatus.sent || s == QuotationStatus.accepted)
        TutorialTarget(id: 'quotation-convert', child: FilledButton.icon(
          onPressed: _busy ? null : _convert,
          icon: const Icon(AppIcons.shoppingCartCheckout),
          label: Text(context.l10n.convertToOrder),
        )),
      if (s == QuotationStatus.sent || s == QuotationStatus.rejected)
        TutorialTarget(id: 'quotation-revise', child: OutlinedButton.icon(
          onPressed: _busy ? null : _revise,
          icon: const Icon(AppIcons.editNote),
          label: Text(context.l10n.newRevision),
        )),
    ];
  }

  List<Widget> _editor(ThemeData theme) {
    final preview = _preview;
    final q = _q;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SearchPicker<Customer>(
              key: ValueKey(_customer?.id),
              label: context.l10n.customer,
              initial: _customer,
              display: (c) => '${c.code} · ${c.name}',
              search: (q) async =>
                  (await _api.crm.listCustomers(q: q, limit: 20)).items,
              onSelected: (c) {
                _setDirty(true);
                _selectCustomer(c);
              },
            ),
          ),
          const SizedBox(width: 16),
          if (_customer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${context.l10n.zoneAndRebate(_customer!.priceZoneCode ?? '—', number(_customer!.discountPercent ?? '0'))}\n'
                '${_customer!.street}, ${_customer!.postalCode} ${_customer!.city}',
              ),
            ),
        ],
      ),
      if (_customer != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: 520,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('opp-${_customer!.id}-${_opportunities.length}'),
            initialValue: _opportunityId,
            decoration: InputDecoration(
              labelText: context.l10n.opportunityOptional,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.l10n.none),
              ),
              for (final o in _opportunities)
                DropdownMenuItem<String?>(
                  value: o.id,
                  child: Text(
                    '${o.number} · ${o.title} (${context.l10n.opportunityStage(o.stage.json ?? '')})',
                  ),
                ),
            ],
            onChanged: (v) {
              _setDirty(true);
              setState(() => _opportunityId = v);
            },
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.l10n.purpose),
          SegmentedButton<String>(
            key: const ValueKey('purpose'),
            showSelectedIcon: false,
            segments: [
              for (final p in const ['installation', 'stock'])
                ButtonSegment(
                  value: p,
                  label: Text(context.l10n.purposeName(p)),
                ),
            ],
            selected: {_purpose},
            onSelectionChanged: (s) {
              setState(() => _purpose = s.first);
              _setDirty(true);
              _refreshPreview();
            },
          ),
          SizedBox(
            width: 200,
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
              decoration: InputDecoration(
                labelText: context.l10n.deliveryCountry,
                hintText: _customer == null
                    ? null
                    : context.l10n.deliveryCountryDefault(
                        _customer!.countryCode,
                      ),
              ),
              onChanged: (_) {
                // A grid belongs to one country.
                setState(() => _gridId = null);
                _onEdited();
              },
            ),
          ),
          _gridField(),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.priceListOf(
              date(
                preview?.priceDate ??
                    _priceDate ??
                    _q?.quoteDate ??
                    DateTime.now(),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _pickPriceDate,
            icon: const Icon(AppIcons.history),
            label: Text(context.l10n.useAnotherPriceListDate),
          ),
        ],
      ),
      if ((preview?.unconfirmedLines ?? 0) > 0)
        MaterialBanner(
          leading: const Icon(AppIcons.info),
          content: Text(
            context.l10n.indicativeToConfirm(preview!.unconfirmedLines),
          ),
          actions: const [SizedBox.shrink()],
        ),
      const SizedBox(height: 8),
      _linesTable(
        theme,
        rows: [
          for (final (i, l) in _lines.indexed)
            _TableRow(
              code: l.product.code,
              level: l.level,
              description: l.description ?? l.product.name,
              detail: l.sectionAndComment,
              quantity: _numField(l.quantity, l.product.unit),
              listPrice: l.hasConfirmablePrice
                  ? _numField(
                      l.price,
                      '€',
                      hint: number(
                        preview?.lines.elementAtOrNull(i)?.listUnitPrice,
                      ),
                      label: l.price.text.trim().isEmpty
                          ? context.l10n.confirm
                          : null,
                    )
                  : Text(
                      money(preview?.lines.elementAtOrNull(i)?.listUnitPrice),
                    ),
              rebate: _rebateText(preview?.lines.elementAtOrNull(i)),
              discount: l.isNet
                  ? Text(context.l10n.pricingNet)
                  : _numField(l.discount, '%', signed: true),
              netPrice: money(preview?.lines.elementAtOrNull(i)?.netUnitPrice),
              total: money(preview?.lines.elementAtOrNull(i)?.lineTotal),
              onRemove: () {
                setState(() => _removeLine(l));
                _setDirty(true);
                _refreshPreview();
              },
              onAddSub: l.isPercent ? null : () => _addSubItem(l),
              extra: _remarkFields(l),
            ),
          // Added by logistics (no product); the server keeps it, so it is never sent back. Once the
          // preview is there its lines (which carry the same shipping line) decide, like its totals.
          for (final l
              in (preview?.lines ?? q?.lines ?? const <QuotationLine>[]).where(
                (l) => l.productId == null,
              ))
            _lineRow(l, _q?.currency ?? 'EUR'),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 420,
          child: SearchPicker<Product>(
            label: context.l10n.addProduct,
            clearOnSelect: true,
            display: (p) => '${p.code} · ${p.name}',
            search: (q) async => (await _api.products.listProducts(
              q: q,
              active: true,
              limit: 20,
            )).items,
            onSelected: _addProduct,
          ),
        ),
      ),
      if (_previewError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _previewError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 8),
      _hints(
        preview?.warnings ?? q?.warnings ?? const [],
        preview?.suggestions ?? q?.suggestions ?? const [],
        editable: true,
      ),
      const SizedBox(height: 8),
      if (preview != null)
        _totals(
          theme,
          preview.subtotal,
          preview.vatGroups,
          preview.total,
          'EUR',
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _notes,
        maxLines: 3,
        onChanged: (_) => _setDirty(true),
        decoration: InputDecoration(labelText: context.l10n.notes),
      ),
    ];
  }

  /// The grid choice, only when the delivery country has several active grids.
  Widget _gridField() {
    if (_purpose == 'stock') return const SizedBox.shrink();
    return PowerGridField(
      country: _countryOrNull ?? _customer?.countryCode ?? '',
      selectedId: _gridId,
      onChanged: (v) {
        setState(() => _gridId = v);
        _setDirty(true);
        _refreshPreview();
      },
    );
  }

  /// Warnings and suggestions; none for stock, and suggestions already on the quotation are left
  /// out. In the editor each suggestion can be added as a line.
  Widget _hints(
    List<SalesWarning> warnings,
    List<SalesSuggestion> suggestions, {
    required bool editable,
  }) {
    if (_purpose == 'stock' && editable) return const SizedBox.shrink();
    final present = {for (final l in _lines) l.product.id};
    return SalesHints(
      warnings: warnings,
      suggestions: [
        for (final s in suggestions)
          if (!present.contains(s.productId)) s,
      ],
      onAdd: editable ? _addSuggestion : null,
    );
  }

  /// Appends a quantity-1 line for the product, then its options: the required ones are added as
  /// option lines right away and the optional ones are offered in a dialog. The preview prices them.
  Future<void> _addProduct(Product p) async {
    final line = _Line(p);
    setState(() => _lines.add(line));
    _setDirty(true);
    _refreshPreview();
    List<ProductOption> options;
    try {
      options = (await _api.products.listOptions(id: p.id))
          .where((o) => o.active && o.optionActive)
          .toList();
    } catch (_) {
      // Options are a convenience: a failed lookup never blocks adding the product.
      return;
    }
    if (options.isEmpty || !mounted || !_lines.contains(line)) return;
    final optional = options.where((o) => !o.requiredValue).toList();
    var chosen = options.where((o) => o.requiredValue).toList();
    if (optional.isNotEmpty) {
      final picked = await showOptionsChooser(
        context,
        product: p,
        options: options,
      );
      // Dismissing the dialog adds the product with its required options only.
      chosen = picked ?? chosen;
      if (!mounted || !_lines.contains(line)) return;
    }
    if (chosen.isEmpty) return;
    try {
      final products = [
        for (final o in chosen)
          await _api.products.getProduct(id: o.optionProductId),
      ];
      if (!mounted || !_lines.contains(line)) return;
      final parentQty = parseDecimalInput(line.quantity.text);
      setState(() {
        // After the parent and the options it already has.
        var at = _lines.indexOf(line) + 1;
        while (at < _lines.length && _lines[at].isDescendantOf(line)) {
          at++;
        }
        for (final (i, o) in chosen.indexed) {
          final qty =
              (Decimal.parse(parentQty ?? '1') *
                      Decimal.parse(o.defaultQuantity))
                  .toString();
          _lines.insert(at++, _Line(products[i], quantity: qty, parent: line));
        }
      });
      _refreshPreview();
    } catch (e) {
      if (mounted) setState(() => _previewError = errorMessage(e));
    }
  }

  /// Opens the sub-item chooser for [parent]: its valid options with tick boxes, and a search
  /// for any other products (several can be ticked). The picks become sub-items below the parent,
  /// after the ones it already has. The preview prices them like any other line.
  Future<void> _addSubItem(_Line parent) async {
    List<ProductOption> options;
    try {
      options = (await _api.products.listOptions(id: parent.product.id))
          .where((o) => o.active && o.optionActive)
          .toList();
    } catch (_) {
      // Options are a convenience: the search still works without them.
      options = const [];
    }
    if (!mounted || !_lines.contains(parent)) return;
    final picks = await showSubItemChooser(
      context,
      parent: parent.product,
      options: options,
      alreadyPresent: {
        for (final l in _lines)
          if (l.parent == parent) l.product.id,
      },
    );
    if (picks == null || picks.isEmpty || !mounted) return;
    try {
      final optionProducts = [
        for (final o in picks.options)
          await _api.products.getProduct(id: o.optionProductId),
      ];
      if (!mounted || !_lines.contains(parent)) return;
      final parentQty = Decimal.parse(
        parseDecimalInput(parent.quantity.text) ?? '1',
      );
      setState(() {
        var at = _lines.indexOf(parent) + 1;
        while (at < _lines.length && _lines[at].isDescendantOf(parent)) {
          at++;
        }
        for (final (i, o) in picks.options.indexed) {
          final qty = (parentQty * Decimal.parse(o.defaultQuantity)).toString();
          _lines.insert(
            at++,
            _Line(optionProducts[i], quantity: qty, parent: parent),
          );
        }
        for (final p in picks.products) {
          _lines.insert(at++, _Line(p, parent: parent));
        }
      });
      _setDirty(true);
      _refreshPreview();
    } catch (e) {
      if (mounted) setState(() => _previewError = errorMessage(e));
    }
  }

  /// Appends a quantity-1 line for a suggested product; the preview then prices it.
  Future<void> _addSuggestion(SalesSuggestion s) async {
    try {
      final p = await _api.products.getProduct(id: s.productId);
      if (!mounted || _lines.any((l) => l.product.id == p.id)) return;
      await _addProduct(p);
    } catch (e) {
      if (mounted) setState(() => _previewError = errorMessage(e));
    }
  }

  Widget _numField(
    TextEditingController c,
    String suffix, {
    String? hint,
    String? label,
    bool signed = false,
  }) => SizedBox(
    width: 104,
    child: TextField(
      controller: c,
      textAlign: TextAlign.right,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      decoration: InputDecoration(
        suffixText: suffix,
        hintText: hint,
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onChanged: (_) {
        _onEdited();
        if (label != null) setState(() {});
      },
    ),
  );

  /// "12 % family", "5 % general", "net".
  String _rebateText(QuotationLine? l) {
    if (l == null) return '';
    if (l.rebateSource == 'net') return 'net';
    return '${number(l.rebatePercent)} % ${context.l10n.rebateSource(l.rebateSource)}';
  }

  /// The two remark fields of an editable line, each with a button for the history of earlier
  /// remarks on this product.
  Widget _remarkFields(_Line l) {
    final l10n = context.l10n;
    Widget field(
      TextEditingController c,
      String kind,
      String label,
      String help,
    ) => Expanded(
      child: Tooltip(
        message: help,
        waitDuration: const Duration(milliseconds: 600),
        child: TextField(
          key: ValueKey('$kind-remark-${l.product.id}'),
          controller: c,
          minLines: 1,
          maxLines: null,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            suffixIcon: IconButton(
              key: ValueKey('$kind-remark-history-${l.product.id}'),
              tooltip: l10n.remarkHistory,
              icon: const Icon(AppIcons.history),
              onPressed: () => _pickRemark(l, kind, c),
            ),
          ),
          onChanged: (_) {
            _changed = true;
            _setDirty(true);
          },
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(left: 124 + 16.0 * l.level, top: 4, bottom: 4),
      child: SizedBox(
        width: 1000 - 16.0 * l.level,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field(
              l.customerRemark,
              'customer',
              l10n.remarkCustomer,
              l10n.remarkCustomerHelp,
            ),
            const SizedBox(width: 12),
            field(
              l.productionRemark,
              'production',
              l10n.remarkProduction,
              l10n.remarkProductionHelp,
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the history panel for a remark field and fills the field with the chosen text.
  Future<void> _pickRemark(
    _Line l,
    String kind,
    TextEditingController field,
  ) async {
    final customer = _customer;
    final text = await showRemarkHistory(
      context,
      title: context.l10n.remarkHistory,
      load: (scope) async {
        // The customer and language scopes need the customer of the quotation.
        if (scope != 'all' && customer == null) return const [];
        return _api.sales.remarkHistory(
          id: l.product.id,
          kind: kind,
          scope: scope,
          customerId: scope == 'customer' ? customer!.id : null,
          language: scope == 'language' ? customer!.language : null,
        );
      },
    );
    if (text == null || !mounted) return;
    setState(() => field.text = text);
    _changed = true;
    _setDirty(true);
  }

  /// The remarks of a stored line, under its description (read-only view).
  Widget? _remarkText(QuotationLine l) {
    final lines = [
      if (l.customerRemark?.isNotEmpty ?? false) l.customerRemark!,
      if (l.productionRemark?.isNotEmpty ?? false)
        '${context.l10n.remarkProduction}: ${l.productionRemark}',
    ];
    if (lines.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 100, bottom: 4),
      child: SizedBox(
        width: 740,
        child: Text(
          lines.join('\n'),
          key: ValueKey('remarks-${l.position}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  /// Depth of a stored line below its parents.
  int _levelIn(List<QuotationLine> all, QuotationLine l) {
    var level = 0;
    var parent = l.parentPosition;
    while (parent != null && level <= all.length) {
      level++;
      parent = all
          .where((o) => o.position == parent)
          .firstOrNull
          ?.parentPosition;
    }
    return level;
  }

  _TableRow _lineRow(QuotationLine l, String currency, {int level = 0}) =>
      _TableRow(
        level: level,
        code: l.productCode,
        description: l.description,
        extra: _remarkText(l),
        quantity: Text('${number(l.quantity)} ${l.unit}'),
        listPrice: Text(money(l.listUnitPrice, currency: currency)),
        rebate: _rebateText(l),
        discount: Text(
          l.pricingType == 'net'
              ? context.l10n.pricingNet
              : '${number(l.lineDiscountPercent)} %',
        ),
        netPrice: money(l.netUnitPrice, currency: currency),
        total: money(l.lineTotal, currency: currency),
      );

  /// Tells the salesperson that logistics still has to price the shipment (or has done so).
  List<Widget> _shippingBanner(Quotation q) {
    final pending = q.shippingStatus == 'pending';
    final quoted =
        q.shippingStatus == 'quoted' && q.status == QuotationStatus.draft;
    if (!pending && !quoted) return const [];
    return [
      MaterialBanner(
        key: const ValueKey('shipping-banner'),
        leading: const Icon(AppIcons.localShipping),
        content: Text(
          pending
              ? context.l10n.shippingPendingBanner
              : context.l10n.shippingQuotedBanner,
        ),
        actions: const [SizedBox.shrink()],
      ),
    ];
  }

  List<Widget> _readOnly(Quotation q, ThemeData theme) => [
    Text(q.customerName, style: theme.textTheme.titleMedium),
    Text(
      '${q.customerStreet}, ${q.customerPostalCode} ${q.customerCity} ${q.customerCountryCode}',
    ),
    Text(
      '${context.l10n.zoneAndRebate(q.priceZoneCode, number(q.customerDiscountPercent))} · '
      '${date(q.quoteDate)} – ${context.l10n.validUntil(date(q.validUntil))}',
    ),
    Wrap(
      children: [
        InfoItem(context.l10n.purpose, context.l10n.purposeName(q.purpose)),
        InfoItem(context.l10n.deliveryCountry, q.deliveryCountryCode ?? ''),
      ],
    ),
    if (q.priceDate != q.quoteDate)
      Text(
        context.l10n.pricedOnPriceListOf(date(q.priceDate)),
        style: TextStyle(color: theme.colorScheme.tertiary),
      ),
    if (q.opportunityId != null)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(AppIcons.trendingUp),
          label: Text(context.l10n.openOpportunity),
          onPressed: () => context.push('/opportunities/${q.opportunityId}'),
        ),
      ),
    // Only filled on the create and update responses; a plain GET has none.
    _hints(q.warnings, q.suggestions, editable: false),
    const SizedBox(height: 16),
    _linesTable(
      theme,
      rows: [
        for (final l in q.lines)
          _lineRow(l, q.currency, level: _levelIn(q.lines, l)),
      ],
    ),
    const SizedBox(height: 16),
    _totals(theme, q.subtotal, q.vatGroups, q.total, q.currency),
    if (q.notes.isNotEmpty) ...[
      const SizedBox(height: 16),
      Text(context.l10n.notes, style: theme.textTheme.labelLarge),
      Text(q.notes),
    ],
  ];

  Widget _linesTable(ThemeData theme, {required List<_TableRow> rows}) {
    const widths = [
      124.0,
      240.0,
      120.0,
      120.0,
      120.0,
      110.0,
      110.0,
      120.0,
      96.0,
    ];
    Widget cell(int i, Widget child, {bool right = false}) => SizedBox(
      width: widths[i],
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
    Text h(String s) => Text(s, style: theme.textTheme.labelLarge);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(0, h(context.l10n.code)),
              cell(1, h(context.l10n.description)),
              cell(2, h(context.l10n.quantity), right: true),
              cell(3, h(context.l10n.listPrice), right: true),
              cell(4, h(context.l10n.rebate), right: true),
              cell(5, h(context.l10n.lineDiscount), right: true),
              cell(6, h(context.l10n.netPrice), right: true),
              cell(7, h(context.l10n.total), right: true),
            ],
          ),
          const Divider(),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      cell(
                        0,
                        Padding(
                          padding: EdgeInsets.only(left: 16.0 * r.level),
                          child: Text(r.code, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      cell(
                        1,
                        Padding(
                          padding: EdgeInsets.zero,
                          child: Row(
                            children: [
                              if (r.level > 0)
                                Tooltip(
                                  message: context.l10n.optionLine,
                                  child: const Icon(
                                    AppIcons.subdirectoryArrowRight,
                                    size: 16,
                                  ),
                                ),
                              Flexible(
                                child: r.detail == null
                                    ? Text(
                                        r.description,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            r.description,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            r.detail!,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      cell(2, r.quantity, right: true),
                      cell(3, r.listPrice, right: true),
                      cell(4, Text(r.rebate), right: true),
                      cell(5, r.discount, right: true),
                      cell(6, Text(r.netPrice), right: true),
                      cell(7, Text(r.total), right: true),
                      if (r.onRemove != null)
                        SizedBox(
                          width: widths[8],
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r.onAddSub != null)
                                IconButton(
                                  tooltip: context.l10n.addSubItem,
                                  onPressed: r.onAddSub,
                                  icon: const Icon(AppIcons.add),
                                ),
                              IconButton(
                                tooltip: context.l10n.removeLine,
                                onPressed: r.onRemove,
                                icon: const Icon(AppIcons.close),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (r.extra != null) r.extra!,
                ],
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.all(8),
              child: Text(context.l10n.noLines),
            ),
        ],
      ),
    );
  }

  Widget _totals(
    ThemeData theme,
    String subtotal,
    List<VatGroup> vat,
    String total,
    String currency,
  ) => Align(
    alignment: Alignment.centerRight,
    child: SizedBox(
      width: 340,
      child: Column(
        children: [
          _totalRow(
            context.l10n.totalExclVat,
            money(subtotal, currency: currency),
          ),
          for (final g in vat)
            _totalRow(
              context.l10n.vatOn(
                number(g.vatRate),
                money(g.baseValue, currency: currency),
              ),
              money(g.vat, currency: currency),
            ),
          const Divider(),
          _totalRow(
            context.l10n.totalInclVat,
            money(total, currency: currency),
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );

  Widget _totalRow(String label, String value, {TextStyle? style}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    ),
  );
}

class _TableRow {
  _TableRow({
    required this.code,
    required this.description,
    required this.quantity,
    required this.listPrice,
    required this.rebate,
    required this.discount,
    required this.netPrice,
    required this.total,
    this.onRemove,
    this.onAddSub,
    this.detail,
    this.extra,
    this.level = 0,
  });

  final String code;
  final String description;

  /// A second, smaller line under the description (section and comment).
  final String? detail;

  /// Shown under the row (remarks).
  final Widget? extra;

  /// Depth below a parent line (an option line is indented in the read-only view).
  final int level;
  final Widget quantity;
  final Widget listPrice;
  final String rebate;
  final Widget discount;
  final String netPrice;
  final String total;
  final VoidCallback? onRemove;

  /// Attaches a product below this line as a sub-item (null: not offered, e.g. percent lines).
  final VoidCallback? onAddSub;
}

/// Compares a quotation with today's prices and asks whether to keep or update them.
class RevisionDialog extends ConsumerWidget {
  const RevisionDialog({super.key, required this.quotation});
  final Quotation quotation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.l10n.newRevisionOf(quotation.number)),
      content: SizedBox(
        width: 760,
        child: FutureBuilder<RepricingComparison>(
          future: ref.read(apiProvider).sales.repricing(id: quotation.id),
          builder: (context, snap) {
            // The shipping disclosure comes from the quotation itself while the comparison is
            // loading or failed, so it is always in front of the user before they choose.
            if (snap.hasError) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${context.l10n.repricingFailed(errorMessage(snap.error!))}\n${context.l10n.canStillKeep}',
                    ),
                    ..._shippingNotes(context, null),
                  ],
                ),
              );
            }
            final c = snap.data;
            if (c == null) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    ..._shippingNotes(context, null),
                  ],
                ),
              );
            }
            Text h(String s) => Text(s, style: theme.textTheme.labelLarge);
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.revisionPriceLists(
                      date(c.oldPriceDate),
                      date(c.newPriceDate),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Table(
                    columnWidths: const {1: FlexColumnWidth()},
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(
                        children: [
                          for (final t in [
                            context.l10n.code,
                            context.l10n.description,
                            context.l10n.agreed,
                            context.l10n.current,
                            context.l10n.difference,
                          ])
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: h(t),
                            ),
                        ],
                      ),
                      for (final l in c.lines)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(l.productCode),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                l.needsConfirmation
                                    ? context.l10n.indicativeLine(l.description)
                                    : l.description,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                money(l.oldLineTotal),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                money(l.newLineTotal),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                money(l.difference),
                                textAlign: TextAlign.right,
                                style: _diffStyle(theme, l.difference),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const Divider(),
                  Text(
                    context.l10n.productsTotalChange(
                      money(c.oldSubtotal),
                      money(c.newSubtotal),
                      money(c.difference),
                    ),
                    style: theme.textTheme.titleSmall?.merge(
                      _diffStyle(theme, c.difference),
                    ),
                  ),
                  ..._shippingNotes(context, c),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TutorialTarget(id: 'quotation-revise-keep', child: OutlinedButton(
          onPressed: () => Navigator.pop(context, RevisionPricing.keep),
          child: Text(context.l10n.keepAgreedPrices),
        )),
        FilledButton(
          onPressed: () => Navigator.pop(context, RevisionPricing.current),
          child: Text(context.l10n.updateToCurrentPrices),
        ),
      ],
    );
  }

  /// The quotation's own shipping line (added by logistics, no product), if it has one.
  QuotationLine? get _shippingLine =>
      quotation.lines.where((l) => l.productId == null).firstOrNull;

  /// What happens to the shipping charge: reset with 'current' prices (new logistics quote
  /// needed), carried over with 'keep'. [c] is null while the comparison is unavailable; a
  /// comparison from an older server has no shipping fields, so the quotation decides.
  List<Widget> _shippingNotes(BuildContext context, RepricingComparison? c) {
    final line = _shippingLine;
    final requote = c?.shippingRequoteNeeded ?? (line != null);
    final charge = c?.oldShippingTotal ?? line?.lineTotal;
    final theme = Theme.of(context);
    final hasCharge = charge != null && (double.tryParse(charge) ?? 0) != 0;
    return [
      if (requote)
        Padding(
          key: const ValueKey('revision-shipping-reset'),
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AppIcons.localShipping,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasCharge)
                        Text(
                          context.l10n.revisionShippingExisting(
                            money(charge, currency: quotation.currency),
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      Text(
                        context.l10n.revisionShippingReset,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (line != null)
        Padding(
          key: const ValueKey('revision-shipping-kept'),
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            context.l10n.revisionShippingKept(
              money(line.lineTotal, currency: quotation.currency),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  static TextStyle? _diffStyle(ThemeData theme, String value) {
    final v = double.tryParse(value) ?? 0;
    if (v == 0) return null;
    return TextStyle(
      color: v > 0 ? theme.colorScheme.error : Colors.green.shade700,
    );
  }
}
