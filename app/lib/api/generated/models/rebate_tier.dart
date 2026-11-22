// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_tier.g.dart';

@JsonSerializable()
class RebateTier {
  const RebateTier({
    required this.rate,
    required this.threshold,
  });
  
  factory RebateTier.fromJson(Map<String, Object?> json) => _$RebateTierFromJson(json);
  
  final String rate;
  final String threshold;

  Map<String, Object?> toJson() => _$RebateTierToJson(this);
}
