import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../products/families_dialog.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// A customer's product- and family-specific rebates. The general rebate is in the customer form.
/// For a product the most specific valid rebate wins: product, then family, then general.
class RebatesDialog extends ConsumerStatefulWidget {
  const RebatesDialog({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<RebatesDialog> createState() => _RebatesDialogState();
}

class _RebatesDialogState extends ConsumerState<RebatesDialog> {
  List<CustomerRebate>? _rebates;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref
        .read(apiProvider)
        .crm
        .listRebates(id: widget.customer.id);
    if (mounted) setState(() => _rebates = list);
  }

  String _period(CustomerRebate r) {
    if (r.validFrom == null && r.validTo == null) return context.l10n.always;
    return '${r.validFrom == null ? '…' : date(r.validFrom)} – ${r.validTo == null ? '…' : date(r.validTo)}';
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('rebates.write') ??
        false;
    final c = widget.customer;
    final list = _rebates;
    return AlertDialog(
      title: Text(context.l10n.rebatesOf(c.name)),
      content: SizedBox(
        width: 620,
        child: list == null
            ? const LinearProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'General rebate on all products: ${number(c.discountPercent ?? '0')} % '
                    '(net-priced products are never discounted).',
                  ),
                  const SizedBox(height: 8),
                  if (list.isEmpty) Text(context.l10n.noRebates),
                  for (final r in list)
                    ListTile(
                      leading: Icon(
                        r.scope == 'product'
                            ? AppIcons.inventory2
                            : AppIcons.category,
                      ),
                      title: Text(
                        '${r.scope == 'product' ? r.productCode : 'Family ${r.familyCode}'}: ${number(r.percent)} %',
                      ),
                      subtitle: Text(
                        [
                          _period(r),
                          if (r.notes.isNotEmpty) r.notes,
                        ].join(' · '),
                      ),
                      trailing: canWrite
                          ? IconButton(
                              tooltip: context.l10n.remove,
                              icon: const Icon(AppIcons.delete),
                              onPressed: () async {
                                await runAction(
                                  context,
                                  () => ref
                                      .read(apiProvider)
                                      .crm
                                      .deleteRebate(id: c.id, rebateId: r.id),
                                );
                                _load();
                              },
                            )
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            icon: const Icon(AppIcons.add),
            label: Text(context.l10n.addRebate),
            onPressed: () async {
              final added = await showDialog<bool>(
                context: context,
                builder: (_) => _NewRebate(customer: c),
              );
              if (added == true) _load();
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

class _NewRebate extends ConsumerStatefulWidget {
  const _NewRebate({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_NewRebate> createState() => _NewRebateState();
}

class _NewRebateState extends ConsumerState<_NewRebate> {
  String _scope = 'family';
  String? _familyId;
  Product? _product;
  final _percent = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  String? _error;

  Future<void> _save() async {
    final percent = parseDecimalInput(_percent.text);
    if (percent == null ||
        (_scope == 'family' ? _familyId == null : _product == null)) {
      setState(
        () => _error =
            'Choose a ${_scope == 'family' ? 'family' : 'product'} and enter a percentage.',
      );
      return;
    }
    try {
      await ref
          .read(apiProvider)
          .crm
          .createRebate(
            id: widget.customer.id,
            body: RebateInput(
              scope: _scope,
              familyId: _scope == 'family' ? _familyId : null,
              productId: _scope == 'product' ? _product!.id : null,
              percent: percent,
              validFrom: _from,
              validTo: _to,
              notes: _notes.text,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    final families =
        ref.watch(familiesProvider).value ?? const <ProductFamily>[];
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(context.l10n.addRebate),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'family',
                  label: Text(context.l10n.productFamily),
                ),
                ButtonSegment(
                  value: 'product',
                  label: Text(context.l10n.singleProduct),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            gap,
            if (_scope == 'family')
              DropdownButtonFormField<String>(
                initialValue: _familyId,
                decoration: InputDecoration(labelText: context.l10n.family),
                items: [
                  for (final f in families)
                    DropdownMenuItem(
                      value: f.id,
                      child: Text('${f.code} · ${f.name}'),
                    ),
                ],
                onChanged: (v) => setState(() => _familyId = v),
              )
            else
              SearchPicker<Product>(
                label: context.l10n.product,
                display: (p) => '${p.code} · ${p.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .products
                            .listProducts(q: q, limit: 20))
                        .items
                        .where((p) => p.pricingType != 'net')
                        .toList(),
                onSelected: (p) => setState(() => _product = p),
              ),
            gap,
            TextField(
              controller: _percent,
              decoration: InputDecoration(
                labelText: context.l10n.rebatePercent,
              ),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_from);
                      setState(() => _from = d);
                    },
                    child: Text(
                      _from == null
                          ? '${context.l10n.from}: ${context.l10n.always}'
                          : '${context.l10n.from} ${date(_from)}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_to);
                      setState(() => _to = d);
                    },
                    child: Text(
                      _to == null
                          ? '${context.l10n.until}: ${context.l10n.openEnded}'
                          : '${context.l10n.until} ${date(_to)}',
                    ),
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: _notes,
              decoration: InputDecoration(labelText: context.l10n.notes),
            ),
            if (_error != null) ...[
              gap,
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(context.l10n.save)),
      ],
    );
  }
}
