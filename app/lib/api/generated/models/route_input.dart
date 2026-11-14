// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'route_input.g.dart';

@JsonSerializable()
class RouteInput {
  const RouteInput({
    required this.departmentId,
    this.assignedUserId,
    this.note,
  });
  
  factory RouteInput.fromJson(Map<String, Object?> json) => _$RouteInputFromJson(json);
  
  /// A member of the department who should do it; leave empty to let the department pick it up.
  @JsonKey(includeIfNull: false,name: 'assigned_user_id')
  final String? assignedUserId;
  @JsonKey(name: 'department_id')
  final String departmentId;
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$RouteInputToJson(this);
}
