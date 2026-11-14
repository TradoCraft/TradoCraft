// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_skills_input.g.dart';

@JsonSerializable()
class JobSkillsInput {
  const JobSkillsInput({
    required this.skillIds,
  });
  
  factory JobSkillsInput.fromJson(Map<String, Object?> json) => _$JobSkillsInputFromJson(json);
  
  /// Replaces the skills the job requires.
  @JsonKey(name: 'skill_ids')
  final List<String> skillIds;

  Map<String, Object?> toJson() => _$JobSkillsInputToJson(this);
}
