// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_job_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportJobPage _$ImportJobPageFromJson(Map<String, dynamic> json) =>
    ImportJobPage(
      items: (json['items'] as List<dynamic>)
          .map((e) => ImportJob.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );

Map<String, dynamic> _$ImportJobPageToJson(ImportJobPage instance) =>
    <String, dynamic>{'items': instance.items, 'total': instance.total};
