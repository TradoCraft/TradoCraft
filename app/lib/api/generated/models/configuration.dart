// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'inputs.dart';

part 'configuration.g.dart';

@JsonSerializable()
class Configuration {
  const Configuration({
    required this.createdAt,
    required this.id,
    required this.inputs,
    required this.modelCode,
    required this.modelId,
    required this.modelName,
    required this.name,
    required this.revision,
    required this.revisionId,
    required this.revisionStatus,
    required this.updatedAt,
    this.customerId,
    this.customerName,
    this.newerRevisionId,
    this.quotationId,
    this.quotationNumber,
    this.result,
  });
  
  factory Configuration.fromJson(Map<String, Object?> json) => _$ConfigurationFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  final String id;
  final Inputs inputs;
  @JsonKey(name: 'model_code')
  final String modelCode;
  @JsonKey(name: 'model_id')
  final String modelId;
  @JsonKey(name: 'model_name')
  final String modelName;
  final String name;

  /// The model's active revision when it is newer than this configuration's (offer an upgrade).
  @JsonKey(includeIfNull: false,name: 'newer_revision_id')
  final String? newerRevisionId;
  @JsonKey(includeIfNull: false,name: 'quotation_id')
  final String? quotationId;
  @JsonKey(includeIfNull: false,name: 'quotation_number')
  final String? quotationNumber;

  /// The evaluation when last saved or quoted.
  @JsonKey(includeIfNull: false)
  final dynamic result;
  final int revision;
  @JsonKey(name: 'revision_id')
  final String revisionId;

  /// draft | active | obsolete (of the revision it was made with)
  @JsonKey(name: 'revision_status')
  final String revisionStatus;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ConfigurationToJson(this);
}
