// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'follower.g.dart';

@JsonSerializable()
class Follower {
  const Follower({
    required this.followedAt,
    required this.reason,
    required this.userId,
    required this.userName,
  });
  
  factory Follower.fromJson(Map<String, Object?> json) => _$FollowerFromJson(json);
  
  @JsonKey(name: 'followed_at')
  final DateTime followedAt;

  /// `manual` | `author` | `assigned`
  final String reason;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$FollowerToJson(this);
}
