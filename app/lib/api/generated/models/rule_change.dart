// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rule_change.g.dart';

/// A change a rule made (or, in a dry run, would make).
@JsonSerializable()
class RuleChange {
  const RuleChange({
    required this.kind,
    this.from,
    this.to,
  });
  
  factory RuleChange.fromJson(Map<String, Object?> json) => _$RuleChangeFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? from;
  final String kind;
  @JsonKey(includeIfNull: false)
  final String? to;

  Map<String, Object?> toJson() => _$RuleChangeToJson(this);
}
