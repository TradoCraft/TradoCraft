// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Outage _$OutageFromJson(Map<String, dynamic> json) => Outage(
  downFrom: DateTime.parse(json['down_from'] as String),
  downUntil: DateTime.parse(json['down_until'] as String),
);

Map<String, dynamic> _$OutageToJson(Outage instance) => <String, dynamic>{
  'down_from': instance.downFrom.toIso8601String(),
  'down_until': instance.downUntil.toIso8601String(),
};
