// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reason.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reason _$ReasonFromJson(Map<String, dynamic> json) => Reason(
  check: json['check'] as String,
  message: json['message'] as String,
  status: CheckStatus.fromJson(json['status'] as String),
);

Map<String, dynamic> _$ReasonToJson(Reason instance) => <String, dynamic>{
  'check': instance.check,
  'message': instance.message,
  'status': instance.status,
};
