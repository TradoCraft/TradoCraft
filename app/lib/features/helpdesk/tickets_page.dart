import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import 'call_dialogs.dart';
import 'ticket_extras.dart';
import 'ticket_screen.dart' show teamsProvider;
import '../../shared/app_icons.dart';

const ticketStatuses = [
  'new',
  'open',
  'pending_customer',
  'pending_internal',
  'closed',
];
const ticketPriorities = ['low', 'normal', 'high', 'urgent'];
const ticketCategories = [
  'question',
  'lead',
  'quote_change',
  'order_confirmation',
  'production_question',
  'service',
  'complaint',
  'other',
];

final _tagsProvider = FutureProvider.autoDispose<List<TagCount>>(
  (ref) => ref.watch(apiProvider).helpdesk.listTags(),
);

/// Ticket overview: my tickets, unassigned or all; open ones first.
class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key});

  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  final _list = GlobalKey<EntityListState<Ticket>>();
  String _owner = 'me';
  String _status = 'active';
  String? _team;
  String? _sla;
  String? _tag;
  bool _unread = false;
  bool _watching = false;
  bool _escalated = false;

  void _reload() => _list.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final tags = ref.watch(_tagsProvider).value ?? const <TagCount>[];
    return EntityList<Ticket>(
      key: _list,
      title: l.helpdesk,
      load: (q, offset, limit) async {
        final page = await api.helpdesk.listTickets(
          q: q,
          mine: _owner == 'me' ? true : null,
          unassigned: _owner == 'none' ? true : null,
          teamId: _team,
          sla: _sla,
          tag: _tag,
          unread: _unread ? true : null,
          watching: _watching ? true : null,
          escalated: _escalated ? true : null,
          status: _status == 'all' ? null : _status,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      filters: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'me', label: Text(l.myTickets)),
              ButtonSegment(value: 'none', label: Text(l.unassigned)),
              ButtonSegment(value: 'all', label: Text(l.all)),
            ],
            selected: {_owner},
            onSelectionChanged: (s) {
              setState(() => _owner = s.first);
              _reload();
            },
          ),
          FilterChip(
            key: const ValueKey('filter-unread'),
            label: Text(l.collabFilterUnread),
            selected: _unread,
            onSelected: (v) {
              setState(() => _unread = v);
              _reload();
            },
          ),
          FilterChip(
            key: const ValueKey('filter-watching'),
            label: Text(l.collabFilterWatching),
            selected: _watching,
            onSelected: (v) {
              setState(() => _watching = v);
              _reload();
            },
          ),
          FilterChip(
            key: const ValueKey('filter-escalated'),
            label: Text(l.collabFilterEscalated),
            selected: _escalated,
            onSelected: (v) {
              setState(() => _escalated = v);
              _reload();
            },
          ),
          DropdownButton<String>(
            value: _status,
            items: [
              DropdownMenuItem(value: 'active', child: Text(l.notClosed)),
              DropdownMenuItem(value: 'all', child: Text(l.allStatuses)),
              for (final s in ticketStatuses)
                DropdownMenuItem(value: s, child: Text(l.ticketStatus(s))),
            ],
            onChanged: (v) {
              setState(() => _status = v!);
              _reload();
            },
          ),
        ],
      ),
      moreFilters: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            key: const ValueKey('filter-team'),
            value: teams.any((t) => t.id == _team) ? _team : null,
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(l.allTeams)),
              for (final t in teams)
                DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) {
              setState(() => _team = v);
              _reload();
            },
          ),
          DropdownButton<String?>(
            key: const ValueKey('filter-sla'),
            value: _sla,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l.slaFilterAny),
              ),
              DropdownMenuItem<String?>(
                value: 'breached',
                child: Text(l.slaBreached),
              ),
              DropdownMenuItem<String?>(
                value: 'at_risk',
                child: Text(l.slaAtRisk),
              ),
            ],
            onChanged: (v) {
              setState(() => _sla = v);
              _reload();
            },
          ),
          if (tags.isNotEmpty)
            DropdownButton<String?>(
              key: const ValueKey('filter-tag'),
              value: tags.any((t) => t.tag == _tag) ? _tag : null,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.allTags)),
                for (final t in tags)
                  DropdownMenuItem<String?>(
                    value: t.tag,
                    child: Text('${t.tag} (${t.count})'),
                  ),
              ],
              onChanged: (v) {
                setState(() => _tag = v);
                _reload();
              },
            ),
        ],
      ),
      actions: [
        if (perms.contains('helpdesk.admin'))
          OutlinedButton.icon(
            icon: const Icon(AppIcons.settings),
            label: Text(l.helpdeskSettings),
            onPressed: () => context.push('/helpdesk/settings'),
          ),
        if (perms.contains('helpdesk.write'))
          FilledButton.tonalIcon(
            icon: const Icon(AppIcons.phoneInTalk),
            label: Text(l.whoIsCalling),
            onPressed: () async {
              final d = await showCallerLookup(context);
              if (d != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.callLogged)));
                context.push('/helpdesk/${d.ticket.id}');
              }
            },
          ),
        OutlinedButton.icon(
          key: const ValueKey('open-reports'),
          icon: const Icon(AppIcons.barChart),
          label: Text(l.helpdeskReports),
          onPressed: () => context.push('/helpdesk/reports'),
        ),
        OutlinedButton.icon(
          icon: const Icon(AppIcons.textSnippet),
          label: Text(l.preparedAnswers),
          onPressed: () => context.push('/helpdesk/answers'),
        ),
      ],
      columns: [
        EntityColumn(
          l.number,
          (t) => t.number,
          cell: (context, t) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.unread)
                Tooltip(
                  message: l.collabUnreadTooltip,
                  child: Icon(
                    AppIcons.circle,
                    key: ValueKey('unread-${t.id}'),
                    size: 10,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              else
                const SizedBox(width: 10),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  t.number,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: t.unread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
        EntityColumn(
          l.subject,
          (t) => '${t.unread ? '● ' : ''}${t.subject}',
          flex: 3,
          cell: (context, t) => Row(
            children: [
              if (t.escalatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: l.collabEscalatedBy(t.escalatedByName ?? ''),
                    child: Chip(
                      key: ValueKey('escalated-${t.id}'),
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        AppIcons.trendingUp,
                        size: 14,
                        color: Colors.red.shade700,
                      ),
                      label: Text(l.collabEscalatedBadge),
                    ),
                  ),
                ),
              Flexible(
                child: Text(
                  t.subject,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: t.unread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
        EntityColumn(
          l.customer,
          (t) =>
              t.customerName ??
              (t.contactName.isEmpty ? t.contactEmail : t.contactName),
          flex: 2,
        ),
        EntityColumn(l.category, (t) => l.ticketCategory(t.category)),
        EntityColumn(l.status, (t) => l.ticketStatus(t.status)),
        EntityColumn(l.priority, (t) => l.ticketPriority(t.priority)),
        EntityColumn(
          l.sla,
          (t) => slaSummary(l, t.sla),
          flex: 2,
          cell: (_, t) => SlaBadge(sla: t.sla),
        ),
        EntityColumn(l.team, (t) => t.teamName ?? '—'),
        EntityColumn(l.owner, (t) => t.ownerName ?? '—'),
        EntityColumn(l.updated, (t) => date(t.updatedAt)),
      ],
      createLabel: l.newTicket,
      onCreate: perms.contains('helpdesk.write')
          ? () async {
              final created = await showDialog<TicketDetail>(
                context: context,
                builder: (_) => const NewTicketDialog(),
              );
              if (created != null && context.mounted) {
                context.push('/helpdesk/${created.ticket.id}');
              }
              return created != null;
            }
          : null,
      locationOf: (t) => '/helpdesk/${t.id}',
      onOpen: (t) async =>
          await context.push<bool>('/helpdesk/${t.id}') ?? true,
    );
  }
}

/// A ticket for a phone call, visit or internal question.
class NewTicketDialog extends ConsumerStatefulWidget {
  const NewTicketDialog({super.key});

  @override
  ConsumerState<NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends ConsumerState<NewTicketDialog> {
  final _subject = TextEditingController();
  final _contactName = TextEditingController();
  final _contactEmail = TextEditingController();
  final _body = TextEditingController();
  Customer? _customer;
  List<Contact> _contacts = [];
  Contact? _contact;
  String _category = 'question';
  String? _language;
  bool _internal = false;
  String? _error;

  Future<void> _customerSelected(Customer c) async {
    setState(() {
      _customer = c;
      _contact = null;
      _contacts = [];
      _language ??= c.language;
      if (_contactEmail.text.isEmpty) _contactEmail.text = c.email ?? '';
    });
    final people = await ref
        .read(apiProvider)
        .crm
        .listCustomerContacts(id: c.id)
        .then((p) => p, onError: (Object _) => <Contact>[]);
    if (mounted && _customer?.id == c.id) setState(() => _contacts = people);
  }

  /// A known person brings their name, address and the language to write in.
  void _contactSelected(Contact? c) => setState(() {
    _contact = c;
    if (c != null) {
      _contactName.text = c.fullName;
      _contactEmail.text = c.emails.isEmpty ? '' : c.emails.first.email;
      _language = c.effectiveLanguage;
    }
  });

  Future<void> _save() async {
    try {
      final d = await ref
          .read(apiProvider)
          .helpdesk
          .createTicket(
            body: NewTicketInput(
              subject: _subject.text.trim(),
              body: _body.text.trim(),
              customerId: _customer?.id,
              contactId: _contact?.id,
              contactName: _contactName.text.trim(),
              contactEmail: _contactEmail.text.trim(),
              category: _category,
              language: _language,
              internal: _internal,
            ),
          );
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(l.newTicket),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _subject,
                decoration: InputDecoration(labelText: l.subject),
              ),
              gap,
              SearchPicker<Customer>(
                label: l.customerOptional,
                display: (c) => '${c.code} · ${c.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .crm
                            .listCustomers(q: q, limit: 20))
                        .items,
                onSelected: _customerSelected,
              ),
              if (_contacts.isNotEmpty) ...[
                gap,
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  key: ValueKey('contact-${_contact?.id}'),
                  initialValue: _contact?.id,
                  decoration: InputDecoration(labelText: l.contactPerson),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.noContactLinked),
                    ),
                    for (final c in _contacts)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          '${c.fullName} · ${languageName(c.effectiveLanguage)}',
                        ),
                      ),
                  ],
                  onChanged: (id) => _contactSelected(
                    id == null ? null : _contacts.firstWhere((c) => c.id == id),
                  ),
                ),
              ],
              gap,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contactName,
                      decoration: InputDecoration(labelText: l.contactName),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextField(
                      controller: _contactEmail,
                      decoration: InputDecoration(labelText: l.email),
                    ),
                  ),
                ],
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _category,
                      decoration: InputDecoration(labelText: l.category),
                      items: [
                        for (final c in ticketCategories)
                          DropdownMenuItem(
                            value: c,
                            child: Text(l.ticketCategory(c)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                  gap,
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      key: ValueKey(_language),
                      initialValue: _language,
                      decoration: InputDecoration(labelText: l.language),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l.automatic),
                        ),
                        for (final c in languageCodes)
                          DropdownMenuItem<String?>(
                            value: c,
                            child: Text(languageName(c)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _language = v),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.internalTicket),
                subtitle: Text(l.internalTicketHelp),
                value: _internal,
                onChanged: (v) => setState(() => _internal = v ?? false),
              ),
              TextField(
                controller: _body,
                maxLines: 5,
                decoration: InputDecoration(labelText: l.whatWasAsked),
              ),
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
        FilledButton(onPressed: _save, child: Text(l.create)),
      ],
    );
  }
}
