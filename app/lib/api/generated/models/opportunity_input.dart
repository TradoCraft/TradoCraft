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
    this.expectedClose,
    this.expectedValue,
    this.notes,
    this.ownerUserId,
    this.probability,
  });
  
  factory OpportunityInput.fromJson(Map<String, Object?> json) => _$OpportunityInputFromJson(json);
  
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

  /// Defaults to the stage's default probability.
  @JsonKey(includeIfNull: false)
  final int? probability;
  final String title;

  Map<String, Object?> toJson() => _$OpportunityInputToJson(this);
}
