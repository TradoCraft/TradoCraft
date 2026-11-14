import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'finance_settings_page.dart';
import 'invoices_page.dart';

/// One segment of the Finance section (supplier invoices and the match settings).
class FinanceSegment {
  /// Creates a segment shown under [label] when the user holds [permission].
  const FinanceSegment({
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

/// All segments of the Finance page, in display order; the control is hidden while only one
/// segment is visible.
final financeSegments = <FinanceSegment>[
  FinanceSegment(
    id: 'invoices',
    label: (l) => l.finSupplierInvoices,
    permission: 'finance.read',
    builder: (_) => const SupplierInvoicesList(),
  ),
  FinanceSegment(
    id: 'settings',
    label: (l) => l.finSettings,
    permission: 'finance.approve',
    builder: (_) => const FinanceSettingsPage(),
  ),
];

/// The Finance section: a segmented control over its lists, with the selected list below.
class FinancePage extends ConsumerStatefulWidget {
  /// Creates the page.
  const FinancePage({super.key});

  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
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
                key: const ValueKey('finance-retry'),
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
      for (final s in financeSegments)
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
              key: const ValueKey('finance-segments'),
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
            key: ValueKey('finance-${current.id}'),
            child: current.builder(context),
          ),
        ),
      ],
    );
  }
}
