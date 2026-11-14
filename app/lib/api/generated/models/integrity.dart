// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'balance_difference.dart';

part 'integrity.g.dart';

@JsonSerializable()
class Integrity {
  const Integrity({
    required this.differences,
    required this.ok,
  });
  
  factory Integrity.fromJson(Map<String, Object?> json) => _$IntegrityFromJson(json);
  
  final List<BalanceDifference> differences;

  /// The balance table equals the sum of the ledger.
  final bool ok;

  Map<String, Object?> toJson() => _$IntegrityToJson(this);
}
