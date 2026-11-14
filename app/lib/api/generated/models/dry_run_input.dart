// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'dry_run_input.g.dart';

@JsonSerializable()
class DryRunInput {
  const DryRunInput({
    required this.ticketId,
    required this.trigger,
  });
  
  factory DryRunInput.fromJson(Map<String, Object?> json) => _$DryRunInputFromJson(json);
  
  @JsonKey(name: 'ticket_id')
  final String ticketId;

  /// created | updated | customer_replied
  final String trigger;

  Map<String, Object?> toJson() => _$DryRunInputToJson(this);
}
