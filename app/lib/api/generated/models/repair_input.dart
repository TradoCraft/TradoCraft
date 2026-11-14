// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'repair_input.g.dart';

@JsonSerializable()
class RepairInput {
  const RepairInput({
    required this.faultDescription,
    required this.priority,
    required this.warranty,
    this.contactId,
    this.customerReference,
    this.productDescription,
    this.productId,
    this.serialNumber,
  });
  
  factory RepairInput.fromJson(Map<String, Object?> json) => _$RepairInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;
  @JsonKey(name: 'fault_description')
  final String faultDescription;
  final String priority;
  @JsonKey(includeIfNull: false,name: 'product_description')
  final String? productDescription;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  final String warranty;

  Map<String, Object?> toJson() => _$RepairInputToJson(this);
}
