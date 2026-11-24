// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/baseline_import_report.dart';
import '../models/baseline_item.dart';
import '../models/baseline_item_input.dart';
import '../models/baseline_item_type.dart';
import '../models/baseline_item_type_input.dart';
import '../models/baseline_item_type_update.dart';
import '../models/baseline_item_update.dart';
import '../models/closure.dart';
import '../models/closure_input.dart';
import '../models/contact.dart';
import '../models/contact_input.dart';
import '../models/customer.dart';
import '../models/customer_counts.dart';
import '../models/customer_input.dart';
import '../models/customer_page.dart';
import '../models/customer_rebate.dart';
import '../models/delivery_check.dart';
import '../models/format.dart';
import '../models/group_page.dart';
import '../models/import_report.dart';
import '../models/lookup_result.dart';
import '../models/mail_merge_draft.dart';
import '../models/mail_merge_preview.dart';
import '../models/mailing_delivery.dart';
import '../models/match_rule.dart';
import '../models/match_rule_input.dart';
import '../models/opportunity.dart';
import '../models/opportunity_input.dart';
import '../models/opportunity_page.dart';
import '../models/pipeline_stage.dart';
import '../models/product_match_page.dart';
import '../models/rebate_input.dart';
import '../models/stage_input.dart';
import '../models/vat_check.dart';

part 'crm_client.g.dart';

@RestApi()
abstract class CrmClient {
  factory CrmClient(Dio dio, {String? baseUrl}) = _CrmClient;

  @GET('/api/v1/baseline-item-types')
  Future<List<BaselineItemType>> listTypes();

  @POST('/api/v1/baseline-item-types')
  Future<BaselineItemType> createType({
    @Body() required BaselineItemTypeInput body,
  });

  @GET('/api/v1/baseline-item-types/{id}')
  Future<BaselineItemType> getType({
    @Path('id') required String id,
  });

  @PUT('/api/v1/baseline-item-types/{id}')
  Future<BaselineItemType> updateType({
    @Path('id') required String id,
    @Body() required BaselineItemTypeUpdate body,
  });

  /// Deletes an unused type. A type that has items, attribute definitions or that other types allow.
  /// as a parent is refused with 409 (deactivate it with `active: false` instead).
  @DELETE('/api/v1/baseline-item-types/{id}')
  Future<void> deleteType({
    @Path('id') required String id,
  });

  /// Closures of all customers, e.g. to plan deliveries.
  ///
  /// [from] - Closures that end on or after this day. Defaults to today, so past closures drop off.
  ///
  /// [to] - Closures that start on or before this day. Defaults to no upper limit.
  @GET('/api/v1/closures')
  Future<List<Closure>> listAllClosures({
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  /// Finds who is calling or writing: by phone number, e-mail address or name.
  ///
  /// [phone] - A phone number in any format, e.g. the caller id.
  ///
  /// [email] - An e-mail address.
  ///
  /// [q] - Part of a name (first, last or customer), ignoring case and accents.
  @GET('/api/v1/contacts/lookup')
  Future<LookupResult> lookupContacts({
    @Query('phone') String? phone,
    @Query('email') String? email,
    @Query('q') String? q,
  });

  @GET('/api/v1/contacts/{id}')
  Future<Contact> getContact({
    @Path('id') required String id,
  });

  @PUT('/api/v1/contacts/{id}')
  Future<Contact> updateContact({
    @Path('id') required String id,
    @Body() required ContactInput body,
  });

  /// [q] - Searches code, name, VAT number and city, ignoring case and accents ("Liege" finds "Liège").
  ///
  /// [sort] - Sort order: `field` ascending or `-field` descending, comma-separated for several keys (at.
  /// most 3). Fields: code, name, vat_number, email, phone, city, country_code, active.
  /// Default: name.
  ///
  /// [active] - Only active (`true`) or inactive (`false`) customers.
  ///
  /// [countryCode] - Only customers in these countries: one two-letter code or a comma-separated list.
  /// (`BE,NL`, at most 20), case-insensitive. Values combine with OR.
  @GET('/api/v1/customers')
  Future<CustomerPage> listCustomers({
    @Query('q') String? q,
    @Query('sort') String? sort,
    @Query('active') bool? active,
    @Query('country_code') String? countryCode,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/customers')
  Future<Customer> createCustomer({
    @Body() required CustomerInput body,
  });

  /// All customers (with the terms in the active company) as CSV, XLSX or ODS, ordered by code.
  ///
  /// [format] - `csv` (default), `xlsx` or `ods`.
  @GET('/api/v1/customers/export')
  Future<String> exportCustomers({
    @Query('format') Format? format,
  });

  /// [groupBy] - What to count by: `active` or `country_code`.
  ///
  /// [q] - Same as the list.
  ///
  /// [active] - Same as the list.
  ///
  /// [countryCode] - Same as the list.
  @GET('/api/v1/customers/groups')
  Future<GroupPage> customerGroups({
    @Query('group_by') required String groupBy,
    @Query('q') String? q,
    @Query('active') bool? active,
    @Query('country_code') String? countryCode,
  });

  /// Creates or updates customers from a CSV, XLSX or ODS file (detected from the content), keyed by.
  /// `code`. All-or-nothing: with any row error nothing is written (422 with every error);.
  /// `dry_run=true` only reports. `sheet` picks the sheet of a spreadsheet.
  ///
  /// [dryRun] - Validate and count only; nothing is written.
  ///
  /// [sheet] - The sheet to read from an XLSX or ODS file (the first sheet when absent); ignored for CSV.
  ///
  /// [body] - The raw bytes of a file.
  @POST('/api/v1/customers/import')
  Future<ImportReport> importCustomers({
    @Body() required File body,
    @Query('dry_run') bool? dryRun,
    @Query('sheet') String? sheet,
  });

  @GET('/api/v1/customers/mail-merge')
  Future<MailMergePreview> getMailMergeDraft();

  @PUT('/api/v1/customers/mail-merge')
  Future<MailMergePreview> saveMailMergeDraft({
    @Body() required MailMergeDraft body,
  });

  @GET('/api/v1/customers/mail-merge/history')
  Future<List<MailingDelivery>> mailMergeHistory();

  @POST('/api/v1/customers/mail-merge/{approval_id}/confirm')
  Future<void> confirmMailMerge({
    @Path('approval_id') required String approvalId,
  });

  /// Checks a VAT number for the customer form: the format and check digits, other customers with.
  /// the same number, and with `lookup=true` the name and address VIES has for it. Advice only;.
  /// nothing is stored. The lookup needs `customers.write`: it makes the server call VIES.
  ///
  /// [vatNumber] - The number as typed, with or without prefix, spaces and dots.
  ///
  /// [countryCode] - The country of the customer or supplier (ISO 3166-1 alpha-2): the prefix of a number typed.
  /// without one.
  ///
  /// [excludeId] - A record to leave out of the duplicates: the one being edited.
  ///
  /// [lookup] - Also ask VIES, for the name and address (needs the write permission of the module).
  @GET('/api/v1/customers/vat-check')
  Future<VatCheck> checkCustomerVat({
    @Query('vat_number') required String vatNumber,
    @Query('country_code') String? countryCode,
    @Query('exclude_id') String? excludeId,
    @Query('lookup') bool? lookup,
  });

  @GET('/api/v1/customers/{id}')
  Future<Customer> getCustomer({
    @Path('id') required String id,
  });

  @PUT('/api/v1/customers/{id}')
  Future<Customer> updateCustomer({
    @Path('id') required String id,
    @Body() required CustomerInput body,
  });

  /// Closures of one customer, upcoming and current by default.
  ///
  /// [from] - Closures that end on or after this day. Defaults to today, so past closures drop off.
  ///
  /// [to] - Closures that start on or before this day. Defaults to no upper limit.
  @GET('/api/v1/customers/{id}/closures')
  Future<List<Closure>> listCustomerClosures({
    @Path('id') required String id,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  /// Records a closure of the customer.
  @POST('/api/v1/customers/{id}/closures')
  Future<Closure> createClosure({
    @Path('id') required String id,
    @Body() required ClosureInput body,
  });

  /// Can the customer receive a delivery on this day? Shipment planning calls this before it.
  /// promises a date; only recorded closures count, not weekends or public holidays.
  ///
  /// [date] - The day the shipment would be delivered (YYYY-MM-DD).
  @GET('/api/v1/customers/{id}/closures/check')
  Future<DeliveryCheck> checkDeliveryDay({
    @Path('id') required String id,
    @Query('date') required DateTime date,
  });

  /// Changes a closure of the customer.
  @PUT('/api/v1/customers/{id}/closures/{closure_id}')
  Future<Closure> updateClosure({
    @Path('id') required String id,
    @Path('closure_id') required String closureId,
    @Body() required ClosureInput body,
  });

  /// Removes a closure of the customer.
  @DELETE('/api/v1/customers/{id}/closures/{closure_id}')
  Future<void> deleteClosure({
    @Path('id') required String id,
    @Path('closure_id') required String closureId,
  });

  /// [includeInactive] - Include contacts who left or are otherwise inactive.
  @GET('/api/v1/customers/{id}/contacts')
  Future<List<Contact>> listCustomerContacts({
    @Path('id') required String id,
    @Query('include_inactive') bool? includeInactive,
  });

  @POST('/api/v1/customers/{id}/contacts')
  Future<Contact> createContact({
    @Path('id') required String id,
    @Body() required ContactInput body,
  });

  @GET('/api/v1/customers/{id}/counts')
  Future<CustomerCounts> getCustomerCounts({
    @Path('id') required String id,
  });

  @GET('/api/v1/customers/{id}/rebates')
  Future<List<CustomerRebate>> listRebates({
    @Path('id') required String id,
  });

  @POST('/api/v1/customers/{id}/rebates')
  Future<CustomerRebate> createRebate({
    @Path('id') required String id,
    @Body() required RebateInput body,
  });

  @PUT('/api/v1/customers/{id}/rebates/{rebate_id}')
  Future<CustomerRebate> updateRebate({
    @Path('id') required String id,
    @Path('rebate_id') required String rebateId,
    @Body() required RebateInput body,
  });

  /// Removes a rebate. Quotations keep the rebate they were priced with.
  @DELETE('/api/v1/customers/{id}/rebates/{rebate_id}')
  Future<void> deleteRebate({
    @Path('id') required String id,
    @Path('rebate_id') required String rebateId,
  });

  @GET('/api/v1/match-rules')
  Future<List<MatchRule>> list();

  @POST('/api/v1/match-rules')
  Future<MatchRule> create({
    @Body() required MatchRuleInput body,
  });

  /// null.
  ///
  /// The name has been replaced because it contains a keyword. Original name: `get`.
  @GET('/api/v1/match-rules/{id}')
  Future<MatchRule> getApiV1MatchRulesId({
    @Path('id') required String id,
  });

  @PUT('/api/v1/match-rules/{id}')
  Future<MatchRule> update({
    @Path('id') required String id,
    @Body() required MatchRuleInput body,
  });

  @DELETE('/api/v1/match-rules/{id}')
  Future<void> delete({
    @Path('id') required String id,
  });

  /// [q] - Searches number, title and customer name.
  ///
  /// [open] - Only open (not won or lost) opportunities.
  @GET('/api/v1/opportunities')
  Future<OpportunityPage> listOpportunities({
    @Query('q') String? q,
    @Query('stage') String? stage,
    @Query('customer_id') String? customerId,
    @Query('open') bool? open,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/opportunities')
  Future<Opportunity> createOpportunity({
    @Body() required OpportunityInput body,
  });

  /// Count, value and probability-weighted value per stage.
  @GET('/api/v1/opportunities/pipeline')
  Future<List<PipelineStage>> pipeline();

  @GET('/api/v1/opportunities/{id}')
  Future<Opportunity> getOpportunity({
    @Path('id') required String id,
  });

  @PUT('/api/v1/opportunities/{id}')
  Future<Opportunity> updateOpportunity({
    @Path('id') required String id,
    @Body() required OpportunityInput body,
  });

  /// The baseline of an opportunity as a tree (a group holds its bells).
  @GET('/api/v1/opportunities/{id}/baseline')
  Future<List<BaselineItem>> getBaseline({
    @Path('id') required String id,
  });

  /// Previews (`dry_run=true`) or runs the import of a tower configurator export (the JSON as the.
  /// body) into the baseline: one bell group named from the source holding one bell per source.
  /// bell. Items of the same source that an earlier import created are replaced; items entered by.
  /// hand are never removed (those inside a replaced group move to the top level).
  ///
  /// [dryRun] - `true` returns the preview and writes nothing.
  ///
  /// [sourceId] - Identifies the source; an import replaces the items of the same source in the.
  /// opportunity. Default `tower_configurator`, at most 100 characters.
  @POST('/api/v1/opportunities/{id}/baseline/import')
  Future<BaselineImportReport> importBaseline({
    @Path('id') required String id,
    @Body() required dynamic body,
    @Query('dry_run') bool? dryRun,
    @Query('source_id') String? sourceId,
  });

  @POST('/api/v1/opportunities/{id}/baseline/items')
  Future<BaselineItem> createItem({
    @Path('id') required String id,
    @Body() required BaselineItemInput body,
  });

  @PUT('/api/v1/opportunities/{id}/baseline/items/{item_id}')
  Future<BaselineItem> updateItem({
    @Path('id') required String id,
    @Path('item_id') required String itemId,
    @Body() required BaselineItemUpdate body,
  });

  /// Deletes one item. An item that still has children is refused with 409 rather than deleting the.
  /// whole subtree silently: remove or move the children first.
  @DELETE('/api/v1/opportunities/{id}/baseline/items/{item_id}')
  Future<void> deleteItem({
    @Path('id') required String id,
    @Path('item_id') required String itemId,
  });

  /// The source of an imported item as it was received (the whole bell, or the document without.
  /// its bells for the group). 404 for an item entered by hand.
  @GET('/api/v1/opportunities/{id}/baseline/items/{item_id}/source')
  Future<void> getSource({
    @Path('id') required String id,
    @Path('item_id') required String itemId,
  });

  /// [status] - Only products with this status: `suitable`, `unsuitable` or `unknown`.
  ///
  /// [familyId] - Only products of this family.
  ///
  /// [itemId] - Judge against this baseline item (and the items inside it) only, e.g. to suggest products.
  /// for one dial or bell group. 404 when it is not an item of the opportunity.
  ///
  /// [productIds] - Only score these products, as a comma-separated list of up to 20 UUIDs.
  ///
  /// [limit] - Default 100, at most 500.
  @GET('/api/v1/opportunities/{id}/product-matches')
  Future<ProductMatchPage> productMatches({
    @Path('id') required String id,
    @Query('status') String? status,
    @Query('family_id') String? familyId,
    @Query('item_id') String? itemId,
    @Query('product_ids') String? productIds,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Moves an opportunity through the pipeline. `won`/`lost` close it; any other stage reopens it.
  @POST('/api/v1/opportunities/{id}/stage')
  Future<Opportunity> changeStage({
    @Path('id') required String id,
    @Body() required StageInput body,
  });
}
