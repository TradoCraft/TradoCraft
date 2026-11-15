// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_logo_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompanyLogoInfo _$CompanyLogoInfoFromJson(Map<String, dynamic> json) =>
    CompanyLogoInfo(
      contentType: json['content_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$CompanyLogoInfoToJson(CompanyLogoInfo instance) =>
    <String, dynamic>{
      'content_type': instance.contentType,
      'size_bytes': instance.sizeBytes,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
