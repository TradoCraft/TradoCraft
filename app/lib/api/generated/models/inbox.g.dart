// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Inbox _$InboxFromJson(Map<String, dynamic> json) => Inbox(
  activities: (json['activities'] as List<dynamic>)
      .map((e) => InboxActivity.fromJson(e as Map<String, dynamic>))
      .toList(),
  unread: (json['unread'] as List<dynamic>)
      .map((e) => InboxRecord.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$InboxToJson(Inbox instance) => <String, dynamic>{
  'activities': instance.activities,
  'unread': instance.unread,
};
