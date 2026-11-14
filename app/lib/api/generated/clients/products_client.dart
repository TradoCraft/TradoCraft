// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/attribute_definition.dart';
import '../models/attribute_definition_input.dart';
import '../models/bulk_price_change_input.dart';
import '../models/bulk_price_preview.dart';
import '../models/format.dart';
import '../models/import_report.dart';
import '../models/packaging_category.dart';
import '../models/packaging_category_input.dart';
import '../models/power_compatibility_report.dart';
import '../models/power_grid.dart';
import '../models/power_grid_input.dart';
import '../models/power_supply.dart';
import '../models/power_supply_input.dart';
import '../models/price_zone.dart';
import '../models/price_zone_input.dart';
import '../models/product.dart';
import '../models/product_attribute.dart';
import '../models/product_family.dart';
import '../models/product_family_input.dart';
import '../models/product_input.dart';
import '../models/product_option.dart';
import '../models/product_option_input.dart';
import '../models/product_page.dart';
import '../models/product_relation.dart';
import '../models/product_relation_input.dart';
import '../models/product_translation.dart';
import '../models/related_products.dart';
import '../models/zone_price_entry.dart';
import '../models/zone_price_input.dart';

part 'products_client.g.dart';

@RestApi()
abstract class ProductsClient {
  factory ProductsClient(Dio dio, {String? baseUrl}) = _ProductsClient;

  /// [scope] - Only definitions of this scope (`product` or a baseline item type code).
  @GET('/api/v1/attribute-definitions')
  Future<List<AttributeDefinition>> listDefinitions({
    @Query('scope') String? scope,
  });

  @POST('/api/v1/attribute-definitions')
  Future<AttributeDefinition> createDefinition({
    @Body() required AttributeDefinitionInput body,
  });

  @GET('/api/v1/attribute-definitions/{id}')
  Future<AttributeDefinition> getDefinition({
    @Path('id') required String id,
  });

  @PUT('/api/v1/attribute-definitions/{id}')
  Future<AttributeDefinition> updateDefinition({
    @Path('id') required String id,
    @Body() required AttributeDefinitionInput body,
  });

  /// Deletes an unused definition. A definition whose key is stored on products (scope `product`) or.
  /// on baseline items of its type is refused with 409 (deactivate it with `active: false` instead,.
  /// which keeps the stored values readable).
  @DELETE('/api/v1/attribute-definitions/{id}')
  Future<void> deleteDefinition({
    @Path('id') required String id,
  });

  @GET('/api/v1/packaging-categories')
  Future<List<PackagingCategory>> listPackaging();

  @POST('/api/v1/packaging-categories')
  Future<PackagingCategory> createPackaging({
    @Body() required PackagingCategoryInput body,
  });

  @PUT('/api/v1/packaging-categories/{id}')
  Future<PackagingCategory> updatePackaging({
    @Path('id') required String id,
    @Body() required PackagingCategoryInput body,
  });

  /// [country] - Only the grids of this country (ISO alpha-2).
  @GET('/api/v1/power-grids')
  Future<List<PowerGrid>> listPowerGrids({
    @Query('country') String? country,
  });

  @POST('/api/v1/power-grids')
  Future<PowerGrid> createPowerGrid({
    @Body() required PowerGridInput body,
  });

  @PUT('/api/v1/power-grids/{id}')
  Future<PowerGrid> updatePowerGrid({
    @Path('id') required String id,
    @Body() required PowerGridInput body,
  });

  @GET('/api/v1/price-zones')
  Future<List<PriceZone>> listPriceZones();

  /// Creates a price zone in the active company.
  @POST('/api/v1/price-zones')
  Future<PriceZone> createPriceZone({
    @Body() required PriceZoneInput body,
  });

  /// Changes the code, name or sort order of a price zone.
  @PUT('/api/v1/price-zones/{id}')
  Future<PriceZone> updatePriceZone({
    @Path('id') required String id,
    @Body() required PriceZoneInput body,
  });

  /// Deletes a price zone that nothing refers to: refused (409) while zone prices or customer terms use it.
  @DELETE('/api/v1/price-zones/{id}')
  Future<void> deletePriceZone({
    @Path('id') required String id,
  });

  /// Applies a bulk price change: one new dated price per product and zone.
  /// Refused if any product already has a price starting on the same date.
  @POST('/api/v1/prices/bulk/apply')
  Future<BulkPricePreview> applyBulk({
    @Body() required BulkPriceChangeInput body,
  });

  /// Shows what a bulk price change would do, without changing anything.
  @POST('/api/v1/prices/bulk/preview')
  Future<BulkPricePreview> previewBulk({
    @Body() required BulkPriceChangeInput body,
  });

  @GET('/api/v1/product-families')
  Future<List<ProductFamily>> listFamilies();

  @POST('/api/v1/product-families')
  Future<ProductFamily> createFamily({
    @Body() required ProductFamilyInput body,
  });

  @PUT('/api/v1/product-families/{id}')
  Future<ProductFamily> updateFamily({
    @Path('id') required String id,
    @Body() required ProductFamilyInput body,
  });

  /// [productId] - Rules that apply to this product, directly or through its family.
  ///
  /// [familyId] - Rules that name this family.
  ///
  /// [kind] - compatible | incompatible | suggested.
  @GET('/api/v1/product-relations')
  Future<List<ProductRelation>> listProductRelations({
    @Query('product_id') String? productId,
    @Query('family_id') String? familyId,
    @Query('kind') String? kind,
  });

  @POST('/api/v1/product-relations')
  Future<ProductRelation> createProductRelation({
    @Body() required ProductRelationInput body,
  });

  @PUT('/api/v1/product-relations/{id}')
  Future<ProductRelation> updateProductRelation({
    @Path('id') required String id,
    @Body() required ProductRelationInput body,
  });

  /// [q] - Searches code and name, ignoring case and accents.
  @GET('/api/v1/products')
  Future<ProductPage> listProducts({
    @Query('q') String? q,
    @Query('active') bool? active,
    @Query('family_id') String? familyId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/products')
  Future<Product> createProduct({
    @Body() required ProductInput body,
  });

  /// All products as CSV, XLSX or ODS, ordered by code.
  ///
  /// [format] - `csv` (default), `xlsx` or `ods`.
  @GET('/api/v1/products/export')
  Future<String> exportProducts({
    @Query('format') Format? format,
  });

  /// Creates or updates products from a CSV, XLSX or ODS file (detected from the content), keyed by.
  /// `code`. All-or-nothing: with any row error nothing is written (422 with every error);.
  /// `dry_run=true` only reports. `sheet` picks the sheet of a spreadsheet.
  ///
  /// [dryRun] - Validate and count only; nothing is written.
  ///
  /// [sheet] - The sheet to read from an XLSX or ODS file (the first sheet when absent); ignored for CSV.
  ///
  /// [body] - The raw bytes of a file.
  @POST('/api/v1/products/import')
  Future<ImportReport> importProducts({
    @Body() required File body,
    @Query('dry_run') bool? dryRun,
    @Query('sheet') String? sheet,
  });

  @GET('/api/v1/products/{id}')
  Future<Product> getProduct({
    @Path('id') required String id,
  });

  @PUT('/api/v1/products/{id}')
  Future<Product> updateProduct({
    @Path('id') required String id,
    @Body() required ProductInput body,
  });

  /// The typed attributes of a product.
  @GET('/api/v1/products/{id}/attributes')
  Future<List<ProductAttribute>> listAttributes({
    @Path('id') required String id,
  });

  /// Replaces all attributes of a product with the given list (one entry per key).
  @PUT('/api/v1/products/{id}/attributes')
  Future<List<ProductAttribute>> replaceAttributes({
    @Path('id') required String id,
    @Body() required List<ProductAttribute> body,
  });

  /// The options of a product, in display order.
  @GET('/api/v1/products/{id}/options')
  Future<List<ProductOption>> listOptions({
    @Path('id') required String id,
  });

  /// Replaces the options of a product with the given list. Quotations already made keep their lines.
  @PUT('/api/v1/products/{id}/options')
  Future<List<ProductOption>> replaceOptions({
    @Path('id') required String id,
    @Body() required List<ProductOptionInput> body,
  });

  /// [country] - ISO alpha-2 country the product goes to.
  ///
  /// [gridId] - Check against this grid only (it must belong to the country when both are given).
  @GET('/api/v1/products/{id}/power-compatibility')
  Future<PowerCompatibilityReport> getProductPowerCompatibility({
    @Path('id') required String id,
    @Query('country') String? country,
    @Query('grid_id') String? gridId,
  });

  @GET('/api/v1/products/{id}/power-supplies')
  Future<List<PowerSupply>> getProductPowerSupplies({
    @Path('id') required String id,
  });

  /// Replaces the whole supply list of a product (an empty list marks it as non-electrical).
  @PUT('/api/v1/products/{id}/power-supplies')
  Future<List<PowerSupply>> replaceProductPowerSupplies({
    @Path('id') required String id,
    @Body() required List<PowerSupplyInput> body,
  });

  /// Full price history of a product in the active company, newest first per zone.
  @GET('/api/v1/products/{id}/prices')
  Future<List<ZonePriceEntry>> listProductPrices({
    @Path('id') required String id,
  });

  /// Adds a price for a zone from a date. Prices are never edited: a new entry supersedes older ones.
  @POST('/api/v1/products/{id}/prices')
  Future<ZonePriceEntry> addProductPrice({
    @Path('id') required String id,
    @Body() required ZonePriceInput body,
  });

  @GET('/api/v1/products/{id}/related')
  Future<RelatedProducts> getRelatedProducts({
    @Path('id') required String id,
  });

  /// The names and descriptions of a product in other languages.
  @GET('/api/v1/products/{id}/translations')
  Future<List<ProductTranslation>> listTranslations({
    @Path('id') required String id,
  });

  /// Replaces all translations of a product with the given list (one entry per language).
  /// Quotations already priced keep the name they were priced with.
  @PUT('/api/v1/products/{id}/translations')
  Future<List<ProductTranslation>> replaceTranslations({
    @Path('id') required String id,
    @Body() required List<ProductTranslation> body,
  });
}
