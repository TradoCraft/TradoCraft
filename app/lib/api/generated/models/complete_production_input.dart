// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_component_actual.dart';
import 'production_output_input.dart';

part 'complete_production_input.g.dart';

@JsonSerializable()
class CompleteProductionInput {
  const CompleteProductionInput({
    required this.output,
    this.components,
    this.note,
  });

  factory CompleteProductionInput.fromJson(Map<String, Object?> json) =>
      _$CompleteProductionInputFromJson(json);

  /// Actual consumption per component; components that are left out use the BOM quantity.
  @JsonKey(includeIfNull: false)
  final List<ProductionComponentActual>? components;
  @JsonKey(includeIfNull: false)
  final String? note;
  final ProductionOutputInput output;

  Map<String, Object?> toJson() => _$CompleteProductionInputToJson(this);
}
