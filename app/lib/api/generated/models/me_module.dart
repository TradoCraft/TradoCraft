// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'me_module.g.dart';

@JsonSerializable()
class MeModule {
  const MeModule({
    required this.code,
    required this.enabled,
  });
  
  factory MeModule.fromJson(Map<String, Object?> json) => _$MeModuleFromJson(json);
  
  final String code;
  final bool enabled;

  Map<String, Object?> toJson() => _$MeModuleToJson(this);
}
