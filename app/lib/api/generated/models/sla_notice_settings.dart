// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'sla_notice_rule.dart';

part 'sla_notice_settings.g.dart';

@JsonSerializable()
class SlaNoticeSettings {
  const SlaNoticeSettings({required this.rules});

  factory SlaNoticeSettings.fromJson(Map<String, Object?> json) =>
      _$SlaNoticeSettingsFromJson(json);

  /// The most specific rule wins: team and priority, then team, then priority, then neither.
  /// A ticket that matches no rule gets no notice.
  final List<SlaNoticeRule> rules;

  Map<String, Object?> toJson() => _$SlaNoticeSettingsToJson(this);
}
