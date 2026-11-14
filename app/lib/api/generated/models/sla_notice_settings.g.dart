// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sla_notice_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SlaNoticeSettings _$SlaNoticeSettingsFromJson(Map<String, dynamic> json) =>
    SlaNoticeSettings(
      rules: (json['rules'] as List<dynamic>)
          .map((e) => SlaNoticeRule.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SlaNoticeSettingsToJson(SlaNoticeSettings instance) =>
    <String, dynamic>{'rules': instance.rules};
