// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'technician.g.dart';

@JsonSerializable()
class Technician {
  const Technician({
    required this.displayName,
    required this.userId,
  });
  
  factory Technician.fromJson(Map<String, Object?> json) => _$TechnicianFromJson(json);
  
  @JsonKey(name: 'display_name')
  final String displayName;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$TechnicianToJson(this);
}
