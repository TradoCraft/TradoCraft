// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'portal_repair.g.dart';

@JsonSerializable()
class PortalRepair {
  const PortalRepair({
    required this.contactName,
    required this.createdAt,
    required this.customerReference,
    required this.faultDescription,
    required this.id,
    required this.number,
    required this.photoCount,
    required this.productDescription,
    required this.serialNumber,
    required this.status,
    required this.updatedAt,
  });
  
  factory PortalRepair.fromJson(Map<String, Object?> json) => _$PortalRepairFromJson(json);
  
  /// Who registered it (colleagues' repairs are visible with the `customer` scope).
  @JsonKey(name: 'contact_name')
  final String contactName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_reference')
  final String customerReference;
  @JsonKey(name: 'fault_description')
  final String faultDescription;
  final String id;
  final String number;
  @JsonKey(name: 'photo_count')
  final int photoCount;
  @JsonKey(name: 'product_description')
  final String productDescription;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  /// announced | in_repair | waiting_customer | ready | shipped | cancelled
  final String status;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$PortalRepairToJson(this);
}
