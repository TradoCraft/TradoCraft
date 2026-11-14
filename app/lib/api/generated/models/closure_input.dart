// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'closure_input.g.dart';

@JsonSerializable()
class ClosureInput {
  const ClosureInput({
    required this.startsOn,
    this.endsOn,
    this.kind,
    this.notes,
  });
  
  factory ClosureInput.fromJson(Map<String, Object?> json) => _$ClosureInputFromJson(json);
  
  /// Last closed day; defaults to `starts_on` (a single day).
  @JsonKey(includeIfNull: false,name: 'ends_on')
  final DateTime? endsOn;

  /// holiday | collective_leave | inventory | works | other (default other)
  @JsonKey(includeIfNull: false)
  final String? kind;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(name: 'starts_on')
  final DateTime startsOn;

  Map<String, Object?> toJson() => _$ClosureInputToJson(this);
}
