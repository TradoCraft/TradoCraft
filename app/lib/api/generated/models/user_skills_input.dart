// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'user_skill_input.dart';

part 'user_skills_input.g.dart';

@JsonSerializable()
class UserSkillsInput {
  const UserSkillsInput({
    required this.skills,
  });
  
  factory UserSkillsInput.fromJson(Map<String, Object?> json) => _$UserSkillsInputFromJson(json);
  
  /// Replaces the technician's skills.
  final List<UserSkillInput> skills;

  Map<String, Object?> toJson() => _$UserSkillsInputToJson(this);
}
