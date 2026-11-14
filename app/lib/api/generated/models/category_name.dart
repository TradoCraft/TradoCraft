// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'category_name.g.dart';

@JsonSerializable()
class CategoryName {
  const CategoryName({
    required this.language,
    required this.name,
  });
  
  factory CategoryName.fromJson(Map<String, Object?> json) => _$CategoryNameFromJson(json);
  
  final String language;
  final String name;

  Map<String, Object?> toJson() => _$CategoryNameToJson(this);
}
