import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../planning/board_model.dart' show dateOnly;
import 'production_page.dart';

/// How many days the grid shows.
const capacityDays = 14;

typedef _Period = ({DateTime from, String? division});

final _capacityProvider = FutureProvider.autoDispose
    .family<ProductionCapacity, _Period>(
      (ref, p) => ref
          .watch(apiProvider)
          .production
          .productionCapacity(
            from: p.from,
            to: p.from.add(const Duration(days: capacityDays - 1)),
            divisionId: p.division,
          ),
    );

/// Hours with one decimal where needed: 480 minutes is "8", 450 is "7.5".
String _hours(int minutes) =>
    (minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1);

/// Capacity of the work centres per day against the load of the open operations. A view for
/// planners to see overload; moving work is done on the production orders.
class CapacityPage extends ConsumerStatefulWidget {
  const CapacityPage({super.key});

  @override
  ConsumerState<CapacityPage> createState() => _CapacityPageState();
}

class _CapacityPageState extends ConsumerState<CapacityPage> {
  DateTime _from = dateOnly(DateTime.now());
  String? _division;

  void _move(int days) =>
      setState(() => _from = dateOnly(_from.add(Duration(days: days))));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final divisions = ref.watch(divisionsProvider).value ?? const <Division>[];
    final cap = ref.watch(
      _capacityProvider((from: _from, division: _division)),
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.productionCapacity)),
      body: !perms.contains('production.read')
          ? Center(child: Text(l.noPermission))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('capacity-earlier'),
                      tooltip: l.productionCapacityEarlier,
                      icon: const Icon(AppIcons.chevronLeft),
                      onPressed: () => _move(-7),
                    ),
                    OutlinedButton(
                      key: const ValueKey('capacity-today'),
                      onPressed: () =>
                          setState(() => _from = dateOnly(DateTime.now())),
                      child: Text(l.productionCapacityToday),
                    ),
                    IconButton(
                      key: const ValueKey('capacity-later'),
                      tooltip: l.productionCapacityLater,
                      icon: const Icon(AppIcons.chevronRight),
                      onPressed: () => _move(7),
                    ),
                    if (divisions.isNotEmpty)
                      DropdownButton<String?>(
                        key: const ValueKey('capacity-division'),
                        value: _division,
                        hint: Text(l.productionDivision),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(l.productionDivision),
                          ),
                          for (final d in divisions)
                            DropdownMenuItem(value: d.id, child: Text(d.name)),
                        ],
                        onChanged: (v) => setState(() => _division = v),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.productionCapacityLegend,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                cap.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Center(child: Text(errorMessage(e))),
                  data: (c) => c.centres.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.productionCapacityEmpty),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Table(
                            defaultColumnWidth: const FixedColumnWidth(66),
                            columnWidths: const {0: FixedColumnWidth(170)},
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                children: [
                                  const SizedBox.shrink(),
                                  for (final d in c.centres.first.days)
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        '${DateFormat('E', locale).format(d.date)}\n${DateFormat('dd/MM').format(d.date)}',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ),
                                ],
                              ),
                              for (final w in c.centres)
                                TableRow(
                                  key: ValueKey('capacity-row-${w.id}'),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        '${w.code} · ${w.name}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    for (final d in w.days)
                                      Tooltip(
                                        message:
                                            '${minutesText(d.loadMinutes)} / ${minutesText(d.availableMinutes)}'
                                            '${d.overloaded ? ' · ${l.productionCapacityOverloaded}' : ''}',
                                        child: Container(
                                          key: ValueKey(
                                            'capacity-${w.id}-${DateFormat('yyyy-MM-dd').format(d.date)}',
                                          ),
                                          margin: const EdgeInsets.all(1),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          color: d.overloaded
                                              ? scheme.errorContainer
                                              : d.availableMinutes == 0
                                              ? scheme.surfaceContainerHighest
                                              : d.loadMinutes > 0
                                              ? scheme.primaryContainer
                                              : null,
                                          child: Text(
                                            d.availableMinutes == 0 &&
                                                    d.loadMinutes == 0
                                                ? '—'
                                                : '${_hours(d.loadMinutes)}/${_hours(d.availableMinutes)}',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
