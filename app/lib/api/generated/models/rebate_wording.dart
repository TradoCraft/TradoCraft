// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_wording.g.dart';

@JsonSerializable()
class RebateWording {
  const RebateWording({
    required this.active,
    required this.highest,
    required this.language,
  });
  
  factory RebateWording.fromJson(Map<String, Object?> json) => _$RebateWordingFromJson(json);
  
  final String active;
  final String highest;
  final String language;

  Map<String, Object?> toJson() => _$RebateWordingToJson(this);
}
