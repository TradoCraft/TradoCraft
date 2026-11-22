import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/search_picker.dart';
import 'customer_billing_page.dart' show BillingJson, billingDay, billingObject;
import 'invoice_form.dart';

const _base = '/api/v1/customer-rebates';
const _languages = {
  'en': 'English',
  'nl': 'Nederlands',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
};

class CustomerRebatesPage extends ConsumerStatefulWidget {
  const CustomerRebatesPage({super.key});

  @override
  ConsumerState<CustomerRebatesPage> createState() =>
      _CustomerRebatesPageState();
}

class _CustomerRebatesPageState extends ConsumerState<CustomerRebatesPage> {
  BillingJson? _settings;
  List<BillingJson> _schedules = [];
  List<BillingJson> _history = [];
  BillingJson? _review;
  Customer? _customer;
  String? _assignment;
  int _assignmentVersion = 0;
  String? _error;
  bool _busy = true;
  int _rateYear = DateTime.now().year;

  String get _customerPath => '$_base/customers/${_customer!.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = errorMessage(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final dio = ref.read(dioProvider);
    _settings = await billingObject(dio.get('$_base/settings'));
    _schedules = (await dio.get<List<dynamic>>('$_base/schedules')).data!
        .cast<BillingJson>();
    if (_customer != null) await _loadCustomer(_customer!);
  });

  Future<void> _loadCustomer(Customer customer) async {
    _customer = customer;
    _assignment = null;
    _review = null;
    _history = [];
    final dio = ref.read(dioProvider);
    final assignment = await billingObject(
      dio.get('$_customerPath/assignment'),
    );
    _assignment = assignment['schedule_name'] as String?;
    _history = (await dio.get<List<dynamic>>('$_customerPath/history')).data!
        .cast<BillingJson>();
  }

  Future<void> _schedule([BillingJson? schedule]) async {
    final edited = await showDialog<BillingJson>(
      context: context,
      builder: (_) => _ScheduleDialog(schedule: schedule),
    );
    if (!mounted || edited == null) return;
    await _run(() async {
      final dio = ref.read(dioProvider);
      if (schedule == null) {
        await dio.post('$_base/schedules', data: edited);
      } else {
        await dio.put('$_base/schedules/${schedule['id']}', data: edited);
      }
      _schedules = (await dio.get<List<dynamic>>('$_base/schedules')).data!
          .cast<BillingJson>();
    });
  }

  Future<void> _settingsDialog() async {
    final edited = await showDialog<BillingJson>(
      context: context,
      builder: (_) => _WordingDialog(settings: _settings!),
    );
    if (!mounted || edited == null) return;
    await _run(() async {
      _settings = await billingObject(
        ref.read(dioProvider).put('$_base/settings', data: edited),
      );
    });
  }

  Future<void> _assign(String? value) => _run(() async {
    try {
      final result = await billingObject(
        ref
            .read(dioProvider)
            .put(
              '$_customerPath/assignment',
              data: {'schedule_name': value == '' ? null : value},
            ),
      );
      _assignment = result['schedule_name'] as String?;
      _review = null;
    } catch (_) {
      _assignmentVersion++;
      rethrow;
    }
  });

  Future<void> _import() async {
    final entry = await showDialog<BillingJson>(
      context: context,
      builder: (_) => const _HistoryDialog(),
    );
    if (!mounted || entry == null) return;
    await _run(() async {
      await ref.read(dioProvider).put('$_customerPath/history', data: entry);
      await _loadCustomer(_customer!);
    });
  }

  Future<void> _reviewRate() => _run(() async {
    _review = await billingObject(
      ref.read(dioProvider).get('$_customerPath/rates/$_rateYear'),
    );
  });

  Future<void> _approveRate() => _run(() async {
    try {
      _review = await billingObject(
        ref
            .read(dioProvider)
            .post(
              '$_customerPath/rates',
              data: {
                'rate_year': _rateYear,
                if (_review?['proposed_rate'] != null)
                  'proposed_rate': _review!['proposed_rate'],
                if (_review?['eligible_sales'] != null)
                  'eligible_sales': _review!['eligible_sales'],
              },
            ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        _review = await billingObject(
          ref.read(dioProvider).get('$_customerPath/rates/$_rateYear'),
        );
      }
      rethrow;
    }
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final names = {
      for (final schedule in _schedules) schedule['name'] as String,
    };
    final review = _review;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(l.retry),
            ),
          ),
        ],
        if (_settings != null)
          ListTile(
            title: Text(l.cbInvoiceWording),
            subtitle: Text(
              _settings!['show_on_invoices'] == true ? l.cbVisible : l.cbHidden,
            ),
            onTap: _busy ? null : _settingsDialog,
          ),
        const Divider(),
        ListTile(
          title: Text(l.cbSchedules),
          trailing: OutlinedButton(
            onPressed: _busy ? null : () => _schedule(),
            child: Text(l.cbAddSchedule),
          ),
        ),
        for (final schedule in _schedules)
          ListTile(
            title: Text('${schedule['name']} · ${schedule['effective_year']}'),
            subtitle: Text(
              (schedule['tiers'] as List)
                  .cast<BillingJson>()
                  .map((tier) => '${tier['threshold']} → ${tier['rate']}%')
                  .join(' · '),
            ),
            onTap: _busy ? null : () => _schedule(schedule),
          ),
        const Divider(),
        SearchPicker<Customer>(
          label: l.customers,
          search: (q) async =>
              (await ref.read(apiProvider).crm.listCustomers(q: q, limit: 20))
                  .items,
          display: (customer) => '${customer.code} · ${customer.name}',
          enabled: !_busy,
          onSelected: (customer) => _run(() => _loadCustomer(customer)),
        ),
        if (_customer case final customer?) ...[
          ListTile(title: Text(customer.name)),
          DropdownButtonFormField<String>(
            key: ValueKey((customer.id, _assignment, _assignmentVersion)),
            initialValue: names.contains(_assignment) ? _assignment : '',
            decoration: InputDecoration(labelText: l.cbAssignedSchedule),
            items: [
              DropdownMenuItem(value: '', child: Text(l.cbNoSchedule)),
              for (final name in names)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: _busy ? null : _assign,
          ),
          ListTile(
            title: Text(l.cbOpeningBalances),
            trailing: OutlinedButton(
              onPressed: _busy ? null : _import,
              child: Text(l.cbImportBalance),
            ),
          ),
          for (final total in _history)
            ListTile(
              title: Text('${total['year']} · ${total['eligible_sales']}'),
              subtitle: Text('${l.cbCutoff}: ${total['cutoff']}'),
            ),
          TextFormField(
            initialValue: '$_rateYear',
            enabled: !_busy,
            decoration: InputDecoration(labelText: l.cbRateYear),
            keyboardType: TextInputType.number,
            onChanged: (value) => setState(() {
              _rateYear = int.tryParse(value) ?? 0;
              _review = null;
            }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _busy || _rateYear < 1900 ? null : _reviewRate,
              child: Text(l.cbReviewRate),
            ),
          ),
          if (review != null)
            ListTile(
              title: Text(
                review['proposed_rate'] == null
                    ? l.cbRateUnavailable
                    : '${review['proposed_rate']}% · ${review['rate_year']}',
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (review['eligible_sales'] != null)
                    Text('${l.cbEligibleSales}: ${review['eligible_sales']}'),
                  if (review['approved_rate'] != null)
                    Text('${l.cbApprovedRate}: ${review['approved_rate']}%'),
                ],
              ),
              trailing:
                  review['proposed_rate'] == null ||
                      review['approved_rate'] != null
                  ? null
                  : FilledButton(
                      onPressed: _busy ? null : _approveRate,
                      child: Text(l.cbApproveRate),
                    ),
            ),
        ],
      ],
    );
  }
}

class _WordingDialog extends StatefulWidget {
  const _WordingDialog({required this.settings});

  final BillingJson settings;

  @override
  State<_WordingDialog> createState() => _WordingDialogState();
}

class _WordingDialogState extends State<_WordingDialog> {
  late bool _show;
  late final Map<String, BillingJson> _wording;

  @override
  void initState() {
    super.initState();
    _show = widget.settings['show_on_invoices'] as bool;
    _wording = {
      for (final entry
          in (widget.settings['wording'] as List).cast<BillingJson>())
        entry['language'] as String: {...entry},
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.cbInvoiceWording),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(l.cbShowProgress),
                value: _show,
                onChanged: (value) => setState(() => _show = value),
              ),
              Text(l.cbWordingHelp),
              const SelectableText(
                '{eligible_sales}  {next_threshold}  {amount_to_next_tier}  {next_rate}  {rate_year}',
              ),
              for (final language in _languages.entries) ...[
                ListTile(title: Text(language.value)),
                TextFormField(
                  initialValue: _wording[language.key]?['active'] as String?,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: l.cbNextTierWording),
                  onChanged: (value) => (_wording[language.key] ??= {
                    'language': language.key,
                  })['active'] = value,
                ),
                TextFormField(
                  initialValue: _wording[language.key]?['highest'] as String?,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l.cbHighestTierWording,
                  ),
                  onChanged: (value) => (_wording[language.key] ??= {
                    'language': language.key,
                  })['highest'] = value,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'show_on_invoices': _show,
            'wording': [
              for (final entry in _wording.values)
                {'active': '', 'highest': '', ...entry},
            ],
          }),
          child: Text(l.cbSave),
        ),
      ],
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({this.schedule});

  final BillingJson? schedule;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late String _name;
  late int _year;
  late List<BillingJson> _tiers;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _name = schedule?['name'] as String? ?? '';
    _year = schedule?['effective_year'] as int? ?? DateTime.now().year + 1;
    _tiers = schedule == null
        ? [
            {'threshold': '0', 'rate': '0'},
          ]
        : [
            for (final tier in (schedule['tiers'] as List).cast<BillingJson>())
              {...tier},
          ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.cbSchedules),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _name,
                decoration: InputDecoration(labelText: l.cbScheduleName),
                onChanged: (value) => setState(() => _name = value.trim()),
              ),
              TextFormField(
                initialValue: '$_year',
                decoration: InputDecoration(labelText: l.cbRateYear),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    setState(() => _year = int.tryParse(value) ?? 0),
              ),
              for (final tier in _tiers)
                Row(
                  key: ObjectKey(tier),
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: tier['threshold']?.toString(),
                        decoration: InputDecoration(labelText: l.cbThreshold),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) => tier['threshold'] = value
                            .trim()
                            .replaceAll(',', '.'),
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        initialValue: tier['rate']?.toString(),
                        decoration: InputDecoration(labelText: l.cbRate),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) =>
                            tier['rate'] = value.trim().replaceAll(',', '.'),
                      ),
                    ),
                    if (_tiers.length > 1)
                      TextButton(
                        onPressed: () => setState(() => _tiers.remove(tier)),
                        child: Text(l.cbRemoveLine),
                      ),
                  ],
                ),
              TextButton(
                onPressed: () =>
                    setState(() => _tiers.add({'threshold': '', 'rate': ''})),
                child: Text(l.cbAddTier),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _name.isEmpty || _year < 1900
              ? null
              : () => Navigator.of(context).pop({
                  'name': _name,
                  'effective_year': _year,
                  'tiers': _tiers,
                }),
          child: Text(l.cbSave),
        ),
      ],
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog();

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  int _year = DateTime.now().year;
  DateTime _cutoff = DateTime(DateTime.now().year - 1, 12, 31);
  String _amount = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.cbImportBalance),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: '$_year',
            decoration: InputDecoration(labelText: l.cbSalesYear),
            keyboardType: TextInputType.number,
            onChanged: (value) =>
                setState(() => _year = int.tryParse(value) ?? 0),
          ),
          InvoiceDateField(
            label: l.cbCutoff,
            value: _cutoff,
            onChanged: (date) => setState(() => _cutoff = date ?? _cutoff),
          ),
          TextFormField(
            decoration: InputDecoration(labelText: l.cbEligibleSales),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (value) =>
                setState(() => _amount = value.trim().replaceAll(',', '.')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _year < 1900 || double.tryParse(_amount) == null
              ? null
              : () => Navigator.of(context).pop({
                  'year': _year,
                  'cutoff': billingDay(_cutoff),
                  'eligible_sales': _amount,
                }),
          child: Text(l.cbImportBalance),
        ),
      ],
    );
  }
}
