import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/csv_transfer.dart';
import '../../shared/entity_list.dart';
import 'customer_form.dart';
import '../../l10n/l10n.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _list = GlobalKey<EntityListState<Customer>>();

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final permissions = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = permissions.contains('customers.write');
    return EntityList<Customer>(
      key: _list,
      title: context.l10n.customers,
      load: (q, offset, limit) async {
        final page = await api.crm.listCustomers(
          q: q,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      columns: [
        EntityColumn(context.l10n.code, (c) => c.code),
        EntityColumn(context.l10n.name, (c) => c.name, flex: 3),
        EntityColumn(context.l10n.city, (c) => c.city, flex: 2),
        EntityColumn(context.l10n.vat, (c) => c.vatNumber ?? '', flex: 2),
        EntityColumn(context.l10n.zone, (c) => c.priceZoneCode ?? '—'),
      ],
      actions: [
        CsvMenu(
          entity: context.l10n.customers,
          exportPath: '/api/v1/customers/export',
          filename: 'customers.csv',
          canExport: permissions.contains('customers.read'),
          canImport: canWrite,
          importer: (csv, {required dryRun}) => postCsv(
            ref.read(dioProvider),
            '/api/v1/customers/import',
            csv,
            dryRun: dryRun,
          ),
          onImported: () => _list.currentState?.reload(),
        ),
      ],
      createTargetId: 'customers-create',
      createLabel: context.l10n.newCustomer,
      onCreate: canWrite ? () => showCustomerForm(context) : null,
      onOpen: (c) =>
          showCustomerForm(context, customer: c, readOnly: !canWrite),
    );
  }
}
