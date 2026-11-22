// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_wording.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateWording _$RebateWordingFromJson(Map<String, dynamic> json) =>
    RebateWording(
      active: json['active'] as String,
      highest: json['highest'] as String,
      language: json['language'] as String,
    );

Map<String, dynamic> _$RebateWordingToJson(RebateWording instance) =>
    <String, dynamic>{
      'active': instance.active,
      'highest': instance.highest,
      'language': instance.language,
    };
