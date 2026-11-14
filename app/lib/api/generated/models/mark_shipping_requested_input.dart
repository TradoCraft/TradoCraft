// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mark_shipping_requested_input.g.dart';

@JsonSerializable()
class MarkShippingRequestedInput {
  const MarkShippingRequestedInput({
    required this.carrier,
    this.notes,
  });
  
  factory MarkShippingRequestedInput.fromJson(Map<String, Object?> json) => _$MarkShippingRequestedInputFromJson(json);
  
  /// The carrier(s) asked for a price.
  final String carrier;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$MarkShippingRequestedInputToJson(this);
}
