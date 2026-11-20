// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreadPage _$ThreadPageFromJson(Map<String, dynamic> json) => ThreadPage(
  items: (json['items'] as List<dynamic>)
      .map((e) => ThreadItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  nextBeforeId: json['next_before_id'] as String?,
);

Map<String, dynamic> _$ThreadPageToJson(ThreadPage instance) =>
    <String, dynamic>{
      'items': instance.items,
      'next_before_id': ?instance.nextBeforeId,
    };
