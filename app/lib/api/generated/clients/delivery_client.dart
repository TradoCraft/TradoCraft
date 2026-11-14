// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/cancel_delivery_input.dart';
import '../models/create_delivery_input.dart';
import '../models/delivery_note.dart';
import '../models/delivery_page.dart';
import '../models/delivery_settings.dart';
import '../models/delivery_summary.dart';
import '../models/serial_choice.dart';
import '../models/ship_delivery_input.dart';
import '../models/update_delivery_input.dart';

part 'delivery_client.g.dart';

@RestApi()
abstract class DeliveryClient {
  factory DeliveryClient(Dio dio, {String? baseUrl}) = _DeliveryClient;

  /// Delivery notes, newest planned date first.
  ///
  /// [status] - planned | shipped | cancelled.
  ///
  /// [q] - Searches the number, the order number, the customer name and the tracking number.
  ///
  /// [plannedFrom] - Planned on or after this day.
  ///
  /// [plannedTo] - Planned on or before this day.
  @GET('/api/v1/deliveries')
  Future<DeliveryPage> listNotes({
    @Query('status') String? status,
    @Query('q') String? q,
    @Query('customer_id') String? customerId,
    @Query('planned_from') DateTime? plannedFrom,
    @Query('planned_to') DateTime? plannedTo,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// One delivery note with its lines.
  @GET('/api/v1/deliveries/{id}')
  Future<DeliveryNote> getNote({
    @Path('id') required String id,
  });

  /// Changes a planned delivery note: date, carrier, address, notes and lines.
  @PUT('/api/v1/deliveries/{id}')
  Future<DeliveryNote> updateNote({
    @Path('id') required String id,
    @Body() required UpdateDeliveryInput body,
  });

  /// Cancels a planned delivery note. A shipped note cannot be cancelled.
  @POST('/api/v1/deliveries/{id}/cancel')
  Future<DeliveryNote> cancelNote({
    @Path('id') required String id,
    @Body() required CancelDeliveryInput body,
  });

  /// The serial units that are in stock at the location of a line of a planned note: what can be.
  /// chosen as its serial number.
  ///
  /// [q] - Part of the serial number.
  @GET('/api/v1/deliveries/{id}/lines/{line_id}/serial-units')
  Future<List<SerialChoice>> serialChoices({
    @Path('id') required String id,
    @Path('line_id') required String lineId,
    @Query('q') String? q,
  });

  /// The delivery note as a PDF. A planned note is a preview; a shipped one is the final document.
  ///
  /// [lang] - nl | fr | en | de | es; default: the language of the customer.
  @GET('/api/v1/deliveries/{id}/pdf')
  Future<void> deliveryPdf({
    @Path('id') required String id,
    @Query('lang') String? lang,
  });

  /// Ships a planned delivery note: the goods leave the stock (consuming the reservations of the.
  /// order) and the order becomes `partially_shipped`, or `shipped` once everything is delivered.
  @POST('/api/v1/deliveries/{id}/ship')
  Future<DeliveryNote> shipNote({
    @Path('id') required String id,
    @Body() required ShipDeliveryInput body,
  });

  /// The delivery settings of the company.
  @GET('/api/v1/delivery/settings')
  Future<DeliverySettings> getSettings();

  /// Changes the delivery settings. Audited.
  @PUT('/api/v1/delivery/settings')
  Future<DeliverySettings> putSettings({
    @Body() required DeliverySettings body,
  });

  /// The delivery notes of one order.
  @GET('/api/v1/orders/{id}/deliveries')
  Future<List<DeliverySummary>> listForOrder({
    @Path('id') required String id,
  });

  /// Plans a delivery for an order: a note with lines proposed from the order's reservations.
  @POST('/api/v1/orders/{id}/deliveries')
  Future<DeliveryNote> createNote({
    @Path('id') required String id,
    @Body() required CreateDeliveryInput body,
  });
}
