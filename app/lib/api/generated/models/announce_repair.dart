// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'announce_repair.g.dart';

@JsonSerializable()
class AnnounceRepair {
  const AnnounceRepair({
    required this.faultDescription,
    this.customerReference,
    this.productDescription,
    this.serialNumber,
  });
  
  factory AnnounceRepair.fromJson(Map<String, Object?> json) => _$AnnounceRepairFromJson(json);
  
  /// The customer's own reference (RMA or purchase order).
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;
  @JsonKey(name: 'fault_description')
  final String faultDescription;

  /// The product in the customer's words, e.g. "Pump 5 kW, blue".
  @JsonKey(includeIfNull: false,name: 'product_description')
  final String? productDescription;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;

  Map<String, Object?> toJson() => _$AnnounceRepairToJson(this);
}
