import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../../shared/app_icons.dart';

const repairStatuses = [
  'announced',
  'received',
  'routed',
  'in_progress',
  'waiting_customer',
  'waiting_parts',
  'completed',
  'shipped',
  'cancelled',
];
const _priorities = ['low', 'normal', 'high', 'urgent'];

final departmentsProvider = FutureProvider.autoDispose<List<Department>>(
  (ref) => ref.watch(apiProvider).repairs.listDepartments(),
);

/// All repairs: the queue of the people who triage, and of each department.
class RepairsPage extends ConsumerStatefulWidget {
  const RepairsPage({super.key});

  @override
  ConsumerState<RepairsPage> createState() => _RepairsPageState();
}

class _RepairsPageState extends ConsumerState<RepairsPage> {
  final _list = GlobalKey<EntityListState<Repair>>();
  String _status = 'open';
  String _department = 'all';

  void _reload() => _list.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final departments = ref.watch(departmentsProvider).value ?? const [];
    return EntityList<Repair>(
      key: _list,
      title: l.repairs,
      load: (q, offset, limit) async {
        final page = await api.repairs.listRepairs(
          q: q,
          status: _status == 'all' ? null : _status,
          department: _department == 'all' ? null : _department,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      filters: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: _status,
            items: [
              DropdownMenuItem(value: 'open', child: Text(l.notClosed)),
              DropdownMenuItem(value: 'all', child: Text(l.allStatuses)),
              for (final s in repairStatuses)
                DropdownMenuItem(value: s, child: Text(l.repairStatus(s))),
            ],
            onChanged: (v) {
              setState(() => _status = v!);
              _reload();
            },
          ),
          DropdownButton<String>(
            value: _department,
            items: [
              DropdownMenuItem(value: 'all', child: Text(l.all)),
              DropdownMenuItem(value: 'none', child: Text(l.notRouted)),
              for (final d in departments)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (v) {
              setState(() => _department = v!);
              _reload();
            },
          ),
        ],
      ),
      actions: [
        if (perms.contains('departments.write'))
          OutlinedButton.icon(
            icon: const Icon(AppIcons.accountTree),
            label: Text(l.departments),
            onPressed: () => context.push('/repairs/departments'),
          ),
      ],
      columns: [
        EntityColumn(l.number, (r) => r.number),
        EntityColumn(l.customer, (r) => r.customerName, flex: 2),
        EntityColumn(
          l.productDescription,
          (r) => [
            if (r.productCode != null) r.productCode!,
            r.productDescription,
            if (r.serialNumber.isNotEmpty) r.serialNumber,
          ].where((e) => e.isNotEmpty).join(' · '),
          flex: 3,
        ),
        EntityColumn(l.status, (r) => l.repairStatus(r.status)),
        EntityColumn(l.department, (r) => r.departmentName ?? '—'),
        EntityColumn(l.priority, (r) => l.ticketPriority(r.priority)),
        EntityColumn(l.updated, (r) => date(r.updatedAt)),
      ],
      createLabel: l.newRepair,
      onCreate: perms.contains('repairs.write')
          ? () async {
              final d = await showNewRepairDialog(context);
              if (d != null && context.mounted) {
                context.push('/repairs/${d.repair.id}');
              }
              return d != null;
            }
          : null,
      locationOf: (r) => '/repairs/${r.id}',
      onOpen: (r) async => await context.push<bool>('/repairs/${r.id}') ?? true,
    );
  }
}

/// Registers a repair. With [ticketId] it is created from a ticket (customer and person come from
/// the ticket) and defaults to "announced": the customer said it is coming.
Future<RepairDetail?> showNewRepairDialog(
  BuildContext context, {
  String? ticketId,
  Customer? customer,
  String? contactId,
  String? fault,
}) => showDialog<RepairDetail>(
  context: context,
  builder: (_) => NewRepairDialog(
    ticketId: ticketId,
    customer: customer,
    contactId: contactId,
    fault: fault,
  ),
);

class NewRepairDialog extends ConsumerStatefulWidget {
  const NewRepairDialog({
    super.key,
    this.ticketId,
    this.customer,
    this.contactId,
    this.fault,
  });
  final String? ticketId;
  final Customer? customer;
  final String? contactId;
  final String? fault;

  @override
  ConsumerState<NewRepairDialog> createState() => _NewRepairDialogState();
}

class _NewRepairDialogState extends ConsumerState<NewRepairDialog> {
  late final _product = TextEditingController();
  late final _serial = TextEditingController();
  late final _fault = TextEditingController(text: widget.fault);
  late final _reference = TextEditingController();
  late Customer? _customer = widget.customer;
  List<Contact> _contacts = [];
  late String? _contactId = widget.contactId;
  String _warranty = 'unknown';
  String _priority = 'normal';
  late bool _announced = widget.ticketId != null;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_customer != null) _loadContacts(_customer!.id);
  }

  @override
  void dispose() {
    for (final t in [_product, _serial, _fault, _reference]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _loadContacts(String customerId) async {
    final list = await ref
        .read(apiProvider)
        .crm
        .listCustomerContacts(id: customerId)
        .then((p) => p, onError: (Object _) => <Contact>[]);
    if (mounted) setState(() => _contacts = list);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(apiProvider)
          .repairs
          .createRepair(
            body: NewRepairInput(
              customerId: _customer?.id,
              contactId: _contactId,
              ticketId: widget.ticketId,
              productDescription: _product.text.trim(),
              serialNumber: _serial.text.trim(),
              faultDescription: _fault.text.trim(),
              customerReference: _reference.text.trim(),
              warranty: _warranty,
              priority: _priority,
              announced: _announced,
            ),
          );
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
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(l.newRepair),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.customer == null)
                SearchPicker<Customer>(
                  label: widget.ticketId != null
                      ? l.customerOptional
                      : l.customer,
                  display: (c) => '${c.code} · ${c.name}',
                  search: (q) async =>
                      (await ref
                              .read(apiProvider)
                              .crm
                              .listCustomers(q: q, limit: 20))
                          .items,
                  onSelected: (c) {
                    setState(() {
                      _customer = c;
                      _contactId = null;
                      _contacts = [];
                    });
                    _loadContacts(c.id);
                  },
                )
              else
                Text(
                  widget.customer!.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              if (_contacts.isNotEmpty) ...[
                gap,
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _contactId,
                  decoration: InputDecoration(labelText: l.contactPerson),
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
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _product,
                      decoration: InputDecoration(
                        labelText: l.productDescription,
                      ),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextField(
                      controller: _serial,
                      decoration: InputDecoration(labelText: l.serialNumber),
                    ),
                  ),
                ],
              ),
              gap,
              TextField(
                controller: _fault,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: l.faultDescription),
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reference,
                      decoration: InputDecoration(
                        labelText: l.customerReference,
                      ),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _warranty,
                      decoration: InputDecoration(labelText: l.warranty),
                      items: [
                        for (final w in [
                          'unknown',
                          'in_warranty',
                          'out_of_warranty',
                        ])
                          DropdownMenuItem(
                            value: w,
                            child: Text(l.warrantyLabel(w)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _warranty = v!),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _priority,
                      decoration: InputDecoration(labelText: l.priority),
                      items: [
                        for (final p in _priorities)
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.announcedNotReceived),
                value: _announced,
                onChanged: (v) => setState(() => _announced = v ?? false),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
