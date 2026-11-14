// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_unit_input.g.dart';

@JsonSerializable()
class SerialUnitInput {
  const SerialUnitInput({
    this.clear,
    this.serialUnitId,
  });
  
  factory SerialUnitInput.fromJson(Map<String, Object?> json) => _$SerialUnitInputFromJson(json);
  
  /// True to unlink the serial unit (and the automatic warranty result with it).
  @JsonKey(includeIfNull: false)
  final bool? clear;

  /// The serial unit the repair is about.
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  Map<String, Object?> toJson() => _$SerialUnitInputToJson(this);
}
