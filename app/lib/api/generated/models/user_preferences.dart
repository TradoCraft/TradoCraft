// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'shortcut_binding.dart';

part 'user_preferences.g.dart';

/// Per-user preferences stored across sessions and devices.
@JsonSerializable()
class UserPreferences {
  const UserPreferences({
    this.shortcuts,
  });
  
  factory UserPreferences.fromJson(Map<String, Object?> json) => _$UserPreferencesFromJson(json);
  
  /// Custom shortcut bindings keyed by `ShortcutAction.name`.
  @JsonKey(includeIfNull: false)
  final Map<String, ShortcutBinding>? shortcuts;

  Map<String, Object?> toJson() => _$UserPreferencesToJson(this);
}
