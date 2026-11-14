// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'check_status.dart';

part 'reason.g.dart';

@JsonSerializable()
class Reason {
  const Reason({
    required this.check,
    required this.message,
    required this.status,
  });
  
  factory Reason.fromJson(Map<String, Object?> json) => _$ReasonFromJson(json);
  
  /// `power`, `baseline`, `motor` or `rule:<rule name>`.
  final String check;
  final String message;
  final CheckStatus status;

  Map<String, Object?> toJson() => _$ReasonToJson(this);
}
