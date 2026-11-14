// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'timeline_item.g.dart';

/// One line of the activity timeline: an event or a message, oldest first.
@JsonSerializable()
class TimelineItem {
  const TimelineItem({
    required this.at,
    required this.comment,
    required this.id,
    required this.kind,
    required this.source,
    this.actorName,
    this.actorUserId,
    this.fromValue,
    this.previousUserId,
    this.previousUserName,
    this.targetTeamId,
    this.targetTeamName,
    this.targetUserId,
    this.targetUserName,
    this.toValue,
  });
  
  factory TimelineItem.fromJson(Map<String, Object?> json) => _$TimelineItemFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'actor_name')
  final String? actorName;

  /// The colleague (events, notes, replies) or the customer's name (incoming messages).
  @JsonKey(includeIfNull: false,name: 'actor_user_id')
  final String? actorUserId;
  final DateTime at;

  /// Events: the internal reason or comment. Messages: the first 300 characters.
  final String comment;

  /// status / priority: the old value; merged: the number of the merged ticket.
  @JsonKey(includeIfNull: false,name: 'from_value')
  final String? fromValue;
  final String id;

  /// Events: created | assigned | delegated | escalated | status | priority | merged |.
  /// tag_added | tag_removed. Messages: email_in | email_out | note | call_in | call_out | portal_in.
  final String kind;
  @JsonKey(includeIfNull: false,name: 'previous_user_id')
  final String? previousUserId;
  @JsonKey(includeIfNull: false,name: 'previous_user_name')
  final String? previousUserName;

  /// event | message
  final String source;
  @JsonKey(includeIfNull: false,name: 'target_team_id')
  final String? targetTeamId;
  @JsonKey(includeIfNull: false,name: 'target_team_name')
  final String? targetTeamName;
  @JsonKey(includeIfNull: false,name: 'target_user_id')
  final String? targetUserId;
  @JsonKey(includeIfNull: false,name: 'target_user_name')
  final String? targetUserName;

  /// status / priority: the new value; assigned: `owner` or `team`; tags: the tag;.
  /// merged: the target ticket number.
  @JsonKey(includeIfNull: false,name: 'to_value')
  final String? toValue;

  Map<String, Object?> toJson() => _$TimelineItemToJson(this);
}
