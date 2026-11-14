// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'presence_input.g.dart';

@JsonSerializable()
class PresenceInput {
  const PresenceInput({
    required this.mode,
  });
  
  factory PresenceInput.fromJson(Map<String, Object?> json) => _$PresenceInputFromJson(json);
  
  /// viewing | replying
  final String mode;

  Map<String, Object?> toJson() => _$PresenceInputToJson(this);
}
