// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reason_input.g.dart';

@JsonSerializable()
class ReasonInput {
  const ReasonInput({
    this.reason,
  });
  
  factory ReasonInput.fromJson(Map<String, Object?> json) => _$ReasonInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? reason;

  Map<String, Object?> toJson() => _$ReasonInputToJson(this);
}
