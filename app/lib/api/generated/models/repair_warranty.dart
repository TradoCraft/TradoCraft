// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'serial_unit_ref.dart';

part 'repair_warranty.g.dart';

@JsonSerializable()
class RepairWarranty {
  const RepairWarranty({
    required this.arrived,
    required this.auto,
    required this.candidates,
    required this.comparedWith,
    required this.overridden,
    required this.overrideReason,
    required this.repairId,
    required this.warranty,
    this.autoAt,
    this.autoUntil,
    this.overrideAt,
    this.overrideBy,
    this.overrideByName,
    this.serialUnit,
  });
  
  factory RepairWarranty.fromJson(Map<String, Object?> json) => _$RepairWarrantyFromJson(json);
  
  /// False while the repair has not been received yet; the result is provisional then.
  final bool arrived;

  /// The automatic result: unknown | in_warranty | out_of_warranty
  final String auto;
  @JsonKey(includeIfNull: false,name: 'auto_at')
  final DateTime? autoAt;

  /// The `warranty_until` the automatic result was based on.
  @JsonKey(includeIfNull: false,name: 'auto_until')
  final DateTime? autoUntil;

  /// Several serial units match the serial number: the intake person picks one.
  final List<SerialUnitRef> candidates;

  /// The date the lookup compared with: when the product arrived, or today while it has not.
  @JsonKey(name: 'compared_with')
  final DateTime comparedWith;
  final bool overridden;
  @JsonKey(includeIfNull: false,name: 'override_at')
  final DateTime? overrideAt;
  @JsonKey(includeIfNull: false,name: 'override_by')
  final String? overrideBy;
  @JsonKey(includeIfNull: false,name: 'override_by_name')
  final String? overrideByName;
  @JsonKey(name: 'override_reason')
  final String overrideReason;
  @JsonKey(name: 'repair_id')
  final String repairId;
  @JsonKey(includeIfNull: false,name: 'serial_unit')
  final SerialUnitRef? serialUnit;

  /// The final status: unknown | in_warranty | out_of_warranty | void
  final String warranty;

  Map<String, Object?> toJson() => _$RepairWarrantyToJson(this);
}
