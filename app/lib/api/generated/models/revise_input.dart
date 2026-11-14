// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'revision_pricing.dart';

part 'revise_input.g.dart';

@JsonSerializable()
class ReviseInput {
  const ReviseInput({
    required this.pricing,
  });
  
  factory ReviseInput.fromJson(Map<String, Object?> json) => _$ReviseInputFromJson(json);
  
  final RevisionPricing pricing;

  Map<String, Object?> toJson() => _$ReviseInputToJson(this);
}
