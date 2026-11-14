// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_unit_ref.g.dart';

@JsonSerializable()
class SerialUnitRef {
  const SerialUnitRef({
    required this.id,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.serialNumber,
    this.customerId,
    this.warrantyUntil,
  });
  
  factory SerialUnitRef.fromJson(Map<String, Object?> json) => _$SerialUnitRefFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  final String id;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'serial_number')
  final String serialNumber;
  @JsonKey(includeIfNull: false,name: 'warranty_until')
  final DateTime? warrantyUntil;

  Map<String, Object?> toJson() => _$SerialUnitRefToJson(this);
}
