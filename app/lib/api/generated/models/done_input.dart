// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'done_input.g.dart';

@JsonSerializable()
class DoneInput {
  const DoneInput({
    required this.done,
  });
  
  factory DoneInput.fromJson(Map<String, Object?> json) => _$DoneInputFromJson(json);
  
  final bool done;

  Map<String, Object?> toJson() => _$DoneInputToJson(this);
}
