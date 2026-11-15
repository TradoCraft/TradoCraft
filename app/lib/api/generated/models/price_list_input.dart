// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'price_list_settings.dart';

part 'price_list_input.g.dart';

@JsonSerializable()
class PriceListInput {
  const PriceListInput({
    required this.code,
    required this.name,
    required this.validFrom,
    this.settings,
  });
  
  factory PriceListInput.fromJson(Map<String, Object?> json) => _$PriceListInputFromJson(json);
  
  final String code;
  final String name;
  @JsonKey(includeIfNull: false)
  final PriceListSettings? settings;

  /// Accepts `2027-01-01` and the datetime string the Dart client sends.
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;

  Map<String, Object?> toJson() => _$PriceListInputToJson(this);
}
