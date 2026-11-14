import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../shared/format.dart';
import '../../shared/record_history.dart';
import '../../shared/vat_field.dart';
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
    this.screen = false,
    this.onDone,
  });

  /// Shows the form as a page (the customer screen) instead of a dialog.
  final bool screen;

  /// Screen mode: called with the saved customer, or null when the user closes the form.
  final void Function(Customer? saved)? onDone;

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

  @override
  void initState() {
    super.initState();
    // In the customer screen an edit marks the tab as holding unsaved changes (ADR 0041). A
    // controller also notifies for a cursor or selection move: only a changed text counts.
    for (final t in [
      _code,
      _name,
      _vat,
      _email,
      _phone,
      _street,
      _postal,
      _city,
      _country,
      _discount,
      _terms,
    ]) {
      var last = t.text;
      t.addListener(() {
        if (t.text == last) return;
        last = t.text;
        _markDirty();
      });
    }
  }

  /// Nothing is edited while the form is read-only or a save is under way: an edit made after the
  /// payload was taken would be lost when the saved customer replaces the form.
  bool get _locked => widget.readOnly || _saving;

  void _markDirty() {
    if (widget.screen && !widget.readOnly && mounted) {
      TabScope.reportDirty(context, true);
    }
  }

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
      if (mounted) _finish(saved);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Builds a row that wraps when the page is narrow. [build] gets the available width, or null
  /// in the dialog: its content sits in an `IntrinsicWidth`, which cannot hold a `LayoutBuilder`,
  /// and 560 px fits the single-row layout.
  Widget _responsive(
    Widget Function(BuildContext context, double? width) build,
  ) => widget.screen
      ? LayoutBuilder(builder: (c, box) => build(c, box.maxWidth))
      : Builder(builder: (c) => build(c, null));

  /// Ends the form: a dialog pops with the result, a screen hands it to its owner.
  void _finish(Customer? saved) {
    if (widget.screen) {
      TabScope.reportDirty(context, false);
      widget.onDone?.call(saved);
    } else {
      Navigator.pop(context, saved);
    }
  }

  /// Asks the server about the number in the form (ADR 0058).
  Future<VatCheck> _checkVat({required String number, required bool lookup}) {
    final country = _country.text.trim().toUpperCase();
    return ref
        .read(apiProvider)
        .crm
        .checkCustomerVat(
          vatNumber: number,
          countryCode: country.isEmpty ? null : country,
          excludeId: c?.id,
          lookup: lookup,
        );
  }

  /// Fills the empty name and address fields from what VIES knows. Fields that already hold text
  /// are left as they are. Returns whether anything was filled. Not once the form is being saved:
  /// the payload is already taken, and the fields must keep showing what was sent.
  bool _fillFromVies(ViesLookup v) {
    if (_saving) return false;
    var filled = false;
    void fill(TextEditingController t, String? value) {
      if (value != null && value.isNotEmpty && t.text.trim().isEmpty) {
        t.text = value;
        filled = true;
      }
    }

    fill(_name, v.name);
    fill(_street, v.street);
    fill(_postal, v.postalCode);
    fill(_city, v.city);
    return filled;
  }

  Widget _field(
    TextEditingController t,
    String label, {
    bool required = false,
    String? Function(String)? check,
  }) => TextFormField(
    controller: t,
    readOnly: _locked,
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
    final content = Form(
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
            VatNumberField(
              fieldKey: const ValueKey('customer-vat'),
              controller: _vat,
              label: context.l10n.vatNumber,
              enabled: !widget.readOnly && !_saving,
              check: _checkVat,
              // The lookup makes the server call VIES: for those who may change customers.
              onLookup: !widget.readOnly && can(ref, 'customers.write')
                  ? _fillFromVies
                  : null,
            ),
            gap,
            Row(
              children: [
                Expanded(child: _field(_email, context.l10n.email)),
                gap,
                Expanded(child: _field(_phone, context.l10n.phone)),
              ],
            ),
            gap,
            DropdownButtonFormField<String>(
              isExpanded:
                  true, // a long regime name must not overflow a narrow form
              initialValue: _vatRegime,
              decoration: InputDecoration(labelText: context.l10n.vatRegime),
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
              onChanged: _locked
                  ? null
                  : (v) {
                      setState(() => _vatRegime = v!);
                      _markDirty();
                    },
            ),
            gap,
            _field(_street, context.l10n.street),
            gap,
            _responsive((context, width) {
              final postal = SizedBox(
                width: 110,
                child: _field(_postal, context.l10n.postalCode),
              );
              final country = SizedBox(
                width: 80,
                child: _field(
                  _country,
                  context.l10n.country,
                  check: (s) => s.length == 2 ? null : context.l10n.twoLetters,
                ),
              );
              final language = SizedBox(
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
                  onChanged: _locked
                      ? null
                      : (v) {
                          setState(() => _language = v!);
                          _markDirty();
                        },
                ),
              );
              // The fixed fields take 110 + 80 + 110 and three gaps; the city needs room too.
              const fixed = 110 + 80 + 110 + 3 * 12;
              if (width == null || width >= fixed + 160) {
                return Row(
                  children: [
                    postal,
                    gap,
                    Expanded(child: _field(_city, context.l10n.city)),
                    gap,
                    country,
                    gap,
                    language,
                  ],
                );
              }
              // Too narrow for one row (a phone, a narrow tab): the fields wrap, same widths.
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  postal,
                  SizedBox(
                    width: (width - 110 - 12).clamp(120.0, width),
                    child: _field(_city, context.l10n.city),
                  ),
                  country,
                  language,
                ],
              );
            }),
            const Divider(height: 32),
            _responsive((context, width) {
              final zone = zones.when(
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
                  onChanged: _locked
                      ? null
                      : (v) {
                          setState(() => _zoneId = v);
                          _markDirty();
                        },
                  validator: (v) => v == null ? context.l10n.required : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(errorMessage(e)),
              );
              final discount = SizedBox(
                width: 110,
                child: _field(
                  _discount,
                  context.l10n.generalRebatePercent,
                  check: (s) => parseDecimalInput(s.isEmpty ? '0' : s) == null
                      ? context.l10n.numberRequired
                      : null,
                ),
              );
              final terms = SizedBox(
                width: 120,
                child: _field(
                  _terms,
                  context.l10n.paymentDays,
                  check: (s) => int.tryParse(s) == null
                      ? context.l10n.numberRequired
                      : null,
                ),
              );
              // The zone dropdown needs about 300 px next to the two fixed fields.
              if (width == null || width >= 110 + 120 + 24 + 300) {
                return Row(
                  children: [
                    Expanded(child: zone),
                    gap,
                    discount,
                    gap,
                    terms,
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: width, child: zone),
                  discount,
                  terms,
                ],
              );
            }),
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
    );
    final actions = [
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
            if (!widget.screen) Navigator.pop(context);
            router.push('/jobs/equipment/${c!.id}');
          },
        ),
      if (c != null)
        RecordHistoryButton(entity: 'customer', id: c!.id, title: c!.name),
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
        onPressed: () => _finish(null),
        child: Text(widget.readOnly ? context.l10n.close : context.l10n.cancel),
      ),
      if (!widget.readOnly)
        TutorialTarget(
          id: 'customer-form-save',
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.l10n.save),
          ),
        ),
    ];
    if (widget.screen) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(c == null ? context.l10n.newCustomer : c!.name),
      content: SizedBox(width: 560, child: content),
      actions: actions,
    );
  }
}
