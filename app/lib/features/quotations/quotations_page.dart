import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../framework/search/filter_model.dart';
import '../../shared/app_icons.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../tutorial/controller.dart';
import 'quotation_repository.dart';
import '../../l10n/l10n.dart';

class QuotationsPage extends ConsumerStatefulWidget {
  const QuotationsPage({super.key});

  @override
  ConsumerState<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends ConsumerState<QuotationsPage> {
  final _list = GlobalKey<EntityListState<QuotationSummary>>();

  @override
  Widget build(BuildContext context) {
    ref.listen(tutorialAssistCompletedProvider, (_, completed) {
      if (completed?.missionId == 'quotation' && completed?.stepId == 'create') {
        _list.currentState?.reload();
      }
    });
    final repo = ref.watch(quotationRepositoryProvider);
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('quotations.write') ??
        false;
    return EntityList<QuotationSummary>(
      key: _list,
      title: context.l10n.quotations,
      loadQuery: (query) async => (await repo.list(query)).asLoaderResult,
      prefsKey: 'quotations',
      resizableColumns: true,
      columnMenu: true,
      filterDefs: [
        FilterDef(
          key: 'status',
          label: context.l10n.status,
          options: [
            for (final s in QuotationStatus.values.where(
              (s) => s != QuotationStatus.$unknown,
            ))
              (s.json!, context.l10n.quotationStatus(s.json!)),
          ],
        ),
      ],
      columns: [
        EntityColumn(
          context.l10n.numberRequired,
          (q) => '${q.number}  r${q.revision}',
          flex: 2,
          sortKey: 'number',
        ),
        EntityColumn(
          context.l10n.customer,
          (q) => q.customerName,
          flex: 3,
          sortKey: 'customer_name',
        ),
        EntityColumn(
          context.l10n.date,
          (q) => date(q.quoteDate),
          sortKey: 'quote_date',
        ),
        EntityColumn(
          context.l10n.status,
          (q) => context.l10n.quotationStatus(q.status.json ?? ''),
          sortKey: 'status',
        ),
        EntityColumn(
          context.l10n.totalExclVat,
          (q) => money(q.subtotal, currency: q.currency),
          numeric: true,
          sortKey: 'subtotal',
          flex: 2,
        ),
      ],
      actions: [
        if (can(ref, 'configurator.use'))
          OutlinedButton.icon(
            onPressed: () => context.go('/configurator'),
            icon: const Icon(AppIcons.dashboardCustomize),
            label: Text(context.l10n.configure),
          ),
      ],
      createTargetId: 'quotations-create',
      createLabel: context.l10n.newQuotation,
      onCreate: canWrite
          ? () async => await context.push<bool>('/quotations/new') ?? true
          : null,
      locationOf: (q) => '/quotations/${q.id}',
      onOpen: (q) async =>
          await context.push<bool>('/quotations/${q.id}') ?? true,
    );
  }
}
