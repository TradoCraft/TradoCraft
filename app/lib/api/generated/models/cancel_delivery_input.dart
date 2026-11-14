// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'cancel_delivery_input.g.dart';

@JsonSerializable()
class CancelDeliveryInput {
  const CancelDeliveryInput({
    required this.reason,
  });
  
  factory CancelDeliveryInput.fromJson(Map<String, Object?> json) => _$CancelDeliveryInputFromJson(json);
  
  final String reason;

  Map<String, Object?> toJson() => _$CancelDeliveryInputToJson(this);
}
