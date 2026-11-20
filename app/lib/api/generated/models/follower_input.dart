// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'follower_input.g.dart';

@JsonSerializable()
class FollowerInput {
  const FollowerInput({
    required this.userId,
  });
  
  factory FollowerInput.fromJson(Map<String, Object?> json) => _$FollowerInputFromJson(json);
  
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$FollowerInputToJson(this);
}
