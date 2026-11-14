import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'power_text.dart';
import 'app_icons.dart';

/// Warnings (power grid, incompatible products) and suggested additions that the server returns
/// with a quotation, a pricing preview or an order confirmation. They never block anything.
///
/// Warnings are stacked as banners, grouped by kind. Suggestions are shown in a collapsible panel;
/// with [onAdd] each one gets an "Add" button, without it they are only listed.
class SalesHints extends StatelessWidget {
  const SalesHints({
    super.key,
    required this.warnings,
    required this.suggestions,
    this.onAdd,
  });

  final List<SalesWarning> warnings;
  final List<SalesSuggestion> suggestions;
  final void Function(SalesSuggestion suggestion)? onAdd;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty && suggestions.isEmpty) return const SizedBox.shrink();
    final kinds = <String>[];
    for (final w in warnings) {
      if (!kinds.contains(w.kind)) kinds.add(w.kind);
    }
    return Column(
      key: const ValueKey('sales-hints'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in kinds) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              context.l10n.warningKind(kind),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final w in warnings.where((w) => w.kind == kind))
            _WarningBanner(w),
        ],
        if (suggestions.isNotEmpty)
          _SuggestionPanel(suggestions: suggestions, onAdd: onAdd),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner(this.warning);
  final SalesWarning warning;

  Map<Object?, Object?> get _details {
    final d = warning.details;
    return d is Map ? d.cast<Object?, Object?>() : const {};
  }

  /// The wording, and whether it is only informational.
  (String, List<String>, bool) _text(BuildContext context) {
    final l = context.l10n;
    final d = _details;
    final code = warning.productCode;
    if (warning.kind == 'incompatible_products') {
      final pair = d['product_codes'];
      final codes = pair is List && pair.length >= 2
          ? [pair[0].toString(), pair[1].toString()]
          : [code, '?'];
      final note = d['note'];
      return (
        l.hintsIncompatibleProducts(codes[0], codes[1]),
        [if (note is String && note.isNotEmpty) note],
        false,
      );
    }
    if (warning.kind == 'power_grid') {
      final country = (d['country_code'] ?? '').toString();
      switch (d['status']) {
        case 'incompatible':
          String profiles(Object? v) => powerProfilesText(
            v is List ? v.map(powerProfileFromJson) : const <String>[],
          );
          final extra = <String>[];
          if (d['supported'] is List) {
            extra.add(l.hintsSupported(profiles(d['supported'])));
          }
          if (d['available'] is List) {
            extra.add(l.hintsAvailable(profiles(d['available'])));
          }
          return (l.hintsPowerIncompatible(code), extra, false);
        case 'needs_external_supply':
          return (l.hintsPowerExternal(code), const [], true);
        case 'unknown_grid':
          return (l.hintsPowerUnknown(country, code), const [], false);
      }
    }
    return (warning.message, const [], false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, extra, info) = _text(context);
    return Container(
      key: ValueKey('warning-${warning.kind}-${warning.productCode}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: info ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            info ? AppIcons.info : AppIcons.warningAmber,
            color: info ? scheme.onSecondaryContainer : scheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                for (final e in extra)
                  Text(e, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.suggestions, required this.onAdd});
  final List<SalesSuggestion> suggestions;
  final void Function(SalesSuggestion)? onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      child: ExpansionTile(
        key: const ValueKey('suggestions-panel'),
        initiallyExpanded: true,
        leading: const Icon(AppIcons.lightbulb),
        title: Text('${l.suggestionsTitle} (${suggestions.length})'),
        children: [
          for (final s in suggestions)
            ListTile(
              key: ValueKey('suggestion-${s.productId}'),
              dense: true,
              title: Text('${s.productCode} · ${s.productName}'),
              subtitle: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(l.suggestionReason(s.reason)),
                  ),
                  if (s.strength != null)
                    Text(l.suggestionStrength(s.strength!)),
                  if (s.confidence != null)
                    Text(l.suggestionConfidence((s.confidence! * 100).round())),
                  Text(l.suggestionBecause(s.becauseOfCode)),
                  if (s.note.isNotEmpty) Text(s.note),
                ],
              ),
              trailing: onAdd == null
                  ? null
                  : OutlinedButton.icon(
                      icon: const Icon(AppIcons.add),
                      label: Text(l.add),
                      onPressed: () => onAdd!(s),
                    ),
            ),
        ],
      ),
    );
  }
}
