import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'power_text.dart';

/// Picks the power grid of a delivery country. Shown only when [country] (ISO alpha-2) has at
/// least [minGrids] (default two) active grids; the first option, "any grid in this country", reports null.
///
/// Shared by the quotation editor and the order edit mode, so both behave the same.
class PowerGridField extends ConsumerWidget {
  const PowerGridField({
    super.key,
    required this.country,
    required this.selectedId,
    required this.onChanged,
    this.minGrids = 2,
  });

  final String country;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// The number of active grids from which the field is shown. The quotation and order screens
  /// keep 2 (one grid is implied there); the opportunity form passes 1, because its grid is an
  /// optional site fact that must be pickable even when the country has a single grid.
  final int minGrids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (country.length != 2) return const SizedBox.shrink();
    final grids = (ref.watch(powerGridsProvider(country)).value ?? const [])
        .where((g) => g.active)
        .toList();
    if (grids.length < minGrids) return const SizedBox.shrink();
    return SizedBox(
      width: 300,
      child: DropdownButtonFormField<String?>(
        key: ValueKey('grid-$country-${grids.length}'),
        initialValue: grids.any((g) => g.id == selectedId) ? selectedId : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.l10n.powerGrid),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(context.l10n.powerAnyGrid),
          ),
          for (final g in grids)
            DropdownMenuItem<String?>(
              value: g.id,
              child: Text(
                powerProfileText(
                  voltage: g.voltageV,
                  phases: g.phases,
                  frequency: g.frequencyHz,
                ),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
