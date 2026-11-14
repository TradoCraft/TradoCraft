// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'helpdesk_settings.g.dart';

@JsonSerializable()
class HelpdeskSettings {
  const HelpdeskSettings({
    required this.csatEnabled,
    this.defaultTeamId,
  });
  
  factory HelpdeskSettings.fromJson(Map<String, Object?> json) => _$HelpdeskSettingsFromJson(json);
  
  /// Send a satisfaction survey when a ticket is closed.
  @JsonKey(name: 'csat_enabled')
  final bool csatEnabled;

  /// New tickets from e-mail, the portal and the phone start in this team.
  @JsonKey(includeIfNull: false,name: 'default_team_id')
  final String? defaultTeamId;

  Map<String, Object?> toJson() => _$HelpdeskSettingsToJson(this);
}
