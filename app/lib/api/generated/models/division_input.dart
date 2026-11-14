// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'division_input.g.dart';

/// Input to create or change a division.
@JsonSerializable()
class DivisionInput {
  const DivisionInput({
    required this.code,
    required this.name,
    this.active,
    this.memberUserIds,
    this.sortOrder,
  });
  
  factory DivisionInput.fromJson(Map<String, Object?> json) => _$DivisionInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  final String code;

  /// When present, replaces all members of the division (active users of the company only);.
  /// when absent, the members stay as they are.
  @JsonKey(includeIfNull: false,name: 'member_user_ids')
  final List<String>? memberUserIds;
  final String name;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$DivisionInputToJson(this);
}
