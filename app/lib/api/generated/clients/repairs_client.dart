// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/department.dart';
import '../models/department_input.dart';
import '../models/findings_input.dart';
import '../models/new_repair_input.dart';
import '../models/package.dart';
import '../models/package_close_input.dart';
import '../models/package_detail.dart';
import '../models/package_input.dart';
import '../models/package_open_input.dart';
import '../models/package_page.dart';
import '../models/package_repair_link_input.dart';
import '../models/package_repair_suggestions.dart';
import '../models/repair.dart';
import '../models/repair_detail.dart';
import '../models/repair_input.dart';
import '../models/repair_note_input.dart';
import '../models/repair_page.dart';
import '../models/repair_warranty.dart';
import '../models/route_input.dart';
import '../models/serial_unit_input.dart';
import '../models/status_input.dart';
import '../models/warranty_override_input.dart';

part 'repairs_client.g.dart';

@RestApi()
abstract class RepairsClient {
  factory RepairsClient(Dio dio, {String? baseUrl}) = _RepairsClient;

  @GET('/api/v1/departments')
  Future<List<Department>> listDepartments();

  @POST('/api/v1/departments')
  Future<Department> createDepartment({
    @Body() required DepartmentInput body,
  });

  @PUT('/api/v1/departments/{id}')
  Future<Department> updateDepartment({
    @Path('id') required String id,
    @Body() required DepartmentInput body,
  });

  /// [q] - Searches number, tracking number, sender, customer and the customer's reference.
  ///
  /// [status] - A status, or `open` for everything not closed.
  ///
  /// [kind] - repair | other | return_to_sender.
  @GET('/api/v1/packages')
  Future<PackagePage> listPackages({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('kind') String? kind,
    @Query('customer_id') String? customerId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Registers a parcel at the dock. The same `client_id` again returns the first parcel (200).
  @POST('/api/v1/packages')
  Future<PackageDetail> createPackage({
    @Body() required PackageInput body,
  });

  @GET('/api/v1/packages/{id}')
  Future<PackageDetail> getPackage({
    @Path('id') required String id,
  });

  /// Corrects the details of a parcel while it is registered or opened.
  @PUT('/api/v1/packages/{id}')
  Future<PackageDetail> updatePackage({
    @Path('id') required String id,
    @Body() required PackageInput body,
  });

  /// Closes a parcel without a repair: refused at the dock and sent back unopened (`registered`), or.
  /// an opened repair parcel that turned out to hold nothing to repair (needs `packages.open` too).
  @POST('/api/v1/packages/{id}/close')
  Future<PackageDetail> closePackage({
    @Path('id') required String id,
    @Body() required PackageCloseInput body,
  });

  /// Opens a parcel and decides what it is. A `repair` parcel becomes `opened` and waits to be linked.
  /// with a repair; `other` and `return_to_sender` close it at once (a note is required).
  @POST('/api/v1/packages/{id}/open')
  Future<PackageDetail> openPackage({
    @Path('id') required String id,
    @Body() required PackageOpenInput body,
  });

  /// Adds a photo of the box: the request body is the image itself (JPEG, PNG or WebP, at most 12 MB).
  /// The same `client_id` again does not add a second photo.
  ///
  /// [filename] - The original file name.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload (safe retries).
  @POST('/api/v1/packages/{id}/photos')
  Future<PackageDetail> uploadPackagePhoto({
    @Path('id') required String id,
    @Body() required String body,
    @Query('caption') String? caption,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  /// The image itself.
  @GET('/api/v1/packages/{id}/photos/{photo_id}')
  Future<String> getPackagePhoto({
    @Path('id') required String id,
    @Path('photo_id') required String photoId,
  });

  /// Announced repairs that may belong to this parcel, best first, with the reasons. Nothing is linked:.
  /// confirm with `POST /packages/{id}/repairs`.
  ///
  /// [serial] - The serial number read from the product.
  ///
  /// [ticket] - A ticket number the customer mentioned.
  ///
  /// [product] - What the product is, as far as one can tell.
  @GET('/api/v1/packages/{id}/repair-suggestions')
  Future<PackageRepairSuggestions> listPackageRepairSuggestions({
    @Path('id') required String id,
    @Query('serial') String? serial,
    @Query('ticket') String? ticket,
    @Query('product') String? product,
  });

  /// Confirms that a parcel holds a repair: either an existing repair (an announced one becomes.
  /// `received`) or a new one created from the parcel. The parcel becomes `linked`. One parcel can.
  /// hold several repairs, one repair can arrive in several parcels.
  @POST('/api/v1/packages/{id}/repairs')
  Future<RepairDetail> linkPackageRepair({
    @Path('id') required String id,
    @Body() required PackageRepairLinkInput body,
  });

  /// Removes the link between a parcel and a repair (a mistake). The repair keeps its status. The parcel.
  /// goes back to `opened` when its last repair is unlinked.
  @DELETE('/api/v1/packages/{id}/repairs/{repair_id}')
  Future<PackageDetail> unlinkPackageRepair({
    @Path('id') required String id,
    @Path('repair_id') required String repairId,
  });

  /// [q] - Searches number, customer, serial number, product and fault.
  ///
  /// [status] - A status, or `open` for everything not yet shipped or cancelled.
  ///
  /// [department] - A department id, or `none` for repairs not routed yet.
  ///
  /// [assigned] - `me` for repairs assigned to me, or a user id.
  @GET('/api/v1/repairs')
  Future<RepairPage> listRepairs({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('department') String? department,
    @Query('assigned') String? assigned,
    @Query('customer_id') String? customerId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Registers a repair. Give a `ticket_id` to create it from the ticket where it was announced.
  @POST('/api/v1/repairs')
  Future<RepairDetail> createRepair({
    @Body() required NewRepairInput body,
  });

  @GET('/api/v1/repairs/{id}')
  Future<RepairDetail> getRepair({
    @Path('id') required String id,
  });

  /// Changes the descriptive fields of a repair (not its status or department).
  @PUT('/api/v1/repairs/{id}')
  Future<RepairDetail> updateRepair({
    @Path('id') required String id,
    @Body() required RepairInput body,
  });

  /// Records the findings (and the diagnosis) of a repair.
  @PUT('/api/v1/repairs/{id}/findings')
  Future<RepairDetail> setRepairFindings({
    @Path('id') required String id,
    @Body() required FindingsInput body,
  });

  /// An internal note on the repair (diagnosis, parts used, test results). The customer never sees it.
  @POST('/api/v1/repairs/{id}/notes')
  Future<RepairDetail> addRepairNote({
    @Path('id') required String id,
    @Body() required RepairNoteInput body,
  });

  /// Opened repair parcels of the repair's customer that are not linked to any repair yet: the other.
  /// direction of matching, for an announced repair that has just arrived. Confirm with.
  /// `POST /packages/{id}/repairs`.
  @GET('/api/v1/repairs/{id}/package-suggestions')
  Future<List<Package>> listRepairPackageSuggestions({
    @Path('id') required String id,
  });

  /// The parcels a repair arrived in.
  @GET('/api/v1/repairs/{id}/packages')
  Future<List<Package>> listRepairPackages({
    @Path('id') required String id,
  });

  /// Adds a photo: the request body is the image itself (JPEG, PNG or WebP, at most 12 MB).
  ///
  /// [filename] - The original file name.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload (safe retries).
  @POST('/api/v1/repairs/{id}/photos')
  Future<RepairDetail> uploadRepairPhoto({
    @Path('id') required String id,
    @Body() required String body,
    @Query('caption') String? caption,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  /// The image itself.
  @GET('/api/v1/repairs/{id}/photos/{photo_id}')
  Future<String> getRepairPhoto({
    @Path('id') required String id,
    @Path('photo_id') required String photoId,
  });

  /// Routes a repair to a department (or on to another one). It waits there as `routed`.
  @POST('/api/v1/repairs/{id}/route')
  Future<RepairDetail> routeRepair({
    @Path('id') required String id,
    @Body() required RouteInput body,
  });

  /// Links the repair to a serial unit (or unlinks it) and reruns the warranty lookup. Fills the.
  /// product and serial number of the repair from the unit when they are empty.
  @PUT('/api/v1/repairs/{id}/serial-unit')
  Future<RepairDetail> setRepairSerialUnit({
    @Path('id') required String id,
    @Body() required SerialUnitInput body,
  });

  /// Moves a repair along its workflow (everything except routing, see `/route`).
  @POST('/api/v1/repairs/{id}/status')
  Future<RepairDetail> setRepairStatus({
    @Path('id') required String id,
    @Body() required StatusInput body,
  });

  /// The warranty card: the automatic result, the serial unit it is based on, the override, and the.
  /// final status.
  @GET('/api/v1/repairs/{id}/warranty')
  Future<RepairWarranty> getRepairWarranty({
    @Path('id') required String id,
  });

  /// Declares the warranty void (misuse). The automatic result stays visible; who, when and why are.
  /// recorded. It cannot turn an out-of-warranty product into an in-warranty one.
  @PUT('/api/v1/repairs/{id}/warranty/override')
  Future<RepairDetail> voidRepairWarranty({
    @Path('id') required String id,
    @Body() required WarrantyOverrideInput body,
  });

  /// Removes the override: the warranty follows the automatic result again.
  @DELETE('/api/v1/repairs/{id}/warranty/override')
  Future<RepairDetail> removeRepairWarrantyOverride({
    @Path('id') required String id,
    @Body() required WarrantyOverrideInput body,
  });

  /// Runs the warranty lookup again (after the serial unit's warranty date was filled in).
  @POST('/api/v1/repairs/{id}/warranty/recheck')
  Future<RepairWarranty> recheckRepairWarranty({
    @Path('id') required String id,
  });

  /// The repairs registered for a ticket (the ticket may announce several).
  @GET('/api/v1/tickets/{id}/repairs')
  Future<List<Repair>> listTicketRepairs({
    @Path('id') required String id,
  });
}
