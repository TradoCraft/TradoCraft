// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/announce_repair.dart';
import '../models/confirm_portal_order.dart';
import '../models/file_info.dart';
import '../models/kb_vote.dart';
import '../models/login_link_input.dart';
import '../models/message_input.dart';
import '../models/new_priority_request.dart';
import '../models/new_ticket.dart';
import '../models/portal_order.dart';
import '../models/portal_order_detail.dart';
import '../models/portal_profile.dart';
import '../models/portal_repair.dart';
import '../models/portal_repair_detail.dart';
import '../models/portal_session.dart';
import '../models/portal_ticket.dart';
import '../models/portal_ticket_detail.dart';
import '../models/priority_request.dart';
import '../models/profile_input.dart';
import '../models/reader_category.dart';
import '../models/reader_entry.dart';
import '../models/reader_summary.dart';
import '../models/session_input.dart';

part 'portal_client.g.dart';

@RestApi()
abstract class PortalClient {
  factory PortalClient(Dio dio, {String? baseUrl}) = _PortalClient;

  /// [language] - nl | fr | en | de | es (default: the company's language)
  @GET('/api/v1/portal/kb/categories')
  Future<List<ReaderCategory>> listPortalKbCategories({
    @Query('language') String? language,
  });

  /// Browse or search the help articles.
  ///
  /// [q] - Search words.
  ///
  /// [categoryId] - Includes the sub-categories of this category.
  ///
  /// [language] - nl | fr | en | de | es (default: the company's language).
  @GET('/api/v1/portal/kb/entries')
  Future<List<ReaderSummary>> listPortalKbEntries({
    @Query('q') String? q,
    @Query('category_id') String? categoryId,
    @Query('tag') String? tag,
    @Query('language') String? language,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// One article. Counts one view. Internal, draft and archived entries are "not found".
  ///
  /// [language] - nl | fr | en | de | es (default: the company's language).
  @GET('/api/v1/portal/kb/entries/{id}')
  Future<ReaderEntry> getPortalKbEntry({
    @Path('id') required String id,
    @Query('language') String? language,
  });

  @GET('/api/v1/portal/kb/entries/{id}/images/{file_id}')
  Future<String> getPortalKbImage({
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  /// Says whether the article helped. One vote per contact and article; sending it again changes it.
  @PUT('/api/v1/portal/kb/entries/{id}/vote')
  Future<void> votePortalKbEntry({
    @Path('id') required String id,
    @Body() required KbVote body,
  });

  /// Up to three articles that fit what the contact types, for the "new ticket" form.
  ///
  /// [q] - What the customer typed so far, e.g. the subject of a new ticket.
  @GET('/api/v1/portal/kb/suggestions')
  Future<List<ReaderSummary>> suggestPortalKbEntries({
    @Query('q') String? q,
    @Query('language') String? language,
  });

  /// Always answers 202, whether or not the address belongs to a portal user, so the endpoint.
  /// cannot be used to find out who is a customer.
  @POST('/api/v1/portal/login-links')
  Future<void> requestLoginLink({
    @Body() required LoginLinkInput body,
  });

  @GET('/api/v1/portal/me')
  Future<PortalProfile> getMe();

  @PUT('/api/v1/portal/me')
  Future<PortalProfile> updateMe({
    @Body() required ProfileInput body,
  });

  /// Orders of the customer: the latest revision that was sent or confirmed, never a draft.
  @GET('/api/v1/portal/orders')
  Future<List<PortalOrder>> listPortalOrders();

  @GET('/api/v1/portal/orders/{id}')
  Future<PortalOrderDetail> getPortalOrder({
    @Path('id') required String id,
  });

  /// The customer confirms their order. Only the latest sent revision can be confirmed.
  @POST('/api/v1/portal/orders/{id}/confirm')
  Future<PortalOrderDetail> confirmPortalOrder({
    @Path('id') required String id,
    @Body() required ConfirmPortalOrder body,
  });

  /// Asks staff to treat the order as more or less urgent. Staff decide.
  @POST('/api/v1/portal/orders/{id}/priority-requests')
  Future<PriorityRequest> requestPortalOrderPriority({
    @Path('id') required String id,
    @Body() required NewPriorityRequest body,
  });

  @GET('/api/v1/portal/repairs')
  Future<List<PortalRepair>> listPortalRepairs();

  /// Announces a repair that the customer is going to send in. Photos can be added afterwards.
  @POST('/api/v1/portal/repairs')
  Future<PortalRepairDetail> announcePortalRepair({
    @Body() required AnnounceRepair body,
  });

  @GET('/api/v1/portal/repairs/{id}')
  Future<PortalRepairDetail> getPortalRepair({
    @Path('id') required String id,
  });

  /// Adds a photo to a repair: the request body is the image (JPEG, PNG or WebP, at most 12 MB).
  ///
  /// [clientId] - A client-chosen id: sending the same id again returns the first upload.
  @POST('/api/v1/portal/repairs/{id}/photos')
  Future<PortalRepairDetail> uploadPortalRepairPhoto({
    @Path('id') required String id,
    @Body() required String body,
    @Query('caption') String? caption,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  @GET('/api/v1/portal/repairs/{id}/photos/{photo_id}')
  Future<String> getPortalRepairPhoto({
    @Path('id') required String id,
    @Path('photo_id') required String photoId,
  });

  /// Logs out: the session token stops working.
  @DELETE('/api/v1/portal/session')
  Future<void> endSession();

  /// Exchanges a login link for a session. A link works once.
  @POST('/api/v1/portal/sessions')
  Future<PortalSession> createSession({
    @Body() required SessionInput body,
  });

  @GET('/api/v1/portal/tickets')
  Future<List<PortalTicket>> listPortalTickets();

  @POST('/api/v1/portal/tickets')
  Future<PortalTicketDetail> createPortalTicket({
    @Body() required NewTicket body,
  });

  @GET('/api/v1/portal/tickets/{id}')
  Future<PortalTicketDetail> getPortalTicket({
    @Path('id') required String id,
  });

  /// Uploads a file to a ticket: the request body is the file (JPEG, PNG, WebP or PDF, at most.
  /// 12 MB). Send its id in `attachment_ids` with the next message.
  ///
  /// [filename] - The original file name.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload (safe retries).
  @POST('/api/v1/portal/tickets/{id}/attachments')
  Future<FileInfo> uploadPortalTicketAttachment({
    @Path('id') required String id,
    @Body() required String body,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  /// A file of a message the customer can see, as a download.
  @GET('/api/v1/portal/tickets/{id}/attachments/{file_id}')
  Future<String> getPortalTicketAttachment({
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  /// Adds a message to a ticket. A closed ticket is reopened.
  @POST('/api/v1/portal/tickets/{id}/messages')
  Future<PortalTicketDetail> addPortalMessage({
    @Path('id') required String id,
    @Body() required MessageInput body,
  });
}
