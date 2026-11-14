import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';

/// The options of a product: products offered with it on a quotation. A required option is added
/// to the quotation automatically. Editable with `products.write`; saving replaces the whole set.
class OptionsTab extends ConsumerStatefulWidget {
  const OptionsTab({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<OptionsTab> createState() => _OptionsTabState();
}

/// One editable row of the options list.
class _Row {
  _Row(
    this.productId,
    this.code,
    this.name,
    String quantity,
    this.required, {
    this.active = true,
  }) : quantity = TextEditingController(text: quantity);
  final String productId;
  final String code;
  final String name;
  final TextEditingController quantity;
  bool required;

  /// Whether the option is switched on; kept from the stored option so saving does not change it.
  final bool active;
}

/// State of [OptionsTab]: the rows being edited and the save call.
class _OptionsTabState extends ConsumerState<OptionsTab> {
  final List<_Row> _rows = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  TradocraftApi get _api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.quantity.dispose();
    }
    super.dispose();
  }

  void _fill(List<ProductOption> options) {
    for (final r in _rows) {
      r.quantity.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        options.map(
          (o) => _Row(
            o.optionProductId,
            o.optionCode,
            o.optionName,
            number(o.defaultQuantity),
            o.requiredValue,
            active: o.active,
          ),
        ),
      );
  }

  Future<void> _load() async {
    try {
      final options = await _api.products.listOptions(id: widget.product.id);
      if (!mounted) return;
      setState(() {
        _fill(options);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final body = <ProductOptionInput>[];
    for (final (i, r) in _rows.indexed) {
      final q = parseDecimalInput(r.quantity.text);
      if (q == null || double.tryParse(q) == null || double.parse(q) <= 0) {
        setState(() => _error = context.l10n.optionsInvalidQuantity);
        return;
      }
      body.add(
        ProductOptionInput(
          optionProductId: r.productId,
          defaultQuantity: q,
          requiredValue: r.required,
          sortOrder: i,
          active: r.active,
        ),
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _api.products.replaceOptions(
        id: widget.product.id,
        body: body,
      );
      if (!mounted) return;
      setState(() => _fill(saved));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.optionsSaved)));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'products.write');
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.optionsIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        if (_rows.isEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(l.optionsNone)),
        for (final r in _rows)
          ListTile(
            key: ValueKey('option-${r.productId}'),
            dense: true,
            title: Text('${r.code} · ${r.name}'),
            trailing: SizedBox(
              width: 420,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: ValueKey('option-qty-${r.productId}'),
                      controller: r.quantity,
                      enabled: canWrite,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: l.optionQuantity,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    key: ValueKey('option-required-${r.productId}'),
                    label: Text(l.optionRequired),
                    selected: r.required,
                    onSelected: canWrite
                        ? (v) => setState(() => r.required = v)
                        : null,
                  ),
                  if (canWrite)
                    IconButton(
                      key: ValueKey('option-remove-${r.productId}'),
                      tooltip: l.optionRemove,
                      icon: const Icon(AppIcons.close),
                      onPressed: () => setState(() {
                        _rows.remove(r);
                        r.quantity.dispose();
                      }),
                    ),
                ],
              ),
            ),
          ),
        if (canWrite) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 420,
            child: SearchPicker<Product>(
              label: l.optionAdd,
              clearOnSelect: true,
              display: (p) => '${p.code} · ${p.name}',
              search: (q) async => (await _api.products.listProducts(
                q: q,
                active: true,
                limit: 20,
              )).items,
              onSelected: (p) {
                if (p.id == widget.product.id ||
                    _rows.any((r) => r.productId == p.id)) {
                  return;
                }
                setState(
                  () => _rows.add(_Row(p.id, p.code, p.name, '1', false)),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('options-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(AppIcons.save),
              label: Text(l.save),
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
