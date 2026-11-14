// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'portal_ticket.g.dart';

@JsonSerializable()
class PortalTicket {
  const PortalTicket({
    required this.category,
    required this.contactName,
    required this.createdAt,
    required this.id,
    required this.number,
    required this.status,
    required this.subject,
    required this.updatedAt,
    this.closedAt,
  });
  
  factory PortalTicket.fromJson(Map<String, Object?> json) => _$PortalTicketFromJson(json);
  
  final String category;
  @JsonKey(includeIfNull: false,name: 'closed_at')
  final DateTime? closedAt;

  /// Who raised it (colleagues' tickets are visible with the `customer` scope).
  @JsonKey(name: 'contact_name')
  final String contactName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final String number;

  /// open | pending_customer (we wait for the customer) | closed
  final String status;
  final String subject;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$PortalTicketToJson(this);
}
