// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/goods_receipt_detail.dart';
import '../models/goods_receipt_summary.dart';
import '../models/new_purchase_order_input.dart';
import '../models/new_supplier_input.dart';
import '../models/purchase_order_detail.dart';
import '../models/purchase_order_summary.dart';
import '../models/receive_goods_input.dart';
import '../models/set_supplier_product_input.dart';
import '../models/supplier.dart';
import '../models/supplier_product.dart';
import '../models/update_purchase_order_input.dart';
import '../models/update_supplier_input.dart';
import '../models/vat_check.dart';

part 'purchasing_client.g.dart';

@RestApi()
abstract class PurchasingClient {
  factory PurchasingClient(Dio dio, {String? baseUrl}) = _PurchasingClient;

  /// [id] - Goods Receipt ID
  @GET('/api/v1/goods-receipts/{id}')
  Future<GoodsReceiptDetail> getReceipt({
    @Path('id') required String id,
  });

  /// [id] - Product ID
  @GET('/api/v1/products/{id}/suppliers')
  Future<List<SupplierProduct>> listProductSuppliers({
    @Path('id') required String id,
  });

  @GET('/api/v1/purchase-orders')
  Future<List<PurchaseOrderSummary>> listOrders({
    @Query('supplier_id') String? supplierId,
    @Query('status') String? status,
  });

  @POST('/api/v1/purchase-orders')
  Future<PurchaseOrderDetail> createOrder({
    @Body() required NewPurchaseOrderInput body,
  });

  /// [id] - Purchase Order ID
  @GET('/api/v1/purchase-orders/{id}')
  Future<PurchaseOrderDetail> getOrder({
    @Path('id') required String id,
  });

  /// [id] - Purchase Order ID
  @PUT('/api/v1/purchase-orders/{id}')
  Future<PurchaseOrderDetail> updateOrder({
    @Path('id') required String id,
    @Body() required UpdatePurchaseOrderInput body,
  });

  /// [id] - Purchase Order ID
  @POST('/api/v1/purchase-orders/{id}/approve')
  Future<PurchaseOrderDetail> approveOrder({
    @Path('id') required String id,
  });

  /// [id] - Purchase Order ID
  @POST('/api/v1/purchase-orders/{id}/cancel')
  Future<PurchaseOrderDetail> cancelOrder({
    @Path('id') required String id,
  });

  /// [id] - Purchase Order ID
  @GET('/api/v1/purchase-orders/{id}/receipts')
  Future<List<GoodsReceiptSummary>> listOrderReceipts({
    @Path('id') required String id,
  });

  /// [id] - Purchase Order ID
  @POST('/api/v1/purchase-orders/{id}/receipts')
  Future<GoodsReceiptDetail> receiveGoods({
    @Path('id') required String id,
    @Body() required ReceiveGoodsInput body,
  });

  /// [id] - Purchase Order ID
  @POST('/api/v1/purchase-orders/{id}/send')
  Future<PurchaseOrderDetail> sendOrder({
    @Path('id') required String id,
  });

  /// [q] - Searches name, code, e-mail address and contact person, ignoring case and accents.
  @GET('/api/v1/suppliers')
  Future<List<Supplier>> listSuppliers({
    @Query('active_only') bool? activeOnly,
    @Query('q') String? q,
  });

  @POST('/api/v1/suppliers')
  Future<Supplier> createSupplier({
    @Body() required NewSupplierInput body,
  });

  /// Checks a supplier's VAT number for the supplier form: the format and check digits, other.
  /// suppliers of the company with the same number, and with `lookup=true` the name and address VIES.
  /// has for it (ADR 0058). Advice only; nothing is stored. The lookup needs `purchasing.write`.
  ///
  /// [vatNumber] - The number as typed, with or without prefix, spaces and dots.
  ///
  /// [countryCode] - The country of the customer or supplier (ISO 3166-1 alpha-2): the prefix of a number typed.
  /// without one.
  ///
  /// [excludeId] - A record to leave out of the duplicates: the one being edited.
  ///
  /// [lookup] - Also ask VIES, for the name and address (needs the write permission of the module).
  @GET('/api/v1/suppliers/vat-check')
  Future<VatCheck> checkSupplierVat({
    @Query('vat_number') required String vatNumber,
    @Query('country_code') String? countryCode,
    @Query('exclude_id') String? excludeId,
    @Query('lookup') bool? lookup,
  });

  /// [id] - Supplier ID
  @GET('/api/v1/suppliers/{id}')
  Future<Supplier> getSupplier({
    @Path('id') required String id,
  });

  /// [id] - Supplier ID
  @PUT('/api/v1/suppliers/{id}')
  Future<Supplier> updateSupplier({
    @Path('id') required String id,
    @Body() required UpdateSupplierInput body,
  });

  /// [id] - Supplier ID
  @GET('/api/v1/suppliers/{id}/products')
  Future<List<SupplierProduct>> listSupplierProducts({
    @Path('id') required String id,
  });

  /// [id] - Supplier ID.
  ///
  /// [productId] - Product ID.
  @POST('/api/v1/suppliers/{id}/products/{product_id}')
  Future<SupplierProduct> setSupplierProduct({
    @Path('id') required String id,
    @Path('product_id') required String productId,
    @Body() required SetSupplierProductInput body,
  });

  /// [id] - Supplier ID.
  ///
  /// [productId] - Product ID.
  @DELETE('/api/v1/suppliers/{id}/products/{product_id}')
  Future<void> deleteSupplierProduct({
    @Path('id') required String id,
    @Path('product_id') required String productId,
  });
}
