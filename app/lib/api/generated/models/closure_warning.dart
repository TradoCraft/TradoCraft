// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'closure.dart';

part 'closure_warning.g.dart';

/// The customer is closed on the planned date.
@JsonSerializable()
class ClosureWarning {
  const ClosureWarning({
    required this.closure,
    required this.nextOpenDay,
  });
  
  factory ClosureWarning.fromJson(Map<String, Object?> json) => _$ClosureWarningFromJson(json);
  
  /// The closure that covers the planned date.
  final Closure closure;

  /// The first day after the closure(s).
  @JsonKey(name: 'next_open_day')
  final DateTime nextOpenDay;

  Map<String, Object?> toJson() => _$ClosureWarningToJson(this);
}
