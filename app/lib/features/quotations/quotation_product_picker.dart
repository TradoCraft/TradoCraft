import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/search_picker.dart';

typedef _Choice = (Product product, int searchId);

/// Shows catalogue results immediately and adds advisory site suitability when available.
class QuotationProductPicker extends StatefulWidget {
  const QuotationProductPicker({
    super.key,
    required this.api,
    required this.label,
    required this.onSelected,
    this.opportunityId,
    this.clearOnSelect = false,
  });

  final TradocraftApi api;
  final String label;
  final ValueChanged<Product> onSelected;
  final String? opportunityId;
  final bool clearOnSelect;

  @override
  State<QuotationProductPicker> createState() => _QuotationProductPickerState();
}

class _QuotationProductPickerState extends State<QuotationProductPicker> {
  int _searchId = 0;
  (int, Map<String, MatchStatus>)? _matches;

  Future<List<_Choice>> _searchProducts(String query) async {
    final searchId = ++_searchId;
    final opportunityId = widget.opportunityId;
    final products = (await widget.api.products.listProducts(
      q: query,
      active: true,
      limit: 20,
    )).items;
    if (mounted &&
        searchId == _searchId &&
        opportunityId != null &&
        products.isNotEmpty) {
      unawaited(_loadMatches(opportunityId, products, searchId));
    }
    return [for (final product in products) (product, searchId)];
  }

  Future<void> _loadMatches(
    String opportunityId,
    List<Product> products,
    int searchId,
  ) async {
    try {
      final matches = await widget.api.crm.productMatches(
        id: opportunityId,
        productIds: products.map((product) => product.id).join(','),
      );
      if (!mounted ||
          searchId != _searchId ||
          opportunityId != widget.opportunityId) {
        return;
      }
      setState(() {
        _matches = (
          searchId,
          {for (final match in matches.items) match.id: match.status},
        );
      });
    } catch (_) {
      // The catalogue results remain available without suitability.
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final l = context.l10n;
    return SearchPicker<_Choice>(
      label: widget.label,
      clearOnSelect: widget.clearOnSelect,
      display: (choice) {
        final (product, searchId) = choice;
        final status = matches != null && matches.$1 == searchId
            ? matches.$2[product.id]
            : null;
        final suitability = switch (status) {
          MatchStatus.suitable => l.matchesSuitable,
          MatchStatus.unsuitable => l.matchesUnsuitable,
          MatchStatus.unknown => l.matchesUnknown,
          _ => null,
        };
        return [product.code, product.name, ?suitability].join(' · ');
      },
      search: _searchProducts,
      onSelected: (choice) => widget.onSelected(choice.$1),
    );
  }
}
