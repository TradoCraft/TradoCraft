// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'todo_settings.g.dart';

@JsonSerializable()
class TodoSettings {
  const TodoSettings({required this.emailReminders});

  factory TodoSettings.fromJson(Map<String, Object?> json) =>
      _$TodoSettingsFromJson(json);

  /// Whether a digest mail is sent when items are due or overdue. On by default.
  @JsonKey(name: 'email_reminders')
  final bool emailReminders;

  Map<String, Object?> toJson() => _$TodoSettingsToJson(this);
}
