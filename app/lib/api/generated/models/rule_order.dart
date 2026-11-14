// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rule_order.g.dart';

@JsonSerializable()
class RuleOrder {
  const RuleOrder({
    required this.ids,
  });
  
  factory RuleOrder.fromJson(Map<String, Object?> json) => _$RuleOrderFromJson(json);
  
  /// Every rule of the company, in the wanted order.
  final List<String> ids;

  Map<String, Object?> toJson() => _$RuleOrderToJson(this);
}
