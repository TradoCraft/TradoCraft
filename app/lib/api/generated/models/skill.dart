// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'skill.g.dart';

@JsonSerializable()
class Skill {
  const Skill({
    required this.code,
    required this.id,
    required this.name,
  });
  
  factory Skill.fromJson(Map<String, Object?> json) => _$SkillFromJson(json);
  
  final String code;
  final String id;
  final String name;

  Map<String, Object?> toJson() => _$SkillToJson(this);
}
