// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'definition_kind.dart';
import 'select_option.dart';

part 'attribute_definition.g.dart';

@JsonSerializable()
class AttributeDefinition {
  const AttributeDefinition({
    required this.active,
    required this.id,
    required this.key,
    required this.kind,
    required this.label,
    required this.options,
    required this.scope,
    required this.sortOrder,
    this.unit,
  });
  
  factory AttributeDefinition.fromJson(Map<String, Object?> json) => _$AttributeDefinitionFromJson(json);
  
  final bool active;
  final String id;
  final String key;
  final DefinitionKind kind;
  final String label;
  final List<SelectOption> options;

  /// `product` or a baseline item type code.
  final String scope;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(includeIfNull: false)
  final String? unit;

  Map<String, Object?> toJson() => _$AttributeDefinitionToJson(this);
}
