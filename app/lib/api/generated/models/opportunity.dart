// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'opportunity_stage.dart';

part 'opportunity.g.dart';

@JsonSerializable()
class Opportunity {
  const Opportunity({
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.expectedValue,
    required this.id,
    required this.notes,
    required this.number,
    required this.ownerName,
    required this.ownerUserId,
    required this.probability,
    required this.stage,
    required this.title,
    required this.updatedAt,
    this.closedAt,
    this.expectedClose,
    this.lostReason,
  });
  
  factory Opportunity.fromJson(Map<String, Object?> json) => _$OpportunityFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'closed_at')
  final DateTime? closedAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false,name: 'expected_close')
  final DateTime? expectedClose;
  @JsonKey(name: 'expected_value')
  final String expectedValue;
  final String id;
  @JsonKey(includeIfNull: false,name: 'lost_reason')
  final String? lostReason;
  final String notes;
  final String number;
  @JsonKey(name: 'owner_name')
  final String ownerName;
  @JsonKey(name: 'owner_user_id')
  final String ownerUserId;
  final int probability;
  final OpportunityStage stage;
  final String title;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$OpportunityToJson(this);
}
