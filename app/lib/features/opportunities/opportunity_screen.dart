import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import 'opportunity_form.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

final _opportunityProvider = FutureProvider.autoDispose
    .family<Opportunity, String>(
      (ref, id) => ref.watch(apiProvider).crm.getOpportunity(id: id),
    );

final _quotationsProvider = FutureProvider.autoDispose
    .family<QuotationPage, String>(
      (ref, id) => ref
          .watch(apiProvider)
          .sales
          .listQuotations(opportunityId: id, limit: 100),
    );

const _openStages = [
  OpportunityStage.lead,
  OpportunityStage.qualified,
  OpportunityStage.proposal,
  OpportunityStage.negotiation,
];

class OpportunityScreen extends ConsumerStatefulWidget {
  const OpportunityScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<OpportunityScreen> createState() => _OpportunityScreenState();
}

class _OpportunityScreenState extends ConsumerState<OpportunityScreen> {
  String get id => widget.id;

  @override
  void initState() {
    super.initState();
    // The same opportunity may already be open further down the navigation stack, keeping
    // its cached data alive; always show the current state when a screen opens.
    Future.microtask(() {
      ref.invalidate(_opportunityProvider(id));
      ref.invalidate(_quotationsProvider(id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final opp = ref.watch(_opportunityProvider(id));
    final canWrite =
        ref
            .watch(meProvider)
            .value
            ?.permissions
            .contains('opportunities.write') ??
        false;
    final canQuote =
        ref.watch(meProvider).value?.permissions.contains('quotations.write') ??
        false;
    void refresh() {
      ref.invalidate(_opportunityProvider(id));
      ref.invalidate(_quotationsProvider(id));
    }

    return Scaffold(
      body: opp.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (o) {
          final closed =
              o.stage == OpportunityStage.won ||
              o.stage == OpportunityStage.lost;
          final api = ref.read(apiProvider);
          Future<void> setStage(
            OpportunityStage stage, {
            String? reason,
          }) async {
            await runAction(
              context,
              () => api.crm.changeStage(
                id: id,
                body: StageInput(stage: stage, lostReason: reason),
              ),
            );
            refresh();
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    onPressed: () => context.canPop()
                        ? context.pop(true)
                        : context.go('/opportunities'),
                    icon: const Icon(AppIcons.arrowBack),
                  ),
                  Text(
                    '${o.number}  ${o.title}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Chip(
                    label: Text(
                      context.l10n.opportunityStage(o.stage.json ?? ''),
                    ),
                  ),
                  if (canWrite)
                    OutlinedButton.icon(
                      icon: const Icon(AppIcons.edit),
                      label: Text(context.l10n.edit),
                      onPressed: () async {
                        if (await showOpportunityForm(
                              context,
                              opportunity: o,
                            ) !=
                            null) {
                          refresh();
                        }
                      },
                    ),
                  if (canQuote && !closed)
                    FilledButton.icon(
                      icon: const Icon(AppIcons.requestQuote),
                      label: Text(context.l10n.newQuotation),
                      onPressed: () async {
                        await context.push(
                          '/quotations/new?customer=${o.customerId}&opportunity=${o.id}',
                        );
                        refresh();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                children: [
                  InfoItem(context.l10n.customer, o.customerName),
                  InfoItem(context.l10n.owner, o.ownerName),
                  InfoItem(context.l10n.expectedValue, money(o.expectedValue)),
                  InfoItem(context.l10n.probability, '${o.probability} %'),
                  InfoItem(context.l10n.expectedClose, date(o.expectedClose)),
                  if (o.lostReason != null)
                    InfoItem(context.l10n.lostReason, o.lostReason!),
                ],
              ),
              if (o.notes.isNotEmpty) Text(o.notes),
              if (canWrite) ...[
                const SizedBox(height: 16),
                Text(
                  context.l10n.stage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SegmentedButton<OpportunityStage>(
                      segments: [
                        for (final s in _openStages)
                          ButtonSegment(
                            value: s,
                            label: Text(context.l10n.opportunityStage(s.json!)),
                          ),
                      ],
                      selected: {if (_openStages.contains(o.stage)) o.stage},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (s) =>
                          s.isEmpty ? null : setStage(s.first),
                    ),
                    FilledButton.tonal(
                      onPressed: o.stage == OpportunityStage.won
                          ? null
                          : () => setStage(OpportunityStage.won),
                      child: Text(context.l10n.won),
                    ),
                    FilledButton.tonal(
                      onPressed: o.stage == OpportunityStage.lost
                          ? null
                          : () async {
                              final reason = await askText(
                                context,
                                title: context.l10n.markAsLost,
                                label: context.l10n.reason,
                              );
                              if (reason != null && reason.isNotEmpty) {
                                await setStage(
                                  OpportunityStage.lost,
                                  reason: reason,
                                );
                              }
                            },
                      child: Text(context.l10n.lost),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text(
                context.l10n.quotations,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ref
                  .watch(_quotationsProvider(id))
                  .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(errorMessage(e)),
                    data: (page) => page.items.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(context.l10n.noQuotations),
                          )
                        : Column(
                            children: [
                              for (final q in page.items)
                                ListTile(
                                  title: Text(
                                    '${q.number}  rev. ${q.revision}',
                                  ),
                                  subtitle: Text(
                                    '${context.l10n.quotationStatus(q.status.json ?? '')} · ${date(q.quoteDate)}',
                                  ),
                                  trailing: Text(
                                    money(q.subtotal, currency: q.currency),
                                  ),
                                  onTap: () async {
                                    await context.push('/quotations/${q.id}');
                                    refresh();
                                  },
                                ),
                            ],
                          ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
