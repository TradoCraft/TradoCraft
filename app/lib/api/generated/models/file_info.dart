// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'file_info.g.dart';

@JsonSerializable()
class FileInfo {
  const FileInfo({
    required this.contentType,
    required this.createdAt,
    required this.filename,
    required this.id,
    required this.sizeBytes,
    required this.uploaderName,
  });
  
  factory FileInfo.fromJson(Map<String, Object?> json) => _$FileInfoFromJson(json);
  
  /// image/jpeg | image/png | image/webp | application/pdf
  @JsonKey(name: 'content_type')
  final String contentType;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String filename;
  final String id;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;
  @JsonKey(name: 'uploader_name')
  final String uploaderName;

  Map<String, Object?> toJson() => _$FileInfoToJson(this);
}
