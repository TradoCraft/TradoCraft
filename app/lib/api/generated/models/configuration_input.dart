// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'inputs.dart';

part 'configuration_input.g.dart';

@JsonSerializable()
class ConfigurationInput {
  const ConfigurationInput({
    this.customerId,
    this.inputs,
    this.modelId,
    this.name,
    this.revisionId,
  });
  
  factory ConfigurationInput.fromJson(Map<String, Object?> json) => _$ConfigurationInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false)
  final Inputs? inputs;

  /// The model; the configuration is made with its active revision ...
  @JsonKey(includeIfNull: false,name: 'model_id')
  final String? modelId;
  @JsonKey(includeIfNull: false)
  final String? name;

  /// ... or this active revision. On an update: moves the configuration to this (active).
  /// revision; left out, it stays on its own.
  @JsonKey(includeIfNull: false,name: 'revision_id')
  final String? revisionId;

  Map<String, Object?> toJson() => _$ConfigurationInputToJson(this);
}
