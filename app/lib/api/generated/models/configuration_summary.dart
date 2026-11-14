// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'configuration_summary.g.dart';

@JsonSerializable()
class ConfigurationSummary {
  const ConfigurationSummary({
    required this.id,
    required this.modelCode,
    required this.modelId,
    required this.modelName,
    required this.name,
    required this.revision,
    required this.updatedAt,
    this.customerId,
    this.customerName,
    this.newerRevision,
    this.quotationId,
    this.quotationNumber,
  });
  
  factory ConfigurationSummary.fromJson(Map<String, Object?> json) => _$ConfigurationSummaryFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  final String id;
  @JsonKey(name: 'model_code')
  final String modelCode;
  @JsonKey(name: 'model_id')
  final String modelId;
  @JsonKey(name: 'model_name')
  final String modelName;
  final String name;

  /// The number of the model's active revision when it is newer (an upgrade is available).
  @JsonKey(includeIfNull: false,name: 'newer_revision')
  final int? newerRevision;
  @JsonKey(includeIfNull: false,name: 'quotation_id')
  final String? quotationId;
  @JsonKey(includeIfNull: false,name: 'quotation_number')
  final String? quotationNumber;

  /// The revision it was made with.
  final int revision;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ConfigurationSummaryToJson(this);
}
