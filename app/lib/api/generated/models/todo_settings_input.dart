// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'todo_settings_input.g.dart';

@JsonSerializable()
class TodoSettingsInput {
  const TodoSettingsInput({
    required this.emailReminders,
  });
  
  factory TodoSettingsInput.fromJson(Map<String, Object?> json) => _$TodoSettingsInputFromJson(json);
  
  @JsonKey(name: 'email_reminders')
  final bool emailReminders;

  Map<String, Object?> toJson() => _$TodoSettingsInputToJson(this);
}
