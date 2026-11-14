// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'create_delivery_input.g.dart';

@JsonSerializable()
class CreateDeliveryInput {
  const CreateDeliveryInput({
    this.carrier,
    this.closureOverrideReason,
    this.notes,
    this.plannedDate,
  });
  
  factory CreateDeliveryInput.fromJson(Map<String, Object?> json) => _$CreateDeliveryInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? carrier;

  /// Needed to plan on a closed day when the policy is `override`.
  @JsonKey(includeIfNull: false,name: 'closure_override_reason')
  final String? closureOverrideReason;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'planned_date')
  final DateTime? plannedDate;

  Map<String, Object?> toJson() => _$CreateDeliveryInputToJson(this);
}
