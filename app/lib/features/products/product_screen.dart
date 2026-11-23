import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import 'bom_tab.dart';
import 'media_tab.dart';
import 'options_tab.dart';
import 'prices_tab.dart';
import 'power_tab.dart';
import 'suitability_tab.dart';
import 'product_form.dart';
import 'related_tab.dart';
import 'serials_tab.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

final productProvider = FutureProvider.autoDispose.family<Product, String>(
  (ref, id) => ref.watch(apiProvider).products.getProduct(id: id),
);

/// Product detail: prices, bill of materials and serial numbers.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  bool _editing = false;

  String get id => widget.id;

  @override
  Widget build(BuildContext context) {
    if (id == 'new') {
      return ProductForm(
        asTab: true,
        onSaved: (saved) {
          if (context.mounted) context.go('/products/${saved.id}');
        },
      );
    }
    final product = ref.watch(productProvider(id));
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('products.write') ??
        false;
    final canSeeStock =
        ref.watch(meProvider).value?.permissions.contains('inventory.read') ??
        false;
    return Scaffold(
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (p) {
          if (_editing) {
            return ProductForm(
              product: p,
              asTab: true,
              onSaved: (_) {
                ref.invalidate(productProvider(id));
                setState(() => _editing = false);
              },
              onCancel: () {
                TabScope.reportDirty(context, false);
                setState(() => _editing = false);
              },
            );
          }
          final hasBom =
              p.productType == 'manufactured' ||
              p.productType == 'configurable';
          final serial = p.tracking == 'serial';
          final tabs = [
            Tab(text: context.l10n.prices),
            Tab(text: context.l10n.productMedia),
            if (hasBom) Tab(text: context.l10n.billOfMaterials),
            if (serial) Tab(text: context.l10n.serialNumbers),
            Tab(text: context.l10n.powerTab),
            Tab(text: context.l10n.suitabilityTab),
            Tab(text: context.l10n.relatedTab),
            Tab(text: context.l10n.optionsTab),
          ];
          return DefaultTabController(
            length: tabs.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () => context.canPop()
                            ? context.pop(true)
                            : context.go('/products'),
                        icon: const Icon(AppIcons.arrowBack),
                      ),
                      Text(
                        '${p.code} · ${p.name}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (canSeeStock)
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.warehouse),
                          label: Text(context.l10n.stockTitle),
                          onPressed: () =>
                              context.push('/stock/products/${p.id}'),
                        ),
                      if (canWrite)
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.edit),
                          label: Text(context.l10n.edit),
                          onPressed: () async {
                            if (TabScope.maybeOf(context) != null) {
                              setState(() => _editing = true);
                              return;
                            }
                            if (await showProductForm(context, product: p) !=
                                null) {
                              ref.invalidate(productProvider(id));
                            }
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    children: [
                      InfoItem(
                        context.l10n.type,
                        context.l10n.productType(p.productType),
                      ),
                      InfoItem(context.l10n.unit, p.unit),
                      InfoItem(context.l10n.vat, '${number(p.vatRate)} %'),
                      InfoItem(
                        context.l10n.tracking,
                        context.l10n.trackingLabel(p.tracking),
                      ),
                      InfoItem(context.l10n.family, p.familyCode ?? ''),
                      InfoItem(
                        context.l10n.pricing,
                        context.l10n.pricingFlags(
                          nonDiscountable: p.nonDiscountable,
                          priceOnRequest: p.priceOnRequest,
                          priceIsIndicative: p.priceIsIndicative,
                        ),
                      ),
                      InfoItem(
                        context.l10n.status,
                        p.active ? 'active' : 'inactive',
                      ),
                      if (p.packagingCategoryCode != null)
                        InfoItem(
                          context.l10n.packagingCategory,
                          p.packagingCategoryCode!,
                        ),
                      if (p.lengthMm != null &&
                          p.widthMm != null &&
                          p.heightMm != null)
                        InfoItem(
                          context.l10n.dimensions,
                          context.l10n.dimensionsValue(
                            p.lengthMm!,
                            p.widthMm!,
                            p.heightMm!,
                          ),
                        ),
                      if (p.weightG != null)
                        InfoItem(
                          context.l10n.weight,
                          context.l10n.weightValue(p.weightG!),
                        ),
                      if (p.description.isNotEmpty)
                        InfoItem(context.l10n.description, p.description),
                    ],
                  ),
                ),
                TabBar(isScrollable: true, tabs: tabs),
                Expanded(
                  child: TabBarView(
                    children: [
                      PricesTab(product: p),
                      MediaTab(productId: p.id),
                      if (hasBom) BomTab(product: p),
                      if (serial) SerialsTab(product: p),
                      PowerTab(product: p),
                      SuitabilityTab(product: p),
                      RelatedTab(product: p),
                      OptionsTab(product: p),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
