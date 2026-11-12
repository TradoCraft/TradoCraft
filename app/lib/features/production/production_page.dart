import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../field/offline/kv_store.dart';
import '../tutorial/targets.dart';

/// The states a production order can be filtered on.
const productionStatuses = [
  'released',
  'in_progress',
  'completed',
  'cancelled',
];

/// The divisions of the company (for the filter and for choosing one).
final divisionsProvider = FutureProvider.autoDispose<List<Division>>(
  (ref) => ref.watch(apiProvider).production.listDivisions(),
);

/// Storage key (per user) of the remembered queue scope: `mine` or `all`.
const productionScopeKey = 'production.queue_scope';

/// The divisions the signed-in user is a member of.
List<Division> myDivisions(List<Division> all) =>
    all.where((d) => d.isMember).toList();

/// The production queue: most urgent first, with what is short of stock flagged.
class ProductionQueuePage extends ConsumerStatefulWidget {
  const ProductionQueuePage({super.key});

  @override
  ConsumerState<ProductionQueuePage> createState() =>
      _ProductionQueuePageState();
}

class _ProductionQueuePageState extends ConsumerState<ProductionQueuePage> {
  final _list = GlobalKey<EntityListState<ProductionSummary>>();
  String? _status;
  String? _division;

  /// The user's own choice of scope (`true`: my divisions); null until chosen or restored.
  bool? _mineChoice;
  bool _scopeRestored = false;

  @override
  void initState() {
    super.initState();
    ref.read(userKvStoreProvider).get(productionScopeKey).then((v) {
      if (!mounted) return;
      setState(() {
        _scopeRestored = true;
        if (v == 'mine') _mineChoice = true;
        if (v == 'all') _mineChoice = false;
      });
    });
  }

  void _setScope(bool mine) {
    setState(() => _mineChoice = mine);
    ref
        .read(userKvStoreProvider)
        .set(productionScopeKey, mine ? 'mine' : 'all');
    // The loader is rebuilt with the new scope first; then the list reloads.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _list.currentState?.reload(),
    );
  }

  Future<bool?> _buildForStock() => showDialog<bool>(
    context: context,
    builder: (_) => const _StockOrderDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final divisionsAsync = ref.watch(divisionsProvider);
    final divisions = divisionsAsync.value ?? const <Division>[];
    final mine = myDivisions(divisions);
    // Workers default to their own divisions; planners, sales and admins (who can write or
    // administer production) to everything. Without a division there is no scope at all.
    final defaultMine =
        mine.isNotEmpty &&
        !perms.contains('production.write') &&
        !perms.contains('production.admin');
    final scopeMine = mine.isNotEmpty && (_mineChoice ?? defaultMine);
    if (!_scopeRestored ||
        ref.watch(meProvider).isLoading ||
        divisionsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // A division that no longer exists is not a valid filter: drop it, so it is not sent either.
    if (_division != null &&
        divisionsAsync.hasValue &&
        !divisions.any((d) => d.id == _division)) {
      _division = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _list.currentState?.reload(),
      );
    }
    return EntityList<ProductionSummary>(
      key: _list,
      title: l.production,
      load: (q, offset, limit) async {
        final page = await api.production.listOrders(
          q: q,
          status: _status,
          divisionId: _division,
          mine: scopeMine ? true : null,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      emptyText: scopeMine ? l.productionScopeEmpty : null,
      emptyAction: scopeMine
          ? TextButton(
              key: const ValueKey('scope-show-all'),
              onPressed: () => _setScope(false),
              child: Text(l.productionShowAllDivisions),
            )
          : null,
      filters: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mine.isNotEmpty) ...[
            TutorialTarget(id: 'production-scope', child: SegmentedButton<bool>(
              key: const ValueKey('queue-scope'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(l.productionScopeMine)),
                ButtonSegment(value: false, label: Text(l.productionScopeAll)),
              ],
              selected: {scopeMine},
              onSelectionChanged: (s) => _setScope(s.first),
            )),
            const SizedBox(width: 12),
            Tooltip(
              message: l.productionYourDivisions,
              child: Wrap(
                key: const ValueKey('my-divisions'),
                spacing: 4,
                children: [
                  for (final d in mine)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(d.name),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          DropdownButton<String?>(
            value: _status,
            hint: Text(l.allStatuses),
            items: [
              DropdownMenuItem(value: null, child: Text(l.allStatuses)),
              for (final s in productionStatuses)
                DropdownMenuItem(value: s, child: Text(l.productionStatus(s))),
            ],
            onChanged: (s) {
              setState(() => _status = s);
              _list.currentState?.reload();
            },
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: _division,
            hint: Text(l.productionDivision),
            items: [
              DropdownMenuItem(value: null, child: Text(l.productionDivision)),
              for (final d in divisions)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (d) {
              setState(() => _division = d);
              _list.currentState?.reload();
            },
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          key: const ValueKey('to-release'),
          icon: const Icon(AppIcons.outbox),
          label: Text(l.productionToRelease),
          onPressed: () async {
            await context.push('/production/release');
            _list.currentState?.reload();
          },
        ),
        if (perms.contains('production.admin'))
          TutorialTarget(id: 'production-divisions', child: IconButton(
            key: const ValueKey('divisions'),
            tooltip: l.productionDivisions,
            icon: const Icon(AppIcons.settings),
            onPressed: () => context.push('/production/divisions'),
          )),
      ],
      onCreate: perms.contains('production.write') ? _buildForStock : null,
      createTargetId: 'production-build',
      createLabel: l.productionBuildForStock,
      columns: [
        EntityColumn(l.number, (o) => o.number, flex: 2),
        EntityColumn(
          l.product,
          (o) => '${o.productCode} · ${o.productName}',
          flex: 4,
        ),
        EntityColumn(
          l.quantity,
          (o) => '${number(o.quantity)} ${o.unit}',
          numeric: true,
          flex: 2,
        ),
        EntityColumn(
          l.order,
          (o) => [
            o.orderNumber,
            o.customerName,
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          flex: 4,
        ),
        EntityColumn(l.priority, (o) => l.orderPriority(o.priority), flex: 2),
        EntityColumn(
          l.productionDivision,
          (o) => o.divisionName ?? '',
          flex: 2,
        ),
        EntityColumn(
          l.productionPlannedReady,
          (o) => date(o.plannedReadyDate),
          flex: 2,
        ),
        EntityColumn(
          l.status,
          (o) =>
              l.productionStatus(o.status) +
              (o.shortComponents > 0 ? ' · ${l.productionShort}' : ''),
          flex: 3,
          cell: (context, o) => Row(
            children: [
              Flexible(child: Text(l.productionStatus(o.status))),
              if (o.shortComponents > 0 || o.orderCancelled) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: o.orderCancelled
                      ? l.productionOrderCancelled
                      : l.productionShort,
                  child: Icon(
                    AppIcons.warningAmber,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      locationOf: (o) => '/production/${o.id}',
      onOpen: (o) async =>
          await context.push<bool>('/production/${o.id}') ?? true,
    );
  }
}

/// Creates a production order to build a product for stock.
class _StockOrderDialog extends ConsumerStatefulWidget {
  const _StockOrderDialog();

  @override
  ConsumerState<_StockOrderDialog> createState() => _StockOrderDialogState();
}

class _StockOrderDialogState extends ConsumerState<_StockOrderDialog> {
  Product? _product;
  final _quantity = TextEditingController(text: '1');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = parseDecimalInput(_quantity.text);
    if (_product == null || quantity == null) {
      setState(() => _error = context.l10n.productionBuildForStock);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final po = await ref
          .read(apiProvider)
          .production
          .release(
            body: ReleaseProductionInput(
              productId: _product!.id,
              quantity: quantity,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      context.push('/production/${po.id}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.productionBuildForStock),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchPicker<Product>(
              label: l.product,
              display: (p) => '${p.code} · ${p.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .products
                          .listProducts(q: q, limit: 20))
                      .items
                      .where(
                        (p) =>
                            p.productType == 'manufactured' ||
                            p.productType == 'configurable',
                      )
                      .toList(),
              onSelected: (p) => setState(() => _product = p),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('stock-quantity'),
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l.quantity),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TutorialTarget(id: 'production-build-save', child: FilledButton(
          key: const ValueKey('stock-save'),
          onPressed: _saving ? null : _save,
          child: Text(l.productionRelease),
        )),
      ],
    );
  }
}
