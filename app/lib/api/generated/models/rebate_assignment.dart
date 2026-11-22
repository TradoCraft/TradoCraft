// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_assignment.g.dart';

@JsonSerializable()
class RebateAssignment {
  const RebateAssignment({
    required this.customerId,
    this.scheduleName,
  });
  
  factory RebateAssignment.fromJson(Map<String, Object?> json) => _$RebateAssignmentFromJson(json);
  
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false,name: 'schedule_name')
  final String? scheduleName;

  Map<String, Object?> toJson() => _$RebateAssignmentToJson(this);
}
