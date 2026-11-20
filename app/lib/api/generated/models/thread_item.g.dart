// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreadItem _$ThreadItemFromJson(Map<String, dynamic> json) => ThreadItem(
  body: json['body'] as String,
  changes: json['changes'] as List<dynamic>,
  createdAt: DateTime.parse(json['created_at'] as String),
  editable: json['editable'] as bool,
  files: (json['files'] as List<dynamic>)
      .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
  id: json['id'] as String,
  kind: json['kind'] as String,
  authorId: json['author_id'] as String?,
  authorName: json['author_name'] as String?,
  editedAt: json['edited_at'] == null
      ? null
      : DateTime.parse(json['edited_at'] as String),
);

Map<String, dynamic> _$ThreadItemToJson(ThreadItem instance) =>
    <String, dynamic>{
      'author_id': ?instance.authorId,
      'author_name': ?instance.authorName,
      'body': instance.body,
      'changes': instance.changes,
      'created_at': instance.createdAt.toIso8601String(),
      'editable': instance.editable,
      'edited_at': ?instance.editedAt?.toIso8601String(),
      'files': instance.files,
      'id': instance.id,
      'kind': instance.kind,
    };
