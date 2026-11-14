// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'favorite_remark.g.dart';

/// The customer remark of an item in one language.
@JsonSerializable()
class FavoriteRemark {
  const FavoriteRemark({
    required this.language,
    required this.text,
  });
  
  factory FavoriteRemark.fromJson(Map<String, Object?> json) => _$FavoriteRemarkFromJson(json);
  
  /// nl | fr | en | de | es
  final String language;
  final String text;

  Map<String, Object?> toJson() => _$FavoriteRemarkToJson(this);
}
