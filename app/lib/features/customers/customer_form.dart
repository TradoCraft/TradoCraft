import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../framework/components/chatter/chatter_panel.dart';
import '../../framework/components/chatter/chatter_repository.dart';
import '../../framework/form/record_form_controller.dart';
import '../../framework/form/record_form_view.dart';
import '../../shared/decimal_field.dart';
import '../../shared/format.dart';
import '../../shared/record_history.dart';
import '../../shared/vat_field.dart';
import '../contacts/contacts_dialog.dart';
import 'closures_dialog.dart';
import 'customer_repository.dart';
import 'rebates_dialog.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

final customerCountsProvider = FutureProvider.autoDispose
    .family<CustomerCounts?, String>((ref, id) async {
      try {
        return await ref.watch(apiProvider).crm.getCustomerCounts(id: id);
      } catch (_) {
        return null;
      }
    });

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

/// The customer form, as a dialog (the list) or as a page (`screen`, the customer screen). The
/// page is a `RecordFormView` (ADR 0085): header, smart buttons for the related records, the
/// concurrent-edit banner and unsaved-edit tracking come from there.
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
    this.titleExtras = const [],
  });

  /// Shows the form as a page (the customer screen) instead of a dialog.
  final bool screen;

  /// Screen mode: called with the saved customer, or null when the user closes the form.
  final void Function(Customer? saved)? onDone;

  /// Screen mode: shown next to the title (the to-do button).
  final List<Widget> titleExtras;

  final String? initialName;
  final String? initialEmail;
  final String? initialLanguage;

  final Customer? customer;
  final bool readOnly;

  @override
  ConsumerState<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<CustomerForm> {
  late final _form = RecordFormController<Customer>(
    initial: widget.customer,
    versionOf: (c) => c.version,
  );
  Customer? get c => _form.record;
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
  late final _discount = DecimalInputController(
    text: editableDecimal(c?.discountPercent ?? '0'),
    scale: 2,
    percentagePoints: true,
  );
  late final _terms = TextEditingController(
    text: '${c?.paymentTermsDays ?? 30}',
  );
  late String _language = c?.language ?? widget.initialLanguage ?? 'nl';
  late String _vatRegime = c?.vatRegime ?? 'domestic';
  bool _vatRegimeManuallyChanged = false;
  late String? _zoneId = c?.priceZoneId;

  /// Bumped when a reload replaces the dropdown values, so they show the new ones.
  int _reloads = 0;

  List<TextEditingController> get _texts => [
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
  ];

  String? _nn(TextEditingController t) =>
      t.text.trim().isEmpty ? null : t.text.trim();

  @override
  void initState() {
    super.initState();
    _form.addListener(_rebuild);
    if (c == null) {
      final co = ref.read(meProvider).value?.company.countryCode ?? '';
      if (co.isNotEmpty) {
        _vatRegime = deriveDefaultVatRegime(
          companyCountry: co,
          customerCountry: _country.text,
          vatNumber: _vat.text,
        );
      }
    } else {
      _form.watch(ref, entityType: 'customer', recordId: c!.id);
    }
    // Tracked even when read-only now: permissions can load after the form is built, and the
    // view only reports edits to the tab while the form is writable.
    _texts.forEach(_form.track);
    for (final t in [_country, _vat]) {
      var last = t.text;
      t.addListener(() {
        if (t.text == last) return;
        last = t.text;
        _syncAutoVatRegime();
      });
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.removeListener(_rebuild);
    _form.dispose();
    for (final t in _texts) {
      t.dispose();
    }
    super.dispose();
  }

  void _syncAutoVatRegime() {
    if (c != null || _vatRegimeManuallyChanged) return;
    final co = ref.read(meProvider).value?.company.countryCode ?? '';
    if (co.isEmpty) return;
    final derived = deriveDefaultVatRegime(
      companyCountry: co,
      customerCountry: _country.text,
      vatNumber: _vat.text,
    );
    if (derived != _vatRegime) {
      setState(() => _vatRegime = derived);
    }
  }

  /// Nothing is edited while the form is read-only or a save is under way: an edit made after the
  /// payload was taken would be lost when the saved customer replaces the form.
  bool get _locked => widget.readOnly || _form.busy;

  Future<void> _save() async {
    final repo = ref.read(customerRepositoryProvider);
    final id = c?.id;
    final saved = await _form.save((version) {
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
        discountPercent: _discount.decimal ?? '0',
        paymentTermsDays: int.parse(_terms.text.trim()),
        expectedVersion: version,
      );
      return id == null ? repo.create(input) : repo.update(id, input);
    });
    if (saved != null && mounted) _finish(saved);
  }

  Future<void> _reloadCustomer() async {
    final id = c?.id;
    if (id == null) return;
    await _form.reload(() async {
      final fresh = await ref.read(customerRepositoryProvider).get(id);
      // Filled while the controller is busy: these are not edits.
      if (mounted) _fill(fresh);
      return fresh;
    });
  }

  void _fill(Customer fresh) {
    setState(() {
      _code.text = fresh.code;
      _name.text = fresh.name;
      _vat.text = fresh.vatNumber ?? '';
      _email.text = fresh.email ?? '';
      _phone.text = fresh.phone ?? '';
      _street.text = fresh.street;
      _postal.text = fresh.postalCode;
      _city.text = fresh.city;
      _country.text = fresh.countryCode;
      _discount.text = editableDecimal(fresh.discountPercent ?? '0');
      _terms.text = '${fresh.paymentTermsDays ?? 30}';
      _language = fresh.language;
      _vatRegime = fresh.vatRegime;
      _zoneId = fresh.priceZoneId;
      _reloads++;
    });
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
    if (_form.busy) return false;
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
    _syncAutoVatRegime();
    return filled;
  }

  void _edited(VoidCallback change) {
    setState(change);
    _form.markDirty();
  }

  Widget _field(
    TextEditingController t,
    String label, {
    bool required = false,
    String? Function(String)? check,
  }) => TextFormField(
    controller: t,
    focusNode: t is DecimalInputController ? t.focusNode : null,
    readOnly: _locked,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final s = (v ?? '').trim();
      if (required && s.isEmpty) return context.l10n.required;
      return check?.call(s);
    },
  );

  /// The fields, shared by the dialog and the page.
  Widget _fields(BuildContext context) {
    final zones = ref.watch(priceZonesProvider);
    const gap = SizedBox(width: 12, height: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 140,
              child: _field(_code, context.l10n.code, required: true),
            ),
            gap,
            Expanded(child: _field(_name, context.l10n.name, required: true)),
          ],
        ),
        gap,
        VatNumberField(
          fieldKey: const ValueKey('customer-vat'),
          controller: _vat,
          label: context.l10n.vatNumber,
          enabled: !_locked,
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
          key: ValueKey('vat-regime-$_vatRegime'),
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
              value: 'domestic_reverse_charge',
              child: Text(context.l10n.vatRegimeDomesticReverseCharge),
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
              : (v) => _edited(() {
                  _vatRegime = v!;
                  _vatRegimeManuallyChanged = true;
                }),
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
              key: ValueKey('language-$_reloads'),
              initialValue: _language,
              decoration: InputDecoration(labelText: context.l10n.appLanguage),
              items: const [
                DropdownMenuItem(value: 'nl', child: Text('NL')),
                DropdownMenuItem(value: 'fr', child: Text('FR')),
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'de', child: Text('DE')),
                DropdownMenuItem(value: 'es', child: Text('ES')),
              ],
              onChanged: _locked ? null : (v) => _edited(() => _language = v!),
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
              key: ValueKey('zone-$_reloads'),
              initialValue: _zoneId,
              decoration: InputDecoration(labelText: context.l10n.priceZone),
              items: [
                for (final z in list)
                  DropdownMenuItem(
                    value: z.id,
                    child: Text('${z.code} – ${z.name}'),
                  ),
                // The stored zone is no longer offered (inactive or missing): keep it
                // selectable so editing does not change the customer's zone.
                if (c?.priceZoneId != null &&
                    !list.any((z) => z.id == c?.priceZoneId))
                  DropdownMenuItem(
                    value: c?.priceZoneId,
                    child: Text(c?.priceZoneCode ?? c!.priceZoneId!),
                  ),
              ],
              onChanged: _locked ? null : (v) => _edited(() => _zoneId = v),
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
              check: (s) => s.isNotEmpty && _discount.decimal == null
                  ? context.l10n.cfgInvalidNumber
                  : null,
            ),
          );
          final terms = SizedBox(
            width: 120,
            child: _field(
              _terms,
              context.l10n.paymentDays,
              check: (s) =>
                  int.tryParse(s) == null ? context.l10n.numberRequired : null,
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
      ],
    );
  }

  bool get _canSeeEquipment =>
      ref.read(meProvider).value?.permissions.contains('field.read') ?? false;

  void _openEquipment() {
    final router = GoRouter.of(context);
    if (!widget.screen) Navigator.pop(context);
    router.push('/jobs/equipment/${c!.id}');
  }

  Future<void> _openContacts() async {
    await showContactsDialog(context, c!);
    if (mounted) ref.invalidate(customerCountsProvider(c!.id));
  }

  Future<void> _openClosures() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ClosuresDialog(customer: c!),
    );
    if (mounted) ref.invalidate(customerCountsProvider(c!.id));
  }

  Future<void> _openRebates() async {
    await showDialog<void>(
      context: context,
      builder: (_) => RebatesDialog(customer: c!),
    );
    if (mounted) ref.invalidate(customerCountsProvider(c!.id));
  }

  Widget _saveButton() => TutorialTarget(
    id: 'customer-form-save',
    child: FilledButton(
      onPressed: _form.busy ? null : _save,
      child: Text(context.l10n.save),
    ),
  );

  Widget _closeButton() => TextButton(
    onPressed: () => _finish(null),
    child: Text(widget.readOnly ? context.l10n.close : context.l10n.cancel),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(meProvider, (_, _) => _syncAutoVatRegime());
    final c = this.c;
    if (widget.screen) return _page(context, c);
    return _dialog(context, c);
  }

  Widget _page(BuildContext context, Customer? c) {
    final counts = c == null
        ? null
        : ref.watch(customerCountsProvider(c.id)).value;
    return RecordFormView<Customer>(
      controller: _form,
      title: c?.name ?? context.l10n.newCustomer,
      onBack: () => _finish(null),
      titleExtras: widget.titleExtras,
      reportDirty: !widget.readOnly,
      maxSheetWidth: 720,
      chatter: c == null
          ? null
          : ChatterPanel(
              kind: ChatterKind.customer,
              recordId: c.id,
              refresh: _form.chatterTick,
            ),
      onReload: _reloadCustomer,
      actions: [
        if (!widget.readOnly) _saveButton(),
        _closeButton(),
        if (c != null)
          RecordHistoryButton(entity: 'customer', id: c.id, title: c.name),
      ],
      smartButtons: [
        if (c != null) ...[
          SmartButton(
            icon: AppIcons.people,
            label: context.l10n.contacts,
            count: counts == null ? null : '${counts.contacts}',
            onPressed: _openContacts,
          ),
          if (_canSeeEquipment)
            SmartButton(
              icon: AppIcons.precisionManufacturing,
              label: context.l10n.customerEquipment,
              count: counts?.equipment == null ? null : '${counts!.equipment}',
              onPressed: _openEquipment,
            ),
          SmartButton(
            icon: AppIcons.eventBusy,
            label: context.l10n.closures,
            count: counts == null ? null : '${counts.closures}',
            onPressed: _openClosures,
          ),
          SmartButton(
            icon: AppIcons.percent,
            label: context.l10n.productRebates,
            count: counts == null ? null : '${counts.productRebates}',
            onPressed: _openRebates,
          ),
        ],
      ],
      body: _fields(context),
    );
  }

  Widget _dialog(BuildContext context, Customer? c) {
    const gap = SizedBox(width: 12, height: 12);
    final notice = _form.notice;
    final content = Form(
      key: _form.formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice != null) ...[
              RecordConflictNotice(
                notice: notice,
                onReload: _form.busy ? null : _reloadCustomer,
                onDismiss: _form.dismissNotice,
              ),
              gap,
            ],
            _fields(context),
            if (_form.error != null) ...[
              gap,
              Text(
                _form.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
    return AlertDialog(
      title: Text(c == null ? context.l10n.newCustomer : c.name),
      content: SizedBox(width: 560, child: content),
      actions: [
        if (c != null) ...[
          TextButton.icon(
            icon: const Icon(AppIcons.people),
            label: Text(context.l10n.contacts),
            onPressed: () => showContactsDialog(context, c),
          ),
          if (_canSeeEquipment)
            TextButton.icon(
              icon: const Icon(AppIcons.precisionManufacturing),
              label: Text(context.l10n.customerEquipment),
              onPressed: _openEquipment,
            ),
          RecordHistoryButton(entity: 'customer', id: c.id, title: c.name),
          TextButton.icon(
            icon: const Icon(AppIcons.eventBusy),
            label: Text(context.l10n.closures),
            onPressed: _openClosures,
          ),
          TextButton.icon(
            icon: const Icon(AppIcons.percent),
            label: Text(context.l10n.productRebates),
            onPressed: _openRebates,
          ),
        ],
        _closeButton(),
        if (!widget.readOnly) _saveButton(),
      ],
    );
  }
}
