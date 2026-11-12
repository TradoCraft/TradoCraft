import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import 'supplier_form.dart';

/// The suppliers list of the Purchasing section: search, active filter, create, open in a tab.
class SuppliersList extends ConsumerStatefulWidget {
  /// Creates the list.
  const SuppliersList({super.key});

  @override
  ConsumerState<SuppliersList> createState() => _SuppliersListState();
}

class _SuppliersListState extends ConsumerState<SuppliersList> {
  final _list = GlobalKey<EntityListState<Supplier>>();
  bool _activeOnly = true;

  /// The API returns the whole (small) supplier list, so search and paging happen here.
  Future<(List<Supplier>, int)> _load(String? q, int offset, int limit) async {
    final all = await ref
        .read(apiProvider)
        .purchasing
        .listSuppliers(activeOnly: _activeOnly);
    final needle = q?.toLowerCase();
    final hits = needle == null
        ? all
        : [
            for (final s in all)
              if ('${s.name} ${s.code} ${s.email} ${s.contactPerson}'
                  .toLowerCase()
                  .contains(needle))
                s,
          ];
    final end = (offset + limit).clamp(0, hits.length);
    return (hits.sublist(offset.clamp(0, end), end), hits.length);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'purchasing.write');
    return EntityList<Supplier>(
      key: _list,
      title: l.purchSuppliers,
      emptyText: l.purchNoSuppliers,
      load: _load,
      columns: [
        EntityColumn(l.code, (s) => s.code),
        EntityColumn(l.name, (s) => s.name, flex: 3),
        EntityColumn(l.country, (s) => s.country),
        EntityColumn(l.contactPerson, (s) => s.contactPerson, flex: 2),
        EntityColumn(
          l.purchPaymentTerms,
          (s) => l.purchDays(s.paymentTermsDays),
        ),
        if (!_activeOnly)
          EntityColumn(l.active, (s) => s.active ? l.yes : l.no),
      ],
      filters: FilterChip(
        key: const ValueKey('suppliers-active-only'),
        label: Text(l.purchActiveOnly),
        selected: _activeOnly,
        onSelected: (v) {
          setState(() => _activeOnly = v);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _list.currentState?.reload(),
          );
        },
      ),
      createTargetId: 'suppliers-create',
      createLabel: l.purchNewSupplier,
      onCreate: canWrite
          ? () async {
              final created = await showNewSupplierDialog(context);
              if (created != null && context.mounted) {
                context.push('/suppliers/${created.id}');
              }
              return created != null;
            }
          : null,
      locationOf: (s) => '/suppliers/${s.id}',
      onOpen: (s) async {
        await context.push('/suppliers/${s.id}');
        return null;
      },
    );
  }
}
