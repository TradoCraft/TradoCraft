// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_equipment.g.dart';

@JsonSerializable()
class JobEquipment {
  const JobEquipment({
    required this.productCode,
    required this.productName,
    required this.serialNumber,
    required this.serialUnitId,
    required this.status,
    required this.warrantyNote,
    required this.warrantyStatus,
    this.warrantyUntil,
  });
  
  factory JobEquipment.fromJson(Map<String, Object?> json) => _$JobEquipmentFromJson(json);
  
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'serial_number')
  final String serialNumber;
  @JsonKey(name: 'serial_unit_id')
  final String serialUnitId;
  final String status;
  @JsonKey(name: 'warranty_note')
  final String warrantyNote;

  /// in_warranty | expired | unknown
  @JsonKey(name: 'warranty_status')
  final String warrantyStatus;
  @JsonKey(includeIfNull: false,name: 'warranty_until')
  final DateTime? warrantyUntil;

  Map<String, Object?> toJson() => _$JobEquipmentToJson(this);
}
