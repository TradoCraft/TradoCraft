// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'photo.g.dart';

@JsonSerializable()
class Photo {
  const Photo({
    required this.caption,
    required this.contentType,
    required this.createdAt,
    required this.filename,
    required this.id,
    required this.sizeBytes,
    required this.uploaderName,
  });
  
  factory Photo.fromJson(Map<String, Object?> json) => _$PhotoFromJson(json);
  
  final String caption;
  @JsonKey(name: 'content_type')
  final String contentType;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String filename;

  /// The id of the file; fetch it from `/repairs/{id}/photos/{photo_id}`.
  final String id;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;
  @JsonKey(name: 'uploader_name')
  final String uploaderName;

  Map<String, Object?> toJson() => _$PhotoToJson(this);
}
