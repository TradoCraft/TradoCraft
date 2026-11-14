// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'audit_event.dart';

part 'audit_page.g.dart';

/// A page of events, newest first.
@JsonSerializable()
class AuditPage {
  const AuditPage({
    required this.items,
    this.nextBeforeId,
  });
  
  factory AuditPage.fromJson(Map<String, Object?> json) => _$AuditPageFromJson(json);
  
  final List<AuditEvent> items;

  /// Pass as `before_id` for the next (older) page; absent on the last page.
  @JsonKey(includeIfNull: false,name: 'next_before_id')
  final int? nextBeforeId;

  Map<String, Object?> toJson() => _$AuditPageToJson(this);
}
