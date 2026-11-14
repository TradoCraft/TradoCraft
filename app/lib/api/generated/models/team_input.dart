// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'member_input.dart';

part 'team_input.g.dart';

@JsonSerializable()
class TeamInput {
  const TeamInput({
    required this.name,
    this.active,
    this.members,
  });
  
  factory TeamInput.fromJson(Map<String, Object?> json) => _$TeamInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// The complete member list: members not listed are removed.
  @JsonKey(includeIfNull: false)
  final List<MemberInput>? members;
  final String name;

  Map<String, Object?> toJson() => _$TeamInputToJson(this);
}
