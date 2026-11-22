// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/billing_document.dart';
import '../models/billing_summary.dart';
import '../models/credit_draft_input.dart';
import '../models/invoice_draft_input.dart';
import '../models/legacy_invoice_input.dart';
import '../models/rebate_assignment.dart';
import '../models/rebate_assignment_input.dart';
import '../models/rebate_historical_input.dart';
import '../models/rebate_historical_total.dart';
import '../models/rebate_rate_approval_input.dart';
import '../models/rebate_rate_review.dart';
import '../models/rebate_schedule.dart';
import '../models/rebate_schedule_input.dart';
import '../models/rebate_settings.dart';

part 'customer_billing_client.g.dart';

@RestApi()
abstract class CustomerBillingClient {
  factory CustomerBillingClient(Dio dio, {String? baseUrl}) = _CustomerBillingClient;

  @GET('/api/v1/customer-invoices')
  Future<List<BillingSummary>> listCustomerDocuments({
    @Query('kind') String? kind,
    @Query('status') String? status,
    @Query('customer_id') String? customerId,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/customer-invoices')
  Future<BillingDocument> createCustomerInvoice({
    @Body() required InvoiceDraftInput body,
  });

  @POST('/api/v1/customer-invoices/credits')
  Future<BillingDocument> createCustomerCredit({
    @Body() required CreditDraftInput body,
  });

  @POST('/api/v1/customer-invoices/legacy')
  Future<BillingDocument> registerLegacyCustomerInvoice({
    @Body() required LegacyInvoiceInput body,
  });

  @GET('/api/v1/customer-invoices/{id}')
  Future<BillingDocument> getCustomerDocument({
    @Path('id') required String id,
  });

  @DELETE('/api/v1/customer-invoices/{id}')
  Future<void> discardCustomerDocument({
    @Path('id') required String id,
  });

  @GET('/api/v1/customer-invoices/{id}/pdf')
  @DioResponseType(ResponseType.stream)
  Stream<String> downloadCustomerDocument({
    @Path('id') required String id,
  });

  @POST('/api/v1/customer-invoices/{id}/post')
  Future<BillingDocument> postCustomerDocument({
    @Path('id') required String id,
  });

  @GET('/api/v1/customer-rebates/customers/{customer}/assignment')
  Future<RebateAssignment> getCustomerRebateAssignment({
    @Path('customer') required String customer,
  });

  @PUT('/api/v1/customer-rebates/customers/{customer}/assignment')
  Future<RebateAssignment> setCustomerRebateAssignment({
    @Path('customer') required String customer,
    @Body() required RebateAssignmentInput body,
  });

  @GET('/api/v1/customer-rebates/customers/{customer}/history')
  Future<List<RebateHistoricalTotal>> listCustomerRebateHistory({
    @Path('customer') required String customer,
  });

  @PUT('/api/v1/customer-rebates/customers/{customer}/history')
  Future<RebateHistoricalTotal> upsertCustomerRebateHistory({
    @Path('customer') required String customer,
    @Body() required RebateHistoricalInput body,
  });

  @POST('/api/v1/customer-rebates/customers/{customer}/rates')
  Future<RebateRateReview> approveCustomerRebateRate({
    @Path('customer') required String customer,
    @Body() required RebateRateApprovalInput body,
  });

  @GET('/api/v1/customer-rebates/customers/{customer}/rates/{year}')
  Future<RebateRateReview> reviewCustomerRebateRate({
    @Path('customer') required String customer,
    @Path('year') required int year,
  });

  @GET('/api/v1/customer-rebates/schedules')
  Future<List<RebateSchedule>> listCustomerRebateSchedules();

  @POST('/api/v1/customer-rebates/schedules')
  Future<RebateSchedule> createCustomerRebateSchedule({
    @Body() required RebateScheduleInput body,
  });

  @PUT('/api/v1/customer-rebates/schedules/{schedule}')
  Future<RebateSchedule> updateCustomerRebateSchedule({
    @Path('schedule') required String schedule,
    @Body() required RebateScheduleInput body,
  });

  @GET('/api/v1/customer-rebates/settings')
  Future<RebateSettings> getCustomerRebateSettings();

  @PUT('/api/v1/customer-rebates/settings')
  Future<RebateSettings> updateCustomerRebateSettings({
    @Body() required RebateSettings body,
  });
}
