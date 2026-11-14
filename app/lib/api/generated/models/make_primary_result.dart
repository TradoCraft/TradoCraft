// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'make_primary_result.g.dart';

/// The company that was made primary.
@JsonSerializable()
class MakePrimaryResult {
  const MakePrimaryResult({required this.companyId, required this.name});

  factory MakePrimaryResult.fromJson(Map<String, Object?> json) =>
      _$MakePrimaryResultFromJson(json);

  /// The new primary company.
  @JsonKey(name: 'company_id')
  final String companyId;

  /// Its name.
  final String name;

  Map<String, Object?> toJson() => _$MakePrimaryResultToJson(this);
}
