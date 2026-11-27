// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mailing_opt_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailingOptOut _$MailingOptOutFromJson(Map<String, dynamic> json) =>
    MailingOptOut(
      email: json['email'] as String,
      optedOutAt: DateTime.parse(json['opted_out_at'] as String),
      source: json['source'] as String,
      recordedBy: json['recorded_by'] as String?,
      recordedByName: json['recorded_by_name'] as String?,
    );

Map<String, dynamic> _$MailingOptOutToJson(MailingOptOut instance) =>
    <String, dynamic>{
      'email': instance.email,
      'opted_out_at': instance.optedOutAt.toIso8601String(),
      'recorded_by': ?instance.recordedBy,
      'recorded_by_name': ?instance.recordedByName,
      'source': instance.source,
    };
