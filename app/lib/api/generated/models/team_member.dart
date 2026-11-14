// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'team_member.g.dart';

@JsonSerializable()
class TeamMember {
  const TeamMember({
    required this.displayName,
    required this.isLead,
    required this.userId,
  });
  
  factory TeamMember.fromJson(Map<String, Object?> json) => _$TeamMemberFromJson(json);
  
  @JsonKey(name: 'display_name')
  final String displayName;
  @JsonKey(name: 'is_lead')
  final bool isLead;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$TeamMemberToJson(this);
}
