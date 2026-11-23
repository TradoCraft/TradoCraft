// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_preferences.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserPreferences _$UserPreferencesFromJson(Map<String, dynamic> json) =>
    UserPreferences(
      autosaveMinutes: (json['autosave_minutes'] as num?)?.toInt(),
      shortcuts: (json['shortcuts'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ShortcutBinding.fromJson(e as Map<String, dynamic>)),
      ),
    );

Map<String, dynamic> _$UserPreferencesToJson(UserPreferences instance) =>
    <String, dynamic>{
      'autosave_minutes': ?instance.autosaveMinutes,
      'shortcuts': ?instance.shortcuts,
    };
