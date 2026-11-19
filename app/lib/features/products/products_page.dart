import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/csv_transfer.dart';
import '../../framework/search/filter_model.dart';
import '../../framework/search/group_model.dart';
import '../../shared/entity_list.dart';
import '../../shared/format.dart';
import '../tutorial/controller.dart';
import 'bulk_price_dialog.dart';
import 'families_dialog.dart';
import 'product_thumb.dart';
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
    ref.listen(productsRefreshProvider, (_, _) => _list.currentState?.reload());
    ref.listen(tutorialAssistCompletedProvider, (_, completed) {
      if (completed == null) return;
      final isProductStep = switch (completed.missionId) {
        'conveyors' => const {
          'motor1p',
          'motor',
          'vfd',
          'conveyor',
        }.contains(completed.stepId),
        'plc' => const {
          'base',
          'lic30',
          'lic50',
          'lic100',
          'expansion',
          'master',
        }.contains(completed.stepId),
        'displays' => const {
          'display',
          'swipe',
          'temp',
        }.contains(completed.stepId),
        'sensors' => const {
          'ir',
          'analog',
          'pusher',
          'labeler',
        }.contains(completed.stepId),
        _ => false,
      };
      if (isProductStep) {
        _list.currentState?.reload();
      }
    });
    final api = ref.watch(apiProvider);
    final permissions = ref.watch(meProvider).value?.permissions ?? const [];
    final canChangePrices = permissions.contains('prices.write');
    final canWrite = permissions.contains('products.write');
    return EntityList<Product>(
      key: _list,
      title: context.l10n.products,
      filterDefs: [
        FilterDef(
          key: 'active',
          label: context.l10n.status,
          options: [
            ('true', context.l10n.active),
            ('false', context.l10n.inactive),
          ],
        ),
        FilterDef(
          key: 'product_type',
          label: context.l10n.type,
          options: [
            for (final t in productTypes) (t, context.l10n.productType(t)),
          ],
        ),
      ],
      groupDefs: [
        GroupDef('active', context.l10n.status),
        GroupDef('product_type', context.l10n.type),
      ],
      loadGroups: (query, groupBy) async {
        final page = await api.products.productGroups(
          groupBy: groupBy,
          q: query.q,
          active: query.flag('active'),
          productType: query.csv('product_type'),
        );
        return [for (final g in page.groups) GroupBucket(g.value, g.count)];
      },
      loadQuery: (query) async {
        final page = await api.products.listProducts(
          q: query.q,
          sort: query.sort,
          active: query.flag('active'),
          productType: query.csv('product_type'),
          offset: query.offset,
          limit: query.limit,
        );
        return (page.items, page.total);
      },
      prefsKey: 'products',
      resizableColumns: true,
      columnMenu: true,
      columns: [
        EntityColumn(
          context.l10n.photos,
          (p) => p.defaultMediaKind ?? '',
          id: 'picture',
          cell: (context, p) => ProductThumb(
            productId: p.id,
            productCode: p.code,
            mediaId: p.defaultMediaId,
            isVideo: p.defaultMediaKind == 'video',
            isModel: p.defaultMediaKind == 'model',
          ),
        ),
        EntityColumn(context.l10n.code, (p) => p.code, sortKey: 'code'),
        EntityColumn(
          context.l10n.name,
          (p) => p.name,
          flex: 3,
          sortKey: 'name',
        ),
        EntityColumn(
          context.l10n.family,
          (p) => p.familyCode ?? '',
          sortKey: 'family_code',
        ),
        EntityColumn(
          context.l10n.type,
          (p) => context.l10n.productType(p.productType),
          sortKey: 'product_type',
        ),
        EntityColumn(
          context.l10n.pricing,
          (p) => context.l10n.pricingFlags(
            nonDiscountable: p.nonDiscountable,
            priceOnRequest: p.priceOnRequest,
            priceIsIndicative: p.priceIsIndicative,
          ),
        ),
        EntityColumn(
          context.l10n.tracking,
          (p) => context.l10n.trackingLabel(p.tracking),
        ),
        EntityColumn(context.l10n.unit, (p) => p.unit, sortKey: 'unit'),
        EntityColumn(
          context.l10n.vat,
          (p) => '${number(p.vatRate)} %',
          numeric: true,
          cell: (_, p) => Text(
            '${number(p.vatRate)} %',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
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
          fileStem: 'products',
          canExport: permissions.contains('products.read'),
          canImport: canWrite,
          importer: (bytes, {required dryRun}) => postImportFile(
            ref.read(dioProvider),
            '/api/v1/products/import',
            bytes,
            dryRun: dryRun,
          ),
          onImported: () => _list.currentState?.reload(),
        ),
      ],
      createLabel: context.l10n.newProduct,
      createTargetId: 'products-create',
      onCreate: canWrite
          ? () async {
              if (GoRouter.maybeOf(context) != null) {
                return await context.push<bool>('/products/new') ?? false;
              }
              return await showProductForm(context) != null;
            }
          : null,
      locationOf: (p) => '/products/${p.id}',
      onOpen: (p) async =>
          await context.push<bool>('/products/${p.id}') ?? true,
    );
  }
}
