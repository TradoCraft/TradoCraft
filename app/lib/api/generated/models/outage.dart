// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'outage.g.dart';

/// A period without any beat.
@JsonSerializable()
class Outage {
  const Outage({
    required this.downFrom,
    required this.downUntil,
  });
  
  factory Outage.fromJson(Map<String, Object?> json) => _$OutageFromJson(json);
  
  @JsonKey(name: 'down_from')
  final DateTime downFrom;
  @JsonKey(name: 'down_until')
  final DateTime downUntil;

  Map<String, Object?> toJson() => _$OutageToJson(this);
}
