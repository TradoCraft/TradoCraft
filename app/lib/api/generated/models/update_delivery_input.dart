// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'delivery_line_input.dart';
import 'delivery_ship_to_input.dart';

part 'update_delivery_input.g.dart';

@JsonSerializable()
class UpdateDeliveryInput {
  const UpdateDeliveryInput({
    this.carrier,
    this.closureOverrideReason,
    this.expectedUpdatedAt,
    this.lines,
    this.notes,
    this.plannedDate,
    this.shipTo,
    this.trackingNumber,
  });
  
  factory UpdateDeliveryInput.fromJson(Map<String, Object?> json) => _$UpdateDeliveryInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? carrier;

  /// Needed to plan on a closed day when the policy is `override`.
  @JsonKey(includeIfNull: false,name: 'closure_override_reason')
  final String? closureOverrideReason;

  /// The `updated_at` of the note as it was loaded; refused (409) when the note changed since.
  @JsonKey(includeIfNull: false,name: 'expected_updated_at')
  final DateTime? expectedUpdatedAt;

  /// Replaces all lines; omitted keeps them.
  @JsonKey(includeIfNull: false)
  final List<DeliveryLineInput>? lines;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'planned_date')
  final DateTime? plannedDate;

  /// Replaces the ship-to address; omitted keeps it.
  @JsonKey(includeIfNull: false,name: 'ship_to')
  final DeliveryShipToInput? shipTo;
  @JsonKey(includeIfNull: false,name: 'tracking_number')
  final String? trackingNumber;

  Map<String, Object?> toJson() => _$UpdateDeliveryInputToJson(this);
}
