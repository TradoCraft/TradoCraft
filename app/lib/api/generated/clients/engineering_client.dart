// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/attach_input.dart';
import '../models/bom.dart';
import '../models/bom_input.dart';
import '../models/bom_summary.dart';
import '../models/detach_input.dart';
import '../models/explosion.dart';
import '../models/new_bom_input.dart';
import '../models/serial_input.dart';
import '../models/serial_status_input.dart';
import '../models/serial_unit_detail.dart';
import '../models/serial_unit_page.dart';
import '../models/warranty_input.dart';

part 'engineering_client.g.dart';

@RestApi()
abstract class EngineeringClient {
  factory EngineeringClient(Dio dio, {String? baseUrl}) = _EngineeringClient;

  @GET('/api/v1/boms/{id}')
  Future<Bom> getBom({
    @Path('id') required String id,
  });

  /// Replaces the notes and lines of a draft BOM.
  @PUT('/api/v1/boms/{id}')
  Future<Bom> updateBom({
    @Path('id') required String id,
    @Body() required BomInput body,
  });

  /// Makes a draft the active revision. The previous active revision becomes obsolete.
  /// Refused if it would create a cycle anywhere in the product structure.
  @POST('/api/v1/boms/{id}/activate')
  Future<Bom> activateBom({
    @Path('id') required String id,
  });

  /// Explodes the active BOM of a product through all levels.
  ///
  /// [quantity] - Quantity of the product to explode. Default 1.
  @GET('/api/v1/products/{id}/bom/explode')
  Future<Explosion> explodeBom({
    @Path('id') required String id,
    @Query('quantity') String? quantity,
  });

  @GET('/api/v1/products/{id}/boms')
  Future<List<BomSummary>> listBoms({
    @Path('id') required String id,
  });

  /// Starts a new draft revision, copied from `copy_from` or from the active BOM.
  @POST('/api/v1/products/{id}/boms')
  Future<Bom> createBom({
    @Path('id') required String id,
    @Body() required NewBomInput body,
  });

  /// Registers a serialised unit. (Later also created automatically by production and goods receipt.)
  @POST('/api/v1/products/{id}/serials')
  Future<SerialUnitDetail> createSerial({
    @Path('id') required String id,
    @Body() required SerialInput body,
  });

  /// [q] - Searches serial number and product code.
  @GET('/api/v1/serials')
  Future<SerialUnitPage> listSerials({
    @Query('q') String? q,
    @Query('product_id') String? productId,
    @Query('status') String? status,
    @Query('customer_id') String? customerId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/api/v1/serials/{id}')
  Future<SerialUnitDetail> getSerial({
    @Path('id') required String id,
  });

  /// Records that a serialised component was built into this unit. The component's product must be.
  /// part of the unit's BOM revision, and no more units may be attached than the BOM quantity.
  @POST('/api/v1/serials/{id}/components')
  Future<SerialUnitDetail> attachComponent({
    @Path('id') required String id,
    @Body() required AttachInput body,
  });

  /// Removes a component (e.g. replaced during a repair). The link is kept in the history.
  @POST('/api/v1/serials/{id}/components/{child_id}/remove')
  Future<SerialUnitDetail> detachComponent({
    @Path('id') required String id,
    @Path('child_id') required String childId,
    @Body() required DetachInput body,
  });

  @PUT('/api/v1/serials/{id}/status')
  Future<SerialUnitDetail> setStatus({
    @Path('id') required String id,
    @Body() required SerialStatusInput body,
  });

  /// Sets the warranty of a unit: until when, and a note (terms, contract).
  @PUT('/api/v1/serials/{id}/warranty')
  Future<SerialUnitDetail> setWarranty({
    @Path('id') required String id,
    @Body() required WarrantyInput body,
  });
}
