// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/cancel_order_input.dart';
import '../models/configured_import_result.dart';
import '../models/configured_quotation_input.dart';
import '../models/confirm_order_input.dart';
import '../models/convert_input.dart';
import '../models/dismiss_request_input.dart';
import '../models/mark_shipping_requested_input.dart';
import '../models/order.dart';
import '../models/order_edit_input.dart';
import '../models/order_page.dart';
import '../models/pricing_preview.dart';
import '../models/pricing_preview_input.dart';
import '../models/priority_change.dart';
import '../models/priority_input.dart';
import '../models/priority_request.dart';
import '../models/quotation.dart';
import '../models/quotation_input.dart';
import '../models/quotation_page.dart';
import '../models/remark_history_entry.dart';
import '../models/repricing_comparison.dart';
import '../models/revise_input.dart';
import '../models/shipping_quote_input.dart';
import '../models/shipping_request.dart';

part 'sales_client.g.dart';

@RestApi()
abstract class SalesClient {
  factory SalesClient(Dio dio, {String? baseUrl}) = _SalesClient;

  /// [q] - Searches order number, quotation number, customer name and customer reference.
  @GET('/api/v1/orders')
  Future<OrderPage> listOrders({
    @Query('q') String? q,
    @Query('customer_id') String? customerId,
    @Query('status') String? status,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// The latest revision of an order.
  @GET('/api/v1/orders/{id}')
  Future<Order> getOrder({
    @Path('id') required String id,
  });

  /// Edits the draft revision: quantities, discounts, descriptions and notes. Prices and rebates.
  /// stay as agreed on the quotation; totals are recomputed here.
  @PUT('/api/v1/orders/{id}')
  Future<Order> editOrder({
    @Path('id') required String id,
    @Body() required OrderEditInput body,
  });

  /// Cancels the order. Possible until it is ready for shipping; while it is in production only when.
  /// no production order is open any more (the planner cancels those first).
  @POST('/api/v1/orders/{id}/cancel')
  Future<Order> cancel({
    @Path('id') required String id,
    @Body() required CancelOrderInput body,
  });

  /// Confirms the order on the customer's behalf (e.g. after a phone call or an e-mail).
  @POST('/api/v1/orders/{id}/confirm')
  Future<Order> confirm({
    @Path('id') required String id,
    @Body() required ConfirmOrderInput body,
  });

  /// Changes the priority of an order. The reason is required; the change is kept in the history.
  @PUT('/api/v1/orders/{id}/priority')
  Future<Order> changePriority({
    @Path('id') required String id,
    @Body() required PriorityInput body,
  });

  @GET('/api/v1/orders/{id}/priority-history')
  Future<List<PriorityChange>> priorityHistory({
    @Path('id') required String id,
  });

  /// Customer requests to change the priority, newest first.
  @GET('/api/v1/orders/{id}/priority-requests')
  Future<List<PriorityRequest>> listRequests({
    @Path('id') required String id,
  });

  /// Turns a customer request down without changing the priority.
  @POST('/api/v1/orders/{id}/priority-requests/{request_id}/dismiss')
  Future<PriorityRequest> dismissRequest({
    @Path('id') required String id,
    @Path('request_id') required String requestId,
    @Body() required DismissRequestInput body,
  });

  /// Starts the next revision as a draft, copying the latest one. The sent revision is kept and.
  /// marked superseded: the customer can no longer confirm it.
  @POST('/api/v1/orders/{id}/revisions')
  Future<Order> newRevision({
    @Path('id') required String id,
  });

  /// A specific revision of an order, e.g. an older one that was sent.
  @GET('/api/v1/orders/{id}/revisions/{revision}')
  Future<Order> getOrderRevision({
    @Path('id') required String id,
    @Path('revision') required int revision,
  });

  /// The order confirmation of one revision as PDF (a draft carries a watermark).
  @GET('/api/v1/orders/{id}/revisions/{revision}/pdf')
  Future<List<int>> orderPdf({
    @Path('id') required String id,
    @Path('revision') required int revision,
  });

  /// Sends the draft revision: it becomes `sent`, the order confirmation PDF is rendered in the.
  /// customer's language and queued as an e-mail for the worker. Refused (409) when there is no.
  /// address to send it to.
  @POST('/api/v1/orders/{id}/send')
  Future<Order> sendOrder({
    @Path('id') required String id,
  });

  /// Prices lines for a customer without saving. The app calls this while the user edits,.
  /// so every number on screen comes from the server's pricing engine.
  @POST('/api/v1/pricing/preview')
  Future<PricingPreview> preview({
    @Body() required PricingPreviewInput body,
  });

  /// The distinct production or customer remarks used on earlier quotation lines of a product, newest.
  /// first, limited to the caller's company. Scope `customer` looks at the given customer, `language`.
  /// at quotations whose customer language equals `language`, `all` at everything. Empty remarks are.
  /// left out.
  ///
  /// [kind] - `production` or `customer`.
  ///
  /// [scope] - `customer` (quotes of `customer_id`), `language` (quotes in `language`) or `all`.
  ///
  /// [customerId] - Needed for scope `customer`.
  ///
  /// [language] - Needed for scope `language`: the language of the quotation being edited (ISO 639-1).
  @GET('/api/v1/products/{id}/remark-history')
  Future<List<RemarkHistoryEntry>> remarkHistory({
    @Path('id') required String id,
    @Query('kind') required String kind,
    @Query('scope') required String scope,
    @Query('customer_id') String? customerId,
    @Query('language') String? language,
  });

  /// [q] - Searches number and customer name.
  @GET('/api/v1/quotations')
  Future<QuotationPage> listQuotations({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('customer_id') String? customerId,
    @Query('opportunity_id') String? opportunityId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/quotations')
  Future<Quotation> createQuotation({
    @Body() required QuotationInput body,
  });

  /// Imports a configured quotation, or re-imports it.
  ///
  /// * First import of `(source, external_ref)`: a new draft quotation (201, `created`).
  /// * Latest revision is a draft: it is replaced and repriced today (200, `updated`).
  /// * Latest revision is sent or rejected: the next revision is created and filled (201,.
  ///   `revised`), as `POST /quotations/{id}/revise` followed by an update.
  /// * Latest revision is accepted: 409.
  ///
  /// Unknown or inactive product codes are skipped with an `unknown_product` warning (with their.
  /// sub-lines), or refused with 422 when `strict`. Needs `quotations.import`.
  @POST('/api/v1/quotations/configured')
  Future<ConfiguredImportResult> importConfigured({
    @Body() required ConfiguredQuotationInput body,
  });

  @GET('/api/v1/quotations/{id}')
  Future<Quotation> getQuotation({
    @Path('id') required String id,
  });

  /// Replaces customer, dates, notes and lines of a draft, repricing everything at its price date.
  @PUT('/api/v1/quotations/{id}')
  Future<Quotation> updateQuotation({
    @Path('id') required String id,
    @Body() required QuotationInput body,
  });

  @POST('/api/v1/quotations/{id}/accept')
  Future<Quotation> acceptQuotation({
    @Path('id') required String id,
  });

  /// Converts a sent or accepted quotation revision into a draft sales order (revision 1).
  @POST('/api/v1/quotations/{id}/convert')
  Future<Order> convert({
    @Path('id') required String id,
    @Body() required ConvertInput body,
  });

  @GET('/api/v1/quotations/{id}/pdf')
  Future<List<int>> quotationPdf({
    @Path('id') required String id,
  });

  @POST('/api/v1/quotations/{id}/reject')
  Future<Quotation> rejectQuotation({
    @Path('id') required String id,
  });

  /// Compares a quotation with today's price list and rebates, line by line. Changes nothing.
  @GET('/api/v1/quotations/{id}/repricing')
  Future<RepricingComparison> repricing({
    @Path('id') required String id,
  });

  /// Creates the next revision as a new draft with the same number; the revised quotation becomes.
  /// `superseded`. `keep` copies the agreed prices and price list date unchanged; `current` reprices.
  /// at today's price list and rebates (indicative prices must then be confirmed again).
  @POST('/api/v1/quotations/{id}/revise')
  Future<Quotation> reviseQuotation({
    @Path('id') required String id,
    @Body() required ReviseInput body,
  });

  /// Freezes the quotation. From now on it can only be accepted, rejected or revised.
  /// Shipping is reconciled first (a request may be opened or cancelled). Refused while indicative.
  /// prices are unconfirmed, and (409) while its shipping cost is still to be quoted, unless the.
  /// caller passes `override_shipping=true`, which always needs `shipping.manage` (403 otherwise).
  ///
  /// [overrideShipping] - Send although the shipping cost has not been quoted yet. Needs the permission.
  /// `shipping.manage`.
  @POST('/api/v1/quotations/{id}/send')
  Future<Quotation> sendQuotation({
    @Path('id') required String id,
    @Query('override_shipping') bool? overrideShipping,
  });

  /// The shipping requests that logistics works on (open and requested by default).
  ///
  /// [status] - open | requested | quoted | cancelled. Default: the work queue (open and requested).
  @GET('/api/v1/shipping-requests')
  Future<List<ShippingRequest>> listShippingRequests({
    @Query('status') String? status,
  });

  /// Enters the quoted shipping cost: the request becomes `quoted` and the quotation gets (or.
  /// updates) its `SHIPPING` line, with totals and VAT recomputed.
  @POST('/api/v1/shipping-requests/{id}/quote')
  Future<ShippingRequest> enterShippingQuote({
    @Path('id') required String id,
    @Body() required ShippingQuoteInput body,
  });

  /// Records that the carriers have been asked for a price.
  @POST('/api/v1/shipping-requests/{id}/request')
  Future<ShippingRequest> markShippingRequested({
    @Path('id') required String id,
    @Body() required MarkShippingRequestedInput body,
  });
}
