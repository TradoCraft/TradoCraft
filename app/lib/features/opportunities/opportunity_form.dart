import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/format.dart';
import '../../shared/power_grid_field.dart';
import 'baseline_logic.dart';
import '../../shared/search_picker.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

final _customerCountryProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, id) async =>
          (await ref.watch(apiProvider).crm.getCustomer(id: id)).countryCode,
    );

/// Create or edit an opportunity. Returns the saved opportunity, or null when cancelled.
Future<Opportunity?> showOpportunityForm(
  BuildContext context, {
  Opportunity? opportunity,
}) => showDialog<Opportunity>(
  context: context,
  builder: (_) => OpportunityForm(opportunity: opportunity),
);

class OpportunityForm extends ConsumerStatefulWidget {
  const OpportunityForm({super.key, this.opportunity});
  final Opportunity? opportunity;

  @override
  ConsumerState<OpportunityForm> createState() => _OpportunityFormState();
}

class _OpportunityFormState extends ConsumerState<OpportunityForm> {
  late final o = widget.opportunity;
  late final _title = TextEditingController(text: o?.title);
  late final _value = TextEditingController(
    text: o == null ? '' : number(o!.expectedValue),
  );
  late final _probability = TextEditingController(
    text: o == null ? '' : '${o!.probability}',
  );
  late final _notes = TextEditingController(text: o?.notes);
  late String? _customerId = o?.customerId;
  late String? _customerLabel = o?.customerName;
  late DateTime? _close = o?.expectedClose;
  late String? _gridId = o?.powerGridId;

  /// ISO country picked with a new customer; an existing opportunity's comes from its customer.
  String? _pickedCountry;
  String? _error;

  Future<void> _save() async {
    final value = parseDecimalInput(_value.text.isEmpty ? '0' : _value.text);
    final probability = _probability.text.trim().isEmpty
        ? null
        : int.tryParse(_probability.text.trim());
    if (_title.text.trim().isEmpty || _customerId == null || value == null) {
      setState(() => _error = context.l10n.titleCustomerValueRequired);
      return;
    }
    final grid = powerGridInput(stored: o?.powerGridId, chosen: _gridId);
    final body = OpportunityInput(
      title: _title.text.trim(),
      customerId: _customerId!,
      expectedValue: value,
      probability: probability,
      expectedClose: _close,
      notes: _notes.text,
      powerGridId: grid.id,
      clearPowerGrid: grid.clear,
    );
    try {
      final crm = ref.read(apiProvider).crm;
      final saved = o == null
          ? await crm.createOpportunity(body: body)
          : await crm.updateOpportunity(id: o!.id, body: body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The country of the customer decides which grids are on offer.
    final country =
        _pickedCountry ??
        (o == null
            ? ''
            : ref.watch(_customerCountryProvider(o!.customerId)).value ?? '');
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(o == null ? context.l10n.newOpportunity : o!.number),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: context.l10n.title),
            ),
            gap,
            if (o == null)
              SearchPicker<Customer>(
                label: context.l10n.customer,
                display: (c) => '${c.code} · ${c.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .crm
                            .listCustomers(q: q, limit: 20))
                        .items,
                onSelected: (c) => setState(() {
                  _customerId = c.id;
                  _customerLabel = c.name;
                  _pickedCountry = c.countryCode;
                  // A grid belongs to the country of the customer.
                  _gridId = null;
                }),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.customerNamed(_customerLabel ?? '')),
              ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    decoration: InputDecoration(
                      labelText: context.l10n.expectedValueEur,
                    ),
                  ),
                ),
                gap,
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _probability,
                    decoration: InputDecoration(
                      labelText: context.l10n.probabilityPercent,
                      hintText: context.l10n.byStage,
                    ),
                  ),
                ),
              ],
            ),
            gap,
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _close == null
                    ? context.l10n.noExpectedClose
                    : context.l10n.expectedCloseDate(date(_close)),
              ),
              trailing: const Icon(AppIcons.calendarToday),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _close ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _close = d);
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: PowerGridField(
                country: country,
                selectedId: _gridId,
                onChanged: (id) => setState(() => _gridId = id),
              ),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.notes),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(context.l10n.save)),
      ],
    );
  }
}
