// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'opportunity_stage.dart';

part 'pipeline_stage.g.dart';

@JsonSerializable()
class PipelineStage {
  const PipelineStage({
    required this.count,
    required this.stage,
    required this.totalValue,
    required this.weightedValue,
  });
  
  factory PipelineStage.fromJson(Map<String, Object?> json) => _$PipelineStageFromJson(json);
  
  final int count;
  final OpportunityStage stage;
  @JsonKey(name: 'total_value')
  final String totalValue;

  /// Sum of expected value × probability.
  @JsonKey(name: 'weighted_value')
  final String weightedValue;

  Map<String, Object?> toJson() => _$PipelineStageToJson(this);
}
