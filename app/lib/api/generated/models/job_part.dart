// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_part.g.dart';

@JsonSerializable()
class JobPart {
  const JobPart({
    required this.billable,
    required this.createdAt,
    required this.description,
    required this.id,
    required this.quantity,
    required this.unit,
    this.addedByName,
    this.productCode,
    this.productId,
    this.serialNumber,
    this.serialUnitId,
  });
  
  factory JobPart.fromJson(Map<String, Object?> json) => _$JobPartFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'added_by_name')
  final String? addedByName;
  final bool billable;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String description;

  /// Chosen by the client.
  final String id;
  @JsonKey(includeIfNull: false,name: 'product_code')
  final String? productCode;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;
  final String unit;

  Map<String, Object?> toJson() => _$JobPartToJson(this);
}
