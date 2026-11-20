// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follower.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Follower _$FollowerFromJson(Map<String, dynamic> json) => Follower(
  followedAt: DateTime.parse(json['followed_at'] as String),
  reason: json['reason'] as String,
  userId: json['user_id'] as String,
  userName: json['user_name'] as String,
);

Map<String, dynamic> _$FollowerToJson(Follower instance) => <String, dynamic>{
  'followed_at': instance.followedAt.toIso8601String(),
  'reason': instance.reason,
  'user_id': instance.userId,
  'user_name': instance.userName,
};
