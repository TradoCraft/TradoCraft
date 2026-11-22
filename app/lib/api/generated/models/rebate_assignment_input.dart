// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_assignment_input.g.dart';

@JsonSerializable()
class RebateAssignmentInput {
  const RebateAssignmentInput({
    this.scheduleName,
  });
  
  factory RebateAssignmentInput.fromJson(Map<String, Object?> json) => _$RebateAssignmentInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'schedule_name')
  final String? scheduleName;

  Map<String, Object?> toJson() => _$RebateAssignmentInputToJson(this);
}
