// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'model_update.g.dart';

@JsonSerializable()
class ModelUpdate {
  const ModelUpdate({
    required this.active,
    required this.name,
    this.description,
    this.productId,
    this.translations,
  });
  
  factory ModelUpdate.fromJson(Map<String, Object?> json) => _$ModelUpdateFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? description;
  final String name;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false)
  final dynamic translations;

  Map<String, Object?> toJson() => _$ModelUpdateToJson(this);
}
