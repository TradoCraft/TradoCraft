// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'priority_request.g.dart';

@JsonSerializable()
class PriorityRequest {
  const PriorityRequest({
    required this.createdAt,
    required this.id,
    required this.message,
    required this.orderId,
    required this.requestedByContactId,
    required this.requestedByName,
    required this.requestedPriority,
    required this.resolutionNote,
    required this.status,
    this.resolvedAt,
  });
  
  factory PriorityRequest.fromJson(Map<String, Object?> json) => _$PriorityRequestFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final String message;
  @JsonKey(name: 'order_id')
  final String orderId;
  @JsonKey(name: 'requested_by_contact_id')
  final String requestedByContactId;
  @JsonKey(name: 'requested_by_name')
  final String requestedByName;

  /// low | expedite
  @JsonKey(name: 'requested_priority')
  final String requestedPriority;
  @JsonKey(name: 'resolution_note')
  final String resolutionNote;
  @JsonKey(includeIfNull: false,name: 'resolved_at')
  final DateTime? resolvedAt;

  /// open | applied | dismissed
  final String status;

  Map<String, Object?> toJson() => _$PriorityRequestToJson(this);
}
