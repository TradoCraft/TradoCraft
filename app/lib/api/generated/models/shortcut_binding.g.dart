// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shortcut_binding.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShortcutBinding _$ShortcutBindingFromJson(Map<String, dynamic> json) =>
    ShortcutBinding(
      key: json['key'] as String,
      mod: json['mod'] as String,
      shift: json['shift'] as bool?,
    );

Map<String, dynamic> _$ShortcutBindingToJson(ShortcutBinding instance) =>
    <String, dynamic>{
      'key': instance.key,
      'mod': instance.mod,
      'shift': ?instance.shift,
    };
