// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_line.dart';
import 'quotation_status.dart';
import 'sales_suggestion.dart';
import 'sales_warning.dart';
import 'vat_group.dart';

part 'quotation.g.dart';

/// A quotation with its lines (flat JSON: header fields, `lines`, `vat_groups`).
@JsonSerializable()
class Quotation {
  const Quotation({
    required this.total,
    required this.createdAt,
    required this.createdBy,
    required this.currency,
    required this.customerCity,
    required this.customerCountryCode,
    required this.customerDiscountPercent,
    required this.customerId,
    required this.customerLanguage,
    required this.customerName,
    required this.customerPostalCode,
    required this.customerStreet,
    required this.companyId,
    required this.id,
    required this.lines,
    required this.notes,
    required this.number,
    required this.revision,
    required this.priceDate,
    required this.priceZoneCode,
    required this.purpose,
    required this.quoteDate,
    required this.warnings,
    required this.shippingStatus,
    required this.status,
    required this.subtotal,
    required this.suggestions,
    required this.vatTotal,
    required this.vatGroups,
    required this.vatRegime,
    required this.validUntil,
    required this.updatedAt,
    this.customerVatNumber,
    this.supersedesId,
    this.sentAt,
    this.powerGridId,
    this.deliveryCountryCode,
    this.opportunityId,
  });
  
  factory Quotation.fromJson(Map<String, Object?> json) => _$QuotationFromJson(json);
  
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by')
  final String createdBy;
  final String currency;
  @JsonKey(name: 'customer_city')
  final String customerCity;
  @JsonKey(name: 'customer_country_code')
  final String customerCountryCode;
  @JsonKey(name: 'customer_discount_percent')
  final String customerDiscountPercent;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_language')
  final String customerLanguage;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(name: 'customer_postal_code')
  final String customerPostalCode;
  @JsonKey(name: 'customer_street')
  final String customerStreet;
  @JsonKey(includeIfNull: false,name: 'customer_vat_number')
  final String? customerVatNumber;

  /// Country the goods are delivered to (ISO alpha-2).
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final String id;
  final List<QuotationLine> lines;
  final String notes;
  final String number;
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;

  /// The grid at the delivery country the goods are connected to.
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;
  @JsonKey(name: 'price_date')
  final DateTime priceDate;
  @JsonKey(name: 'price_zone_code')
  final String priceZoneCode;

  /// installation | stock
  final String purpose;
  @JsonKey(name: 'quote_date')
  final DateTime quoteDate;
  final int revision;
  @JsonKey(includeIfNull: false,name: 'sent_at')
  final DateTime? sentAt;

  /// not_required | pending (shipping cost still to be quoted; sending is blocked) | quoted
  @JsonKey(name: 'shipping_status')
  final String shippingStatus;
  final QuotationStatus status;
  final String subtotal;

  /// Products worth adding; filled together with `warnings`.
  final List<SalesSuggestion> suggestions;
  @JsonKey(includeIfNull: false,name: 'supersedes_id')
  final String? supersedesId;
  final String total;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @JsonKey(name: 'valid_until')
  final DateTime validUntil;
  @JsonKey(name: 'vat_groups')
  final List<VatGroup> vatGroups;

  /// `domestic` (VAT charged), `intra_eu` (reverse charge) or `outside_eu`: VAT is only shown and.
  /// charged for `domestic`.
  @JsonKey(name: 'vat_regime')
  final String vatRegime;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  /// Hints about the lines (power grid fit, incompatible products); filled when the quotation is.
  /// created or updated, empty otherwise. Never blocking.
  final List<SalesWarning> warnings;

  Map<String, Object?> toJson() => _$QuotationToJson(this);
}
