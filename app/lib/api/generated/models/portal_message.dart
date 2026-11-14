// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'file_info.dart';

part 'portal_message.g.dart';

@JsonSerializable()
class PortalMessage {
  const PortalMessage({
    required this.attachments,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.direction,
    required this.id,
  });
  
  factory PortalMessage.fromJson(Map<String, Object?> json) => _$PortalMessageFromJson(json);
  
  /// Files sent with the message. Files on internal notes are never shown.
  final List<FileInfo> attachments;
  @JsonKey(name: 'author_name')
  final String authorName;
  final String body;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// incoming (from the customer) | outgoing (from us)
  final String direction;
  final String id;

  Map<String, Object?> toJson() => _$PortalMessageToJson(this);
}
