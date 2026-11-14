// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'settings_input.g.dart';

@JsonSerializable()
class SettingsInput {
  const SettingsInput({
    required this.csatEnabled,
    this.defaultTeamId,
  });
  
  factory SettingsInput.fromJson(Map<String, Object?> json) => _$SettingsInputFromJson(json);
  
  @JsonKey(name: 'csat_enabled')
  final bool csatEnabled;
  @JsonKey(includeIfNull: false,name: 'default_team_id')
  final String? defaultTeamId;

  Map<String, Object?> toJson() => _$SettingsInputToJson(this);
}
