// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'attach_input.g.dart';

@JsonSerializable()
class AttachInput {
  const AttachInput({
    required this.childId,
  });
  
  factory AttachInput.fromJson(Map<String, Object?> json) => _$AttachInputFromJson(json);
  
  @JsonKey(name: 'child_id')
  final String childId;

  Map<String, Object?> toJson() => _$AttachInputToJson(this);
}
