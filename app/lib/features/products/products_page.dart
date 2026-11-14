import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/csv_transfer.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import 'bulk_price_dialog.dart';
import 'families_dialog.dart';
import 'packaging_dialog.dart';
import 'power_grids_dialog.dart';
import 'product_form.dart';
import 'relations_dialog.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _list = GlobalKey<EntityListState<Product>>();

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final permissions = ref.watch(meProvider).value?.permissions ?? const [];
    final canChangePrices = permissions.contains('prices.write');
    final canWrite = permissions.contains('products.write');
    return EntityList<Product>(
      key: _list,
      title: context.l10n.products,
      load: (q, offset, limit) async {
        final page = await api.products.listProducts(
          q: q,
          offset: offset,
          limit: limit,
        );
        return (page.items, page.total);
      },
      columns: [
        EntityColumn(context.l10n.code, (p) => p.code),
        EntityColumn(context.l10n.name, (p) => p.name, flex: 3),
        EntityColumn(context.l10n.family, (p) => p.familyCode ?? ''),
        EntityColumn(
          context.l10n.type,
          (p) => context.l10n.productType(p.productType),
        ),
        EntityColumn(
          context.l10n.pricing,
          (p) => p.pricingType == 'list'
              ? ''
              : context.l10n.pricingType(p.pricingType),
        ),
        EntityColumn(
          context.l10n.tracking,
          (p) => context.l10n.trackingLabel(p.tracking),
        ),
        EntityColumn(context.l10n.unit, (p) => p.unit),
        EntityColumn(
          context.l10n.vat,
          (p) => '${number(p.vatRate)} %',
          numeric: true,
        ),
      ],
      actions: [
        OutlinedButton.icon(
          icon: const Icon(AppIcons.category),
          label: Text(context.l10n.families),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const FamiliesDialog(),
          ),
        ),
        if (canWrite)
          OutlinedButton.icon(
            icon: const Icon(AppIcons.inventory),
            label: Text(context.l10n.packagingCategories),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const PackagingDialog(),
            ),
          ),
        if (canWrite)
          OutlinedButton.icon(
            icon: const Icon(AppIcons.bolt),
            label: Text(context.l10n.powerGridsTitle),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const PowerGridsDialog(),
            ),
          ),
        if (canWrite)
          OutlinedButton.icon(
            icon: const Icon(AppIcons.link),
            label: Text(context.l10n.relationsTitle),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const RelationsDialog(),
            ),
          ),
        if (canChangePrices)
          OutlinedButton.icon(
            icon: const Icon(AppIcons.trendingUp),
            label: Text(context.l10n.bulkPriceChange),
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const BulkPriceDialog(),
            ),
          ),
        CsvMenu(
          entity: context.l10n.products,
          exportPath: '/api/v1/products/export',
          filename: 'products.csv',
          canExport: permissions.contains('products.read'),
          canImport: canWrite,
          importer: (csv, {required dryRun}) => postCsv(
            ref.read(dioProvider),
            '/api/v1/products/import',
            csv,
            dryRun: dryRun,
          ),
          onImported: () => _list.currentState?.reload(),
        ),
      ],
      createLabel: context.l10n.newProduct,
      createTargetId: 'products-create',
      onCreate: canWrite
          ? () async => await showProductForm(context) != null
          : null,
      locationOf: (p) => '/products/${p.id}',
      onOpen: (p) async =>
          await context.push<bool>('/products/${p.id}') ?? true,
    );
  }
}
