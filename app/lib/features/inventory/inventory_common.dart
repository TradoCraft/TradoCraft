import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// True when the signed-in user holds the permission (false while the user is loading).
bool hasPermission(WidgetRef ref, String permission) =>
    ref.watch(meProvider).value?.permissions.contains(permission) ?? false;

/// Warehouses and service vans with their locations.
final warehousesProvider = FutureProvider.autoDispose<List<Warehouse>>(
  (ref) => ref.watch(apiProvider).inventory.listWarehouses(),
);

/// An active location as `(id, "WAREHOUSE/LOCATION")`.
typedef LocationChoice = (String id, String label);

List<LocationChoice> locationChoices(List<Warehouse> warehouses) => [
  for (final w in warehouses)
    if (w.active)
      for (final l in w.locations)
        if (l.active) (l.id, '${w.code}/${l.code}'),
];

/// Picks one of the active locations.
class LocationField extends ConsumerWidget {
  const LocationField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);
    // A failed load must not look like "no locations are configured": say so and offer a retry
    // that keeps the dialog open.
    if (warehouses.hasError && !warehouses.hasValue) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorMessage(warehouses.error!),
          errorMaxLines: 3,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(AppIcons.refresh),
            label: Text(context.l10n.retry),
            onPressed: () => ref.invalidate(warehousesProvider),
          ),
        ),
      );
    }
    final choices = locationChoices(warehouses.value ?? []);
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${choices.length}'),
      initialValue: choices.any((c) => c.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        // An empty list greys the field out; say why and where to fix it.
        helper: choices.isEmpty && warehouses.hasValue
            ? Text(
                context.l10n.stockNoLocationsHint,
                key: const ValueKey('no-locations-hint'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : null,
        helperMaxLines: 3,
      ),
      items: [
        for (final c in choices)
          DropdownMenuItem(value: c.$1, child: Text(c.$2)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Availability state of an order line as a coloured chip.
class StockStateChip extends StatelessWidget {
  const StockStateChip(this.state, {super.key});
  final String state;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (label, color) = switch (state) {
      'reserved' => (l.stockStateReserved, Colors.green.shade700),
      'available' => (l.stockStateAvailable, Colors.green.shade700),
      'partial' => (l.stockStatePartial, Colors.orange.shade800),
      'short' => (l.stockStateShort, Colors.red.shade700),
      _ => (l.stockStateNotStocked, Colors.grey.shade600),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color)),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.transparent,
    );
  }
}

/// Section title used on the stock screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Row(
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}
