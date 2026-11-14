// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'member.g.dart';

@JsonSerializable()
class Member {
  const Member({
    required this.displayName,
    required this.userId,
  });
  
  factory Member.fromJson(Map<String, Object?> json) => _$MemberFromJson(json);
  
  @JsonKey(name: 'display_name')
  final String displayName;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$MemberToJson(this);
}
