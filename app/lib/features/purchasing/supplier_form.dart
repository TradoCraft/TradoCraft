import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../tutorial/targets.dart';

/// The editable fields of a supplier: the controllers behind the create dialog and the edit mode
/// of the detail screen.
class SupplierDraft {
  /// Starts from [s], or from an empty supplier (country and currency of the company) when null.
  SupplierDraft(Supplier? s, {String country = 'BE', String currency = 'EUR'})
    : name = TextEditingController(text: s?.name ?? ''),
      code = TextEditingController(text: s?.code ?? ''),
      country = TextEditingController(text: s?.country ?? country),
      currency = TextEditingController(text: s?.currency ?? currency),
      terms = TextEditingController(text: '${s?.paymentTermsDays ?? 30}'),
      taxId = TextEditingController(text: s?.taxId ?? ''),
      email = TextEditingController(text: s?.email ?? ''),
      phone = TextEditingController(text: s?.phone ?? ''),
      contact = TextEditingController(text: s?.contactPerson ?? ''),
      notes = TextEditingController(text: s?.notes ?? ''),
      active = s?.active ?? true;

  /// Supplier name (required).
  final TextEditingController name;

  /// Supplier code; empty on create lets the server number it.
  final TextEditingController code;

  /// ISO 3166 alpha-2 country code (required).
  final TextEditingController country;

  /// ISO 4217 currency code.
  final TextEditingController currency;

  /// Payment terms in days.
  final TextEditingController terms;

  /// VAT number.
  final TextEditingController taxId;

  /// Contact e-mail address.
  final TextEditingController email;

  /// Contact phone number.
  final TextEditingController phone;

  /// Name of the contact person.
  final TextEditingController contact;

  /// Free notes.
  final TextEditingController notes;

  /// Whether the supplier is active (edit mode only).
  bool active;

  List<TextEditingController> get _all => [
    name,
    code,
    country,
    currency,
    terms,
    taxId,
    email,
    phone,
    contact,
    notes,
  ];

  /// Calls [listener] whenever a field changes.
  void addListener(VoidCallback listener) {
    for (final c in _all) {
      c.addListener(listener);
    }
  }

  /// Releases the controllers.
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }

  /// The first problem with the input, or null when it can be sent.
  String? validate(BuildContext context) {
    final l = context.l10n;
    if (name.text.trim().isEmpty) return l.purchNameRequired;
    if (country.text.trim().length != 2) return l.purchCountryInvalid;
    final cur = currency.text.trim();
    if (cur.isNotEmpty && cur.length != 3) return l.purchCurrencyInvalid;
    final days = int.tryParse(terms.text.trim());
    if (terms.text.trim().isNotEmpty && (days == null || days < 0)) {
      return l.purchTermsInvalid;
    }
    return null;
  }

  int? get _terms => int.tryParse(terms.text.trim());

  /// The payload that creates a supplier from the draft.
  NewSupplierInput toNew() => NewSupplierInput(
    name: name.text.trim(),
    code: code.text.trim().isEmpty ? null : code.text.trim(),
    country: country.text.trim().toUpperCase(),
    currency: currency.text.trim().isEmpty ? null : currency.text.trim(),
    paymentTermsDays: _terms,
    taxId: taxId.text.trim(),
    email: email.text.trim(),
    phone: phone.text.trim(),
    contactPerson: contact.text.trim(),
    notes: notes.text.trim(),
  );

  /// The payload that updates a supplier from the draft (every field is sent).
  UpdateSupplierInput toUpdate() => UpdateSupplierInput(
    name: name.text.trim(),
    code: code.text.trim().isEmpty ? null : code.text.trim(),
    country: country.text.trim().toUpperCase(),
    currency: currency.text.trim().isEmpty ? null : currency.text.trim(),
    paymentTermsDays: _terms,
    taxId: taxId.text.trim(),
    email: email.text.trim(),
    phone: phone.text.trim(),
    contactPerson: contact.text.trim(),
    notes: notes.text.trim(),
    active: active,
  );
}

/// The input fields of a [SupplierDraft], laid out in wrapping rows.
class SupplierFields extends StatelessWidget {
  /// Shows the fields of [draft]; [showActive] adds the active switch (existing suppliers).
  const SupplierFields({
    super.key,
    required this.draft,
    this.showActive = false,
    this.onActiveChanged,
    this.enabled = true,
  });

  /// The draft being edited.
  final SupplierDraft draft;

  /// Whether to show the active switch.
  final bool showActive;

  /// Called when the active switch is toggled.
  final ValueChanged<bool>? onActiveChanged;

  /// False while a request is pending: all inputs are disabled.
  final bool enabled;

  Widget _field(
    String key,
    TextEditingController c,
    String label, {
    double width = 240,
    int maxLines = 1,
    TextInputType? type,
  }) => SizedBox(
    width: width,
    child: TextField(
      key: ValueKey('supplier-$key'),
      controller: c,
      maxLines: maxLines,
      keyboardType: type,
      enabled: enabled,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _field('name', draft.name, l.name, width: 340),
        _field('code', draft.code, l.code, width: 140),
        _field('country', draft.country, l.country, width: 100),
        _field('currency', draft.currency, l.currency, width: 100),
        _field(
          'terms',
          draft.terms,
          l.purchPaymentTerms,
          width: 160,
          type: TextInputType.number,
        ),
        _field('taxid', draft.taxId, l.vatNumber),
        _field('contact', draft.contact, l.contactPerson),
        _field('email', draft.email, l.email),
        _field('phone', draft.phone, l.phone),
        _field('notes', draft.notes, l.notes, width: 500, maxLines: 3),
        if (showActive)
          SizedBox(
            width: 240,
            child: SwitchListTile(
              key: const ValueKey('supplier-active'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.active),
              value: draft.active,
              onChanged: enabled ? onActiveChanged : null,
            ),
          ),
      ],
    );
  }
}

/// Shows the create dialog; returns the new supplier, or null when cancelled.
Future<Supplier?> showNewSupplierDialog(BuildContext context) =>
    showDialog<Supplier>(
      context: context,
      builder: (_) => const _NewSupplierDialog(),
    );

class _NewSupplierDialog extends ConsumerStatefulWidget {
  const _NewSupplierDialog();

  @override
  ConsumerState<_NewSupplierDialog> createState() => _NewSupplierDialogState();
}

class _NewSupplierDialogState extends ConsumerState<_NewSupplierDialog> {
  late final SupplierDraft _draft;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final company = ref.read(meProvider).value?.company;
    _draft = SupplierDraft(
      null,
      country: company?.countryCode ?? 'BE',
      currency: company?.currency ?? 'EUR',
    );
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = _draft.validate(context);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiProvider)
          .purchasing
          .createSupplier(body: _draft.toNew());
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.purchNewSupplier),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SupplierFields(draft: _draft, enabled: !_busy),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TutorialTarget(id: 'supplier-form-save', child: FilledButton(
          key: const ValueKey('supplier-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        )),
      ],
    );
  }
}
