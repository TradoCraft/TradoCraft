// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chatter_note_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatterNoteInput _$ChatterNoteInputFromJson(Map<String, dynamic> json) =>
    ChatterNoteInput(
      body: json['body'] as String,
      clientId: json['client_id'] as String?,
      fileIds: (json['file_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ChatterNoteInputToJson(ChatterNoteInput instance) =>
    <String, dynamic>{
      'body': instance.body,
      'client_id': ?instance.clientId,
      'file_ids': ?instance.fileIds,
    };
