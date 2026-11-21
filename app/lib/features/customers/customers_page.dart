import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/csv_transfer.dart';
import '../../framework/search/filter_model.dart';
import '../../shared/entity_list.dart';
import 'customer_repository.dart';
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
    final repo = ref.watch(customerRepositoryProvider);
    final permissions = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = permissions.contains('customers.write');
    return EntityList<Customer>(
      key: _list,
      title: context.l10n.customers,
      loadQuery: (query) async => (await repo.list(query)).asLoaderResult,
      prefsKey: 'customers',
      filterDefs: [
        FilterDef(
          key: 'active',
          label: context.l10n.status,
          options: [
            ('true', context.l10n.active),
            ('false', context.l10n.inactive),
          ],
        ),
      ],
      resizableColumns: true,
      columnMenu: true,
      columns: [
        EntityColumn(context.l10n.code, (c) => c.code, sortKey: 'code'),
        EntityColumn(
          context.l10n.name,
          (c) => c.name,
          flex: 3,
          sortKey: 'name',
        ),
        EntityColumn(
          context.l10n.city,
          (c) => c.city,
          flex: 2,
          sortKey: 'city',
        ),
        EntityColumn(
          context.l10n.vat,
          (c) => c.vatNumber ?? '',
          flex: 2,
          sortKey: 'vat_number',
        ),
        EntityColumn(context.l10n.zone, (c) => c.priceZoneCode ?? '—'),
      ],
      actions: [
        if (canWrite && permissions.contains('kb.read'))
          TextButton(
            onPressed: () => context.push('/customers/mail-merge'),
            child: Text(context.l10n.mailMerge),
          ),
        CsvMenu(
          entity: context.l10n.customers,
          exportPath: '/api/v1/customers/export',
          fileStem: 'customers',
          canExport: permissions.contains('customers.read'),
          canImport: canWrite,
          importer: (bytes, {required dryRun}) => postImportFile(
            ref.read(dioProvider),
            '/api/v1/customers/import',
            bytes,
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
