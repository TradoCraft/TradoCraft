// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mass_action.dart';

part 'mass_update_input.g.dart';

@JsonSerializable()
class MassUpdateInput {
  const MassUpdateInput({
    required this.action,
    this.body,
    this.childIds,
    this.dryRun,
    this.status,
    this.subject,
  });
  
  factory MassUpdateInput.fromJson(Map<String, Object?> json) => _$MassUpdateInputFromJson(json);
  
  final MassAction action;

  /// The message (reply or note).
  @JsonKey(includeIfNull: false)
  final String? body;

  /// Only these children; default all children of the bundle.
  @JsonKey(includeIfNull: false,name: 'child_ids')
  final List<String>? childIds;

  /// Run everything and roll it back, so that the result shows what would happen.
  @JsonKey(includeIfNull: false,name: 'dry_run')
  final bool? dryRun;

  /// The new status (`status`); for a reply, the status after sending (default pending_customer).
  @JsonKey(includeIfNull: false)
  final String? status;

  /// Subject of the e-mail (`reply`); default "Re: <subject of the child>".
  @JsonKey(includeIfNull: false)
  final String? subject;

  Map<String, Object?> toJson() => _$MassUpdateInputToJson(this);
}
