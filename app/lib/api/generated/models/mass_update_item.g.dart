// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mass_update_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MassUpdateItem _$MassUpdateItemFromJson(Map<String, dynamic> json) =>
    MassUpdateItem(
      number: json['number'] as String,
      outcome: MassOutcome.fromJson(json['outcome'] as String),
      subject: json['subject'] as String,
      ticketId: json['ticket_id'] as String,
      reason: json['reason'] as String?,
      recipient: json['recipient'] as String?,
    );

Map<String, dynamic> _$MassUpdateItemToJson(MassUpdateItem instance) =>
    <String, dynamic>{
      'number': instance.number,
      'outcome': instance.outcome,
      'reason': ?instance.reason,
      'recipient': ?instance.recipient,
      'subject': instance.subject,
      'ticket_id': instance.ticketId,
    };
