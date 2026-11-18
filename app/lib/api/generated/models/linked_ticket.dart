// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'linked_ticket.g.dart';

/// The other end of a link, with what is needed to judge the bundle at a glance.
@JsonSerializable()
class LinkedTicket {
  const LinkedTicket({
    required this.linkId,
    required this.merged,
    required this.number,
    required this.priority,
    required this.status,
    required this.subject,
    required this.ticketId,
    required this.updatedAt,
    this.customerName,
    this.ownerName,
  });
  
  factory LinkedTicket.fromJson(Map<String, Object?> json) => _$LinkedTicketFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;
  @JsonKey(name: 'link_id')
  final String linkId;

  /// The ticket was merged into another one and is closed.
  final bool merged;
  final String number;
  @JsonKey(includeIfNull: false,name: 'owner_name')
  final String? ownerName;
  final String priority;
  final String status;
  final String subject;
  @JsonKey(name: 'ticket_id')
  final String ticketId;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$LinkedTicketToJson(this);
}
