// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'linked_ticket.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkedTicket _$LinkedTicketFromJson(Map<String, dynamic> json) => LinkedTicket(
  linkId: json['link_id'] as String,
  merged: json['merged'] as bool,
  number: json['number'] as String,
  priority: json['priority'] as String,
  status: json['status'] as String,
  subject: json['subject'] as String,
  ticketId: json['ticket_id'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  customerName: json['customer_name'] as String?,
  ownerName: json['owner_name'] as String?,
);

Map<String, dynamic> _$LinkedTicketToJson(LinkedTicket instance) =>
    <String, dynamic>{
      'customer_name': ?instance.customerName,
      'link_id': instance.linkId,
      'merged': instance.merged,
      'number': instance.number,
      'owner_name': ?instance.ownerName,
      'priority': instance.priority,
      'status': instance.status,
      'subject': instance.subject,
      'ticket_id': instance.ticketId,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
