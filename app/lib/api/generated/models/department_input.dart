// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'department_input.g.dart';

@JsonSerializable()
class DepartmentInput {
  const DepartmentInput({
    required this.code,
    required this.name,
    this.active,
    this.memberUserIds,
    this.sortOrder,
  });
  
  factory DepartmentInput.fromJson(Map<String, Object?> json) => _$DepartmentInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// Short unique code, e.g. `ELEC`.
  final String code;

  /// The colleagues who work in this department and may work on its repairs.
  @JsonKey(includeIfNull: false,name: 'member_user_ids')
  final List<String>? memberUserIds;
  final String name;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$DepartmentInputToJson(this);
}
