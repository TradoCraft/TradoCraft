// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'presence_entry.g.dart';

/// A colleague who is looking at (or answering) the ticket right now.
@JsonSerializable()
class PresenceEntry {
  const PresenceEntry({
    required this.mode,
    required this.seenAt,
    required this.userId,
    required this.userName,
  });
  
  factory PresenceEntry.fromJson(Map<String, Object?> json) => _$PresenceEntryFromJson(json);
  
  /// viewing | replying
  final String mode;
  @JsonKey(name: 'seen_at')
  final DateTime seenAt;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$PresenceEntryToJson(this);
}
