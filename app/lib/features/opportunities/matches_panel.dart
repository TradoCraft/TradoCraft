import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';

/// (opportunity id, baseline item id or null for the whole baseline).
typedef MatchKey = (String, String?);

/// Every active product judged against the site baseline (ADR 0068, decision 7), optionally
/// against one baseline item (and the items inside it) only.
final productMatchesProvider = FutureProvider.autoDispose
    .family<ProductMatchPage, MatchKey>(
      (ref, key) => ref
          .watch(apiProvider)
          .crm
          .productMatches(id: key.$1, itemId: key.$2, limit: 500),
    );

int _rank(MatchStatus s) => switch (s) {
  MatchStatus.suitable => 0,
  MatchStatus.unknown => 1,
  _ => 2,
};

/// Suitable first, then unknown, then not suitable; the server order is kept within a group.
List<ProductMatch> orderMatches(List<ProductMatch> items) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final c = _rank(a.$2.status).compareTo(_rank(b.$2.status));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// The matches of an opportunity below its baseline. Hidden without `products.read`.
class MatchesPanel extends ConsumerWidget {
  const MatchesPanel({super.key, required this.opportunityId});
  final String opportunityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(ref, 'products.read')) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.matchesTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        MatchesList(opportunityId: opportunityId),
      ],
    );
  }
}

/// The list itself: suitable products at full strength, the others dimmed with the reasons that
/// kept them out beneath. [itemId] limits the judgement to one baseline item.
class MatchesList extends ConsumerWidget {
  const MatchesList({super.key, required this.opportunityId, this.itemId});
  final String opportunityId;
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final key = (opportunityId, itemId);
    final page = ref.watch(productMatchesProvider(key));
    if (page.hasError) {
      return Row(
        children: [
          Expanded(child: Text(errorMessage(page.error!))),
          TextButton(
            onPressed: () => ref.invalidate(productMatchesProvider(key)),
            child: Text(l.retry),
          ),
        ],
      );
    }
    final value = page.value;
    if (value == null) return const LinearProgressIndicator();
    if (value.items.isEmpty) {
      return Padding(
        key: const ValueKey('matches-empty'),
        padding: const EdgeInsets.all(8),
        child: Text(l.matchesEmpty),
      );
    }
    return Column(
      children: [
        if (value.total > value.items.length)
          Padding(
            key: const ValueKey('matches-showing'),
            padding: const EdgeInsets.all(8),
            child: Text(l.matchesShowing(value.items.length, value.total)),
          ),
        for (final m in orderMatches(value.items)) _MatchTile(m),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile(this.match);
  final ProductMatch match;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final suitable = match.status == MatchStatus.suitable;
    final label = switch (match.status) {
      MatchStatus.suitable => l.matchesSuitable,
      MatchStatus.unknown => l.matchesUnknown,
      _ => l.matchesUnsuitable,
    };
    // Suitable products need no explanation; the others say what kept them out.
    final reasons = [
      for (final r in match.reasons)
        if (r.status != CheckStatus.ok) r.message,
    ];
    final tile = ListTile(
      key: ValueKey('match-${match.id}'),
      dense: true,
      title: Text('${match.code} · ${match.name}'),
      subtitle: suitable
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in reasons.isEmpty ? [l.matchesNoReason] : reasons)
                  Text(r),
              ],
            ),
      trailing: Text(label),
    );
    return suitable
        ? tile
        : Opacity(
            key: ValueKey('match-grey-${match.id}'),
            opacity: 0.55,
            child: tile,
          );
  }
}

/// "Suggest products" for one baseline item: the same list, filtered to that item.
Future<void> showSuggestedProducts(
  BuildContext context, {
  required String opportunityId,
  required String itemId,
  required String itemLabel,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(ctx.l10n.matchesForItem(itemLabel)),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: MatchesList(opportunityId: opportunityId, itemId: itemId),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text(ctx.l10n.close),
      ),
    ],
  ),
);
