// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'followers.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Followers _$FollowersFromJson(Map<String, dynamic> json) => Followers(
  following: json['following'] as bool,
  items: (json['items'] as List<dynamic>)
      .map((e) => Follower.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$FollowersToJson(Followers instance) => <String, dynamic>{
  'following': instance.following,
  'items': instance.items,
};
