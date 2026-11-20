// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_status_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TicketStatusInput _$TicketStatusInputFromJson(Map<String, dynamic> json) =>
    TicketStatusInput(
      status: json['status'] as String,
      expectedVersion: (json['expected_version'] as num?)?.toInt(),
    );

Map<String, dynamic> _$TicketStatusInputToJson(TicketStatusInput instance) =>
    <String, dynamic>{
      'expected_version': ?instance.expectedVersion,
      'status': instance.status,
    };
