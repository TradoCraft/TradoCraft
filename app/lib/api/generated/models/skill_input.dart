// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'skill_input.g.dart';

@JsonSerializable()
class SkillInput {
  const SkillInput({
    required this.code,
    required this.name,
  });
  
  factory SkillInput.fromJson(Map<String, Object?> json) => _$SkillInputFromJson(json);
  
  final String code;
  final String name;

  Map<String, Object?> toJson() => _$SkillInputToJson(this);
}
