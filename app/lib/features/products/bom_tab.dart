import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../production/cost_rollup_dialog.dart';
import '../production/work_centres_page.dart' show workCentresProvider;
import '../tutorial/targets.dart';

/// An editable operation of the routing of a draft BOM revision.
class _EditOp {
  _EditOp({
    required this.centreId,
    String name = '',
    String setup = '0',
    String run = '0',
    this.notes = '',
  }) : name = TextEditingController(text: name),
       setup = TextEditingController(text: setup),
       run = TextEditingController(text: run);

  String? centreId;
  final TextEditingController name;
  final TextEditingController setup;
  final TextEditingController run;
  final String notes;
}

/// An editable line of a draft BOM.
class _EditLine {
  _EditLine({
    required this.productId,
    required this.code,
    required this.name,
    required this.unit,
    String quantity = '1',
    String scrap = '0',
  }) : quantity = TextEditingController(text: quantity),
       scrap = TextEditingController(text: scrap);

  final String productId;
  final String code;
  final String name;
  final String unit;
  final TextEditingController quantity;
  final TextEditingController scrap;
}

/// Bill of materials of a product: revisions, editing the draft, activation and explosion.
class BomTab extends ConsumerStatefulWidget {
  const BomTab({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<BomTab> createState() => _BomTabState();
}

class _BomTabState extends ConsumerState<BomTab> {
  List<BomSummary> _revisions = [];
  Bom? _bom;
  final List<_EditLine> _lines = [];

  /// The routing of the revision that is shown (loaded when the user may see production).
  final List<_EditOp> _ops = [];
  bool _routingDirty = false;
  final _notes = TextEditingController();
  final _explodeQty = TextEditingController(text: '1');
  Explosion? _explosion;
  bool _loading = true;
  String? _error;

  TradocraftApi get _api => ref.read(apiProvider);
  bool get _isDraft => _bom?.status == 'draft';
  Set<String> get _perms =>
      ref.read(meProvider).value?.permissions.toSet() ?? const {};
  bool get _canSeeRouting => _perms.contains('production.read');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? select}) async {
    setState(() => _loading = true);
    try {
      final revisions = await _api.engineering.listBoms(id: widget.product.id);
      final active = revisions.where((b) => b.status == 'active').firstOrNull;
      final id = select ?? active?.id ?? revisions.firstOrNull?.id;
      final bom = id == null ? null : await _api.engineering.getBom(id: id);
      setState(() {
        _revisions = revisions;
        _setBom(bom);
        _error = null;
      });
      if (bom != null) await _loadRouting(bom.id);
      if (active != null && _explosion == null) await _explode();
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Loads the routing of a revision for those who may see production (waits for the permissions
  /// when they have not arrived yet). A routing that cannot be read is shown as empty.
  Future<void> _loadRouting(String bomId) async {
    try {
      final me = await ref.read(meProvider.future);
      if (!me.permissions.contains('production.read')) return;
      final r = await _api.production.getRouting(id: bomId);
      if (!mounted || _bom?.id != bomId) return;
      setState(() {
        _ops
          ..clear()
          ..addAll(
            r.operations.map(
              (o) => _EditOp(
                centreId: o.workCentreId,
                name: o.name,
                setup: o.setupMinutes.toString(),
                run: number(o.runMinutesPerUnit),
                notes: o.notes,
              ),
            ),
          );
        _routingDirty = false;
      });
    } catch (_) {
      if (mounted && _bom?.id == bomId) setState(() => _ops.clear());
    }
  }

  void _setBom(Bom? bom) {
    // The routing belongs to the revision: it stays when the same revision is shown again (after
    // a save) and is loaded when another one is.
    if (bom?.id != _bom?.id) {
      _ops.clear();
      _routingDirty = false;
    }
    _bom = bom;
    _notes.text = bom?.notes ?? '';
    _lines
      ..clear()
      ..addAll(
        (bom?.lines ?? const []).map(
          (l) => _EditLine(
            productId: l.componentProductId,
            code: l.componentCode,
            name: l.componentName,
            unit: l.componentUnit,
            quantity: number(l.quantity),
            scrap: number(l.scrapPercent),
          ),
        ),
      );
  }

  Future<void> _select(String id) async {
    final bom = await _api.engineering.getBom(id: id);
    setState(() => _setBom(bom));
    await _loadRouting(bom.id);
  }

  Future<void> _newRevision() async {
    Bom? created;
    final ok = await runAction(context, () async {
      created = await _api.engineering.createBom(
        id: widget.product.id,
        body: const NewBomInput(),
      );
    });
    if (ok) await _load(select: created!.id);
  }

  Future<bool> _saveDraft() async {
    final lines = <BomLineInput>[];
    for (final (i, l) in _lines.indexed) {
      final q = parseDecimalInput(l.quantity.text);
      final s = parseDecimalInput(l.scrap.text.isEmpty ? '0' : l.scrap.text);
      if (q == null || s == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.enterValidNumbersLine(i + 1))),
        );
        return false;
      }
      lines.add(
        BomLineInput(
          componentProductId: l.productId,
          quantity: q,
          scrapPercent: s,
        ),
      );
    }
    // The routing is part of the revision: saved first, so a routing that is refused leaves the
    // lines as they were and nothing is lost on screen.
    if (_isDraft && _routingDirty && _perms.contains('bom.write')) {
      if (!await _saveRouting()) return false;
      if (!mounted) return false;
    }
    Bom? saved;
    final ok = await runAction(
      context,
      () async => saved = await _api.engineering.updateBom(
        id: _bom!.id,
        body: BomInput(notes: _notes.text, lines: lines),
      ),
      success: context.l10n.draftSaved,
    );
    if (ok) setState(() => _setBom(saved));
    return ok;
  }

  Future<bool> _saveRouting() async {
    final ops = <RoutingOperationInput>[];
    for (final (i, o) in _ops.indexed) {
      final setup = int.tryParse(
        o.setup.text.trim().isEmpty ? '0' : o.setup.text.trim(),
      );
      final run = parseDecimalInput(o.run.text.isEmpty ? '0' : o.run.text);
      if (setup == null ||
          run == null ||
          o.centreId == null ||
          o.name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.enterValidNumbersLine(i + 1))),
        );
        return false;
      }
      ops.add(
        RoutingOperationInput(
          name: o.name.text.trim(),
          workCentreId: o.centreId!,
          setupMinutes: setup,
          runMinutesPerUnit: run,
          notes: o.notes,
        ),
      );
    }
    final ok = await runAction(
      context,
      () => _api.production.setRouting(
        id: _bom!.id,
        body: BomRoutingInput(operations: ops),
      ),
    );
    if (ok) _routingDirty = false;
    return ok;
  }

  Future<void> _activate() async {
    if (!await _saveDraft()) return;
    if (!mounted) return;
    final ok = await runAction(
      context,
      () => _api.engineering.activateBom(id: _bom!.id),
      success: context.l10n.revisionActivated,
    );
    if (ok) {
      _explosion = null;
      await _load(select: _bom!.id);
    }
  }

  Future<void> _explode() async {
    final q = parseDecimalInput(_explodeQty.text);
    if (q == null) return;
    try {
      final e = await _api.engineering.explodeBom(
        id: widget.product.id,
        quantity: q,
      );
      setState(() => _explosion = e);
    } catch (e) {
      setState(() => _explosion = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bom == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('bom.write') ?? false;
    final theme = Theme.of(context);
    final hasDraft = _revisions.any((r) => r.status == 'draft');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_revisions.isEmpty) Text(context.l10n.noBom),
            if (_revisions.isNotEmpty)
              DropdownButton<String>(
                value: _bom?.id,
                items: [
                  for (final r in _revisions)
                    DropdownMenuItem(
                      value: r.id,
                      child: Text(
                        context.l10n.revisionItem(
                          r.revision,
                          context.l10n.bomStatus(r.status),
                          r.lineCount,
                        ),
                      ),
                    ),
                ],
                onChanged: (id) => id == null ? null : _select(id),
              ),
            if (canWrite && !hasDraft)
              TutorialTarget(
                id: 'bom-new-revision',
                child: OutlinedButton.icon(
                  onPressed: _newRevision,
                  icon: const Icon(AppIcons.add),
                  label: Text(context.l10n.newRevision),
                ),
              ),
            if (_perms.contains('inventory.cost') &&
                _canSeeRouting &&
                _revisions.any((r) => r.status == 'active'))
              OutlinedButton.icon(
                key: const ValueKey('cost-rollup'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CostRollupDialog(product: widget.product),
                ),
                icon: const Icon(AppIcons.calculate),
                label: Text(context.l10n.productionCostRollup),
              ),
            if (canWrite && _isDraft) ...[
              OutlinedButton.icon(
                onPressed: _saveDraft,
                icon: const Icon(AppIcons.save),
                label: Text(context.l10n.saveDraft),
              ),
              TutorialTarget(
                id: 'bom-activate',
                child: FilledButton.icon(
                  onPressed: _activate,
                  icon: const Icon(AppIcons.check),
                  label: Text(context.l10n.activate),
                ),
              ),
            ],
          ],
        ),
        if (_bom != null) ...[
          const SizedBox(height: 8),
          if (!_isDraft)
            Text(
              _bom!.status == 'active'
                  ? 'Active since ${date(_bom!.activatedAt)}. Changes go through a new revision.'
                  : context.l10n.obsoleteRevision,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          _linesTable(theme, editable: canWrite && _isDraft),
          if (canWrite && _isDraft) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 420,
                child: TutorialTarget(
                  id: 'bom-add-component',
                  child: SearchPicker<Product>(
                    label: context.l10n.addComponent,
                    clearOnSelect: true,
                    display: (p) => '${p.code} · ${p.name}',
                    search: (q) async =>
                        (await _api.products.listProducts(
                              q: q,
                              active: true,
                              limit: 20,
                            )).items
                            .where(
                              (p) =>
                                  p.id != widget.product.id &&
                                  p.productType != 'service',
                            )
                            .toList(),
                    onSelected: (p) => setState(
                      () => _lines.add(
                        _EditLine(
                          productId: p.id,
                          code: p.code,
                          name: p.name,
                          unit: p.unit,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: context.l10n.revisionNotes,
              ),
            ),
          ],
        ],
        if (_bom != null && _canSeeRouting)
          ..._routingSection(theme, editable: canWrite && _isDraft),
        const Divider(height: 40),
        Text(
          context.l10n.materialRequirements,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _explodeQty,
                decoration: InputDecoration(
                  labelText: context.l10n.quantity,
                  suffixText: widget.product.unit,
                ),
                onSubmitted: (_) => _explode(),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _explode,
              child: Text(context.l10n.explode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_explosion == null)
          Text(context.l10n.noActiveBom)
        else
          _explosionView(theme, _explosion!),
      ],
    );
  }

  /// The routing of the revision: operations in order, each on a work centre. Editable on a
  /// draft by whoever may edit BOMs; saved together with the lines.
  List<Widget> _routingSection(ThemeData theme, {required bool editable}) {
    final l = context.l10n;
    final centres =
        ref.watch(workCentresProvider).value ?? const <WorkCentre>[];
    String centreLabel(String? id) {
      final c = centres.where((w) => w.id == id).firstOrNull;
      return c == null ? '' : '${c.code} · ${c.name}';
    }

    return [
      const Divider(height: 40),
      Text(l.productionRouting, style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      if (_ops.isEmpty && !editable)
        Text(l.productionRoutingNone, style: theme.textTheme.bodySmall)
      else if (_ops.isNotEmpty)
        Table(
          columnWidths: const {
            0: FixedColumnWidth(40),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(220),
            3: FixedColumnWidth(110),
            4: FixedColumnWidth(130),
            5: FixedColumnWidth(144),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final h in [
                  '#',
                  l.productionRoutingOperation,
                  l.productionWorkCentres,
                  l.productionRoutingSetup,
                  l.productionRoutingRun,
                  '',
                ])
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(h, style: theme.textTheme.labelLarge),
                  ),
              ],
            ),
            for (final (i, o) in _ops.indexed)
              TableRow(
                key: ObjectKey(o),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text('${i + 1}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: editable
                        ? TextField(
                            key: ValueKey('op-name-$i'),
                            controller: o.name,
                            onChanged: (_) => _routingDirty = true,
                          )
                        : Text(o.name.text),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: editable
                        ? DropdownButton<String>(
                            key: ValueKey('op-centre-$i'),
                            isExpanded: true,
                            value: centres.any((w) => w.id == o.centreId)
                                ? o.centreId
                                : null,
                            items: [
                              for (final w in centres.where(
                                (w) => w.active || w.id == o.centreId,
                              ))
                                DropdownMenuItem(
                                  value: w.id,
                                  enabled: w.active || w.id == o.centreId,
                                  child: Text('${w.code} · ${w.name}'),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              o.centreId = v;
                              _routingDirty = true;
                            }),
                          )
                        : Text(centreLabel(o.centreId)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: editable
                        ? TextField(
                            key: ValueKey('op-setup-$i'),
                            controller: o.setup,
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _routingDirty = true,
                          )
                        : Text(o.setup.text, textAlign: TextAlign.right),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: editable
                        ? TextField(
                            key: ValueKey('op-run-$i'),
                            controller: o.run,
                            textAlign: TextAlign.right,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => _routingDirty = true,
                          )
                        : Text(o.run.text, textAlign: TextAlign.right),
                  ),
                  editable
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('op-up-$i'),
                              tooltip: l.moveUp,
                              onPressed: i == 0
                                  ? null
                                  : () => setState(() {
                                      _ops.insert(i - 1, _ops.removeAt(i));
                                      _routingDirty = true;
                                    }),
                              icon: const Icon(AppIcons.arrowUpward),
                            ),
                            IconButton(
                              key: ValueKey('op-down-$i'),
                              tooltip: l.moveDown,
                              onPressed: i == _ops.length - 1
                                  ? null
                                  : () => setState(() {
                                      _ops.insert(i + 1, _ops.removeAt(i));
                                      _routingDirty = true;
                                    }),
                              icon: const Icon(AppIcons.arrowDownward),
                            ),
                            IconButton(
                              key: ValueKey('op-remove-$i'),
                              tooltip: l.remove,
                              onPressed: () => setState(() {
                                _ops.removeAt(i);
                                _routingDirty = true;
                              }),
                              icon: const Icon(AppIcons.close),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ],
              ),
          ],
        ),
      if (editable) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('add-operation'),
            onPressed: centres.where((w) => w.active).isEmpty
                ? null
                : () => setState(() {
                    _ops.add(
                      _EditOp(
                        centreId: centres.firstWhere((w) => w.active).id,
                      ),
                    );
                    _routingDirty = true;
                  }),
            icon: const Icon(AppIcons.add),
            label: Text(l.productionRoutingAddOperation),
          ),
        ),
        if (centres.where((w) => w.active).isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.productionRoutingNoWorkCentres,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    ];
  }

  Widget _linesTable(ThemeData theme, {required bool editable}) {
    final bom = _bom!;
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(40),
        1: FixedColumnWidth(130),
        2: FlexColumnWidth(),
        3: FixedColumnWidth(130),
        4: FixedColumnWidth(110),
        5: FixedColumnWidth(48),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (final h in [
              '#',
              context.l10n.component,
              context.l10n.description,
              context.l10n.quantity,
              context.l10n.scrapPercent,
              '',
            ])
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(h, style: theme.textTheme.labelLarge),
              ),
          ],
        ),
        for (final (i, l) in _lines.indexed)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text('${i + 1}'),
              ),
              Padding(padding: const EdgeInsets.all(6), child: Text(l.code)),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Flexible(child: Text(l.name)),
                    if (!editable &&
                        bom.lines.elementAtOrNull(i)?.componentHasBom == true)
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Chip(label: Text(context.l10n.subassembly)),
                      ),
                    if (!editable &&
                        bom.lines.elementAtOrNull(i)?.componentTracking ==
                            'serial')
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Chip(label: Text(context.l10n.serial)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: editable
                    ? TextField(
                        controller: l.quantity,
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(suffixText: l.unit),
                      )
                    : Text(
                        '${l.quantity.text} ${l.unit}',
                        textAlign: TextAlign.right,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: editable
                    ? TextField(controller: l.scrap, textAlign: TextAlign.right)
                    : Text(
                        l.scrap.text == '0' ? '' : '${l.scrap.text} %',
                        textAlign: TextAlign.right,
                      ),
              ),
              editable
                  ? IconButton(
                      tooltip: context.l10n.removeLine,
                      onPressed: () => setState(() => _lines.removeAt(i)),
                      icon: const Icon(AppIcons.close),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
      ],
    );
  }

  Widget _explosionView(ThemeData theme, Explosion e) => Wrap(
    spacing: 32,
    runSpacing: 16,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Structure (revision ${e.bomRevision})',
              style: theme.textTheme.labelLarge,
            ),
            for (final n in e.nodes)
              Padding(
                padding: EdgeInsets.only(left: (n.level - 1) * 24.0, top: 4),
                child: Row(
                  children: [
                    Icon(
                      n.isLeaf ? AppIcons.circleOutlined : AppIcons.accountTree,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${n.code}  ${n.name}')),
                    Text('${number(n.requiredQuantity)} ${n.unit}'),
                  ],
                ),
              ),
          ],
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.totalsToBuyOrMake,
              style: theme.textTheme.labelLarge,
            ),
            for (final r in e.requirements)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${r.code}  ${r.name}')),
                    Text('${number(r.quantity)} ${r.unit}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
