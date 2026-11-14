// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'audit_event.g.dart';

/// One audited event: who did what to which record, and when.
@JsonSerializable()
class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.data,
    required this.entity,
    required this.entityId,
    required this.id,
    required this.occurredAt,
    this.userEmail,
    this.userId,
    this.userName,
  });

  factory AuditEvent.fromJson(Map<String, Object?> json) =>
      _$AuditEventFromJson(json);

  /// What happened (`created`, `updated`, `sent`, ...); the modules name their own.
  final String action;

  /// What the module recorded: for an update usually `{"changes": {"field": {"from", "to"}}}`,.
  /// but each module decides, and some record nothing but the action.
  final dynamic data;

  /// The kind of record (`customer`, `quotation`, `supplier_invoice`, ...).
  final String entity;
  @JsonKey(name: 'entity_id')
  final String entityId;

  /// Increases with time; the cursor for the next page.
  final int id;
  @JsonKey(name: 'occurred_at')
  final DateTime occurredAt;
  @JsonKey(includeIfNull: false, name: 'user_email')
  final String? userEmail;

  /// Absent for an event without a staff user, such as a customer acting in the portal; who.
  /// acted is then in `data`.
  @JsonKey(includeIfNull: false, name: 'user_id')
  final String? userId;
  @JsonKey(includeIfNull: false, name: 'user_name')
  final String? userName;

  Map<String, Object?> toJson() => _$AuditEventToJson(this);
}
