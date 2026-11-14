// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'shipping_request.g.dart';

@JsonSerializable()
class ShippingRequest {
  const ShippingRequest({
    required this.createdAt,
    required this.customerName,
    required this.id,
    required this.notes,
    required this.quotationId,
    required this.quotationNumber,
    required this.quotationRevision,
    required this.status,
    this.carrier,
    this.currency,
    this.deliveryCountryCode,
    this.quotedAmount,
    this.quotedAt,
    this.quotedBy,
    this.requestedAt,
    this.requestedBy,
  });
  
  factory ShippingRequest.fromJson(Map<String, Object?> json) => _$ShippingRequestFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? carrier;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final String id;
  final String notes;
  @JsonKey(name: 'quotation_id')
  final String quotationId;
  @JsonKey(name: 'quotation_number')
  final String quotationNumber;
  @JsonKey(name: 'quotation_revision')
  final int quotationRevision;
  @JsonKey(includeIfNull: false,name: 'quoted_amount')
  final String? quotedAmount;
  @JsonKey(includeIfNull: false,name: 'quoted_at')
  final DateTime? quotedAt;
  @JsonKey(includeIfNull: false,name: 'quoted_by')
  final String? quotedBy;
  @JsonKey(includeIfNull: false,name: 'requested_at')
  final DateTime? requestedAt;
  @JsonKey(includeIfNull: false,name: 'requested_by')
  final String? requestedBy;

  /// open | requested | quoted | cancelled
  final String status;

  Map<String, Object?> toJson() => _$ShippingRequestToJson(this);
}
