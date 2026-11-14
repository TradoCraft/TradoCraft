// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_build_component_input.g.dart';

@JsonSerializable()
class ProductionBuildComponentInput {
  const ProductionBuildComponentInput({
    this.autoReleaseSubassemblies,
  });
  
  factory ProductionBuildComponentInput.fromJson(Map<String, Object?> json) => _$ProductionBuildComponentInputFromJson(json);
  
  /// Also release the subassemblies of the new production order that are short.
  @JsonKey(includeIfNull: false,name: 'auto_release_subassemblies')
  final bool? autoReleaseSubassemblies;

  Map<String, Object?> toJson() => _$ProductionBuildComponentInputToJson(this);
}
