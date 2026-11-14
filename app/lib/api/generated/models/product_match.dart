// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'match_status.dart';
import 'reason.dart';

part 'product_match.g.dart';

@JsonSerializable()
class ProductMatch {
  const ProductMatch({
    required this.code,
    required this.id,
    required this.name,
    required this.reasons,
    required this.status,
    this.familyCode,
    this.familyId,
  });
  
  factory ProductMatch.fromJson(Map<String, Object?> json) => _$ProductMatchFromJson(json);
  
  final String code;
  @JsonKey(includeIfNull: false,name: 'family_code')
  final String? familyCode;
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  final String id;
  final String name;
  final List<Reason> reasons;
  final MatchStatus status;

  Map<String, Object?> toJson() => _$ProductMatchToJson(this);
}
