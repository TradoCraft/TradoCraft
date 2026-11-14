// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'member.dart';

part 'department.g.dart';

@JsonSerializable()
class Department {
  const Department({
    required this.active,
    required this.code,
    required this.id,
    required this.members,
    required this.name,
    required this.openRepairs,
    required this.sortOrder,
  });
  
  factory Department.fromJson(Map<String, Object?> json) => _$DepartmentFromJson(json);
  
  final bool active;
  final String code;
  final String id;
  final List<Member> members;
  final String name;

  /// Repairs currently in this department (routed, in progress or waiting).
  @JsonKey(name: 'open_repairs')
  final int openRepairs;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$DepartmentToJson(this);
}
