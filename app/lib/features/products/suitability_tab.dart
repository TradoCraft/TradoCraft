import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'suitability_logic.dart';

final _definitionsProvider =
    FutureProvider.autoDispose<List<AttributeDefinition>>(
      (ref) =>
          ref.watch(apiProvider).products.listDefinitions(scope: 'product'),
    );

final _attributesProvider = FutureProvider.autoDispose
    .family<List<ProductAttribute>, String>(
      (ref, productId) =>
          ref.watch(apiProvider).products.listAttributes(id: productId),
    );

/// What a product is suitable for (dial size range, motion, ...): one input per active
/// product-scope attribute definition, saved through the replace-all attributes endpoint.
/// Read-only without `products.write`.
class SuitabilityTab extends ConsumerWidget {
  const SuitabilityTab({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defs = ref.watch(_definitionsProvider);
    final attrs = ref.watch(_attributesProvider(product.id));
    final failed = defs.error ?? attrs.error;
    if (failed != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(errorMessage(failed)),
          TextButton(
            onPressed: () {
              ref.invalidate(_definitionsProvider);
              ref.invalidate(_attributesProvider(product.id));
            },
            child: Text(context.l10n.retry),
          ),
        ],
      );
    }
    if (!defs.hasValue || !attrs.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    final active = defs.requireValue.where((d) => d.active).toList();
    if (active.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.l10n.suitabilityEmpty,
            key: const ValueKey('suitability-empty'),
          ),
        ],
      );
    }
    return _SuitabilityForm(
      product: product,
      defs: active,
      stored: attrs.requireValue,
    );
  }
}

class _SuitabilityForm extends ConsumerStatefulWidget {
  const _SuitabilityForm({
    required this.product,
    required this.defs,
    required this.stored,
  });
  final Product product;
  final List<AttributeDefinition> defs;
  final List<ProductAttribute> stored;

  @override
  ConsumerState<_SuitabilityForm> createState() => _SuitabilityFormState();
}

class _SuitabilityFormState extends ConsumerState<_SuitabilityForm> {
  /// One controller per input; a range has two (`key` -> [min, max]).
  late final Map<String, List<TextEditingController>> _c;
  late final Map<String, String> _selected;
  Map<String, AttrError> _errors = {};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = rawFromAttributes(widget.defs, widget.stored);
    _c = {};
    _selected = {};
    for (final d in widget.defs) {
      final v = raw[d.key]!;
      if (d.kind == DefinitionKind.select) {
        _selected[d.key] = v.first;
      } else {
        _c[d.key] = [for (final t in v) TextEditingController(text: t)];
      }
    }
  }

  @override
  void dispose() {
    for (final list in _c.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String _message(AttrError e) {
    final l = context.l10n;
    return switch (e) {
      AttrError.notNumber => l.attrEnterNumber,
      AttrError.rangeIncomplete => l.attrRangeIncomplete,
      AttrError.rangeOrder => l.attrRangeOrder,
      AttrError.notInOptions => l.attrNotInOptions,
    };
  }

  Future<void> _save() async {
    final raw = {
      for (final d in widget.defs)
        d.key: d.kind == DefinitionKind.select
            ? [_selected[d.key] ?? '']
            : [for (final c in _c[d.key]!) c.text],
    };
    final r = buildAttributes(
      defs: widget.defs,
      existing: widget.stored,
      raw: raw,
    );
    if (r.errors.isNotEmpty) {
      setState(() {
        _errors = r.errors;
        _error = null;
      });
      return;
    }
    setState(() {
      _errors = {};
      _error = null;
      _saving = true;
    });
    try {
      await ref
          .read(apiProvider)
          .products
          .replaceAttributes(id: widget.product.id, body: r.attributes);
      ref.invalidate(_attributesProvider(widget.product.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.saved)));
      }
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(AttributeDefinition d, bool canWrite) {
    final l = context.l10n;
    final err = _errors[d.key];
    final suffix = (d.unit ?? '').isEmpty ? null : d.unit;
    final numberKeyboard = const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    switch (d.kind) {
      case DefinitionKind.range:
        final (lo, hi) = (_c[d.key]![0], _c[d.key]![1]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                key: ValueKey('attr-${d.key}-min'),
                controller: lo,
                enabled: canWrite,
                keyboardType: numberKeyboard,
                decoration: InputDecoration(
                  labelText: '${d.label} ${l.attrMin}',
                  suffixText: suffix,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: TextField(
                key: ValueKey('attr-${d.key}-max'),
                controller: hi,
                enabled: canWrite,
                keyboardType: numberKeyboard,
                decoration: InputDecoration(
                  labelText: '${d.label} ${l.attrMax}',
                  suffixText: suffix,
                ),
              ),
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 16),
                child: Text(
                  _message(err),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
      case DefinitionKind.select:
        final current = _selected[d.key] ?? '';
        final known = d.options.any((o) => o.value == current);
        return SizedBox(
          width: 292,
          child: DropdownButtonFormField<String>(
            key: ValueKey('attr-${d.key}'),
            initialValue: current,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: d.label,
              errorText: err == null ? null : _message(err),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(l.none)),
              for (final o in d.options)
                DropdownMenuItem(value: o.value, child: Text(o.label)),
              // A stored value that is no longer an option stays visible until changed.
              if (current.isNotEmpty && !known)
                DropdownMenuItem(value: current, child: Text(current)),
            ],
            onChanged: canWrite
                ? (v) => setState(() => _selected[d.key] = v ?? '')
                : null,
          ),
        );
      case DefinitionKind.number:
      case DefinitionKind.text:
      case DefinitionKind.$unknown:
        final isNumber = d.kind == DefinitionKind.number;
        return SizedBox(
          width: 292,
          child: TextField(
            key: ValueKey('attr-${d.key}'),
            controller: _c[d.key]![0],
            enabled: canWrite,
            keyboardType: isNumber ? numberKeyboard : TextInputType.text,
            decoration: InputDecoration(
              labelText: d.label,
              suffixText: isNumber ? suffix : null,
              errorText: err == null ? null : _message(err),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'products.write');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.suitabilityHelp),
        const SizedBox(height: 12),
        for (final d in widget.defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _field(d, canWrite),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (canWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
          ),
      ],
    );
  }
}
