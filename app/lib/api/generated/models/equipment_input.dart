// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'equipment_input.g.dart';

@JsonSerializable()
class EquipmentInput {
  const EquipmentInput({
    required this.serialUnitId,
  });
  
  factory EquipmentInput.fromJson(Map<String, Object?> json) => _$EquipmentInputFromJson(json);
  
  @JsonKey(name: 'serial_unit_id')
  final String serialUnitId;

  Map<String, Object?> toJson() => _$EquipmentInputToJson(this);
}
