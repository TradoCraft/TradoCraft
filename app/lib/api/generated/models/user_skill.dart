// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'user_skill.g.dart';

@JsonSerializable()
class UserSkill {
  const UserSkill({
    required this.code,
    required this.level,
    required this.name,
    required this.skillId,
  });
  
  factory UserSkill.fromJson(Map<String, Object?> json) => _$UserSkillFromJson(json);
  
  final String code;

  /// 1 = basic, 2 = proficient, 3 = expert.
  final int level;
  final String name;
  @JsonKey(name: 'skill_id')
  final String skillId;

  Map<String, Object?> toJson() => _$UserSkillToJson(this);
}
