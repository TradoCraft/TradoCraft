import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../helpdesk/ticket_screen.dart' show usersProvider;
import 'contracts_page.dart';
import '../../shared/app_icons.dart';

/// One visit template while it is being edited.
class _Tpl {
  _Tpl({
    this.id,
    String title = '',
    String instructions = '',
    List<String> tasks = const [],
    this.kind = 'maintenance',
    this.recurrence = 'months',
    int interval = 3,
    int lead = 14,
    int? minutes,
    Set<int>? months,
    DateTime? anchor,
    Set<String>? techs,
    this.active = true,
  }) : title = TextEditingController(text: title),
       instructions = TextEditingController(text: instructions),
       tasks = TextEditingController(text: tasks.join('\n')),
       interval = TextEditingController(text: '$interval'),
       lead = TextEditingController(text: '$lead'),
       minutes = TextEditingController(text: minutes?.toString() ?? ''),
       months = months ?? {},
       anchor = anchor ?? DateTime.now(),
       techs = techs ?? {};

  factory _Tpl.from(VisitTemplate t) => _Tpl(
    id: t.id,
    title: t.title,
    instructions: t.instructions,
    tasks: t.tasks,
    kind: t.kind,
    recurrence: t.recurrence,
    interval: t.intervalN,
    lead: t.leadDays,
    minutes: t.estimatedMinutes,
    months: t.months.toSet(),
    anchor: t.anchorDate,
    techs: t.technicians.map((x) => x.userId).toSet(),
    active: t.active,
  );

  final String? id;
  final TextEditingController title;
  final TextEditingController instructions;
  final TextEditingController tasks;
  final TextEditingController interval;
  final TextEditingController lead;
  final TextEditingController minutes;
  String kind;
  String recurrence;
  Set<int> months;
  DateTime anchor;
  Set<String> techs;
  bool active;

  void dispose() {
    for (final c in [title, instructions, tasks, interval, lead, minutes]) {
      c.dispose();
    }
  }

  TemplateInput toInput() => TemplateInput(
    id: id,
    title: title.text.trim(),
    instructions: instructions.text.trim(),
    kind: kind,
    recurrence: recurrence,
    intervalN: int.tryParse(interval.text.trim()) ?? 1,
    months: recurrence == 'months_list' ? (months.toList()..sort()) : [],
    anchorDate: anchor,
    leadDays: int.tryParse(lead.text.trim()) ?? 14,
    estimatedMinutes: int.tryParse(minutes.text.trim()),
    technicianIds: techs.toList(),
    tasks: tasks.text
        .split('\n')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(),
    active: active,
  );
}

/// A contract and its visit templates: create, edit, activate, suspend, end; with the visits that
/// are coming up and the jobs generated so far. [id] is null for a new contract.
class ContractScreen extends ConsumerStatefulWidget {
  const ContractScreen({super.key, this.id});
  final String? id;

  @override
  ConsumerState<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends ConsumerState<ContractScreen> {
  ContractDetail? _c;
  String? _error;
  bool _busy = false;
  int _generation = 0;

  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _response = TextEditingController();
  final _resolution = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime? _end;
  bool _autoRenew = false;
  String? _customerId;
  String? _customerName;
  final _equipmentIds = <String>{};
  List<CustomerEquipment> _units = [];
  final _templates = <_Tpl>[];

  FieldClient get _field => ref.read(apiProvider).field;
  bool get _isNew => widget.id == null;

  @override
  void initState() {
    super.initState();
    if (!_isNew) _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _notes, _response, _resolution]) {
      c.dispose();
    }
    for (final t in _templates) {
      t.dispose();
    }
    super.dispose();
  }

  void _fill(ContractDetail c) {
    _c = c;
    _title.text = c.title;
    _notes.text = c.notes;
    _response.text = c.responseHours?.toString() ?? '';
    _resolution.text = c.resolutionHours?.toString() ?? '';
    _start = c.startDate;
    _end = c.endDate;
    _autoRenew = c.autoRenew;
    _customerId = c.customerId;
    _customerName = c.customerName;
    _equipmentIds
      ..clear()
      ..addAll(c.equipment.map((e) => e.serialUnitId));
    for (final t in _templates) {
      t.dispose();
    }
    _templates
      ..clear()
      ..addAll(c.visitTemplates.map(_Tpl.from));
    _generation++;
  }

  Future<void> _load() async {
    try {
      final c = await _field.getContract(id: widget.id!);
      if (!mounted) return;
      setState(() => _fill(c));
      _loadUnits();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _loadUnits() async {
    final cid = _customerId;
    if (cid == null) return;
    try {
      final u = await _field.listCustomerEquipment(id: cid);
      if (mounted) setState(() => _units = u);
    } catch (_) {}
  }

  ContractInput _input() => ContractInput(
    customerId: _customerId!,
    title: _title.text.trim(),
    startDate: _start,
    endDate: _end,
    autoRenew: _autoRenew,
    responseHours: int.tryParse(_response.text.trim()),
    resolutionHours: int.tryParse(_resolution.text.trim()),
    notes: _notes.text.trim(),
    contactId: _c?.contactId,
    siteName: _c?.siteName,
    street: _c?.street,
    postalCode: _c?.postalCode,
    city: _c?.city,
    countryCode: _c?.countryCode,
    equipmentIds: _equipmentIds.toList(),
    visitTemplates: [for (final t in _templates) t.toInput()],
  );

  Future<void> _save() async {
    final l = context.l10n;
    if (_customerId == null || _title.text.trim().isEmpty) {
      setState(() => _error = '${l.customer} / ${l.title}');
      return;
    }
    if (_templates.any((t) => t.title.text.trim().isEmpty)) {
      setState(() => _error = l.visitTitleRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    ContractDetail? saved;
    final ok = await runAction(context, () async {
      saved = _isNew
          ? await _field.createContract(body: _input())
          : await _field.updateContract(id: widget.id!, body: _input());
    }, success: l.saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok || saved == null) return;
    if (_isNew) {
      context.pushReplacement('/jobs/contracts/${saved!.id}');
    } else {
      setState(() => _fill(saved!));
    }
  }

  Future<void> _status(
    Future<ContractDetail> Function(String id) action,
  ) async {
    ContractDetail? c;
    final ok = await runAction(
      context,
      () async => c = await action(widget.id!),
    );
    if (ok && c != null && mounted) setState(() => _fill(c!));
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final c = _c;
    if (!_isNew && c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final planner =
        ref.watch(meProvider).value?.permissions.contains('field.plan') ??
        false;
    final ended = c?.status == 'ended';
    final canEdit = planner && !ended;
    final users = (ref.watch(usersProvider).value ?? const <CompanyUser>[])
        .where((u) => u.roles.contains('technician'))
        .toList();
    const gap = SizedBox(height: 12, width: 12);

    Widget dateButton(
      String label,
      DateTime? v,
      ValueChanged<DateTime?> set, {
      bool clearable = false,
    }) {
      return Expanded(
        child: OutlinedButton(
          onPressed: canEdit
              ? () async {
                  final p = await _pickDate(v ?? DateTime.now());
                  if (p != null) setState(() => set(p));
                }
              : null,
          child: Text('$label: ${v == null ? '—' : date(v)}'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/jobs/contracts'),
        ),
        title: Text(c == null ? l.newContract : '${c.number} · ${c.title}'),
        actions: [
          if (c != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l.contractStatus(c.status))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c != null && planner)
            Wrap(
              spacing: 8,
              children: [
                if (c.status == 'draft' || c.status == 'suspended')
                  FilledButton(
                    onPressed: () =>
                        _status((id) => _field.activateContract(id: id)),
                    child: Text(l.activate),
                  ),
                if (c.status == 'active')
                  OutlinedButton(
                    onPressed: () =>
                        _status((id) => _field.suspendContract(id: id)),
                    child: Text(l.suspendContract),
                  ),
                if (!ended)
                  OutlinedButton(
                    onPressed: () =>
                        _status((id) => _field.endContract(id: id)),
                    child: Text(l.endContract),
                  ),
              ],
            ),
          gap,
          if (_isNew)
            SearchPicker<Customer>(
              label: l.customer,
              display: (x) => '${x.code} · ${x.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .crm
                          .listCustomers(q: q, limit: 20))
                      .items,
              onSelected: (x) {
                setState(() {
                  _customerId = x.id;
                  _customerName = x.name;
                  _equipmentIds.clear();
                  _units = [];
                });
                _loadUnits();
              },
            ),
          if (_customerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_customerName!, style: theme.textTheme.titleSmall),
            ),
          gap,
          TextField(
            controller: _title,
            enabled: canEdit,
            decoration: InputDecoration(labelText: l.title),
          ),
          gap,
          Row(
            children: [
              dateButton(l.startDate, _start, (d) => _start = d!),
              gap,
              dateButton(l.endDate, _end, (d) => _end = d, clearable: true),
              if (canEdit && _end != null)
                IconButton(
                  tooltip: l.clear,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => setState(() => _end = null),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.autoRenew),
            value: _autoRenew,
            onChanged: canEdit ? (v) => setState(() => _autoRenew = v) : null,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _response,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.responseHours),
                ),
              ),
              gap,
              Expanded(
                child: TextField(
                  controller: _resolution,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.resolutionHours),
                ),
              ),
            ],
          ),
          gap,
          TextField(
            controller: _notes,
            enabled: canEdit,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: l.notes),
          ),
          const Divider(height: 32),
          Text(l.equipment, style: theme.textTheme.titleSmall),
          if (_units.isEmpty)
            Text(l.noCustomerEquipment, style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              children: [
                for (final u in _units)
                  FilterChip(
                    label: Text('${u.productCode} · ${u.serialNumber}'),
                    selected: _equipmentIds.contains(u.serialUnitId),
                    onSelected: canEdit
                        ? (v) => setState(
                            () => v
                                ? _equipmentIds.add(u.serialUnitId)
                                : _equipmentIds.remove(u.serialUnitId),
                          )
                        : null,
                  ),
              ],
            ),
          const Divider(height: 32),
          Row(
            children: [
              Text(l.visitTemplates, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (canEdit)
                TextButton.icon(
                  icon: const Icon(AppIcons.add),
                  label: Text(l.addVisit),
                  onPressed: () =>
                      setState(() => _templates.add(_Tpl(anchor: _start))),
                ),
            ],
          ),
          for (final t in _templates) _templateCard(t, canEdit, users, l),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(l.save),
                ),
              ),
            ),
          if (c != null) ...[
            const Divider(height: 32),
            Text(l.upcomingVisits, style: theme.textTheme.titleSmall),
            FutureBuilder<List<UpcomingVisit>>(
              key: ValueKey('up-$_generation'),
              future: _field.listContractUpcoming(id: c.id),
              builder: (context, s) {
                if (!s.hasData) {
                  return s.hasError
                      ? Text(errorMessage(s.error!))
                      : const LinearProgressIndicator();
                }
                if (s.data!.isEmpty) return Text(l.noUpcomingVisits);
                return Column(
                  children: [
                    for (final v in s.data!.take(24))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(AppIcons.eventRepeat),
                        title: Text('${date(v.dueDate)} · ${v.title}'),
                        subtitle: Text(
                          v.jobNumber ?? l.jobCreatedOnDate(date(v.generateOn)),
                        ),
                        onTap: v.jobId == null
                            ? null
                            : () => context.push('/jobs/${v.jobId}'),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            Text(l.contractJobs, style: theme.textTheme.titleSmall),
            FutureBuilder<List<Job>>(
              key: ValueKey('jobs-$_generation'),
              future: _field.listContractJobs(id: c.id),
              builder: (context, s) {
                if (!s.hasData) {
                  return s.hasError
                      ? Text(errorMessage(s.error!))
                      : const LinearProgressIndicator();
                }
                return Column(
                  children: [
                    for (final j in s.data!)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${j.number} · ${j.title}'),
                        subtitle: Text(
                          [
                            if (j.dueDate != null) l.dueOnDate(date(j.dueDate)),
                            l.jobStatus(j.status),
                          ].join(' · '),
                        ),
                        onTap: () => context.push('/jobs/${j.id}'),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _templateCard(
    _Tpl t,
    bool canEdit,
    List<CompanyUser> users,
    AppLocalizations l,
  ) {
    const gap = SizedBox(height: 12, width: 12);
    final locale = Localizations.localeOf(context).toString();
    return Card(
      key: ObjectKey(t),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: t.title,
                    enabled: canEdit,
                    decoration: InputDecoration(labelText: l.title),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: l.remove,
                    icon: const Icon(AppIcons.delete),
                    onPressed: () => setState(() {
                      _templates.remove(t);
                      t.dispose();
                    }),
                  ),
              ],
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: t.kind,
                    decoration: InputDecoration(labelText: l.category),
                    items: [
                      for (final k in [
                        'maintenance',
                        'inspection',
                        'repair',
                        'installation',
                        'other',
                      ])
                        DropdownMenuItem(value: k, child: Text(l.jobKind(k))),
                    ],
                    onChanged: canEdit
                        ? (v) => setState(() => t.kind = v!)
                        : null,
                  ),
                ),
                gap,
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: t.recurrence,
                    items: [
                      DropdownMenuItem(
                        value: 'weeks',
                        child: Text(l.recurrenceWeeks),
                      ),
                      DropdownMenuItem(
                        value: 'months',
                        child: Text(l.recurrenceMonths),
                      ),
                      DropdownMenuItem(
                        value: 'months_list',
                        child: Text(l.recurrenceMonthList),
                      ),
                    ],
                    onChanged: canEdit
                        ? (v) => setState(() => t.recurrence = v!)
                        : null,
                  ),
                ),
              ],
            ),
            gap,
            if (t.recurrence == 'months_list')
              Wrap(
                spacing: 6,
                children: [
                  for (var m = 1; m <= 12; m++)
                    FilterChip(
                      label: Text(
                        DateFormat.MMM(locale).format(DateTime(2000, m)),
                      ),
                      selected: t.months.contains(m),
                      onSelected: canEdit
                          ? (v) => setState(
                              () => v ? t.months.add(m) : t.months.remove(m),
                            )
                          : null,
                    ),
                ],
              )
            else
              TextField(
                controller: t.interval,
                enabled: canEdit,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.interval),
              ),
            gap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canEdit
                        ? () async {
                            final p = await _pickDate(t.anchor);
                            if (p != null) setState(() => t.anchor = p);
                          }
                        : null,
                    child: Text('${l.firstDueDate}: ${date(t.anchor)}'),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    controller: t.lead,
                    enabled: canEdit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.leadDays),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    controller: t.minutes,
                    enabled: canEdit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.estimatedMinutes),
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: t.instructions,
              enabled: canEdit,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.instructions),
            ),
            gap,
            TextField(
              controller: t.tasks,
              enabled: canEdit,
              minLines: 2,
              maxLines: 8,
              decoration: InputDecoration(labelText: l.checklistOnePerLine),
            ),
            gap,
            Wrap(
              spacing: 6,
              children: [
                for (final u in users)
                  FilterChip(
                    label: Text(u.displayName),
                    selected: t.techs.contains(u.id),
                    onSelected: canEdit
                        ? (v) => setState(
                            () => v ? t.techs.add(u.id) : t.techs.remove(u.id),
                          )
                        : null,
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.active),
              value: t.active,
              onChanged: canEdit ? (v) => setState(() => t.active = v) : null,
            ),
          ],
        ),
      ),
    );
  }
}
