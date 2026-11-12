import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/format.dart';
import '../contacts/contacts_dialog.dart';
import 'closures_dialog.dart';
import 'rebates_dialog.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

/// Shows the customer form; returns true when saved.
Future<bool?> showCustomerForm(
  BuildContext context, {
  Customer? customer,
  bool readOnly = false,
}) async =>
    await showDialog<Customer>(
      context: context,
      builder: (_) => CustomerForm(customer: customer, readOnly: readOnly),
    ) !=
    null;

/// A new customer pre-filled from e.g. a helpdesk ticket. Returns the created customer.
Future<Customer?> showNewCustomerForm(
  BuildContext context, {
  String? name,
  String? email,
  String? language,
}) => showDialog<Customer>(
  context: context,
  builder: (_) => CustomerForm(
    initialName: name,
    initialEmail: email,
    initialLanguage: language,
  ),
);

class CustomerForm extends ConsumerStatefulWidget {
  const CustomerForm({
    super.key,
    this.customer,
    this.readOnly = false,
    this.initialName,
    this.initialEmail,
    this.initialLanguage,
  });

  final String? initialName;
  final String? initialEmail;
  final String? initialLanguage;

  final Customer? customer;
  final bool readOnly;

  @override
  ConsumerState<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<CustomerForm> {
  final _form = GlobalKey<FormState>();
  late final c = widget.customer;
  late final _code = TextEditingController(text: c?.code);
  late final _name = TextEditingController(text: c?.name ?? widget.initialName);
  late final _vat = TextEditingController(text: c?.vatNumber);
  late final _email = TextEditingController(
    text: c?.email ?? widget.initialEmail,
  );
  late final _phone = TextEditingController(text: c?.phone);
  late final _street = TextEditingController(text: c?.street);
  late final _postal = TextEditingController(text: c?.postalCode);
  late final _city = TextEditingController(text: c?.city);
  late final _country = TextEditingController(text: c?.countryCode ?? 'BE');
  late final _discount = TextEditingController(
    text: number(c?.discountPercent ?? '0'),
  );
  late final _terms = TextEditingController(
    text: '${c?.paymentTermsDays ?? 30}',
  );
  late String _language = c?.language ?? widget.initialLanguage ?? 'nl';
  late String _vatRegime = c?.vatRegime ?? 'domestic';
  late String? _zoneId = c?.priceZoneId;
  bool _saving = false;
  String? _error;

  String? _nn(TextEditingController t) =>
      t.text.trim().isEmpty ? null : t.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = CustomerInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      vatNumber: _nn(_vat),
      vatRegime: _vatRegime,
      email: _nn(_email),
      phone: _nn(_phone),
      street: _street.text.trim(),
      postalCode: _postal.text.trim(),
      city: _city.text.trim(),
      countryCode: _country.text.trim().toUpperCase(),
      language: _language,
      priceZoneId: _zoneId!,
      discountPercent: parseDecimalInput(_discount.text) ?? '0',
      paymentTermsDays: int.parse(_terms.text.trim()),
    );
    try {
      final crm = ref.read(apiProvider).crm;
      final saved = c == null
          ? await crm.createCustomer(body: input)
          : await crm.updateCustomer(id: c!.id, body: input);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController t,
    String label, {
    bool required = false,
    String? Function(String)? check,
  }) => TextFormField(
    controller: t,
    readOnly: widget.readOnly,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final s = (v ?? '').trim();
      if (required && s.isEmpty) return context.l10n.required;
      return check?.call(s);
    },
  );

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(priceZonesProvider);
    const gap = SizedBox(width: 12, height: 12);
    return AlertDialog(
      title: Text(c == null ? context.l10n.newCustomer : c!.name),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: _field(_code, context.l10n.code, required: true),
                    ),
                    gap,
                    Expanded(
                      child: _field(_name, context.l10n.name, required: true),
                    ),
                  ],
                ),
                gap,
                Row(
                  children: [
                    Expanded(child: _field(_vat, context.l10n.vatNumber)),
                    gap,
                    Expanded(child: _field(_email, context.l10n.email)),
                    gap,
                    Expanded(child: _field(_phone, context.l10n.phone)),
                  ],
                ),
                gap,
                DropdownButtonFormField<String>(
                  initialValue: _vatRegime,
                  decoration: InputDecoration(
                    labelText: context.l10n.vatRegime,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'domestic',
                      child: Text(context.l10n.vatRegimeDomestic),
                    ),
                    DropdownMenuItem(
                      value: 'intra_eu',
                      child: Text(context.l10n.vatRegimeIntraEu),
                    ),
                    DropdownMenuItem(
                      value: 'outside_eu',
                      child: Text(context.l10n.vatRegimeOutsideEu),
                    ),
                  ],
                  onChanged: widget.readOnly
                      ? null
                      : (v) => setState(() => _vatRegime = v!),
                ),
                gap,
                _field(_street, context.l10n.street),
                gap,
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: _field(_postal, context.l10n.postalCode),
                    ),
                    gap,
                    Expanded(child: _field(_city, context.l10n.city)),
                    gap,
                    SizedBox(
                      width: 80,
                      child: _field(
                        _country,
                        context.l10n.country,
                        check: (s) =>
                            s.length == 2 ? null : context.l10n.twoLetters,
                      ),
                    ),
                    gap,
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        initialValue: _language,
                        decoration: InputDecoration(
                          labelText: context.l10n.appLanguage,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'nl', child: Text('NL')),
                          DropdownMenuItem(value: 'fr', child: Text('FR')),
                          DropdownMenuItem(value: 'en', child: Text('EN')),
                          DropdownMenuItem(value: 'de', child: Text('DE')),
                          DropdownMenuItem(value: 'es', child: Text('ES')),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _language = v!),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: zones.when(
                        data: (list) => DropdownButtonFormField<String>(
                          initialValue: _zoneId,
                          decoration: InputDecoration(
                            labelText: context.l10n.priceZone,
                          ),
                          items: [
                            for (final z in list)
                              DropdownMenuItem(
                                value: z.id,
                                child: Text('${z.code} – ${z.name}'),
                              ),
                          ],
                          onChanged: widget.readOnly
                              ? null
                              : (v) => setState(() => _zoneId = v),
                          validator: (v) =>
                              v == null ? context.l10n.required : null,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text(errorMessage(e)),
                      ),
                    ),
                    gap,
                    SizedBox(
                      width: 110,
                      child: _field(
                        _discount,
                        context.l10n.generalRebatePercent,
                        check: (s) =>
                            parseDecimalInput(s.isEmpty ? '0' : s) == null
                            ? context.l10n.numberRequired
                            : null,
                      ),
                    ),
                    gap,
                    SizedBox(
                      width: 120,
                      child: _field(
                        _terms,
                        context.l10n.paymentDays,
                        check: (s) => int.tryParse(s) == null
                            ? context.l10n.numberRequired
                            : null,
                      ),
                    ),
                  ],
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
        if (c != null)
          TextButton.icon(
            icon: const Icon(AppIcons.people),
            label: Text(context.l10n.contacts),
            onPressed: () => showContactsDialog(context, c!),
          ),
        if (c != null &&
            (ref.read(meProvider).value?.permissions.contains('field.read') ??
                false))
          TextButton.icon(
            icon: const Icon(AppIcons.precisionManufacturing),
            label: Text(context.l10n.customerEquipment),
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.push('/jobs/equipment/${c!.id}');
            },
          ),
        if (c != null)
          TextButton.icon(
            icon: const Icon(AppIcons.eventBusy),
            label: Text(context.l10n.closures),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ClosuresDialog(customer: c!),
            ),
          ),
        if (c != null)
          TextButton.icon(
            icon: const Icon(AppIcons.percent),
            label: Text(context.l10n.productRebates),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RebatesDialog(customer: c!),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.readOnly ? context.l10n.close : context.l10n.cancel,
          ),
        ),
        if (!widget.readOnly)
          TutorialTarget(id: 'customer-form-save', child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.l10n.save),
          )),
      ],
    );
  }
}
