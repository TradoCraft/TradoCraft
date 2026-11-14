import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/search_picker.dart';
import '../helpdesk/ticket_screen.dart' show usersProvider;
import 'work_log_dialog.dart' show pickDateTime;

final _stamp = DateFormat('dd/MM/yyyy HH:mm');

/// Plans a job (or changes one, with [detail]). Returns the saved job.
Future<JobDetail?> showJobForm(BuildContext context, {JobDetail? detail}) =>
    showDialog<JobDetail>(
      context: context,
      builder: (_) => JobForm(detail: detail),
    );

/// The planner's form: what, for whom, where, when, who goes, and the checklist.
class JobForm extends ConsumerStatefulWidget {
  const JobForm({super.key, this.detail});
  final JobDetail? detail;

  @override
  ConsumerState<JobForm> createState() => _JobFormState();
}

class _JobFormState extends ConsumerState<JobForm> {
  late final j = widget.detail?.job;
  late final _title = TextEditingController(text: j?.title);
  late final _instructions = TextEditingController(text: j?.instructions);
  late final _site = TextEditingController(text: j?.siteName);
  late final _street = TextEditingController(text: j?.street);
  late final _postal = TextEditingController(text: j?.postalCode);
  late final _city = TextEditingController(text: j?.city);
  final _tasks = TextEditingController();
  late String _kind = j?.kind ?? 'maintenance';
  late String _priority = j?.priority ?? 'normal';
  late String? _customerId = j?.customerId;
  late String? _customerName = j?.customerName;
  late String? _contactId = j?.contactId;
  List<Contact> _contacts = [];
  late DateTime? _start = j?.scheduledStart?.toLocal();
  late DateTime? _end = j?.scheduledEnd?.toLocal();
  late final Set<String> _technicians = {
    ...?j?.technicians.map((t) => t.userId),
  };
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_customerId != null) _loadContacts(_customerId!);
  }

  @override
  void dispose() {
    for (final t in [
      _title,
      _instructions,
      _site,
      _street,
      _postal,
      _city,
      _tasks,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _loadContacts(String customer) async {
    final list = await ref
        .read(apiProvider)
        .crm
        .listCustomerContacts(id: customer)
        .then((p) => p, onError: (Object _) => <Contact>[]);
    if (mounted) setState(() => _contacts = list);
  }

  Future<void> _save() async {
    if (_customerId == null) {
      setState(() => _error = context.l10n.customer);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final input = JobInput(
      kind: _kind,
      priority: _priority,
      title: _title.text.trim(),
      instructions: _instructions.text.trim(),
      customerId: _customerId!,
      contactId: _contactId,
      ticketId: j?.ticketId,
      repairId: j?.repairId,
      siteName: _site.text.trim(),
      street: _street.text.trim(),
      postalCode: _postal.text.trim(),
      city: _city.text.trim(),
      latitude: j?.latitude,
      longitude: j?.longitude,
      scheduledStart: _start?.toUtc(),
      scheduledEnd: _end?.toUtc(),
      technicianIds: _technicians.toList(),
      tasks: _tasks.text
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );
    try {
      final field = ref.read(apiProvider).field;
      final d = j == null
          ? await field.createJob(body: input)
          : await field.updateJob(id: j!.id, body: input);
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final users = (ref.watch(usersProvider).value ?? const <CompanyUser>[])
        .where((u) => u.roles.contains('technician'))
        .toList();
    const gap = SizedBox(height: 12, width: 12);
    Widget when(String label, DateTime? v, ValueChanged<DateTime> set) =>
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              final p = await pickDateTime(
                context,
                v ?? DateTime.now().add(const Duration(days: 1)),
              );
              if (p != null) setState(() => set(p));
            },
            child: Text(
              '$label\n${v == null ? l.notScheduled : _stamp.format(v)}',
            ),
          ),
        );
    return AlertDialog(
      title: Text(j == null ? l.newJob : l.editJob),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: l.jobName),
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _kind,
                      decoration: InputDecoration(labelText: l.category),
                      items: [
                        for (final k in [
                          'installation',
                          'maintenance',
                          'repair',
                          'inspection',
                          'other',
                        ])
                          DropdownMenuItem(value: k, child: Text(l.jobKind(k))),
                      ],
                      onChanged: (v) => setState(() => _kind = v!),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _priority,
                      decoration: InputDecoration(labelText: l.priority),
                      items: [
                        for (final p in ['low', 'normal', 'high', 'urgent'])
                          DropdownMenuItem(
                            value: p,
                            child: Text(l.ticketPriority(p)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _priority = v!),
                    ),
                  ),
                ],
              ),
              gap,
              SearchPicker<Customer>(
                key: ValueKey('cust-$_customerId'),
                label: l.customer,
                display: (c) => '${c.code} · ${c.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .crm
                            .listCustomers(q: q, limit: 20))
                        .items,
                onSelected: (c) {
                  setState(() {
                    _customerId = c.id;
                    _customerName = c.name;
                    _contactId = null;
                    _contacts = [];
                  });
                  _loadContacts(c.id);
                },
              ),
              if (_customerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_customerName!),
                ),
              if (_contacts.isNotEmpty) ...[
                gap,
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _contactId,
                  decoration: InputDecoration(labelText: l.onSiteContact),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.noContactLinked),
                    ),
                    for (final c in _contacts)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.fullName),
                      ),
                  ],
                  onChanged: (v) => setState(() => _contactId = v),
                ),
              ],
              gap,
              TextField(
                controller: _instructions,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: l.instructions),
              ),
              gap,
              Text(
                l.siteAddress,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              gap,
              TextField(
                controller: _site,
                decoration: InputDecoration(labelText: l.siteName),
              ),
              gap,
              TextField(
                controller: _street,
                decoration: InputDecoration(labelText: l.streetAddress),
              ),
              gap,
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _postal,
                      decoration: InputDecoration(labelText: l.postalCode),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextField(
                      controller: _city,
                      decoration: InputDecoration(labelText: l.city),
                    ),
                  ),
                ],
              ),
              gap,
              Row(
                children: [
                  when(l.scheduledStart, _start, (v) {
                    _start = v;
                    if (_end == null || _end!.isBefore(v)) {
                      _end = v.add(const Duration(hours: 2));
                    }
                  }),
                  gap,
                  when(l.scheduledEnd, _end, (v) => _end = v),
                ],
              ),
              gap,
              Text(
                l.technicians,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final u in users)
                    FilterChip(
                      label: Text(u.displayName),
                      selected: _technicians.contains(u.id),
                      onSelected: (on) => setState(
                        () => on
                            ? _technicians.add(u.id)
                            : _technicians.remove(u.id),
                      ),
                    ),
                ],
              ),
              if (j == null) ...[
                gap,
                TextField(
                  controller: _tasks,
                  minLines: 3,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: l.tasks,
                    helperText: l.addTask,
                  ),
                ),
              ],
              if (_error != null) ...[
                gap,
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
