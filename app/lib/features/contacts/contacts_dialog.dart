import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'contact_form.dart';
import '../../shared/app_icons.dart';

/// The people at a customer. Opened from the customer form.
Future<void> showContactsDialog(BuildContext context, Customer customer) =>
    showDialog<void>(
      context: context,
      builder: (_) => ContactsDialog(customer: customer),
    );

class ContactsDialog extends ConsumerStatefulWidget {
  const ContactsDialog({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<ContactsDialog> createState() => _ContactsDialogState();
}

class _ContactsDialogState extends ConsumerState<ContactsDialog> {
  List<Contact>? _contacts;
  String? _error;
  bool _inactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(apiProvider)
          .crm
          .listCustomerContacts(
            id: widget.customer.id,
            includeInactive: _inactive,
          );
      if (mounted) setState(() => _contacts = list);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _edit([Contact? contact]) async {
    final saved = await showContactForm(
      context,
      customer: widget.customer,
      contact: contact,
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('contacts.write') ??
        false;
    final theme = Theme.of(context);
    final contacts = _contacts;
    return AlertDialog(
      title: Text('${l.contacts} · ${widget.customer.name}'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: _error != null
            ? Text(_error!)
            : contacts == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilterChip(
                      label: Text(l.showInactive),
                      selected: _inactive,
                      onSelected: (v) {
                        setState(() => _inactive = v);
                        _load();
                      },
                    ),
                  ),
                  Expanded(
                    child: contacts.isEmpty
                        ? Center(child: Text(l.noContacts))
                        : ListView(
                            children: [
                              for (final c in contacts)
                                _ContactTile(
                                  contact: c,
                                  onTap: canWrite ? () => _edit(c) : null,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            icon: const Icon(AppIcons.personAddAlt),
            label: Text(l.newContact),
            onPressed: _edit,
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, this.onTap});
  final Contact contact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = contact;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: CircleAvatar(
        child: Icon(c.active ? AppIcons.person : AppIcons.personOff),
      ),
      title: Text(
        [c.fullName, if (c.jobTitle.isNotEmpty) c.jobTitle].join(' · '),
        style: c.active
            ? null
            : TextStyle(
                color: theme.colorScheme.outline,
                decoration: TextDecoration.lineThrough,
              ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final r in c.roles)
                Chip(
                  label: Text(l.contactRole(r)),
                  visualDensity: VisualDensity.compact,
                ),
              if (c.portalAccess)
                Chip(
                  avatar: const Icon(AppIcons.language, size: 14),
                  label: Text(l.portalTitle),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          Text(
            [
              ...c.emails.map((e) => e.email),
              ...c.phones.map((p) => p.number),
            ].join('  ·  '),
            style: muted,
          ),
          // The language to write in, with a mark when it differs from the company's.
          Text(
            '${languageName(c.effectiveLanguage)}'
            '${c.language != null && c.language != c.customerLanguage ? ' *' : ''}'
            '  ·  ${l.greetingPreview(c.greeting)}',
            style: muted,
          ),
        ],
      ),
    );
  }
}
