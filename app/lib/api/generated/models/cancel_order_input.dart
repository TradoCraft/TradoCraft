// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'cancel_order_input.g.dart';

@JsonSerializable()
class CancelOrderInput {
  const CancelOrderInput({
    required this.reason,
  });
  
  factory CancelOrderInput.fromJson(Map<String, Object?> json) => _$CancelOrderInputFromJson(json);
  
  final String reason;

  Map<String, Object?> toJson() => _$CancelOrderInputToJson(this);
}
