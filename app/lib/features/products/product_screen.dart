import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../framework/form/record_form_controller.dart';
import '../../framework/form/record_form_view.dart';
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
  final _form = RecordFormController<Product>(versionOf: (_) => null);
  bool _editing = false;

  String get id => widget.id;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (id == 'new') {
      return ProductForm(
        asTab: true,
        onSaved: (saved) {
          final scope = TabScope.maybeOf(context);
          if (scope != null) {
            final ws = ref.read(workspaceProvider.notifier);
            ws.close(scope.id);
            ws.focusHome();
          } else if (context.mounted) {
            context.go('/products/${saved.id}');
          }
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
          final tabHeight = (MediaQuery.sizeOf(context).height * 0.55).clamp(
            360.0,
            680.0,
          );
          Widget tabBody(Widget child) =>
              SizedBox(height: tabHeight, child: child);
          return RecordFormView<Product>(
            controller: _form,
            title: '${p.code} · ${p.name}',
            onBack: () => context.canPop()
                ? context.pop(true)
                : context.go('/products'),
            smartButtons: [
              if (canSeeStock)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.warehouse),
                  label: Text(context.l10n.stockTitle),
                  onPressed: () => context.push('/stock/products/${p.id}'),
                ),
            ],
            actions: [
              if (canWrite)
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.edit),
                  label: Text(context.l10n.edit),
                  onPressed: () async {
                    if (TabScope.maybeOf(context) != null) {
                      setState(() => _editing = true);
                      return;
                    }
                    if (await showProductForm(context, product: p) != null) {
                      ref.invalidate(productProvider(id));
                    }
                  },
                ),
            ],
            body: Wrap(
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
            tabs: [
              FormSheetTab(
                label: context.l10n.prices,
                child: tabBody(PricesTab(product: p)),
              ),
              FormSheetTab(
                label: context.l10n.productMedia,
                child: tabBody(MediaTab(productId: p.id)),
              ),
              if (hasBom)
                FormSheetTab(
                  label: context.l10n.billOfMaterials,
                  child: tabBody(BomTab(product: p)),
                ),
              if (serial)
                FormSheetTab(
                  label: context.l10n.serialNumbers,
                  child: tabBody(SerialsTab(product: p)),
                ),
              FormSheetTab(
                label: context.l10n.powerTab,
                child: tabBody(PowerTab(product: p)),
              ),
              FormSheetTab(
                label: context.l10n.suitabilityTab,
                child: tabBody(SuitabilityTab(product: p)),
              ),
              FormSheetTab(
                label: context.l10n.relatedTab,
                child: tabBody(RelatedTab(product: p)),
              ),
              FormSheetTab(
                label: context.l10n.optionsTab,
                child: tabBody(OptionsTab(product: p)),
              ),
            ],
          );
        },
      ),
    );
  }
}
