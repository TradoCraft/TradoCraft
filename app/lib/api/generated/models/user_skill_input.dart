// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'user_skill_input.g.dart';

@JsonSerializable()
class UserSkillInput {
  const UserSkillInput({
    required this.level,
    required this.skillId,
  });
  
  factory UserSkillInput.fromJson(Map<String, Object?> json) => _$UserSkillInputFromJson(json);
  
  final int level;
  @JsonKey(name: 'skill_id')
  final String skillId;

  Map<String, Object?> toJson() => _$UserSkillInputToJson(this);
}
