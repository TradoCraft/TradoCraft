// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reply_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReplyInput _$ReplyInputFromJson(Map<String, dynamic> json) => ReplyInput(
  body: json['body'] as String,
  attachmentIds: (json['attachment_ids'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  cc: (json['cc'] as List<dynamic>?)?.map((e) => e as String).toList(),
  libraryPdfs: (json['library_pdfs'] as List<dynamic>?)
      ?.map((e) => LibraryPdf.fromJson(e as Map<String, dynamic>))
      .toList(),
  status: json['status'] as String?,
  subject: json['subject'] as String?,
  to: (json['to'] as List<dynamic>?)?.map((e) => e as String).toList(),
);

Map<String, dynamic> _$ReplyInputToJson(ReplyInput instance) =>
    <String, dynamic>{
      'attachment_ids': ?instance.attachmentIds,
      'body': instance.body,
      'cc': ?instance.cc,
      'library_pdfs': ?instance.libraryPdfs,
      'status': ?instance.status,
      'subject': ?instance.subject,
      'to': ?instance.to,
    };
