// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/bom_routing.dart';
import '../models/bom_routing_input.dart';
import '../models/cancel_production_input.dart';
import '../models/complete_production_input.dart';
import '../models/division.dart';
import '../models/division_input.dart';
import '../models/product_division.dart';
import '../models/production_build_component_input.dart';
import '../models/production_capacity.dart';
import '../models/production_cost_rollup.dart';
import '../models/production_operation_finish.dart';
import '../models/production_operation_update.dart';
import '../models/production_order.dart';
import '../models/production_page.dart';
import '../models/production_schedule_input.dart';
import '../models/production_serial_candidate.dart';
import '../models/production_to_release.dart';
import '../models/release_production_input.dart';
import '../models/update_production_input.dart';
import '../models/work_centre.dart';
import '../models/work_centre_closure.dart';
import '../models/work_centre_closure_input.dart';
import '../models/work_centre_hours_input.dart';
import '../models/work_centre_input.dart';

part 'production_client.g.dart';

@RestApi()
abstract class ProductionClient {
  factory ProductionClient(Dio dio, {String? baseUrl}) = _ProductionClient;

  /// The routing of a BOM revision: empty operations when it has none.
  @GET('/api/v1/boms/{id}/routing')
  Future<BomRouting> getRouting({
    @Path('id') required String id,
  });

  /// Replaces the routing of a draft BOM revision. Work centres must belong to the company and be.
  /// active, except ones the routing already uses (deactivating a work centre does not break the.
  /// routings that have it).
  @PUT('/api/v1/boms/{id}/routing')
  Future<BomRouting> setRouting({
    @Path('id') required String id,
    @Body() required BomRoutingInput body,
  });

  /// The production queue: most urgent first (sales order priority, then planned-ready date).
  ///
  /// [status] - released | in_progress | completed | cancelled.
  ///
  /// [mine] - When true, only orders of the caller's own divisions and orders without a division.
  /// (unassigned work is never hidden). Default false: everything.
  ///
  /// [q] - Searches the number, the product, the sales order and the customer.
  @GET('/api/v1/production-orders')
  Future<ProductionPage> listOrders({
    @Query('status') String? status,
    @Query('division_id') String? divisionId,
    @Query('mine') bool? mine,
    @Query('order_id') String? orderId,
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Releases a line of a sales order, or a quantity for stock, to production: freezes the active.
  /// BOM and its routing, creates the production order and its components and reserves them.
  /// With `auto_release_subassemblies`, subassemblies that stock does not cover get production.
  /// orders of their own for the shortfall.
  @POST('/api/v1/production-orders')
  Future<ProductionOrder> release({
    @Body() required ReleaseProductionInput body,
  });

  /// One production order with its components and outputs.
  @GET('/api/v1/production-orders/{id}')
  Future<ProductionOrder> getOrder({
    @Path('id') required String id,
  });

  /// Changes the division, the planned-ready date and the notes of an open production order.
  @PUT('/api/v1/production-orders/{id}')
  Future<ProductionOrder> updateOrder({
    @Path('id') required String id,
    @Body() required UpdateProductionInput body,
  });

  /// Cancels an open production order and releases the components reserved for it.
  @POST('/api/v1/production-orders/{id}/cancel')
  Future<ProductionOrder> cancelOrder({
    @Path('id') required String id,
    @Body() required CancelProductionInput body,
  });

  /// Completes a production order: consumes the components (backflush, with the actual quantities.
  /// and scrap), puts the output into stock and moves the sales order on.
  @POST('/api/v1/production-orders/{id}/complete')
  Future<ProductionOrder> completeOrder({
    @Path('id') required String id,
    @Body() required CompleteProductionInput body,
  });

  /// Releases a production order for a component that is built from a BOM and that stock does not.
  /// cover, below this order: it builds what is still missing. The order may list the same.
  /// component more than once, so this compares everything the order needs of the product with.
  /// everything that covers it (reserved, free in stock, already under way in open subassembly.
  /// orders): one build serves all its rows, and building again for another row finds it covered.
  @POST('/api/v1/production-orders/{id}/components/{component_id}/build')
  Future<ProductionOrder> buildComponent({
    @Path('id') required String id,
    @Path('component_id') required String componentId,
    @Body() required ProductionBuildComponentInput body,
  });

  /// The serial units in stock of a serial-tracked component, to choose from when completing.
  ///
  /// [q] - Part of the serial number.
  @GET('/api/v1/production-orders/{id}/components/{component_id}/serial-units')
  Future<List<ProductionSerialCandidate>> serialCandidates({
    @Path('id') required String id,
    @Path('component_id') required String componentId,
    @Query('q') String? q,
  });

  /// Moves an operation to another work centre and/or other dates.
  @PUT('/api/v1/production-orders/{id}/operations/{operation_id}')
  Future<ProductionOrder> updateProductionOperation({
    @Path('id') required String id,
    @Path('operation_id') required String operationId,
    @Body() required ProductionOperationUpdate body,
  });

  /// Finishes an operation (also one that was never started: it is started and finished at once).
  @POST('/api/v1/production-orders/{id}/operations/{operation_id}/finish')
  Future<ProductionOrder> finishProductionOperation({
    @Path('id') required String id,
    @Path('operation_id') required String operationId,
    @Body() required ProductionOperationFinish body,
  });

  /// Takes back the finish (or skip) of an operation, for a mistake.
  @POST('/api/v1/production-orders/{id}/operations/{operation_id}/reopen')
  Future<ProductionOrder> reopenProductionOperation({
    @Path('id') required String id,
    @Path('operation_id') required String operationId,
  });

  /// Starts an operation. Starting the first one starts the production order.
  @POST('/api/v1/production-orders/{id}/operations/{operation_id}/start')
  Future<ProductionOrder> startProductionOperation({
    @Path('id') required String id,
    @Path('operation_id') required String operationId,
  });

  /// The production order as a PDF to print and take to the shop floor.
  ///
  /// [lang] - nl | fr | en | de | es; default: the language of the user, else of the company.
  @GET('/api/v1/production-orders/{id}/pdf')
  Future<void> productionOrderPdf({
    @Path('id') required String id,
    @Query('lang') String? lang,
  });

  /// Tries again to reserve the components that were short at release.
  @POST('/api/v1/production-orders/{id}/reserve')
  Future<ProductionOrder> reserveComponents({
    @Path('id') required String id,
  });

  /// Schedules the operations that have not started again from a date, one after the other on the.
  /// work centres' calendars. The planned-ready date of the order is not changed: the planner.
  /// sets it, with `scheduled_end` as the suggestion.
  @POST('/api/v1/production-orders/{id}/schedule')
  Future<ProductionOrder> scheduleProductionOrder({
    @Path('id') required String id,
    @Body() required ProductionScheduleInput body,
  });

  /// Starts a production order: the order is being built.
  @POST('/api/v1/production-orders/{id}/start')
  Future<ProductionOrder> startOrder({
    @Path('id') required String id,
  });

  /// Capacity against load per work centre and day. Load is the planned minutes of every operation.
  /// of an open production order that is not finished, spread over the working days between its.
  /// planned dates in proportion to what each day offers. Work that is already late lands on the.
  /// first day of the period; an operation that is running still counts in full (no progress is.
  /// recorded).
  ///
  /// [from] - First day.
  ///
  /// [to] - Last day, inclusive; at most 62 days after `from`.
  ///
  /// [divisionId] - Only the work centres of this division.
  @GET('/api/v1/production/capacity')
  Future<ProductionCapacity> productionCapacity({
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
    @Query('division_id') String? divisionId,
  });

  /// Closures, earliest first.
  ///
  /// [workCentreId] - This work centre's closures and the whole-plant ones.
  ///
  /// [from] - Only closures that end on or after this day.
  ///
  /// [to] - Only closures that start on or before this day.
  @GET('/api/v1/production/closures')
  Future<List<WorkCentreClosure>> listWorkCentreClosures({
    @Query('work_centre_id') String? workCentreId,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  /// Adds a closure.
  @POST('/api/v1/production/closures')
  Future<WorkCentreClosure> createWorkCentreClosure({
    @Body() required WorkCentreClosureInput body,
  });

  /// Changes a closure.
  @PUT('/api/v1/production/closures/{id}')
  Future<WorkCentreClosure> updateWorkCentreClosure({
    @Path('id') required String id,
    @Body() required WorkCentreClosureInput body,
  });

  /// Removes a closure.
  @DELETE('/api/v1/production/closures/{id}')
  Future<void> deleteWorkCentreClosure({
    @Path('id') required String id,
  });

  /// The divisions of the company, in their sort order.
  @GET('/api/v1/production/divisions')
  Future<List<Division>> listDivisions();

  /// Adds a division.
  @POST('/api/v1/production/divisions')
  Future<Division> createDivision({
    @Body() required DivisionInput body,
  });

  /// Changes a division.
  @PUT('/api/v1/production/divisions/{id}')
  Future<Division> updateDivision({
    @Path('id') required String id,
    @Body() required DivisionInput body,
  });

  /// Removes a division that nothing uses. One that has production orders is refused with 409.
  /// Conflict: deactivate it instead.
  @DELETE('/api/v1/production/divisions/{id}')
  Future<void> deleteDivision({
    @Path('id') required String id,
  });

  /// The cost of building a quantity of a product from its active BOM and routing, through every.
  /// level of subassemblies (a subassembly is costed from its own BOM and routing, not from its.
  /// standard cost). Material uses standard costs, labour the work centres' cost per hour as they.
  /// are now.
  ///
  /// [quantity] - How many to cost; default 1. The setup time of each operation is counted once.
  @GET('/api/v1/production/products/{id}/cost-rollup')
  Future<ProductionCostRollup> productionCostRollup({
    @Path('id') required String id,
    @Query('quantity') String? quantity,
  });

  /// The division that normally builds a product.
  @GET('/api/v1/production/products/{id}/division')
  Future<ProductDivision> getProductDivision({
    @Path('id') required String id,
  });

  /// Sets (or clears) the division that normally builds a product.
  @PUT('/api/v1/production/products/{id}/division')
  Future<ProductDivision> setProductDivision({
    @Path('id') required String id,
    @Body() required ProductDivision body,
  });

  /// Lines of confirmed orders that are built from a BOM and not yet fully covered by production.
  /// orders: what a planner can release. Most urgent orders first.
  @GET('/api/v1/production/to-release')
  Future<List<ProductionToRelease>> toRelease();

  /// The work centres of the company, in their sort order.
  ///
  /// [active] - Only active (true) or only inactive (false) work centres.
  @GET('/api/v1/production/work-centres')
  Future<List<WorkCentre>> listWorkCentres({
    @Query('active') bool? active,
    @Query('division_id') String? divisionId,
  });

  /// Adds a work centre.
  @POST('/api/v1/production/work-centres')
  Future<WorkCentre> createWorkCentre({
    @Body() required WorkCentreInput body,
  });

  /// Changes a work centre. Deactivating one hides it from new routings; existing routings and.
  /// operations keep it.
  @PUT('/api/v1/production/work-centres/{id}')
  Future<WorkCentre> updateWorkCentre({
    @Path('id') required String id,
    @Body() required WorkCentreInput body,
  });

  /// Removes a work centre that nothing uses. One that routings or operations refer to is refused.
  /// with 409 Conflict: deactivate it instead.
  @DELETE('/api/v1/production/work-centres/{id}')
  Future<void> deleteWorkCentre({
    @Path('id') required String id,
  });

  /// Replaces the opening hours of a work centre. No blocks: the default week applies again.
  @PUT('/api/v1/production/work-centres/{id}/hours')
  Future<WorkCentre> setWorkCentreHours({
    @Path('id') required String id,
    @Body() required WorkCentreHoursInput body,
  });
}
