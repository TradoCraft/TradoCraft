// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_photo.g.dart';

@JsonSerializable()
class JobPhoto {
  const JobPhoto({
    required this.caption,
    required this.createdAt,
    required this.filename,
    required this.id,
    required this.uploaderName,
  });
  
  factory JobPhoto.fromJson(Map<String, Object?> json) => _$JobPhotoFromJson(json);
  
  final String caption;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String filename;

  /// The id of the file; fetch it from `/field/jobs/{id}/photos/{photo_id}`.
  final String id;
  @JsonKey(name: 'uploader_name')
  final String uploaderName;

  Map<String, Object?> toJson() => _$JobPhotoToJson(this);
}
