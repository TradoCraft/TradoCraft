import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/app_icons.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../l10n/l10n.dart';

class QuotationsPage extends ConsumerStatefulWidget {
  const QuotationsPage({super.key});

  @override
  ConsumerState<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends ConsumerState<QuotationsPage> {
  final _list = GlobalKey<EntityListState<QuotationSummary>>();
  QuotationStatus? _status;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('quotations.write') ??
        false;
    return EntityList<QuotationSummary>(
      key: _list,
      title: context.l10n.quotations,
      load: (q, offset, limit) async {
        final page = await api.sales.listQuotations(
          q: q,
          status: _status?.json,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      filters: DropdownButton<QuotationStatus?>(
        value: _status,
        hint: Text(context.l10n.allStatuses),
        items: [
          DropdownMenuItem(value: null, child: Text(context.l10n.allStatuses)),
          for (final s in QuotationStatus.values.where(
            (s) => s != QuotationStatus.$unknown,
          ))
            DropdownMenuItem(
              value: s,
              child: Text(context.l10n.quotationStatus(s.json!)),
            ),
        ],
        onChanged: (s) {
          setState(() => _status = s);
          _list.currentState?.reload();
        },
      ),
      columns: [
        EntityColumn(
          context.l10n.numberRequired,
          (q) => '${q.number}  r${q.revision}',
          flex: 2,
        ),
        EntityColumn(context.l10n.customer, (q) => q.customerName, flex: 3),
        EntityColumn(context.l10n.date, (q) => date(q.quoteDate)),
        EntityColumn(
          context.l10n.status,
          (q) => context.l10n.quotationStatus(q.status.json ?? ''),
        ),
        EntityColumn(
          context.l10n.totalExclVat,
          (q) => money(q.subtotal, currency: q.currency),
          numeric: true,
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
