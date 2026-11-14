import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/photos.dart';
import 'repairs_page.dart' show departmentsProvider;
import '../../shared/app_icons.dart';
import '../packages/repair_packages_section.dart';
import 'repair_findings_section.dart';
import 'repair_warranty_section.dart';

final _when = DateFormat('dd/MM/yyyy HH:mm');

/// One repair: where it is in the workflow and the actions that make sense now, photos, internal
/// notes and the history. The server decides what is allowed; the buttons only offer what fits.
class RepairScreen extends ConsumerStatefulWidget {
  const RepairScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RepairScreen> createState() => _RepairScreenState();
}

class _RepairScreenState extends ConsumerState<RepairScreen> {
  RepairDetail? _d;
  String? _error;
  bool _busy = false;
  final _note = TextEditingController();

  RepairsClient get _repairs => ref.read(apiProvider).repairs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repairs.getRepair(id: widget.id);
      if (mounted) {
        TabScope.reportTitle(context, d.repair.number);
        setState(() => _d = d);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _run(
    Future<RepairDetail> Function() action, {
    String? success,
  }) async {
    setState(() => _busy = true);
    RepairDetail? d;
    final ok = await runAction(
      context,
      () async => d = await action(),
      success: success,
    );
    if (mounted) setState(() => _busy = false);
    if (ok && d != null && mounted) setState(() => _d = d);
  }

  Future<void> _status(String status, {bool askNote = false}) async {
    var note = '';
    if (askNote) {
      final l = context.l10n;
      final n = await askText(
        context,
        title: l.repairStatus(status),
        label: l.notes,
      );
      if (n == null || !mounted) return;
      note = n;
    }
    await _run(
      () => _repairs.setRepairStatus(
        id: widget.id,
        body: StatusInput(status: status, note: note),
      ),
    );
  }

  Future<void> _route() async {
    final input = await showDialog<RouteInput>(
      context: context,
      builder: (_) => RouteDialog(current: _d!.repair.departmentId),
    );
    if (input == null || !mounted) return;
    await _run(
      () => _repairs.routeRepair(id: widget.id, body: input),
      success: context.l10n.saved,
    );
    ref.invalidate(departmentsProvider);
  }

  Future<void> _addNote() async {
    if (_note.text.trim().isEmpty) return;
    await _run(
      () => _repairs.addRepairNote(
        id: widget.id,
        body: RepairNoteInput(note: _note.text.trim()),
      ),
    );
    _note.clear();
  }

  Future<void> _addPhotos(List<PickedPhoto> photos) async {
    final dio = ref.read(dioProvider);
    for (final p in photos) {
      await uploadPhoto(dio, '/api/v1/repairs/${widget.id}/photos', p);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final d = _d;
    if (d == null) {
      return Scaffold(
        body: Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final r = d.repair;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = perms.contains('repairs.write');
    final canRoute = perms.contains('repairs.route');
    final open = !['shipped', 'cancelled'].contains(r.status);

    Widget btn(
      String label,
      IconData icon,
      VoidCallback action, {
      bool primary = false,
    }) {
      final f = primary ? FilledButton.icon : OutlinedButton.icon;
      return f(
        onPressed: _busy ? null : action,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    final actions = <Widget>[
      if (canWrite) ...[
        if (r.status == 'announced')
          btn(
            l.markReceived,
            AppIcons.inventory2,
            () => _status('received'),
            primary: true,
          ),
        if (r.status == 'routed')
          btn(
            l.startWork,
            AppIcons.playArrow,
            () => _status('in_progress'),
            primary: true,
          ),
        if (r.status == 'in_progress') ...[
          btn(
            l.markCompleted,
            AppIcons.checkCircle,
            () => _status('completed', askNote: true),
            primary: true,
          ),
          btn(
            l.markWaitingParts,
            AppIcons.hourglassEmpty,
            () => _status('waiting_parts', askNote: true),
          ),
          btn(
            l.markWaitingCustomer,
            AppIcons.person,
            () => _status('waiting_customer', askNote: true),
          ),
        ],
        if (r.status == 'waiting_parts' ||
            r.status == 'waiting_customer' ||
            r.status == 'completed')
          btn(l.backIntoWork, AppIcons.undo, () => _status('in_progress')),
        if (r.status == 'completed')
          btn(
            l.markShipped,
            AppIcons.localShipping,
            () => _status('shipped'),
            primary: true,
          ),
        if (r.status == 'routed')
          btn(
            l.sendBackToTriage,
            AppIcons.callSplit,
            () => _status('received', askNote: true),
          ),
        if ([
          'announced',
          'received',
          'routed',
          'in_progress',
        ].contains(r.status))
          btn(
            l.cancelRepair,
            AppIcons.cancel,
            () => _status('cancelled', askNote: true),
          ),
      ],
      if (canRoute &&
          [
            'received',
            'routed',
            'in_progress',
            'waiting_customer',
            'waiting_parts',
          ].contains(r.status))
        btn(
          l.routeRepair,
          AppIcons.accountTree,
          _route,
          primary: r.status == 'received',
        ),
    ];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.canPop()
                    ? context.pop(true)
                    : context.go('/repairs'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Expanded(
                child: Text(
                  '${r.number}  ${r.customerName}',
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Chip(label: Text(l.repairStatus(r.status))),
            ],
          ),
          if (r.status == 'announced')
            MaterialBanner(
              leading: const Icon(AppIcons.schedule),
              content: Text(l.repairAnnouncedByTicket),
              actions: const [SizedBox.shrink()],
            ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              InfoItem(l.customer, r.customerName),
              InfoItem(l.contactPerson, r.contactName ?? ''),
              InfoItem(
                l.productDescription,
                [
                  if (r.productCode != null) r.productCode!,
                  r.productDescription,
                ].where((e) => e.isNotEmpty).join(' · '),
              ),
              InfoItem(l.serialNumber, r.serialNumber),
              InfoItem(l.customerReference, r.customerReference),
              InfoItem(l.warranty, l.warrantyLabel(r.warranty)),
              InfoItem(l.priority, l.ticketPriority(r.priority)),
              InfoItem(l.department, r.departmentName ?? l.notRouted),
              InfoItem(l.owner, r.assignedName ?? ''),
              if (r.receivedAt != null)
                InfoItem(
                  l.repairStatusReceived,
                  _when.format(r.receivedAt!.toLocal()),
                ),
            ],
          ),
          if (r.ticketId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(AppIcons.supportAgent),
                label: Text(r.ticketNumber ?? l.helpdesk),
                onPressed: () => context.push('/helpdesk/${r.ticketId}'),
              ),
            ),
          const SizedBox(height: 4),
          Text(l.faultDescription, style: theme.textTheme.labelMedium),
          SelectableText(r.faultDescription),
          if (actions.isNotEmpty && open) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (can(ref, 'packages.read')) ...[
            const Divider(height: 32),
            RepairPackagesSection(
              key: ValueKey('packages-${r.status}'),
              repair: r,
              onChanged: _load,
            ),
          ],
          const Divider(height: 32),
          RepairFindingsSection(
            key: ValueKey('findings-${r.findings}-${r.diagnosis}'),
            repair: r,
            editable: canWrite && open,
            onChanged: (d) => setState(() => _d = d),
          ),
          const Divider(height: 32),
          RepairWarrantySection(
            repair: r,
            open: open,
            onChanged: (d) => setState(() => _d = d),
          ),
          const Divider(height: 32),
          PhotoGallery(
            photos: [
              for (final p in d.photos)
                PhotoItem(id: p.id, caption: p.caption, by: p.uploaderName),
            ],
            dio: ref.watch(dioProvider),
            pathFor: (id) => '/api/v1/repairs/${widget.id}/photos/$id',
            onAdd: canWrite && open ? _addPhotos : null,
          ),
          const Divider(height: 32),
          if (canWrite && open) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l.addNoteHint,
                      filled: true,
                      fillColor: Colors.amber.shade50,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _addNote,
                  child: Text(l.addNote),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text(l.history, style: theme.textTheme.titleSmall),
          for (final e in d.events.reversed) _EventTile(event: e),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final RepairEvent event;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final e = event;
    final (icon, text) = switch (e.kind) {
      'created' => (AppIcons.addCircle, l.repairStatus(e.toStatus ?? '')),
      'routed' => (
        AppIcons.accountTree,
        [
          if (e.fromDepartment != null) e.fromDepartment!,
          '→ ${e.toDepartment ?? ''}',
        ].join(' '),
      ),
      'status' => (
        AppIcons.flag,
        '${l.repairStatus(e.fromStatus ?? '')} → ${l.repairStatus(e.toStatus ?? '')}',
      ),
      'photo' => (AppIcons.photo, l.photos),
      'findings' => (AppIcons.notes, l.eventFindings),
      'serial_unit' => (AppIcons.link, l.eventSerialUnit),
      'warranty_auto' => (AppIcons.verified, l.eventWarrantyAuto),
      'warranty_manual' => (AppIcons.verified, l.eventWarrantyManual),
      'warranty_void' => (AppIcons.gppBad, l.eventWarrantyVoid),
      'warranty_void_removed' => (AppIcons.undo, l.eventWarrantyVoidRemoved),
      _ => (AppIcons.notes, ''),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(
        [
          text,
          if (e.note.isNotEmpty) e.note,
        ].where((s) => s.isNotEmpty).join(' — '),
      ),
      subtitle: Text('${e.actorName} · ${_when.format(e.createdAt.toLocal())}'),
    );
  }
}

/// Chooses the department (and, optionally, a colleague of it) and leaves a note for them.
class RouteDialog extends ConsumerStatefulWidget {
  const RouteDialog({super.key, this.current});
  final String? current;

  @override
  ConsumerState<RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends ConsumerState<RouteDialog> {
  String? _department;
  String? _assignee;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final all = ref.watch(departmentsProvider).value ?? const [];
    final active = all.where((d) => d.active).toList();
    Department? chosen;
    for (final d in active) {
      if (d.id == _department) chosen = d;
    }
    return AlertDialog(
      title: Text(l.routeRepair),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _department,
              decoration: InputDecoration(labelText: l.department),
              items: [
                for (final d in active)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text(
                      d.id == widget.current ? '${d.name} ✓' : d.name,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _department = v;
                _assignee = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              key: ValueKey('assignee-$_department'),
              initialValue: _assignee,
              decoration: InputDecoration(labelText: l.assignTo),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.unassigned),
                ),
                for (final m in chosen?.members ?? const <Member>[])
                  DropdownMenuItem<String?>(
                    value: m.userId,
                    child: Text(m.displayName),
                  ),
              ],
              onChanged: (v) => setState(() => _assignee = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.routeNote),
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
          onPressed: _department == null
              ? null
              : () => Navigator.pop(
                  context,
                  RouteInput(
                    departmentId: _department!,
                    assignedUserId: _assignee,
                    note: _note.text.trim(),
                  ),
                ),
          child: Text(l.routeRepair),
        ),
      ],
    );
  }
}
