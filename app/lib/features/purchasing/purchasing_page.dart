import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'orders_page.dart';
import 'suppliers_page.dart';

/// One segment of the Purchasing section (suppliers now; purchase orders and receipts follow).
class PurchasingSegment {
  /// Creates a segment shown under [label] when the user holds [permission].
  const PurchasingSegment({
    required this.id,
    required this.label,
    required this.permission,
    required this.builder,
  });

  /// Stable identifier, used for the widget keys and the selection.
  final String id;

  /// Localized caption of the segment button.
  final String Function(AppLocalizations l) label;

  /// The permission that makes the segment visible.
  final String permission;

  /// Builds the body of the segment.
  final WidgetBuilder builder;
}

/// All segments of the Purchasing page, in display order. Purchase orders (3b) and goods receipts
/// (3c) are added here; the control is hidden while only one segment is visible.
final purchasingSegments = <PurchasingSegment>[
  PurchasingSegment(
    id: 'suppliers',
    label: (l) => l.purchSuppliers,
    permission: 'purchasing.read',
    builder: (_) => const SuppliersList(),
  ),
  PurchasingSegment(
    id: 'orders',
    label: (l) => l.purchOrders,
    permission: 'purchasing.read',
    builder: (_) => const PurchaseOrdersList(),
  ),
];

/// The Purchasing section: a segmented control over its lists, with the selected list below.
class PurchasingPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const PurchasingPage({super.key});

  @override
  ConsumerState<PurchasingPage> createState() => _PurchasingPageState();
}

class _PurchasingPageState extends ConsumerState<PurchasingPage> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final perms = me.value?.permissions;
    if (perms == null) {
      if (me.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorMessage(me.error!)),
              TextButton(
                key: const ValueKey('purchasing-retry'),
                onPressed: () => ref.invalidate(meProvider),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final segments = [
      for (final s in purchasingSegments)
        if (perms.contains(s.permission)) s,
    ];
    if (segments.isEmpty) return Center(child: Text(context.l10n.noAccess));
    final current = segments.firstWhere(
      (s) => s.id == _selected,
      orElse: () => segments.first,
    );
    return Column(
      children: [
        if (segments.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<String>(
              key: const ValueKey('purchasing-segments'),
              showSelectedIcon: false,
              segments: [
                for (final s in segments)
                  ButtonSegment(
                    value: s.id,
                    label: Text(s.label(context.l10n)),
                  ),
              ],
              selected: {current.id},
              onSelectionChanged: (v) => setState(() => _selected = v.first),
            ),
          ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('purchasing-${current.id}'),
            child: current.builder(context),
          ),
        ),
      ],
    );
  }
}
