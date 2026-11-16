import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';

const _ruleCategories = [
  'standard',
  'intermediate',
  'reduced',
  'zero',
  'construction',
];

String _categoryLabel(AppLocalizations l, String category) => switch (category) {
  'standard' => l.vatCategoryStandard,
  'intermediate' => l.vatCategoryIntermediate,
  'reduced' => l.vatCategoryReduced,
  'zero' => l.vatCategoryZero,
  'construction' => l.vatCategoryConstruction,
  _ => category,
};

/// Admin view and editor for country-specific, temporal, and building-age VAT rules.
class VatRatesPage extends ConsumerStatefulWidget {
  const VatRatesPage({super.key});

  @override
  ConsumerState<VatRatesPage> createState() => _VatRatesPageState();
}

class _VatRatesPageState extends ConsumerState<VatRatesPage> {
  String _countryFilter = '';
  bool _filterInitialized = false;

  Future<void> _edit([CountryVatRate? rule]) async {
    final defaultCountry =
        ref.read(meProvider).value?.company.countryCode ?? 'BE';
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => VatRateDialog(
        rule: rule,
        defaultCountryCode: _countryFilter.isNotEmpty
            ? _countryFilter
            : defaultCountry,
      ),
    );
    if (saved == true && mounted) {
      ref.invalidate(vatRatesProvider);
    }
  }

  Future<void> _delete(CountryVatRate rule) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(
          l.vatRateDeleteConfirm(
            rule.countryCode,
            _categoryLabel(l, rule.category),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).core.deleteVatRate(id: rule.id),
      success: l.saved,
    );
    if (ok && mounted) ref.invalidate(vatRatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = ref.watch(meProvider).value;
    if (!_filterInitialized && me != null) {
      _countryFilter = me.company.countryCode;
      _filterInitialized = true;
    }
    final ratesAsync = ref.watch(vatRatesProvider);
    final isAdmin = can(ref, 'users.admin');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l.vatRatesTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (isAdmin)
              FilledButton.icon(
                key: const ValueKey('vat-rate-add'),
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: Text(l.vatRateAdd),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ratesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                onPressed: () => ref.invalidate(vatRatesProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (rules) {
            final countries = <String>{
              for (final r in rules) r.countryCode,
            }.toList()
              ..sort();
            final filter = countries.contains(_countryFilter)
                ? _countryFilter
                : '';
            final visible = filter.isEmpty
                ? rules
                : rules.where((r) => r.countryCode == filter).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      initialValue: filter,
                      decoration: InputDecoration(labelText: l.vatRateCountry),
                      items: [
                        DropdownMenuItem(value: '', child: Text(l.all)),
                        for (final c in countries)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) =>
                          setState(() => _countryFilter = v ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final r in visible)
                  ListTile(
                    key: ValueKey('vat-rate-${r.id}'),
                    title: Text(
                      '${r.countryCode} · ${_categoryLabel(l, r.category)} · ${number(r.rate)} %',
                    ),
                    subtitle: Text(
                      [
                        '${date(r.startDate)} – ${r.endDate == null ? l.vatRateOngoing : date(r.endDate!)}',
                        if (r.minBuildingAgeYears != null)
                          '${l.vatRateMinBuildingAge}: ≥ ${r.minBuildingAgeYears}',
                        if (r.notes.isNotEmpty) r.notes,
                      ].join(' · '),
                    ),
                    trailing: isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: l.edit,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(r),
                              ),
                              IconButton(
                                tooltip: l.delete,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(r),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Dialog for creating or editing a country VAT rate rule.
class VatRateDialog extends ConsumerStatefulWidget {
  const VatRateDialog({
    super.key,
    this.rule,
    required this.defaultCountryCode,
  });

  final CountryVatRate? rule;
  final String defaultCountryCode;

  @override
  ConsumerState<VatRateDialog> createState() => _VatRateDialogState();
}

class _VatRateDialogState extends ConsumerState<VatRateDialog> {
  late final _country = TextEditingController(
    text: widget.rule?.countryCode ?? widget.defaultCountryCode,
  );
  late String _category = widget.rule?.category ?? 'standard';
  late final _rate = TextEditingController(
    text: widget.rule != null ? number(widget.rule!.rate) : '',
  );
  late final _minAge = TextEditingController(
    text: widget.rule?.minBuildingAgeYears?.toString() ?? '',
  );
  late final _start = TextEditingController(
    text: _isoDate(widget.rule?.startDate ?? DateTime.now()),
  );
  late final _end = TextEditingController(
    text: widget.rule?.endDate != null ? _isoDate(widget.rule!.endDate!) : '',
  );
  late final _notes = TextEditingController(text: widget.rule?.notes ?? '');
  bool _closePrevious = true;
  bool _busy = false;
  String? _error;

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseIsoDate(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final parsed = DateTime.utc(y, mo, day);
    return parsed.year == y && parsed.month == mo && parsed.day == day
        ? parsed
        : null;
  }

  @override
  void dispose() {
    _country.dispose();
    _rate.dispose();
    _minAge.dispose();
    _start.dispose();
    _end.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final cc = _country.text.trim().toUpperCase();
    final rate = parseDecimalInput(_rate.text);
    final start = _parseIsoDate(_start.text);
    final endText = _end.text.trim();
    final end = endText.isEmpty ? null : _parseIsoDate(endText);
    final minAge = _category == 'construction'
        ? int.tryParse(_minAge.text.trim())
        : null;

    if (cc.length != 2 || rate == null || start == null) {
      setState(() => _error = l.stockInvalidNumbers);
      return;
    }
    if (endText.isNotEmpty && end == null) {
      setState(() => _error = l.vatRateStartDate);
      return;
    }
    if (_category == 'construction' &&
        (minAge == null || minAge < 1 || minAge > 200)) {
      setState(() => _error = l.stockInvalidNumbers);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final body = CountryVatRateInput(
      countryCode: cc,
      category: _category,
      rate: rate,
      minBuildingAgeYears: minAge,
      startDate: start,
      endDate: end,
      notes: _notes.text.trim(),
      closePrevious: widget.rule == null ? _closePrevious : null,
    );
    try {
      final core = ref.read(apiProvider).core;
      if (widget.rule == null) {
        await core.createVatRate(body: body);
      } else {
        await core.updateVatRate(id: widget.rule!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final creating = widget.rule == null;
    return AlertDialog(
      title: Text(creating ? l.vatRateAdd : l.vatRateEdit),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _country,
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l.vatRateCountry,
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.vatRateCategory),
                      items: [
                        for (final c in _ruleCategories)
                          DropdownMenuItem(
                            value: c,
                            child: Text(_categoryLabel(l, c)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l.vatRatePercent),
                    ),
                  ),
                  if (_category == 'construction') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _minAge,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l.vatRateMinBuildingAge,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _start,
                      decoration: InputDecoration(labelText: l.vatRateStartDate),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _end,
                      decoration: InputDecoration(labelText: l.vatRateEndDate),
                    ),
                  ),
                ],
              ),
              if (creating) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _closePrevious,
                  onChanged: (v) => setState(() => _closePrevious = v ?? false),
                  title: Text(l.vatRateClosePrevious),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: InputDecoration(labelText: l.vatRateNotes),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
