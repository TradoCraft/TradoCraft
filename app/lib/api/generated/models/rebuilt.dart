// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebuilt.g.dart';

@JsonSerializable()
class Rebuilt {
  const Rebuilt({
    required this.balanceRows,
  });
  
  factory Rebuilt.fromJson(Map<String, Object?> json) => _$RebuiltFromJson(json);
  
  @JsonKey(name: 'balance_rows')
  final int balanceRows;

  Map<String, Object?> toJson() => _$RebuiltToJson(this);
}
