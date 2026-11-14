// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delivery_settings.g.dart';

@JsonSerializable()
class DeliverySettings {
  const DeliverySettings({
    required this.closurePolicy,
  });
  
  factory DeliverySettings.fromJson(Map<String, Object?> json) => _$DeliverySettingsFromJson(json);
  
  /// warn: the date is saved and the closure is shown as a warning (default) |.
  /// override: needs `delivery.override_closure` and a reason | block: always refused.
  @JsonKey(name: 'closure_policy')
  final String closurePolicy;

  Map<String, Object?> toJson() => _$DeliverySettingsToJson(this);
}
