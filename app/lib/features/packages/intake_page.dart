import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../repairs/repair_screen.dart' show RouteDialog;
import '../repairs/repairs_page.dart' show departmentsProvider;
import 'link_dialogs.dart';
import 'receiving_page.dart' show PackageTile;

/// The triage queue of the people who open parcels: parcels to open, opened parcels to match with
/// a repair (or to turn into a new one), and received repairs to route to a department.
class IntakePage extends ConsumerStatefulWidget {
  const IntakePage({super.key});

  @override
  ConsumerState<IntakePage> createState() => _IntakePageState();
}

class _IntakePageState extends ConsumerState<IntakePage> {
  late Future<PackagePage> _toOpen;
  late Future<PackagePage> _toProcess;
  late Future<RepairPage> _toRoute;
  // The first row of the page shown in each queue; the API's total says how many there are.
  static const _pageSize = 100;
  int _openOffset = 0;
  int _processOffset = 0;
  int _routeOffset = 0;

  RepairsClient get _api => ref.read(apiProvider).repairs;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _toOpen = _api.listPackages(
      status: 'registered',
      limit: _pageSize,
      offset: _openOffset,
    );
    _toProcess = _api.listPackages(
      status: 'opened',
      limit: _pageSize,
      offset: _processOffset,
    );
    _toRoute = _api.listRepairs(
      status: 'received',
      limit: _pageSize,
      offset: _routeOffset,
    );
  }

  /// After an action the page may have emptied (the last row of it was handled): step back.
  void _clamp(int shown, int total, int offset, void Function(int) set) {
    if (shown == 0 && offset > 0 && total > 0) {
      final last = ((total - 1) ~/ _pageSize) * _pageSize;
      set(last < offset ? last : offset - _pageSize);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_reload);
      });
    }
  }

  Widget _pager(int offset, int shown, int total, void Function(int) go) {
    final l = context.l10n;
    if (total <= _pageSize && offset == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${offset + 1}–${offset + shown} / $total'),
          IconButton(
            tooltip: l.planningPrevious,
            icon: const Icon(AppIcons.chevronLeft),
            onPressed: offset > 0
                ? () => setState(() {
                    go(offset - _pageSize < 0 ? 0 : offset - _pageSize);
                    _reload();
                  })
                : null,
          ),
          IconButton(
            tooltip: l.planningNext,
            icon: const Icon(AppIcons.chevronRight),
            onPressed: offset + shown < total
                ? () => setState(() {
                    go(offset + _pageSize);
                    _reload();
                  })
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _open(Package p) async {
    final r = await showDialog<PackageOpenInput>(
      context: context,
      builder: (_) => _OpenDialog(pkg: p),
    );
    if (r == null || !mounted) return;
    await runAction(context, () => _api.openPackage(id: p.id, body: r));
    if (mounted) setState(_reload);
  }

  Future<void> _close(Package p) async {
    final l = context.l10n;
    final note = await askText(
      context,
      title: '${l.closeParcel} · ${p.number}',
      label: l.notes,
    );
    if (note == null || !mounted) return;
    if (note.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.noteRequired)));
      return;
    }
    await runAction(
      context,
      () => _api.closePackage(
        id: p.id,
        body: PackageCloseInput(note: note),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _link(Package p) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => LinkParcelDialog(pkg: p),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _route(Repair r) async {
    final input = await showDialog<RouteInput>(
      context: context,
      builder: (_) => RouteDialog(current: r.departmentId),
    );
    if (input == null || !mounted) return;
    await runAction(
      context,
      () => _api.routeRepair(id: r.id, body: input),
      success: context.l10n.saved,
    );
    ref.invalidate(departmentsProvider);
    if (mounted) setState(_reload);
  }

  Widget _packages(
    Future<PackagePage> future,
    int offset,
    void Function(int) go,
    List<Widget> Function(Package) actions,
  ) => FutureBuilder<PackagePage>(
    future: future,
    builder: (context, s) {
      if (s.hasError) return Center(child: Text(errorMessage(s.error!)));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final items = s.data!.items;
      _clamp(items.length, s.data!.total, offset, go);
      if (items.isEmpty) return Center(child: Text(context.l10n.nothingHere));
      return ListView(
        children: [
          _pager(offset, items.length, s.data!.total, go),
          for (final p in items)
            PackageTile(
              package: p,
              trailing: Wrap(spacing: 8, children: actions(p)),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canOpen = can(ref, 'packages.open');
    final canClose = can(ref, 'packages.write');
    final canIntake = can(ref, 'repairs.intake');
    final canRoute = can(ref, 'repairs.route');
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.packagesIntake),
          actions: [
            IconButton(
              tooltip: l.offlineReload,
              icon: const Icon(AppIcons.refresh),
              onPressed: () => setState(_reload),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l.toOpen),
              Tab(text: l.toProcess),
              Tab(text: l.toRoute),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _packages(
              _toOpen,
              _openOffset,
              (o) => _openOffset = o,
              (p) => [
                if (canOpen)
                  FilledButton.icon(
                    icon: const Icon(AppIcons.moveToInbox),
                    label: Text(l.openParcel),
                    onPressed: () => _open(p),
                  ),
                if (canClose)
                  OutlinedButton(
                    onPressed: () => _close(p),
                    child: Text(l.closeParcel),
                  ),
              ],
            ),
            _packages(
              _toProcess,
              _processOffset,
              (o) => _processOffset = o,
              (p) => [
                if (canIntake && p.kind == 'repair')
                  FilledButton.icon(
                    icon: const Icon(AppIcons.link),
                    label: Text(l.linkToRepair),
                    onPressed: () => _link(p),
                  ),
                if (canClose && canOpen)
                  OutlinedButton(
                    onPressed: () => _close(p),
                    child: Text(l.closeParcel),
                  ),
              ],
            ),
            FutureBuilder<RepairPage>(
              future: _toRoute,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(child: Text(errorMessage(s.error!)));
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = s.data!.items;
                _clamp(
                  items.length,
                  s.data!.total,
                  _routeOffset,
                  (o) => _routeOffset = o,
                );
                if (items.isEmpty) return Center(child: Text(l.nothingHere));
                return ListView(
                  children: [
                    _pager(
                      _routeOffset,
                      items.length,
                      s.data!.total,
                      (o) => _routeOffset = o,
                    ),
                    for (final r in items)
                      ListTile(
                        leading: const Icon(AppIcons.buildCircle),
                        title: Text('${r.number} · ${r.customerName}'),
                        subtitle: Text(
                          [
                            r.productDescription,
                            r.serialNumber,
                          ].where((e) => e.isNotEmpty).join(' · '),
                        ),
                        onTap: () => context.push('/repairs/${r.id}'),
                        trailing: canRoute
                            ? FilledButton.icon(
                                icon: const Icon(AppIcons.accountTree),
                                label: Text(l.routeRepair),
                                onPressed: () => _route(r),
                              )
                            : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Decides what the parcel is: a repair, something else, or to be sent back. The last two close it
/// at once, so they need a note.
class _OpenDialog extends StatefulWidget {
  const _OpenDialog({required this.pkg});
  final Package pkg;

  @override
  State<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<_OpenDialog> {
  String _kind = 'repair';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final needsNote = _kind != 'repair';
    final ok = !needsNote || _note.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text('${l.openParcel} · ${widget.pkg.number}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.parcelContents),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v ?? 'repair'),
              child: Column(
                children: [
                  for (final k in ['repair', 'other', 'return_to_sender'])
                    RadioListTile<String>(
                      key: ValueKey('kind-$k'),
                      value: k,
                      title: Text(l.packageKind(k)),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.notes,
                helperText: needsNote ? l.noteRequired : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: ok
              ? () => Navigator.pop(
                  context,
                  PackageOpenInput(kind: _kind, note: _note.text.trim()),
                )
              : null,
          child: Text(l.openParcel),
        ),
      ],
    );
  }
}
