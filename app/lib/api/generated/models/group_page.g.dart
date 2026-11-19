// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupPage _$GroupPageFromJson(Map<String, dynamic> json) => GroupPage(
  groupBy: json['group_by'] as String,
  groups: (json['groups'] as List<dynamic>)
      .map((e) => GroupCount.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$GroupPageToJson(GroupPage instance) => <String, dynamic>{
  'group_by': instance.groupBy,
  'groups': instance.groups,
};
