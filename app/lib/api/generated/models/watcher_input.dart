// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'watcher_input.g.dart';

@JsonSerializable()
class WatcherInput {
  const WatcherInput({
    required this.userId,
  });
  
  factory WatcherInput.fromJson(Map<String, Object?> json) => _$WatcherInputFromJson(json);
  
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$WatcherInputToJson(this);
}
