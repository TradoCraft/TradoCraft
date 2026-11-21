// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_media.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductMedia _$ProductMediaFromJson(Map<String, dynamic> json) => ProductMedia(
  caption: json['caption'] as String,
  contentType: json['content_type'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  filename: json['filename'] as String,
  id: json['id'] as String,
  isDefault: json['is_default'] as bool,
  kind: json['kind'] as String,
  sizeBytes: (json['size_bytes'] as num).toInt(),
);

Map<String, dynamic> _$ProductMediaToJson(ProductMedia instance) =>
    <String, dynamic>{
      'caption': instance.caption,
      'content_type': instance.contentType,
      'created_at': instance.createdAt.toIso8601String(),
      'filename': instance.filename,
      'id': instance.id,
      'is_default': instance.isDefault,
      'kind': instance.kind,
      'size_bytes': instance.sizeBytes,
    };
