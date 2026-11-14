// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/adjustment_input.dart';
import '../models/count_detail.dart';
import '../models/count_entries.dart';
import '../models/count_input.dart';
import '../models/count_page.dart';
import '../models/integrity.dart';
import '../models/issue_input.dart';
import '../models/line_reservation.dart';
import '../models/location.dart';
import '../models/location_input.dart';
import '../models/lot.dart';
import '../models/lot_input.dart';
import '../models/move_page.dart';
import '../models/order_availability.dart';
import '../models/product_stock_page.dart';
import '../models/product_uom.dart';
import '../models/product_uoms_input.dart';
import '../models/rebuilt.dart';
import '../models/receipt_input.dart';
import '../models/reservation_row.dart';
import '../models/reserve_input.dart';
import '../models/reverse_input.dart';
import '../models/stock_move.dart';
import '../models/stock_row_page.dart';
import '../models/transfer_input.dart';
import '../models/uom.dart';
import '../models/uom_input.dart';
import '../models/warehouse.dart';
import '../models/warehouse_input.dart';

part 'inventory_client.g.dart';

@RestApi()
abstract class InventoryClient {
  factory InventoryClient(Dio dio, {String? baseUrl}) = _InventoryClient;

  /// Corrects the stock at a location to a counted quantity, or by a difference.
  @POST('/api/v1/inventory/adjustments')
  Future<StockMove> adjust({
    @Body() required AdjustmentInput body,
  });

  /// Recomputes balances and serial locations from the ledger.
  @POST('/api/v1/inventory/balances/rebuild')
  Future<Rebuilt> rebuild();

  /// [status] - counting | posted | cancelled.
  ///
  /// [q] - Part of the count number or of the warehouse code.
  ///
  /// [limit] - Page size (default 50, at most 200).
  ///
  /// [offset] - Rows to skip, newest first.
  @GET('/api/v1/inventory/counts')
  Future<CountPage> listCounts({
    @Query('status') String? status,
    @Query('warehouse_id') String? warehouseId,
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Starts a count of a warehouse (or a location, or a product in it) and snapshots what the system.
  /// expects. Serial-tracked products are not counted.
  @POST('/api/v1/inventory/counts')
  Future<CountDetail> createCount({
    @Body() required CountInput body,
  });

  @GET('/api/v1/inventory/counts/{id}')
  Future<CountDetail> getCount({
    @Path('id') required String id,
  });

  @POST('/api/v1/inventory/counts/{id}/cancel')
  Future<CountDetail> cancelCount({
    @Path('id') required String id,
  });

  /// Enters counted quantities, and adds lines for stock that was not expected.
  @PUT('/api/v1/inventory/counts/{id}/lines')
  Future<CountDetail> enterCounts({
    @Path('id') required String id,
    @Body() required CountEntries body,
  });

  /// Posts the count: one adjustment move for every counted line whose quantity differs from the.
  /// stock at this moment. Lines without a counted quantity are left alone.
  @POST('/api/v1/inventory/counts/{id}/post')
  Future<CountDetail> postCount({
    @Path('id') required String id,
  });

  /// Compares the balances with the sum of the ledger.
  @GET('/api/v1/inventory/integrity')
  Future<Integrity> integrity();

  /// Takes stock out of a location. The reason decides where it goes: a customer (`shipment`),.
  /// production consumption (`consumption`, `repair_use`) or scrap.
  @POST('/api/v1/inventory/issues')
  Future<StockMove> issue({
    @Body() required IssueInput body,
  });

  @POST('/api/v1/inventory/locations')
  Future<Location> createLocation({
    @Body() required LocationInput body,
  });

  @PUT('/api/v1/inventory/locations/{id}')
  Future<Location> updateLocation({
    @Path('id') required String id,
    @Body() required LocationInput body,
  });

  /// [inStock] - Only lots with stock.
  @GET('/api/v1/inventory/lots')
  Future<List<Lot>> listLots({
    @Query('product_id') String? productId,
    @Query('in_stock') bool? inStock,
  });

  @PUT('/api/v1/inventory/lots/{id}')
  Future<Lot> updateLot({
    @Path('id') required String id,
    @Body() required LotInput body,
  });

  /// [locationId] - Moves from or to this location.
  ///
  /// [kind] - receipt | issue | transfer | adjustment.
  @GET('/api/v1/inventory/moves')
  Future<MovePage> listMoves({
    @Query('product_id') String? productId,
    @Query('location_id') String? locationId,
    @Query('lot_id') String? lotId,
    @Query('serial_unit_id') String? serialUnitId,
    @Query('kind') String? kind,
    @Query('reference_type') String? referenceType,
    @Query('reference_id') String? referenceId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/api/v1/inventory/moves/{id}')
  Future<StockMove> getMove({
    @Path('id') required String id,
  });

  /// Undoes a move with a new move in the opposite direction. The original stays in the ledger.
  @POST('/api/v1/inventory/moves/{id}/reverse')
  Future<StockMove> reverse({
    @Path('id') required String id,
    @Body() required ReverseInput body,
  });

  @GET('/api/v1/inventory/order-lines/{id}/reservation')
  Future<LineReservation> getReservation({
    @Path('id') required String id,
  });

  /// Sets how much stock is reserved for an order line. Idempotent: the same call twice changes.
  /// nothing the second time.
  @PUT('/api/v1/inventory/order-lines/{id}/reservation')
  Future<LineReservation> setReservation({
    @Path('id') required String id,
    @Body() required ReserveInput body,
  });

  /// Availability (ATP) of every line of the order: what is in the warehouses, what is reserved,.
  /// and what this order's lines still lack. Van stock is not counted.
  @GET('/api/v1/inventory/orders/{id}/availability')
  Future<OrderAvailability> orderAvailability({
    @Path('id') required String id,
  });

  @GET('/api/v1/inventory/products/{id}/uoms')
  Future<List<ProductUom>> productUoms({
    @Path('id') required String id,
  });

  /// Replaces the product-specific units (for example a box of 12 pieces).
  @PUT('/api/v1/inventory/products/{id}/uoms')
  Future<List<ProductUom>> setProductUoms({
    @Path('id') required String id,
    @Body() required ProductUomsInput body,
  });

  /// Receives stock at a location from outside (a manual receipt; purchasing posts its own).
  @POST('/api/v1/inventory/receipts')
  Future<StockMove> receive({
    @Body() required ReceiptInput body,
  });

  /// Active reservations, for example to see which orders hold a product. Paged with `limit` and.
  /// `offset`; a page shorter than `limit` is the last one.
  ///
  /// [limit] - Page size (default 100, at most 500).
  ///
  /// [offset] - Rows to skip, in the order of the list.
  @GET('/api/v1/inventory/reservations')
  Future<List<ReservationRow>> listReservations({
    @Query('product_id') String? productId,
    @Query('order_id') String? orderId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// [q] - Searches product code, name, barcode and lot number.
  ///
  /// [includeZero] - Include rows with zero stock (default false).
  @GET('/api/v1/inventory/stock')
  Future<StockRowPage> listStock({
    @Query('product_id') String? productId,
    @Query('warehouse_id') String? warehouseId,
    @Query('location_id') String? locationId,
    @Query('lot_id') String? lotId,
    @Query('q') String? q,
    @Query('include_zero') bool? includeZero,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// [warehouseId] - Count only this warehouse (a van too).
  ///
  /// [q] - Searches code, name and barcode.
  ///
  /// [inStock] - Only products that have stock.
  ///
  /// [belowReorder] - Only products below their reorder minimum.
  @GET('/api/v1/inventory/stock/products')
  Future<ProductStockPage> listProductStock({
    @Query('product_id') String? productId,
    @Query('warehouse_id') String? warehouseId,
    @Query('q') String? q,
    @Query('in_stock') bool? inStock,
    @Query('below_reorder') bool? belowReorder,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Moves stock between two locations (also from a warehouse to a service van).
  @POST('/api/v1/inventory/transfers')
  Future<StockMove> transfer({
    @Body() required TransferInput body,
  });

  @GET('/api/v1/inventory/uoms')
  Future<List<Uom>> listUoms();

  @POST('/api/v1/inventory/uoms')
  Future<Uom> createUom({
    @Body() required UomInput body,
  });

  @GET('/api/v1/inventory/warehouses')
  Future<List<Warehouse>> listWarehouses();

  /// Creates a warehouse or service van with one default location (`MAIN`, for a van `VAN`).
  @POST('/api/v1/inventory/warehouses')
  Future<Warehouse> createWarehouse({
    @Body() required WarehouseInput body,
  });

  @PUT('/api/v1/inventory/warehouses/{id}')
  Future<Warehouse> updateWarehouse({
    @Path('id') required String id,
    @Body() required WarehouseInput body,
  });
}
