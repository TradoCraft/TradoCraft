// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'opportunity_input.g.dart';

@JsonSerializable()
class OpportunityInput {
  const OpportunityInput({
    required this.customerId,
    required this.title,
    this.clearPowerGrid,
    this.expectedClose,
    this.expectedValue,
    this.notes,
    this.ownerUserId,
    this.powerGridId,
    this.probability,
  });
  
  factory OpportunityInput.fromJson(Map<String, Object?> json) => _$OpportunityInputFromJson(json);
  
  /// `true` clears the stored grid on update; combined with `power_grid_id` it is a 422.
  @JsonKey(includeIfNull: false,name: 'clear_power_grid')
  final bool? clearPowerGrid;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false,name: 'expected_close')
  final DateTime? expectedClose;
  @JsonKey(includeIfNull: false,name: 'expected_value')
  final String? expectedValue;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Defaults to the current user.
  @JsonKey(includeIfNull: false,name: 'owner_user_id')
  final String? ownerUserId;

  /// A grid of the customer's country (422 otherwise). On update it is kept when omitted.
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// Defaults to the stage's default probability.
  @JsonKey(includeIfNull: false)
  final int? probability;
  final String title;

  Map<String, Object?> toJson() => _$OpportunityInputToJson(this);
}
