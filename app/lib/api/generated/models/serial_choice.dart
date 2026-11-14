// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_choice.g.dart';

@JsonSerializable()
class SerialChoice {
  const SerialChoice({
    required this.id,
    required this.serialNumber,
  });
  
  factory SerialChoice.fromJson(Map<String, Object?> json) => _$SerialChoiceFromJson(json);
  
  final String id;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  Map<String, Object?> toJson() => _$SerialChoiceToJson(this);
}
