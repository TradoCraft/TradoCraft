// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'equipment_job.dart';

part 'customer_equipment.g.dart';

@JsonSerializable()
class CustomerEquipment {
  const CustomerEquipment({
    required this.productCode,
    required this.productName,
    required this.serialNumber,
    required this.serialUnitId,
    required this.status,
    required this.warrantyNote,
    required this.warrantyStatus,
    required this.jobs,
    this.warrantyUntil,
  });
  
  factory CustomerEquipment.fromJson(Map<String, Object?> json) => _$CustomerEquipmentFromJson(json);
  
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

  /// The jobs this unit was worked on in, newest first (only those the user may see).
  final List<EquipmentJob> jobs;

  Map<String, Object?> toJson() => _$CustomerEquipmentToJson(this);
}
