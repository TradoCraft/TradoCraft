// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'follower.dart';

part 'followers.g.dart';

/// The followers of a record and whether the caller is one of them.
@JsonSerializable()
class Followers {
  const Followers({
    required this.following,
    required this.items,
  });
  
  factory Followers.fromJson(Map<String, Object?> json) => _$FollowersFromJson(json);
  
  final bool following;
  final List<Follower> items;

  Map<String, Object?> toJson() => _$FollowersToJson(this);
}
