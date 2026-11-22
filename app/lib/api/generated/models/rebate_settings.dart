// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rebate_wording.dart';

part 'rebate_settings.g.dart';

@JsonSerializable()
class RebateSettings {
  const RebateSettings({
    required this.showOnInvoices,
    required this.wording,
  });
  
  factory RebateSettings.fromJson(Map<String, Object?> json) => _$RebateSettingsFromJson(json);
  
  @JsonKey(name: 'show_on_invoices')
  final bool showOnInvoices;
  final List<RebateWording> wording;

  Map<String, Object?> toJson() => _$RebateSettingsToJson(this);
}
