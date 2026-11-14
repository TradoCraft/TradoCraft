// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'opportunity_stage.dart';

part 'stage_input.g.dart';

@JsonSerializable()
class StageInput {
  const StageInput({
    required this.stage,
    this.lostReason,
    this.probability,
  });
  
  factory StageInput.fromJson(Map<String, Object?> json) => _$StageInputFromJson(json);
  
  /// Required when the stage is `lost`.
  @JsonKey(includeIfNull: false,name: 'lost_reason')
  final String? lostReason;

  /// Defaults to the stage's default probability.
  @JsonKey(includeIfNull: false)
  final int? probability;
  final OpportunityStage stage;

  Map<String, Object?> toJson() => _$StageInputToJson(this);
}
