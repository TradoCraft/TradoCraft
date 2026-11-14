// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'modules_input.g.dart';

@JsonSerializable()
class ModulesInput {
  const ModulesInput({
    required this.disabledModules,
  });
  
  factory ModulesInput.fromJson(Map<String, Object?> json) => _$ModulesInputFromJson(json);
  
  /// The modules to switch off for the whole company; all others are on.
  @JsonKey(name: 'disabled_modules')
  final List<String> disabledModules;

  Map<String, Object?> toJson() => _$ModulesInputToJson(this);
}
