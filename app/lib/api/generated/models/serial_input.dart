// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_input.g.dart';

@JsonSerializable()
class SerialInput {
  const SerialInput({
    required this.serialNumber,
    this.bomId,
    this.customerId,
    this.notes,
  });
  
  factory SerialInput.fromJson(Map<String, Object?> json) => _$SerialInputFromJson(json);
  
  /// BOM revision the unit was built to. Default: the product's active BOM, if any.
  @JsonKey(includeIfNull: false,name: 'bom_id')
  final String? bomId;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  Map<String, Object?> toJson() => _$SerialInputToJson(this);
}
