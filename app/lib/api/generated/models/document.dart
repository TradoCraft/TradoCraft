// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'document.g.dart';

@JsonSerializable()
class Document {
  const Document({
    required this.id,
    required this.keywords,
    required this.kind,
    required this.productCodes,
    required this.title,
  });
  
  factory Document.fromJson(Map<String, Object?> json) => _$DocumentFromJson(json);
  
  final String id;
  final List<String> keywords;
  final String kind;
  @JsonKey(name: 'product_codes')
  final List<String> productCodes;
  final String title;

  Map<String, Object?> toJson() => _$DocumentToJson(this);
}
