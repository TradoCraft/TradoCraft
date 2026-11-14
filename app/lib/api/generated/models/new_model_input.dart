// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_model_input.g.dart';

@JsonSerializable()
class NewModelInput {
  const NewModelInput({
    required this.code,
    required this.name,
    this.definition,
    this.description,
    this.productId,
    this.translations,
  });
  
  factory NewModelInput.fromJson(Map<String, Object?> json) => _$NewModelInputFromJson(json);
  
  final String code;

  /// The first draft's definition; an empty one when left out.
  @JsonKey(includeIfNull: false)
  final dynamic definition;
  @JsonKey(includeIfNull: false)
  final String? description;
  final String name;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false)
  final dynamic translations;

  Map<String, Object?> toJson() => _$NewModelInputToJson(this);
}
