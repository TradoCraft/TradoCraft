import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// Shows the form for a person at [customer]; returns the saved contact.
Future<Contact?> showContactForm(
  BuildContext context, {
  required Customer customer,
  Contact? contact,
}) => showDialog<Contact>(
  context: context,
  builder: (_) => ContactForm(customer: customer, contact: contact),
);

class _PhoneRow {
  _PhoneRow(this.label, String number)
    : number = TextEditingController(text: number);
  String label;
  final TextEditingController number;
}

/// A person at a customer: name, how to address them, their language (or the customer's),
/// roles, e-mail addresses, phone numbers and access to the customer portal.
class ContactForm extends ConsumerStatefulWidget {
  const ContactForm({super.key, required this.customer, this.contact});

  final Customer customer;
  final Contact? contact;

  @override
  ConsumerState<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<ContactForm> {
  final _form = GlobalKey<FormState>();
  late final c = widget.contact;
  late final _first = TextEditingController(text: c?.firstName);
  late final _last = TextEditingController(text: c?.lastName);
  late final _job = TextEditingController(text: c?.jobTitle);
  late final _emails = TextEditingController(
    text: c?.emails.map((e) => e.email).join(', '),
  );
  late final _notes = TextEditingController(text: c?.notes);
  late final List<_PhoneRow> _phones = [
    for (final p in c?.phones ?? const <ContactPhone>[])
      _PhoneRow(p.label, p.number),
  ];
  late String _title = c?.title ?? 'none';
  late String _addressForm = c?.addressForm ?? 'formal';
  late String? _language = c?.language;
  late final Set<String> _roles = {...?c?.roles};
  late bool _active = c?.active ?? true;
  late bool _portal = c?.portalAccess ?? false;
  late String _scope = c?.portalScope ?? 'own';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final t in [_first, _last, _job, _emails, _notes]) {
      t.dispose();
    }
    for (final p in _phones) {
      p.number.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = ContactInput(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      jobTitle: _job.text.trim(),
      title: _title,
      addressForm: _addressForm,
      language: _language,
      roles: _roles.toList(),
      notes: _notes.text.trim(),
      active: _active,
      portalAccess: _portal,
      portalScope: _scope,
      emails: _emails.text
          .split(RegExp(r'[,;\s]+'))
          .where((e) => e.isNotEmpty)
          .toList(),
      phones: [
        for (final p in _phones)
          if (p.number.text.trim().isNotEmpty)
            PhoneInput(label: p.label, number: p.number.text.trim()),
      ],
    );
    try {
      final crm = ref.read(apiProvider).crm;
      final saved = c == null
          ? await crm.createContact(id: widget.customer.id, body: input)
          : await crm.updateContact(id: c!.id, body: input);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(width: 12, height: 12);
    return AlertDialog(
      title: Text(c == null ? l.newContact : l.editContact),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customer.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                gap,
                Row(
                  children: [
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _title,
                        decoration: InputDecoration(labelText: l.personTitle),
                        items: [
                          for (final t in ['none', 'mr', 'ms'])
                            DropdownMenuItem(
                              value: t,
                              child: Text(l.personTitleLabel(t)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _title = v!),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: TextFormField(
                        controller: _first,
                        decoration: InputDecoration(labelText: l.firstName),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: TextFormField(
                        controller: _last,
                        decoration: InputDecoration(labelText: l.lastName),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? l.required : null,
                      ),
                    ),
                  ],
                ),
                gap,
                TextFormField(
                  controller: _job,
                  decoration: InputDecoration(labelText: l.jobTitle),
                ),
                gap,
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _language,
                        decoration: InputDecoration(labelText: l.language),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              l.languageSameAsCustomer(
                                languageName(widget.customer.language),
                              ),
                            ),
                          ),
                          for (final code in languageCodes)
                            DropdownMenuItem<String?>(
                              value: code,
                              child: Text(languageName(code)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _language = v),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _addressForm,
                        decoration: InputDecoration(labelText: l.addressForm),
                        items: [
                          DropdownMenuItem(
                            value: 'formal',
                            child: Text(l.addressFormal),
                          ),
                          DropdownMenuItem(
                            value: 'informal',
                            child: Text(l.addressInformal),
                          ),
                        ],
                        onChanged: (v) => setState(() => _addressForm = v!),
                      ),
                    ),
                  ],
                ),
                gap,
                Text(l.roles, style: Theme.of(context).textTheme.labelLarge),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in contactRoles)
                      FilterChip(
                        label: Text(l.contactRole(r)),
                        selected: _roles.contains(r),
                        onSelected: (on) => setState(
                          () => on ? _roles.add(r) : _roles.remove(r),
                        ),
                      ),
                  ],
                ),
                gap,
                TextFormField(
                  controller: _emails,
                  decoration: InputDecoration(labelText: l.emailAddresses),
                ),
                gap,
                Row(
                  children: [
                    Text(
                      l.phoneNumbers,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _phones.add(_PhoneRow('work', ''))),
                      icon: const Icon(AppIcons.add),
                      label: Text(l.addPhone),
                    ),
                  ],
                ),
                for (final (i, p) in _phones.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: p.label,
                            items: [
                              for (final k in [
                                'work',
                                'mobile',
                                'direct',
                                'other',
                              ])
                                DropdownMenuItem(
                                  value: k,
                                  child: Text(l.phoneLabel(k)),
                                ),
                            ],
                            onChanged: (v) => setState(() => p.label = v!),
                          ),
                        ),
                        gap,
                        Expanded(
                          child: TextFormField(
                            controller: p.number,
                            decoration: InputDecoration(hintText: l.phoneHint),
                          ),
                        ),
                        IconButton(
                          tooltip: l.remove,
                          onPressed: () => setState(() => _phones.removeAt(i)),
                          icon: const Icon(AppIcons.close),
                        ),
                      ],
                    ),
                  ),
                gap,
                TextFormField(
                  controller: _notes,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: l.notes),
                ),
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.portalAccess),
                  value: _portal,
                  onChanged: (v) => setState(() => _portal = v),
                ),
                if (_portal)
                  DropdownButtonFormField<String>(
                    initialValue: _scope,
                    decoration: InputDecoration(labelText: l.portalScope),
                    items: [
                      DropdownMenuItem(
                        value: 'own',
                        child: Text(l.portalScopeOwn),
                      ),
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text(l.portalScopeCustomer),
                      ),
                    ],
                    onChanged: (v) => setState(() => _scope = v!),
                  ),
                if (c != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.active),
                    subtitle: _active ? null : Text(l.inactiveContact),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                if (_error != null) ...[
                  gap,
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
