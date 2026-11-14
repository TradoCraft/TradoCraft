import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/search_picker.dart';
import 'tickets_page.dart';
import '../../shared/app_icons.dart';

/// "Who is calling?": looks the number up and offers to log the call for the person found.
/// Returns the ticket the call was logged on.
Future<TicketDetail?> showCallerLookup(BuildContext context) =>
    showDialog<TicketDetail>(
      context: context,
      builder: (_) => const CallerLookupDialog(),
    );

/// Logs a call. Without [ticketId] a new ticket is opened for it.
Future<TicketDetail?> showCallDialog(
  BuildContext context, {
  String? ticketId,
  Contact? contact,
  String phone = '',
}) => showDialog<TicketDetail>(
  context: context,
  builder: (_) =>
      CallDialog(ticketId: ticketId, contact: contact, phone: phone),
);

class CallerLookupDialog extends ConsumerStatefulWidget {
  const CallerLookupDialog({super.key});

  @override
  ConsumerState<CallerLookupDialog> createState() => _CallerLookupDialogState();
}

class _CallerLookupDialogState extends ConsumerState<CallerLookupDialog> {
  final _phone = TextEditingController();
  LookupResult? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .crm
          .lookupContacts(phone: _phone.text.trim());
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _log({Contact? contact}) async {
    final d = await showCallDialog(
      context,
      contact: contact,
      phone: _phone.text.trim(),
    );
    if (d != null && mounted) Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final r = _result;
    return AlertDialog(
      title: Text(l.whoIsCalling),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l.phoneNumber,
                      hintText: l.phoneHint,
                    ),
                    onSubmitted: (_) => _lookUp(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _lookUp,
                  icon: const Icon(AppIcons.search),
                  label: Text(l.lookUp),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (r != null) ...[
              const SizedBox(height: 12),
              if (r.contacts.isEmpty && r.customers.isEmpty)
                Text(l.nobodyFound),
              for (final c in r.contacts)
                Card(
                  child: ListTile(
                    leading: const Icon(AppIcons.person),
                    title: Text('${c.fullName} · ${c.customerName}'),
                    subtitle: Text(
                      [
                        if (c.jobTitle.isNotEmpty) c.jobTitle,
                        languageName(c.effectiveLanguage),
                        l.greetingPreview(c.greeting),
                      ].join('  ·  '),
                    ),
                    trailing: FilledButton(
                      onPressed: () => _log(contact: c),
                      child: Text(l.logCall),
                    ),
                  ),
                ),
              for (final c in r.customers)
                Card(
                  child: ListTile(
                    leading: const Icon(AppIcons.business),
                    title: Text(c.name),
                    subtitle: Text(l.customerMainNumber(c.name)),
                    trailing: OutlinedButton(
                      onPressed: () => _log(),
                      child: Text(l.logCall),
                    ),
                  ),
                ),
              if (r.contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () => _log(),
                    icon: const Icon(AppIcons.help),
                    label: Text(l.unknownCaller),
                  ),
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
      ],
    );
  }
}

class CallDialog extends ConsumerStatefulWidget {
  const CallDialog({super.key, this.ticketId, this.contact, this.phone = ''});
  final String? ticketId;
  final Contact? contact;
  final String phone;

  @override
  ConsumerState<CallDialog> createState() => _CallDialogState();
}

class _CallDialogState extends ConsumerState<CallDialog> {
  late final _phone = TextEditingController(text: widget.phone);
  final _summary = TextEditingController();
  final _subject = TextEditingController();
  final _minutes = TextEditingController();
  String _direction = 'in';
  String _category = 'question';
  Customer? _customer;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final t in [_phone, _summary, _subject, _minutes]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_summary.text.trim().isEmpty) {
      setState(() => _error = l.required);
      return;
    }
    final minutes = double.tryParse(_minutes.text.trim().replaceAll(',', '.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(apiProvider)
          .helpdesk
          .logCall(
            body: CallInput(
              ticketId: widget.ticketId,
              direction: _direction,
              phoneNumber: _phone.text.trim(),
              contactId: widget.contact?.id,
              customerId: _customer?.id,
              durationSeconds: minutes == null ? null : (minutes * 60).round(),
              summary: _summary.text.trim(),
              subject: widget.ticketId != null || _subject.text.trim().isEmpty
                  ? null
                  : _subject.text.trim(),
              category: _category,
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
    final c = widget.contact;
    final newTicket = widget.ticketId == null;
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(c == null ? l.logCall : l.callWith(c.fullName)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${c.customerName} · ${languageName(c.effectiveLanguage)}',
                  ),
                ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'in',
                    icon: const Icon(AppIcons.phoneCallback),
                    label: Text(l.callIncoming),
                  ),
                  ButtonSegment(
                    value: 'out',
                    icon: const Icon(AppIcons.phoneForwarded),
                    label: Text(l.callOutgoing),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _phone,
                      decoration: InputDecoration(labelText: l.phoneNumber),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l.callMinutes),
                    ),
                  ),
                ],
              ),
              if (newTicket) ...[
                gap,
                if (c == null)
                  SearchPicker<Customer>(
                    label: l.customerOptional,
                    display: (x) => '${x.code} · ${x.name}',
                    search: (q) async =>
                        (await ref
                                .read(apiProvider)
                                .crm
                                .listCustomers(q: q, limit: 20))
                            .items,
                    onSelected: (x) => setState(() => _customer = x),
                  ),
                if (c == null) gap,
                TextField(
                  controller: _subject,
                  decoration: InputDecoration(labelText: l.subject),
                ),
                gap,
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(labelText: l.category),
                  items: [
                    for (final k in ticketCategories)
                      if (k != 'production_question')
                        DropdownMenuItem(
                          value: k,
                          child: Text(l.ticketCategory(k)),
                        ),
                  ],
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ],
              gap,
              TextField(
                controller: _summary,
                autofocus: true,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(labelText: l.callSummary),
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
        FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
