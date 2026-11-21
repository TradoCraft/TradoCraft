// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'product_media.g.dart';

@JsonSerializable()
class ProductMedia {
  const ProductMedia({
    required this.caption,
    required this.contentType,
    required this.createdAt,
    required this.filename,
    required this.id,
    required this.isDefault,
    required this.kind,
    required this.sizeBytes,
  });
  
  factory ProductMedia.fromJson(Map<String, Object?> json) => _$ProductMediaFromJson(json);
  
  final String caption;
  @JsonKey(name: 'content_type')
  final String contentType;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String filename;

  /// The id of the stored file; also the id in the URLs.
  final String id;

  /// Shown first. Exactly one item of a product has it.
  @JsonKey(name: 'is_default')
  final bool isDefault;

  /// image | video
  final String kind;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;

  Map<String, Object?> toJson() => _$ProductMediaToJson(this);
}
