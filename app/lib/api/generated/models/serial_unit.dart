// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_unit.g.dart';

@JsonSerializable()
class SerialUnit {
  const SerialUnit({
    required this.createdAt,
    required this.id,
    required this.notes,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.serialNumber,
    required this.status,
    required this.updatedAt,
    required this.warrantyNote,
    required this.warrantyStatus,
    this.bomId,
    this.bomRevision,
    this.customerId,
    this.customerName,
    this.parentId,
    this.parentSerialNumber,
    this.warrantyUntil,
  });
  
  factory SerialUnit.fromJson(Map<String, Object?> json) => _$SerialUnitFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'bom_id')
  final String? bomId;
  @JsonKey(includeIfNull: false,name: 'bom_revision')
  final int? bomRevision;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  final String id;
  final String notes;

  /// The unit this one is currently built into.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;
  @JsonKey(includeIfNull: false,name: 'parent_serial_number')
  final String? parentSerialNumber;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  /// in_stock | built_in | delivered | installed | scrapped
  final String status;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @JsonKey(name: 'warranty_note')
  final String warrantyNote;

  /// in_warranty | expired | unknown (no end date recorded)
  @JsonKey(name: 'warranty_status')
  final String warrantyStatus;

  /// The end of the warranty, if known.
  @JsonKey(includeIfNull: false,name: 'warranty_until')
  final DateTime? warrantyUntil;

  Map<String, Object?> toJson() => _$SerialUnitToJson(this);
}
