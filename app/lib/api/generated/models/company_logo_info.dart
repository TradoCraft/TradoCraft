// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'company_logo_info.g.dart';

/// The stored company logo (without the image itself).
@JsonSerializable()
class CompanyLogoInfo {
  const CompanyLogoInfo({
    required this.contentType,
    required this.sizeBytes,
    required this.updatedAt,
  });
  
  factory CompanyLogoInfo.fromJson(Map<String, Object?> json) => _$CompanyLogoInfoFromJson(json);
  
  /// `image/png`, `image/jpeg` or `image/svg+xml`.
  @JsonKey(name: 'content_type')
  final String contentType;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$CompanyLogoInfoToJson(this);
}
