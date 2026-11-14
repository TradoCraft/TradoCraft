// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'module_info.g.dart';

/// A module of the catalogue and whether the company has it on.
@JsonSerializable()
class ModuleInfo {
  const ModuleInfo({
    required this.code,
    required this.enabled,
    required this.permissions,
    required this.requires,
  });
  
  factory ModuleInfo.fromJson(Map<String, Object?> json) => _$ModuleInfoFromJson(json);
  
  final String code;
  final bool enabled;

  /// The permissions this module owns.
  final List<String> permissions;

  /// Modules that must stay on for this one.
  final List<String> requires;

  Map<String, Object?> toJson() => _$ModuleInfoToJson(this);
}
