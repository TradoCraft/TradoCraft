import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'format.dart';

/// What the user ticked in the sub-item chooser.
class SubItemPicks {
  const SubItemPicks({this.options = const [], this.products = const []});

  /// Ticked options of the parent product (they carry a default quantity).
  final List<ProductOption> options;

  /// Other products found by searching, quantity 1.
  final List<Product> products;

  bool get isEmpty => options.isEmpty && products.isEmpty;
}

/// Lets the user pick the sub-items of a quotation line: the valid options of the parent product
/// are listed with tick boxes, and a search finds any other products, several of which can be
/// ticked (ticks survive new searches). Returns null when dismissed.
Future<SubItemPicks?> showSubItemChooser(
  BuildContext context, {
  required Product parent,
  required List<ProductOption> options,
  Set<String> alreadyPresent = const {},
}) => showDialog<SubItemPicks>(
  context: context,
  builder: (_) => SubItemChooser(
    parent: parent,
    options: options,
    alreadyPresent: alreadyPresent,
  ),
);

/// Dialog body of [showSubItemChooser]: tick boxes for the options, a search with ticks for others.
class SubItemChooser extends ConsumerStatefulWidget {
  const SubItemChooser({
    super.key,
    required this.parent,
    required this.options,
    this.alreadyPresent = const {},
  });

  final Product parent;
  final List<ProductOption> options;

  /// Product ids that are already sub-items of the line (not offered again).
  final Set<String> alreadyPresent;

  @override
  ConsumerState<SubItemChooser> createState() => _SubItemChooserState();
}

/// State of [SubItemChooser]: the ticked options, the ticked products (kept across searches) and
/// the current search results.
class _SubItemChooserState extends ConsumerState<SubItemChooser> {
  final _query = TextEditingController();
  final Set<String> _options = {};
  final Map<String, Product> _picked = {};
  List<Product> _results = [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  late final List<ProductOption> _available = [
    for (final o in widget.options)
      if (!widget.alreadyPresent.contains(o.optionProductId)) o,
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Searches 300 ms after the last keystroke.
  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  /// Looks up active products matching [q]; an older answer never replaces a newer one.
  Future<void> _search(String q) async {
    final seq = ++_seq;
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final page = await ref
          .read(apiProvider)
          .products
          .listProducts(q: q.trim(), active: true, limit: 30);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = [
          for (final p in page.items)
            if (p.id != widget.parent.id &&
                !widget.alreadyPresent.contains(p.id))
              p,
        ];
        _error = null;
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _searching = false);
    }
  }

  /// Number of ticked options and products.
  int get _count => _options.length + _picked.length;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final heading = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      key: const ValueKey('sub-item-chooser'),
      title: Text(l.addSubItem),
      content: SizedBox(
        width: 520,
        height: 480,
        child: ListView(
          children: [
            Text(
              l.subItemsOptions(
                '${widget.parent.code} · ${widget.parent.name}',
              ),
              style: heading,
            ),
            if (_available.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.subItemsNoOptions),
              ),
            for (final o in _available)
              CheckboxListTile(
                key: ValueKey('sub-option-${o.optionProductId}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _options.contains(o.optionProductId),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _options.add(o.optionProductId);
                  } else {
                    _options.remove(o.optionProductId);
                  }
                }),
                title: Text('${o.optionCode} · ${o.optionName}'),
                subtitle: Text(
                  [
                    '× ${number(o.defaultQuantity)}',
                    if (o.requiredValue) l.optionRequired,
                  ].join(' · '),
                ),
              ),
            const Divider(height: 24),
            Text(l.subItemsOtherProducts, style: heading),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sub-item-search'),
              controller: _query,
              autofocus: _available.isEmpty,
              decoration: InputDecoration(
                labelText: l.addProduct,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _onQuery,
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final p in _results)
              CheckboxListTile(
                key: ValueKey('sub-product-${p.id}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picked.containsKey(p.id),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _picked[p.id] = p;
                  } else {
                    _picked.remove(p.id);
                  }
                }),
                title: Text('${p.code} · ${p.name}'),
              ),
            // Ticked products stay visible when a new search no longer lists them.
            for (final p in _picked.values.where(
              (p) => !_results.any((r) => r.id == p.id),
            ))
              CheckboxListTile(
                key: ValueKey('sub-product-${p.id}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: true,
                onChanged: (_) => setState(() => _picked.remove(p.id)),
                title: Text('${p.code} · ${p.name}'),
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
          key: const ValueKey('sub-item-add'),
          onPressed: _count == 0
              ? null
              : () => Navigator.pop(
                  context,
                  SubItemPicks(
                    options: [
                      for (final o in _available)
                        if (_options.contains(o.optionProductId)) o,
                    ],
                    products: _picked.values.toList(),
                  ),
                ),
          child: Text('${l.optionsAddSelected} ($_count)'),
        ),
      ],
    );
  }
}
