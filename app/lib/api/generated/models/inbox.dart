// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'inbox_activity.dart';
import 'inbox_record.dart';

part 'inbox.g.dart';

/// What needs the caller's attention across records, for the notifications centre.
@JsonSerializable()
class Inbox {
  const Inbox({
    required this.activities,
    required this.unread,
  });
  
  factory Inbox.fromJson(Map<String, Object?> json) => _$InboxFromJson(json);
  
  /// Open activities assigned to the caller that are due today or earlier.
  final List<InboxActivity> activities;
  final List<InboxRecord> unread;

  Map<String, Object?> toJson() => _$InboxToJson(this);
}
