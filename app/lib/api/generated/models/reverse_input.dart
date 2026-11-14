// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reverse_input.g.dart';

@JsonSerializable()
class ReverseInput {
  const ReverseInput({
    required this.id,
    this.force,
    this.note,
  });
  
  factory ReverseInput.fromJson(Map<String, Object?> json) => _$ReverseInputFromJson(json);
  
  /// Reverse even when that takes stock that is reserved for orders (they then lack stock).
  /// Inventory administrators only, which this endpoint already requires.
  @JsonKey(includeIfNull: false)
  final bool? force;

  /// Chosen by the client for the reversal move.
  final String id;
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$ReverseInputToJson(this);
}
