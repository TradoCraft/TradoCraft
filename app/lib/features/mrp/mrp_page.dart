import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';

/// How far ahead a run plans, in days.
const mrpHorizons = [30, 90, 180];

/// The statuses of the filter: the open proposals first.
const _statuses = ['open', 'converted', 'dismissed', 'superseded', 'all'];

/// How many proposals a page holds.
const mrpPageSize = 100;

/// The proposals of the material requirements planning (ADR 0091): what to buy and what to build,
/// by the day to order. A planner runs the planning, then turns a proposal into a draft purchase
/// order or a released production order, or sets it aside.
class MrpPage extends ConsumerStatefulWidget {
  const MrpPage({super.key});

  @override
  ConsumerState<MrpPage> createState() => _MrpPageState();
}

class _MrpPageState extends ConsumerState<MrpPage> {
  String _status = 'open';
  String? _kind;
  int _horizon = 90;
  bool _busy = false;
  List<MrpProposal> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  // A reload that overtakes a page still on its way: the late page is dropped.
  int _token = 0;
  Future<List<MrpRun>>? _runs;
  bool _started = false;

  /// The first page of the list for the current filters; what was shown is cleared, so the old
  /// filter's proposals are never under the new filter's name.
  Future<void> _loadFirst() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _items = const [];
      _hasMore = false;
    });
    try {
      final page = await ref
          .read(apiProvider)
          .mrp
          .listProposals(status: _status, kind: _kind, limit: mrpPageSize);
      if (!mounted || token != _token) return;
      setState(() {
        _items = page;
        _hasMore = page.length == mrpPageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The next page: after the last proposal shown, with the same filters.
  Future<void> _loadMore() async {
    if (_loadingMore || _items.isEmpty) return;
    final token = _token;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(apiProvider)
          .mrp
          .listProposals(
            status: _status,
            kind: _kind,
            limit: mrpPageSize,
            after: _items.last.id,
          );
      if (!mounted || token != _token) return;
      setState(() {
        _items = [..._items, ...page];
        _hasMore = page.length == mrpPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e;
        _loadingMore = false;
      });
    }
  }

  void _reload() {
    _runs = ref.read(apiProvider).mrp.listRuns();
    _loadFirst();
  }

  Future<void> _run() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final run = await ref
          .read(apiProvider)
          .mrp
          .startRun(body: MrpRunInput(horizonDays: _horizon));
      messenger?.showSnackBar(
        SnackBar(content: Text(l.mrpRunDone('${run.proposals}'))),
      );
      if (mounted) {
        _status = 'open';
        _reload();
      }
    } on DioException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _chooseSupplier() async {
    final l = context.l10n;
    final suppliers = await ref
        .read(apiProvider)
        .purchasing
        .listSuppliers(activeOnly: true);
    if (!mounted) return null;
    String? picked;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(l.mrpChooseSupplier),
          content: DropdownButton<String>(
            key: const ValueKey('mrp-supplier'),
            isExpanded: true,
            value: picked,
            hint: Text(l.mrpNoSupplier),
            items: [
              for (final s in suppliers)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setInner(() => picked = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: picked == null
                  ? null
                  : () => Navigator.pop(ctx, picked),
              child: Text(l.mrpConvert),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _convert(MrpProposal p) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      String? supplier;
      if (p.kind == 'purchase' && p.supplierId == null) {
        supplier = await _chooseSupplier();
        if (supplier == null || !mounted) return;
      }
      final r = await ref
          .read(apiProvider)
          .mrp
          .convertProposal(
            id: p.id,
            body: MrpConvertInput(supplierId: supplier),
          );
      messenger?.showSnackBar(
        SnackBar(content: Text(l.mrpConverted(r.number))),
      );
      if (mounted) _reload();
    } on DioException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _dismiss(MrpProposal p) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(apiProvider).mrp.dismissProposal(id: p.id);
      messenger?.showSnackBar(SnackBar(content: Text(l.mrpDismissed)));
      if (mounted) _reload();
    } on DioException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  String _statusLabel(String s) {
    final l = context.l10n;
    return switch (s) {
      'open' => l.mrpStatusOpen,
      'converted' => l.mrpStatusConverted,
      'dismissed' => l.mrpStatusDismissed,
      'superseded' => l.mrpStatusSuperseded,
      _ => l.mrpStatusAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final canRun = perms.contains('production.write');
    if (!_started) {
      _started = true;
      _runs = ref.read(apiProvider).mrp.listRuns();
      // After the first frame: loading starts with a state change.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFirst();
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.mrpTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canRun) ...[
                  SegmentedButton<int>(
                    key: const ValueKey('mrp-horizon'),
                    showSelectedIcon: false,
                    segments: [
                      for (final d in mrpHorizons)
                        ButtonSegment(
                          value: d,
                          label: Text(l.mrpHorizon('$d')),
                        ),
                    ],
                    selected: {_horizon},
                    onSelectionChanged: (v) =>
                        setState(() => _horizon = v.first),
                  ),
                  FilledButton(
                    key: const ValueKey('mrp-run'),
                    onPressed: _busy ? null : _run,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.mrpRun),
                  ),
                ],
                DropdownButton<String>(
                  key: const ValueKey('mrp-status'),
                  value: _status,
                  items: [
                    for (final s in _statuses)
                      DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                  ],
                  onChanged: (v) {
                    _status = v!;
                    _reload();
                  },
                ),
                DropdownButton<String?>(
                  key: const ValueKey('mrp-kind'),
                  value: _kind,
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.mrpStatusAll)),
                    DropdownMenuItem(
                      value: 'purchase',
                      child: Text(l.mrpKindPurchase),
                    ),
                    DropdownMenuItem(
                      value: 'production',
                      child: Text(l.mrpKindProduction),
                    ),
                  ],
                  onChanged: (v) {
                    _kind = v;
                    _reload();
                  },
                ),
                FutureBuilder<List<MrpRun>>(
                  future: _runs,
                  builder: (context, s) {
                    final runs = s.data;
                    return Text(
                      runs == null || runs.isEmpty
                          ? l.mrpNoRun
                          : l.mrpLastRun(runs.first.number),
                      key: const ValueKey('mrp-last-run'),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _body(context, perms)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Set<String> perms) {
    final l = context.l10n;
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage(_error!)),
            TextButton(onPressed: _reload, child: Text(l.retry)),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(child: Text(l.mrpEmpty));
    }
    return ListView.separated(
      key: const ValueKey('mrp-list'),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const ValueKey('mrp-more'),
                      onPressed: _loadMore,
                      child: Text(l.mrpLoadMore),
                    ),
            ),
          );
        }
        return _tile(context, _items[i], perms);
      },
    );
  }

  String _peg(AppLocalizations l, MrpPeg p) {
    final number = p.number;
    return switch (p.kind) {
      'sales_order' => l.mrpPegSales(number),
      'production_order' => l.mrpPegProduction(number),
      'purchase_order' => l.mrpPegPurchase(number),
      _ => l.mrpPegPlanned(number),
    };
  }

  Widget _tile(BuildContext context, MrpProposal p, Set<String> perms) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final fmt = DateFormat('EEE d MMM', locale);
    final scheme = Theme.of(context).colorScheme;
    final canAct = perms.contains(
      p.kind == 'purchase' ? 'purchasing.write' : 'production.write',
    );
    final pegs = p.pegging.map((e) => _peg(l, e)).toSet().toList();
    return ListTile(
      key: ValueKey('mrp-${p.id}'),
      leading: Icon(
        p.kind == 'purchase'
            ? Icons.shopping_cart_outlined
            : Icons.build_outlined,
        semanticLabel: p.kind == 'purchase'
            ? l.mrpKindPurchase
            : l.mrpKindProduction,
      ),
      title: Text('${p.productCode} · ${p.productName}'),
      subtitle: Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.mrpOrderBy(fmt.format(p.orderDate))),
          Text(l.mrpNeededOn(fmt.format(p.needDate))),
          if (p.supplierName != null) Text(p.supplierName!),
          Text(p.reason == 'demand' ? l.mrpReasonDemand : l.mrpReasonSafety),
          // What became of a proposal that is not open any more: converted, dismissed, or replaced
          // by a later run.
          if (p.status != 'open')
            Text(
              _statusLabel(p.status),
              key: ValueKey('mrp-status-${p.id}'),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (p.lateValue)
            Text(
              l.mrpLate,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (pegs.isNotEmpty) Text(pegs.take(3).join(' · ')),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.quantity,
            key: ValueKey('mrp-qty-${p.id}'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (p.status == 'open' && canAct) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: ValueKey('mrp-convert-${p.id}'),
              onPressed: () => _convert(p),
              child: Text(l.mrpConvert),
            ),
            IconButton(
              key: ValueKey('mrp-dismiss-${p.id}'),
              tooltip: l.mrpDismiss,
              icon: const Icon(Icons.close),
              onPressed: () => _dismiss(p),
            ),
          ],
        ],
      ),
      onTap: p.convertedTo == null
          ? null
          : () => context.push(
              p.kind == 'purchase'
                  ? '/purchase-orders/${p.convertedTo}'
                  : '/production/${p.convertedTo}',
            ),
    );
  }
}
