// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'shortcut_binding.g.dart';

/// A single keyboard shortcut chord override.
@JsonSerializable()
class ShortcutBinding {
  const ShortcutBinding({
    required this.key,
    required this.mod,
    this.shift,
  });
  
  factory ShortcutBinding.fromJson(Map<String, Object?> json) => _$ShortcutBindingFromJson(json);
  
  /// Logical key name (e.g. `"keyB"`, `"digit1"`, `"enter"`, `"escape"`, `"slash"`).
  final String key;

  /// Modifier group: `"primary"` (Alt on Win/Linux, Ctrl on macOS),.
  /// `"standard"` (Ctrl on Win/Linux, Cmd on macOS), or `"none"`.
  final String mod;

  /// Whether Shift must also be held.
  @JsonKey(includeIfNull: false)
  final bool? shift;

  Map<String, Object?> toJson() => _$ShortcutBindingToJson(this);
}
