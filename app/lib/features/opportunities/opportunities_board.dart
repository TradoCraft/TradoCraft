import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../core/theme/tokens.dart';
import '../../framework/views/kanban/kanban_config.dart';
import '../../framework/views/kanban/kanban_controller.dart';
import '../../framework/views/kanban/kanban_view.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'opportunity_form.dart';

/// The stages in pipeline order. Unknown values a newer server might send are not columns.
const _stages = [
  OpportunityStage.lead,
  OpportunityStage.qualified,
  OpportunityStage.proposal,
  OpportunityStage.negotiation,
  OpportunityStage.won,
  OpportunityStage.lost,
];

/// The pipeline as a kanban board (ADR 0087): one column per stage, cards moved by dragging or
/// by the menu on the card. The page owns the search text and the switch to the list.
class OpportunitiesBoard extends ConsumerStatefulWidget {
  const OpportunitiesBoard({super.key});

  @override
  ConsumerState<OpportunitiesBoard> createState() => _OpportunitiesBoardState();
}

class _OpportunitiesBoardState extends ConsumerState<OpportunitiesBoard> {
  final _search = TextEditingController();
  String? _q;
  KanbanController<Opportunity>? _controller;
  Locale? _locale;

  CrmClient get _crm => ref.read(apiProvider).crm;

  @override
  void initState() {
    super.initState();
    // The user's rights arrive after the board is first built, and can change: the "+" follows
    // them. The loaded cards stay.
    ref.listenManual(meProvider, (_, _) {
      if (_controller == null || !mounted) return;
      _controller!.updateConfig(_config(context));
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final controller = _controller;
    if (controller == null) {
      // Created once the localisations are available: the column titles are translated.
      final created = KanbanController(_config(context));
      _controller = created;
      _locale = locale;
      created.load();
    } else if (locale != _locale) {
      // Another language: new titles and sums, the same cards.
      _locale = locale;
      controller.updateConfig(_config(context));
      controller.refreshSummaries();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _search.dispose();
    super.dispose();
  }

  KanbanConfig<Opportunity> _config(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return KanbanConfig<Opportunity>(
      columns: [
        for (final s in _stages)
          KanbanColumnDef(
            s.json!,
            l.opportunityStage(s.json!),
            color: switch (s) {
              OpportunityStage.won => Colors.green.shade600,
              OpportunityStage.lost => scheme.error,
              _ => null,
            },
          ),
      ],
      idOf: (o) => o.id,
      cardBuilder: (context, o) => _OpportunityCard(o),
      loadColumn: (stage, offset, limit) async {
        final page = await _crm.listOpportunities(
          q: _q,
          stage: stage,
          offset: offset,
          limit: limit,
        );
        return KanbanPage(page.items, page.total);
      },
      loadSummaries: () async {
        final stages = await _crm.pipeline();
        return {
          for (final s in stages)
            s.stage.json ?? '':
                '${money(s.totalValue)} · ${l.weighted(money(s.weightedValue))}',
        };
      },
      move: _move,
      onOpen: (o) async {
        await context.push<bool>('/opportunities/${o.id}');
        if (mounted) _controller?.load();
      },
      // Entering a stage resets the probability to the stage's default: the card shows it.
      reloadAfterMove: true,
      // Nothing is created straight into a closed stage.
      canCreateIn: (id) =>
          id != OpportunityStage.won.json && id != OpportunityStage.lost.json,
      onCreate:
          ref
                  .read(meProvider)
                  .value
                  ?.permissions
                  .contains('opportunities.write') ??
              false
          ? _create
          : null,
    );
  }

  Future<MoveResult> _move(Opportunity o, String stageId) async {
    final stage = OpportunityStage.fromJson(stageId);
    final l = context.l10n;
    String? reason;
    if (stage == OpportunityStage.lost) {
      // As on the opportunity screen: a lost opportunity needs a reason.
      reason = await askText(context, title: l.markAsLost, label: l.reason);
      if (reason == null) return MoveResult.cancelled;
      if (reason.isEmpty) throw KanbanMoveRefused(l.kanbanLostCancelled);
    }
    await _crm.changeStage(
      id: o.id,
      body: StageInput(stage: stage, lostReason: reason),
    );
    return MoveResult.moved;
  }

  /// The "+" of a column: the usual form, then the new opportunity is put in that column.
  Future<void> _create(String stageId) async {
    final created = await showOpportunityForm(context);
    if (created == null || !mounted) return;
    final stage = OpportunityStage.fromJson(stageId);
    if (stage != created.stage && stage != OpportunityStage.lost) {
      try {
        await _crm.changeStage(
          id: created.id,
          body: StageInput(stage: stage),
        );
      } catch (e) {
        if (mounted) _controller?.error = errorMessage(e);
      }
    }
    if (mounted) await _controller?.load();
  }

  void _submit(String text) {
    final q = text.trim();
    _q = q.isEmpty ? null : q;
    _controller?.load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final controller = _controller!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 320,
              child: TextField(
                key: const ValueKey('board-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.search,
                  prefixIcon: const Icon(AppIcons.search),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _submit,
              ),
            ),
          ),
        ),
        Expanded(child: KanbanView<Opportunity>(controller: controller)),
      ],
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard(this.o);
  final Opportunity o;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: '${o.number} ${o.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o.number, style: muted),
          Text(
            o.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            o.customerName,
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${money(o.expectedValue)} · ${o.probability} %'
            '${o.expectedClose == null ? '' : ' · ${date(o.expectedClose)}'}',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
