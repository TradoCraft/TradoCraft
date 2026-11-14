// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_definition.dart';

part 'report_run_request.g.dart';

@JsonSerializable()
class ReportRunRequest {
  const ReportRunRequest({
    required this.definition,
    this.asOf,
    this.limit,
    this.offset,
  });
  
  factory ReportRunRequest.fromJson(Map<String, Object?> json) => _$ReportRunRequestFromJson(json);
  
  /// Resolve relative dates as of this day (`YYYY-MM-DD`), see [`resolve_as_of`]. Default today.
  @JsonKey(includeIfNull: false,name: 'as_of')
  final String? asOf;
  final ReportDefinition definition;
  @JsonKey(includeIfNull: false)
  final int? limit;
  @JsonKey(includeIfNull: false)
  final int? offset;

  Map<String, Object?> toJson() => _$ReportRunRequestToJson(this);
}
