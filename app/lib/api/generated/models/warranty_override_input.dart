// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'warranty_override_input.g.dart';

@JsonSerializable()
class WarrantyOverrideInput {
  const WarrantyOverrideInput({
    required this.reason,
  });
  
  factory WarrantyOverrideInput.fromJson(Map<String, Object?> json) => _$WarrantyOverrideInputFromJson(json);
  
  /// Why the warranty is void (misuse). Required.
  final String reason;

  Map<String, Object?> toJson() => _$WarrantyOverrideInputToJson(this);
}
