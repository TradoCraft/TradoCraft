// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'cancel_production_input.g.dart';

@JsonSerializable()
class CancelProductionInput {
  const CancelProductionInput({
    required this.reason,
  });
  
  factory CancelProductionInput.fromJson(Map<String, Object?> json) => _$CancelProductionInputFromJson(json);
  
  final String reason;

  Map<String, Object?> toJson() => _$CancelProductionInputToJson(this);
}
