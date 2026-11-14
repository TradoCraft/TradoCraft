import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/format.dart';
import 'families_dialog.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// Bulk price change: choose zones, family, % or amount, rounding and start date;
/// preview the result; then apply. Applying adds new dated prices; history is untouched.
class BulkPriceDialog extends ConsumerStatefulWidget {
  const BulkPriceDialog({super.key});

  @override
  ConsumerState<BulkPriceDialog> createState() => _BulkPriceDialogState();
}

class _BulkPriceDialogState extends ConsumerState<BulkPriceDialog> {
  final Set<String> _zones = {};
  String? _familyId;
  ChangeKind _kind = ChangeKind.percent;
  final _value = TextEditingController();
  String _rounding = '0.01';
  DateTime _from = DateTime.now().add(const Duration(days: 1));
  BulkPricePreview? _preview;
  String? _error;
  bool _busy = false;

  BulkPriceChangeInput? _input() {
    final value = parseDecimalInput(_value.text);
    if (value == null) {
      setState(() => _error = context.l10n.enterChange);
      return null;
    }
    return BulkPriceChangeInput(
      zoneIds: _zones.toList(),
      familyId: _familyId,
      kind: _kind,
      value: value,
      rounding: _rounding,
      validFrom: DateTime(_from.year, _from.month, _from.day),
    );
  }

  Future<void> _run(bool apply) async {
    final input = _input();
    if (input == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).products;
      final result = apply
          ? await api.applyBulk(body: input)
          : await api.previewBulk(body: input);
      if (!mounted) return;
      if (apply) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.pricesCreated(
                result.applied,
                date(result.validFrom),
              ),
            ),
          ),
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _preview = result);
      }
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed() => setState(() => _preview = null);

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(priceZonesProvider).value ?? const [];
    final families = ref.watch(familiesProvider).value ?? const [];
    final theme = Theme.of(context);
    final p = _preview;
    return AlertDialog(
      title: Text(context.l10n.bulkPriceChange),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.zonesNoneAll,
                style: theme.textTheme.labelLarge,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final z in zones)
                    FilterChip(
                      label: Text(z.code),
                      tooltip: z.name,
                      selected: _zones.contains(z.id),
                      onSelected: (v) {
                        setState(
                          () => v ? _zones.add(z.id) : _zones.remove(z.id),
                        );
                        _changed();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _familyId,
                      decoration: InputDecoration(
                        labelText: context.l10n.productFamily,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(context.l10n.allProducts),
                        ),
                        for (final f in families)
                          DropdownMenuItem<String?>(
                            value: f.id,
                            child: Text('${f.code} · ${f.name}'),
                          ),
                      ],
                      onChanged: (v) {
                        _familyId = v;
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<ChangeKind>(
                    segments: const [
                      ButtonSegment(
                        value: ChangeKind.percent,
                        label: Text('%'),
                      ),
                      ButtonSegment(value: ChangeKind.amount, label: Text('€')),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) {
                      _kind = s.first;
                      _changed();
                    },
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _value,
                      decoration: InputDecoration(
                        labelText: context.l10n.change,
                        hintText: _kind == ChangeKind.percent ? '4.5' : '10',
                      ),
                      onChanged: (_) => _changed(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<String>(
                      initialValue: _rounding,
                      decoration: InputDecoration(
                        labelText: context.l10n.roundTo,
                      ),
                      items: const [
                        DropdownMenuItem(value: '0.01', child: Text('0,01')),
                        DropdownMenuItem(value: '0.05', child: Text('0,05')),
                        DropdownMenuItem(value: '0.1', child: Text('0,10')),
                        DropdownMenuItem(value: '1', child: Text('1,00')),
                      ],
                      onChanged: (v) {
                        _rounding = v!;
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.newPricesValidFrom(date(_from))),
                subtitle: Text(context.l10n.bulkKeepsQuotes),
                trailing: Icon(AppIcons.calendarToday),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _from,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    _from = d;
                    _changed();
                  }
                },
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              if (p != null) ...[
                Divider(),
                Text(
                  [
                    context.l10n.pricesWillChange(p.lines.length),
                    if (p.withoutPrice > 0)
                      context.l10n.skippedWithoutPrice(p.withoutPrice),
                    if (p.conflicts > 0)
                      context.l10n.conflictsOnDate(p.conflicts),
                  ].join(' · '),
                  style: theme.textTheme.titleSmall,
                ),
                DataTable(
                  columns: [
                    DataColumn(label: Text(context.l10n.product)),
                    DataColumn(label: Text(context.l10n.zone)),
                    DataColumn(
                      label: Text(context.l10n.current),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(context.l10n.newItem),
                      numeric: true,
                    ),
                  ],
                  rows: [
                    for (final l in p.lines.take(200))
                      DataRow(
                        color: l.conflict
                            ? WidgetStatePropertyAll(
                                theme.colorScheme.errorContainer,
                              )
                            : null,
                        cells: [
                          DataCell(Text('${l.productCode} · ${l.productName}')),
                          DataCell(Text(l.zoneCode)),
                          DataCell(Text(money(l.currentPrice))),
                          DataCell(Text(money(l.newPrice))),
                        ],
                      ),
                  ],
                ),
                if (p.lines.length > 200)
                  Text(context.l10n.andMore(p.lines.length - 200)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(false),
          child: Text(context.l10n.preview),
        ),
        FilledButton(
          onPressed: _busy || p == null || p.lines.isEmpty || p.conflicts > 0
              ? null
              : () => _run(true),
          child: Text(context.l10n.apply),
        ),
      ],
    );
  }
}
