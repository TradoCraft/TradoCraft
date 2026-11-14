// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'trace_source.dart';

part 'trace.g.dart';

@JsonSerializable()
class Trace {
  const Trace({
    required this.rule,
    required this.rulePath,
    required this.sources,
  });
  
  factory Trace.fromJson(Map<String, Object?> json) => _$TraceFromJson(json);
  
  final String rule;

  /// JSON path of the rule in the definition.
  @JsonKey(name: 'rule_path')
  final String rulePath;
  final List<TraceSource> sources;

  Map<String, Object?> toJson() => _$TraceToJson(this);
}
