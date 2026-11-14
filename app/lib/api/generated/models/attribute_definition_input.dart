// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'definition_kind.dart';
import 'select_option.dart';

part 'attribute_definition_input.g.dart';

@JsonSerializable()
class AttributeDefinitionInput {
  const AttributeDefinitionInput({
    required this.key,
    required this.kind,
    required this.label,
    this.active,
    this.options,
    this.scope,
    this.sortOrder,
    this.unit,
  });
  
  factory AttributeDefinitionInput.fromJson(Map<String, Object?> json) => _$AttributeDefinitionInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// snake_case: lowercase letter first, then lowercase letters, digits and `_`.
  final String key;
  final DefinitionKind kind;
  final String label;

  /// Required (at least one) for `select`, forbidden for the other kinds.
  @JsonKey(includeIfNull: false)
  final List<SelectOption>? options;
  @JsonKey(includeIfNull: false)
  final String? scope;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;
  @JsonKey(includeIfNull: false)
  final String? unit;

  Map<String, Object?> toJson() => _$AttributeDefinitionInputToJson(this);
}
