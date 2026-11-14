// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation.dart';

part 'configured_import_result.g.dart';

@JsonSerializable()
class ConfiguredImportResult {
  const ConfiguredImportResult({
    required this.action,
    required this.quotation,
  });
  
  factory ConfiguredImportResult.fromJson(Map<String, Object?> json) => _$ConfiguredImportResultFromJson(json);
  
  /// created (new quotation) | updated (the draft was replaced) | revised (a new revision of a.
  /// sent or rejected quotation).
  final String action;

  /// The stored quotation. Its `warnings` start with the import's own (`unknown_product`,.
  /// `price_zone_mismatch`), followed by the usual power grid and product relation warnings.
  final Quotation quotation;

  Map<String, Object?> toJson() => _$ConfiguredImportResultToJson(this);
}
