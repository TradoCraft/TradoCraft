// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unsubscribe_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UnsubscribeInfo _$UnsubscribeInfoFromJson(Map<String, dynamic> json) =>
    UnsubscribeInfo(
      companyName: json['company_name'] as String,
      email: json['email'] as String,
      language: json['language'] as String,
      unsubscribed: json['unsubscribed'] as bool,
    );

Map<String, dynamic> _$UnsubscribeInfoToJson(UnsubscribeInfo instance) =>
    <String, dynamic>{
      'company_name': instance.companyName,
      'email': instance.email,
      'language': instance.language,
      'unsubscribed': instance.unsubscribed,
    };
