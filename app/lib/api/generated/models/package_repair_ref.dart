// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_repair_ref.g.dart';

/// A repair linked to a parcel.
@JsonSerializable()
class PackageRepairRef {
  const PackageRepairRef({
    required this.customerName,
    required this.id,
    required this.linkedAt,
    required this.number,
    required this.productDescription,
    required this.serialNumber,
    required this.status,
    this.linkedByName,
  });
  
  factory PackageRepairRef.fromJson(Map<String, Object?> json) => _$PackageRepairRefFromJson(json);
  
  @JsonKey(name: 'customer_name')
  final String customerName;
  final String id;
  @JsonKey(name: 'linked_at')
  final DateTime linkedAt;
  @JsonKey(includeIfNull: false,name: 'linked_by_name')
  final String? linkedByName;
  final String number;
  @JsonKey(name: 'product_description')
  final String productDescription;
  @JsonKey(name: 'serial_number')
  final String serialNumber;
  final String status;

  Map<String, Object?> toJson() => _$PackageRepairRefToJson(this);
}
