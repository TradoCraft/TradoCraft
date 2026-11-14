import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/search_picker.dart';
import '../../l10n/l10n.dart';
import 'families_dialog.dart';
import '../../shared/app_icons.dart';

const relationKinds = ['compatible', 'incompatible', 'suggested'];

/// Short text for one side of a rule: the product code or the family.
String relationSide(
  BuildContext context, {
  String? productCode,
  String? familyCode,
}) => productCode ?? context.l10n.relationFamilyValue(familyCode ?? '?');

String relationTitle(BuildContext context, ProductRelation r) =>
    '${relationSide(context, productCode: r.aProductCode, familyCode: r.aFamilyCode)}'
    ' ${r.bidirectional ? '↔' : '→'} '
    '${relationSide(context, productCode: r.bProductCode, familyCode: r.bFamilyCode)}';

final _relationsProvider = FutureProvider.autoDispose
    .family<List<ProductRelation>, String>(
      (ref, kind) => ref
          .watch(apiProvider)
          .products
          .listProductRelations(kind: kind.isEmpty ? null : kind),
    );

/// Opens the rule editor; true when a rule was saved. [rule] edits, [product] pre-fills side A of
/// a new rule.
Future<bool> showRelationEditor(
  BuildContext context, {
  ProductRelation? rule,
  Product? product,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _RelationEditor(rule: rule, product: product),
    ) ??
    false;

/// Lists the product relation rules and lets product managers add and edit them.
class RelationsDialog extends ConsumerStatefulWidget {
  const RelationsDialog({super.key});

  @override
  ConsumerState<RelationsDialog> createState() => _RelationsDialogState();
}

class _RelationsDialogState extends ConsumerState<RelationsDialog> {
  String _kind = '';

  Future<void> _edit([ProductRelation? r]) async {
    if (await showRelationEditor(context, rule: r)) {
      ref.invalidate(_relationsProvider(_kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rules = ref.watch(_relationsProvider(_kind));
    final canWrite = can(ref, 'products.write');
    return AlertDialog(
      title: Text(l.relationsTitle),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('relation-filter'),
                initialValue: _kind,
                decoration: InputDecoration(labelText: l.relationKindLabel),
                items: [
                  DropdownMenuItem(value: '', child: Text(l.all)),
                  for (final k in relationKinds)
                    DropdownMenuItem(value: k, child: Text(l.relationKind(k))),
                ],
                onChanged: (v) => setState(() => _kind = v ?? ''),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: rules.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(errorMessage(e)),
                data: (list) => list.isEmpty
                    ? Text(l.relationsEmpty)
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final r = list[i];
                          return ListTile(
                            key: ValueKey('rule-${r.id}'),
                            title: Text(relationTitle(context, r)),
                            subtitle: Text(
                              [
                                l.relationKind(r.kind),
                                if (r.kind == 'suggested')
                                  l.suggestionStrength(r.strength),
                                if (!r.active) l.inactive,
                                if (r.note.isNotEmpty) r.note,
                              ].join(' · '),
                            ),
                            trailing: canWrite
                                ? IconButton(
                                    tooltip: context.l10n.edit,
                                    icon: const Icon(AppIcons.edit),
                                    onPressed: () => _edit(r),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(AppIcons.add),
            label: Text(l.newRelation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}

/// A product chosen in a search picker (only what the editor needs).
class _Pick {
  const _Pick(this.id, this.label);
  final String id;
  final String label;
}

/// One side of a rule: either a product or a family.
class _Side {
  _Side({this.productId, this.productLabel, this.familyId})
    : type = familyId != null && productId == null ? 'family' : 'product';
  String? productId;
  String? productLabel;
  String? familyId;

  /// `product` or `family`: what the side is picked from.
  String type;
}

class _RelationEditor extends ConsumerStatefulWidget {
  const _RelationEditor({this.rule, this.product});
  final ProductRelation? rule;
  final Product? product;

  @override
  ConsumerState<_RelationEditor> createState() => _RelationEditorState();
}

class _RelationEditorState extends ConsumerState<_RelationEditor> {
  late String _kind = widget.rule?.kind ?? 'suggested';
  late bool _bidirectional = widget.rule?.bidirectional ?? true;
  late bool _active = widget.rule?.active ?? true;
  late final _strength = TextEditingController(
    text: '${widget.rule?.strength ?? 50}',
  );
  late final _note = TextEditingController(text: widget.rule?.note ?? '');
  late final _a = _initial(
    widget.rule?.aProductId,
    widget.rule?.aProductCode,
    widget.rule?.aFamilyId,
    widget.product,
  );
  late final _b = _initial(
    widget.rule?.bProductId,
    widget.rule?.bProductCode,
    widget.rule?.bFamilyId,
    null,
  );
  String? _error;
  bool _saving = false;

  _Side _initial(String? pid, String? code, String? fid, Product? prefill) {
    if (prefill != null && widget.rule == null) {
      return _Side(productId: prefill.id, productLabel: prefill.code);
    }
    return _Side(productId: pid, productLabel: code, familyId: fid);
  }

  @override
  void dispose() {
    _strength.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if ((_a.productId == null && _a.familyId == null) ||
        (_b.productId == null && _b.familyId == null)) {
      setState(() => _error = l.relationNeedSides);
      return;
    }
    int? strength;
    if (_kind == 'suggested') {
      strength = int.tryParse(_strength.text.trim());
      if (strength == null || strength < 1 || strength > 100) {
        setState(() => _error = l.relationStrengthInvalid);
        return;
      }
    }
    final body = ProductRelationInput(
      kind: _kind,
      aProductId: _a.productId,
      aFamilyId: _a.productId == null ? _a.familyId : null,
      bProductId: _b.productId,
      bFamilyId: _b.productId == null ? _b.familyId : null,
      bidirectional: _bidirectional,
      strength: strength,
      note: _note.text.trim(),
      active: _active,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ref.read(apiProvider).products;
    try {
      if (widget.rule == null) {
        await api.createProductRelation(body: body);
      } else {
        await api.updateProductRelation(id: widget.rule!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 409 (the rule or its mirror exists) and 422 (e.g. a product related to itself) carry a message.
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _saving = false;
        });
      }
    }
  }

  Widget _side(String label, String prefix, _Side side) {
    final l = context.l10n;
    final families = ref.watch(familiesProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          key: ValueKey('$prefix-type'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'product', label: Text(l.product)),
            ButtonSegment(value: 'family', label: Text(l.family)),
          ],
          selected: {side.type},
          onSelectionChanged: (s) => setState(() {
            if (s.first == 'family') {
              side.productId = null;
              side.productLabel = null;
            } else {
              side.familyId = null;
            }
            side.type = s.first;
          }),
        ),
        const SizedBox(height: 8),
        if (side.type == 'family')
          DropdownButtonFormField<String>(
            key: ValueKey('$prefix-family'),
            initialValue: families.any((f) => f.id == side.familyId)
                ? side.familyId
                : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.family),
            items: [
              for (final f in families)
                DropdownMenuItem(
                  value: f.id,
                  child: Text('${f.code} · ${f.name}'),
                ),
            ],
            onChanged: (v) => setState(() => side.familyId = v),
          )
        else
          SearchPicker<_Pick>(
            key: ValueKey('$prefix-product'),
            label: l.product,
            initial: side.productId == null
                ? null
                : _Pick(side.productId!, side.productLabel ?? ''),
            display: (p) => p.label,
            search: (q) async =>
                (await ref
                        .read(apiProvider)
                        .products
                        .listProducts(q: q, limit: 20))
                    .items
                    .map((p) => _Pick(p.id, '${p.code} · ${p.name}'))
                    .toList(),
            onSelected: (p) {
              side.productId = p.id;
              side.productLabel = p.label;
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.rule == null ? l.newRelation : l.relationEdit),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('relation-kind'),
                initialValue: _kind,
                decoration: InputDecoration(labelText: l.relationKindLabel),
                items: [
                  for (final k in relationKinds)
                    DropdownMenuItem(value: k, child: Text(l.relationKind(k))),
                ],
                onChanged: (v) => setState(() => _kind = v!),
              ),
              const SizedBox(height: 16),
              _side(l.relationSideA, 'a', _a),
              const SizedBox(height: 16),
              _side(l.relationSideB, 'b', _b),
              SwitchListTile(
                key: const ValueKey('relation-bidirectional'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.relationBidirectional),
                value: _bidirectional,
                onChanged: (v) => setState(() => _bidirectional = v),
              ),
              if (_kind == 'suggested')
                TextField(
                  key: const ValueKey('relation-strength'),
                  controller: _strength,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l.relationStrength,
                    helperText: l.relationStrengthHelp,
                  ),
                ),
              TextField(
                key: const ValueKey('relation-note'),
                controller: _note,
                decoration: InputDecoration(labelText: l.notes),
              ),
              SwitchListTile(
                key: const ValueKey('relation-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
