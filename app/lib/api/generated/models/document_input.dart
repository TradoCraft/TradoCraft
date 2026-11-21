// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'document_input.g.dart';

@JsonSerializable()
class DocumentInput {
  const DocumentInput({
    required this.kind,
    required this.title,
    this.keywords,
    this.productCodes,
  });

  factory DocumentInput.fromJson(Map<String, Object?> json) => _$DocumentInputFromJson(json);

  @JsonKey(includeIfNull: false)
  final List<String>? keywords;
  final String kind;
  @JsonKey(includeIfNull: false,name: 'product_codes')
  final List<String>? productCodes;
  final String title;

  Map<String, Object?> toJson() => _$DocumentInputToJson(this);
}
