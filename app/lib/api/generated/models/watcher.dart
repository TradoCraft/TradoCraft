// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'watcher.g.dart';

@JsonSerializable()
class Watcher {
  const Watcher({
    required this.createdAt,
    required this.userId,
    required this.userName,
  });
  
  factory Watcher.fromJson(Map<String, Object?> json) => _$WatcherFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$WatcherToJson(this);
}
