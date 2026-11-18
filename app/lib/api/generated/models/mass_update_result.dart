// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mass_update_item.dart';

part 'mass_update_result.g.dart';

@JsonSerializable()
class MassUpdateResult {
  const MassUpdateResult({
    required this.dryRun,
    required this.items,
    required this.updated,
  });
  
  factory MassUpdateResult.fromJson(Map<String, Object?> json) => _$MassUpdateResultFromJson(json);
  
  @JsonKey(name: 'dry_run')
  final bool dryRun;
  final List<MassUpdateItem> items;

  /// How many tickets were (or would be) updated.
  final int updated;

  Map<String, Object?> toJson() => _$MassUpdateResultToJson(this);
}
