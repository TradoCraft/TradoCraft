// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'division_member.dart';

part 'division.g.dart';

/// A production division with its members.
@JsonSerializable()
class Division {
  const Division({
    required this.active,
    required this.code,
    required this.id,
    required this.isMember,
    required this.members,
    required this.name,
    required this.openOrders,
    required this.sortOrder,
  });
  
  factory Division.fromJson(Map<String, Object?> json) => _$DivisionFromJson(json);
  
  final bool active;
  final String code;
  final String id;

  /// Whether the calling user is a member of this division.
  @JsonKey(name: 'is_member')
  final bool isMember;

  /// The users who work in this division, by name.
  final List<DivisionMember> members;
  final String name;

  /// Production orders in this division that are not finished.
  @JsonKey(name: 'open_orders')
  final int openOrders;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$DivisionToJson(this);
}
