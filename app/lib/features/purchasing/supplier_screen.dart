import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../framework/form/record_form_controller.dart';
import '../../framework/form/record_form_view.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/record_history.dart';
import '../tutorial/controller.dart';
import '../tutorial/targets.dart';
import 'supplier_form.dart';
import 'supplier_price_dialog.dart';

/// A supplier in a workspace tab: its details (editable with the write right) and its price list.
class SupplierScreen extends ConsumerStatefulWidget {
  /// Shows the supplier with [id].
  const SupplierScreen({super.key, required this.id});

  /// The supplier to show.
  final String id;

  @override
  ConsumerState<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends ConsumerState<SupplierScreen> {
  final _form = RecordFormController<Supplier>(versionOf: (_) => null);
  bool _formBusy = false;
  List<SupplierProduct> _prices = const [];
  int _priceGeneration = 0;
  SupplierDraft? _draft;
  bool _loading = true;

  PurchasingClient get _api => ref.read(apiProvider).purchasing;

  @override
  void initState() {
    super.initState();
    _form.addListener(_onFormChanged);
    _load();
  }

  void _onFormChanged() {
    if (_formBusy == _form.busy) return;
    _formBusy = _form.busy;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.removeListener(_onFormChanged);
    _form.dispose();
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_priceGeneration;
    setState(() => _loading = true);
    final s = await _form.reload(() => _api.getSupplier(id: widget.id));
    if (!mounted) return;
    if (s != null) {
      TabScope.reportTitle(context, s.name);
      if (generation == _priceGeneration) {
        try {
          final prices = await _api.listSupplierProducts(id: widget.id);
          if (mounted && generation == _priceGeneration) {
            setState(() => _prices = prices);
          }
        } catch (e) {
          if (mounted && generation == _priceGeneration) {
            _form.error = errorMessage(e);
          }
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadPrices() async {
    final generation = ++_priceGeneration;
    try {
      final prices = await _api.listSupplierProducts(id: widget.id);
      if (mounted && generation == _priceGeneration) {
        setState(() => _prices = prices);
      }
    } catch (e) {
      if (mounted && generation == _priceGeneration) {
        _form.error = errorMessage(e);
      }
    }
  }

  void _edit() {
    final draft = SupplierDraft(_form.record);
    draft.addListener(_form.markDirty);
    setState(() => _draft = draft);
  }

  void _stopEditing() {
    final record = _form.record;
    if (record != null) _form.apply(record);
    final d = _draft;
    setState(() => _draft = null);
    // The fields are still on screen for this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => d?.dispose());
  }

  Future<void> _save() async {
    final draft = _draft!;
    final problem = draft.validate(context);
    if (problem != null) {
      _form.error = problem;
      return;
    }
    final saved = await _form.save(
      (_) => _api.updateSupplier(id: widget.id, body: draft.toUpdate()),
    );
    if (saved == null || !mounted) return;
    TabScope.reportTitle(context, saved.name);
    _stopEditing();
  }

  Future<void> _addOrEdit([SupplierProduct? existing]) async {
    final saved = await showSupplierPriceDialog(
      context,
      supplier: _form.record!,
      existing: existing,
    );
    if (saved == true) await _reloadPrices();
  }

  Future<void> _remove(SupplierProduct p) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.purchRemoveProductConfirm(p.productCode)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('price-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAction(
      context,
      () => _api.deleteSupplierProduct(id: widget.id, productId: p.productId),
    );
    if (done) await _reloadPrices();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tutorialAssistCompletedProvider, (_, completed) {
      if (completed?.missionId != 'suppliers') return;
      final supplier = switch (completed?.stepId) {
        'priceMotor' || 'priceFrame' || 'priceController' => 'supplierAId',
        'priceMotorB' => 'supplierBId',
        _ => null,
      };
      if (supplier != null &&
          ref.read(tutorialProvider).values[supplier] == widget.id) {
        _reloadPrices();
      }
    });
    final l = context.l10n;
    final s = _form.record;
    if (s == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_form.error ?? ''),
            TextButton(onPressed: _load, child: Text(l.retry)),
          ],
        ),
      );
    }
    final canWrite = can(ref, 'purchasing.write');
    final editing = _draft != null;
    final busy = _form.busy || _loading;
    return RecordFormView<Supplier>(
      controller: _form,
      title: s.name,
      onReload: _load,
      titleExtras: [
        Text(s.code),
        if (!s.active) Chip(label: Text(l.purchInactive)),
      ],
      actions: [
        RecordHistoryButton(entity: 'supplier', id: s.id, title: s.name),
        if (canWrite && !editing)
          OutlinedButton.icon(
            key: const ValueKey('supplier-edit'),
            onPressed: busy ? null : _edit,
            icon: const Icon(AppIcons.edit),
            label: Text(l.edit),
          ),
        if (editing) ...[
          FilledButton(
            key: const ValueKey('supplier-save'),
            onPressed: busy ? null : _save,
            child: Text(l.save),
          ),
          TextButton(
            key: const ValueKey('supplier-cancel'),
            onPressed: busy ? null : _stopEditing,
            child: Text(l.cancel),
          ),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (editing)
            SupplierFields(
              draft: _draft!,
              supplierId: widget.id,
              showActive: true,
              enabled: !busy,
              onActiveChanged: (v) {
                setState(() => _draft!.active = v);
                _form.markDirty();
              },
            )
          else
            _Facts(supplier: s),
          const Divider(height: 32),
          Row(
            children: [
              Text(
                l.purchPriceList,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              if (canWrite)
                TutorialTarget(
                  id: 'supplier-price-add',
                  child: FilledButton.icon(
                    key: const ValueKey('price-add'),
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(AppIcons.add),
                    label: Text(l.purchAddProduct),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_prices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(l.purchNoPrices),
            )
          else
            for (final p in _prices)
              _PriceTile(
                price: p,
                onEdit: canWrite ? () => _addOrEdit(p) : null,
                onRemove: canWrite ? () => _remove(p) : null,
              ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = supplier;
    return Wrap(
      children: [
        InfoItem(l.country, s.country),
        InfoItem(l.currency, s.currency),
        InfoItem(l.purchPaymentTerms, l.purchDays(s.paymentTermsDays)),
        InfoItem(l.vatNumber, s.taxId),
        InfoItem(l.contactPerson, s.contactPerson),
        InfoItem(l.email, s.email),
        InfoItem(l.phone, s.phone),
        InfoItem(l.notes, s.notes),
      ],
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.price, this.onEdit, this.onRemove});
  final SupplierProduct price;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = price;
    final article = [
      if (p.supplierProductCode.isNotEmpty) p.supplierProductCode,
      if (p.supplierProductName.isNotEmpty) p.supplierProductName,
    ].join(' · ');
    return ListTile(
      key: ValueKey('price-${p.productId}'),
      title: Text('${p.productCode} · ${p.productName}'),
      subtitle: Text(
        [
          if (article.isNotEmpty) article,
          l.purchMoqValue(number(p.moq)),
          l.purchLeadValue(p.leadTimeDays),
          if (p.isPreferred) l.purchPreferred,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${number(p.unitPrice)} ${p.currency}'),
          if (onEdit != null)
            IconButton(
              key: ValueKey('price-edit-${p.productId}'),
              tooltip: l.edit,
              onPressed: onEdit,
              icon: const Icon(AppIcons.edit),
            ),
          if (onRemove != null)
            IconButton(
              key: ValueKey('price-remove-${p.productId}'),
              tooltip: l.remove,
              onPressed: onRemove,
              icon: const Icon(AppIcons.delete),
            ),
        ],
      ),
    );
  }
}
