import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'relations_dialog.dart';
import '../../shared/app_icons.dart';

final _relatedProvider = FutureProvider.autoDispose
    .family<RelatedProducts, String>(
      (ref, productId) =>
          ref.watch(apiProvider).products.getRelatedProducts(id: productId),
    );

/// The relation rules that apply to a product (directly or through its family) and the products
/// that are suggested with it.
class RelatedTab extends ConsumerWidget {
  const RelatedTab({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final related = ref.watch(_relatedProvider(product.id));
    final canWrite = can(ref, 'products.write');
    final theme = Theme.of(context);

    Future<void> edit([ProductRelation? rule]) async {
      if (await showRelationEditor(
        context,
        rule: rule,
        product: rule == null ? product : null,
      )) {
        ref.invalidate(_relatedProvider(product.id));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(l.relationRules, style: theme.textTheme.titleMedium),
            const SizedBox(width: 12),
            if (canWrite)
              FilledButton.tonalIcon(
                icon: const Icon(AppIcons.add),
                label: Text(l.relationAddRule),
                onPressed: edit,
              ),
          ],
        ),
        related.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l.relationNoRules),
                ),
              for (final kind in const [
                'incompatible',
                'suggested',
                'compatible',
              ])
                if (data.rules.any((r) => r.kind == kind)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l.relationKind(kind),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  for (final r in data.rules.where((r) => r.kind == kind))
                    ListTile(
                      key: ValueKey('rule-${r.id}'),
                      dense: true,
                      title: Text(relationTitle(context, r)),
                      subtitle: Text(
                        [
                          if (kind == 'suggested')
                            l.suggestionStrength(r.strength),
                          if (r.note.isNotEmpty) r.note,
                        ].join(' · '),
                      ),
                      trailing: canWrite
                          ? IconButton(
                              tooltip: context.l10n.edit,
                              icon: const Icon(AppIcons.edit),
                              onPressed: () => edit(r),
                            )
                          : null,
                    ),
                ],
              const SizedBox(height: 24),
              Text(l.relationSuggestions, style: theme.textTheme.titleMedium),
              if (data.suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l.relationNoSuggestions),
                ),
              for (final s in data.suggestions)
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
                        label: Text(l.suggestionReason(s.reason.json ?? '')),
                      ),
                      if (s.strength != null)
                        Text(l.suggestionStrength(s.strength!)),
                      if (s.confidence != null)
                        Text(
                          l.suggestionConfidence((s.confidence! * 100).round()),
                        ),
                      Text(l.suggestionBecause(s.becauseOfCode)),
                      if (s.note.isNotEmpty) Text(s.note),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
