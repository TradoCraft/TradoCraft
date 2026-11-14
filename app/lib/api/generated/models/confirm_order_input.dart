// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'confirm_order_input.g.dart';

@JsonSerializable()
class ConfirmOrderInput {
  const ConfirmOrderInput({
    this.note,
    this.revision,
  });
  
  factory ConfirmOrderInput.fromJson(Map<String, Object?> json) => _$ConfirmOrderInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? note;

  /// The revision being confirmed; refused when it is not the latest. Defaults to the latest.
  @JsonKey(includeIfNull: false)
  final int? revision;

  Map<String, Object?> toJson() => _$ConfirmOrderInputToJson(this);
}
