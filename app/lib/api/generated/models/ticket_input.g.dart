// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TicketInput _$TicketInputFromJson(Map<String, dynamic> json) => TicketInput(
  category: json['category'] as String,
  language: json['language'] as String,
  priority: json['priority'] as String,
  status: json['status'] as String,
  subject: json['subject'] as String,
  contactEmail: json['contact_email'] as String?,
  contactId: json['contact_id'] as String?,
  contactName: json['contact_name'] as String?,
  customerId: json['customer_id'] as String?,
  expectedVersion: (json['expected_version'] as num?)?.toInt(),
  opportunityId: json['opportunity_id'] as String?,
  ownerUserId: json['owner_user_id'] as String?,
  quotationId: json['quotation_id'] as String?,
);

Map<String, dynamic> _$TicketInputToJson(TicketInput instance) =>
    <String, dynamic>{
      'category': instance.category,
      'contact_email': ?instance.contactEmail,
      'contact_id': ?instance.contactId,
      'contact_name': ?instance.contactName,
      'customer_id': ?instance.customerId,
      'expected_version': ?instance.expectedVersion,
      'language': instance.language,
      'opportunity_id': ?instance.opportunityId,
      'owner_user_id': ?instance.ownerUserId,
      'priority': instance.priority,
      'quotation_id': ?instance.quotationId,
      'status': instance.status,
      'subject': instance.subject,
    };
