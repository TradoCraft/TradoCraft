// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_status_input.g.dart';

@JsonSerializable()
class SerialStatusInput {
  const SerialStatusInput({
    required this.status,
    this.customerId,
  });
  
  factory SerialStatusInput.fromJson(Map<String, Object?> json) => _$SerialStatusInputFromJson(json);
  
  /// Required for delivered and installed, unless the unit already has a customer.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;

  /// in_stock | delivered | installed | scrapped (built_in is set by attaching to another unit)
  final String status;

  Map<String, Object?> toJson() => _$SerialStatusInputToJson(this);
}
