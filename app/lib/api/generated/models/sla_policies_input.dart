// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'sla_policy.dart';

part 'sla_policies_input.g.dart';

@JsonSerializable()
class SlaPoliciesInput {
  const SlaPoliciesInput({
    required this.policies,
  });
  
  factory SlaPoliciesInput.fromJson(Map<String, Object?> json) => _$SlaPoliciesInputFromJson(json);
  
  final List<SlaPolicy> policies;

  Map<String, Object?> toJson() => _$SlaPoliciesInputToJson(this);
}
