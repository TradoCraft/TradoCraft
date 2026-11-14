// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_status.dart';

part 'quotation_summary.g.dart';

@JsonSerializable()
class QuotationSummary {
  const QuotationSummary({
    required this.currency,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.number,
    required this.purpose,
    required this.quoteDate,
    required this.revision,
    required this.shippingStatus,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.validUntil,
    this.opportunityId,
  });
  
  factory QuotationSummary.fromJson(Map<String, Object?> json) => _$QuotationSummaryFromJson(json);
  
  final String currency;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  final String id;
  final String number;
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;

  /// installation | stock
  final String purpose;
  @JsonKey(name: 'quote_date')
  final DateTime quoteDate;
  final int revision;

  /// not_required | pending | quoted: whether a shipping cost still has to be requested.
  @JsonKey(name: 'shipping_status')
  final String shippingStatus;
  final QuotationStatus status;
  final String subtotal;
  final String total;
  @JsonKey(name: 'valid_until')
  final DateTime validUntil;

  Map<String, Object?> toJson() => _$QuotationSummaryToJson(this);
}
