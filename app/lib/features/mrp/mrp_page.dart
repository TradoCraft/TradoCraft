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
const _statuses = ['open', 'converted', 'dismissed', 'all'];

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
  Future<List<MrpProposal>>? _proposals;
  Future<List<MrpRun>>? _runs;

  Future<List<MrpProposal>> _loadProposals() =>
      ref.read(apiProvider).mrp.listProposals(status: _status, kind: _kind);

  void _reload() {
    setState(() {
      _proposals = _loadProposals();
      _runs = ref.read(apiProvider).mrp.listRuns();
    });
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
      _ => l.mrpStatusAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final canRun = perms.contains('production.write');
    _proposals ??= _loadProposals();
    _runs ??= ref.read(apiProvider).mrp.listRuns();
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
          Expanded(
            child: FutureBuilder<List<MrpProposal>>(
              future: _proposals,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(errorMessage(s.error!)),
                        TextButton(onPressed: _reload, child: Text(l.retry)),
                      ],
                    ),
                  );
                }
                if (s.connectionState != ConnectionState.done || !s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = s.data!;
                if (list.isEmpty) {
                  return Center(child: Text(l.mrpEmpty));
                }
                return ListView.separated(
                  key: const ValueKey('mrp-list'),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _tile(context, list[i], perms),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _peg(AppLocalizations l, Map<String, dynamic> p) {
    final number = '${p['number']}';
    return switch (p['kind']) {
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
    final pegs =
        (p.pegging as List?)
            ?.map((e) => _peg(l, Map<String, dynamic>.from(e as Map)))
            .toSet()
            .toList() ??
        const <String>[];
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
