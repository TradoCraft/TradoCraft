// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reader.g.dart';

/// Somebody who opened the ticket, and when they last did.
@JsonSerializable()
class Reader {
  const Reader({
    required this.lastReadAt,
    required this.userId,
    required this.userName,
  });
  
  factory Reader.fromJson(Map<String, Object?> json) => _$ReaderFromJson(json);
  
  @JsonKey(name: 'last_read_at')
  final DateTime lastReadAt;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$ReaderToJson(this);
}
