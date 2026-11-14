// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'team_member.dart';

part 'team.g.dart';

@JsonSerializable()
class Team {
  const Team({
    required this.active,
    required this.createdAt,
    required this.id,
    required this.members,
    required this.name,
  });
  
  factory Team.fromJson(Map<String, Object?> json) => _$TeamFromJson(json);
  
  final bool active;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final List<TeamMember> members;
  final String name;

  Map<String, Object?> toJson() => _$TeamToJson(this);
}
