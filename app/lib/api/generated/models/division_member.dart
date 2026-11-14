// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'division_member.g.dart';

/// A user who works in a division.
@JsonSerializable()
class DivisionMember {
  const DivisionMember({
    required this.displayName,
    required this.userId,
  });
  
  factory DivisionMember.fromJson(Map<String, Object?> json) => _$DivisionMemberFromJson(json);
  
  /// The name shown for the user.
  @JsonKey(name: 'display_name')
  final String displayName;

  /// The user.
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$DivisionMemberToJson(this);
}
