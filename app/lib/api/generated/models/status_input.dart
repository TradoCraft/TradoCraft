// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'status_input.g.dart';

@JsonSerializable()
class StatusInput {
  const StatusInput({
    required this.status,
    this.note,
  });
  
  factory StatusInput.fromJson(Map<String, Object?> json) => _$StatusInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? note;
  final String status;

  Map<String, Object?> toJson() => _$StatusInputToJson(this);
}
