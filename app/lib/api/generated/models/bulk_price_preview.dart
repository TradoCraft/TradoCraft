// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'bulk_price_line.dart';

part 'bulk_price_preview.g.dart';

@JsonSerializable()
class BulkPricePreview {
  const BulkPricePreview({
    required this.applied,
    required this.conflicts,
    required this.lines,
    required this.validFrom,
    required this.withoutPrice,
  });
  
  factory BulkPricePreview.fromJson(Map<String, Object?> json) => _$BulkPricePreviewFromJson(json);
  
  /// Number of prices created (0 for a preview).
  final int applied;
  final int conflicts;
  final List<BulkPriceLine> lines;
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;

  /// Product/zone combinations without any price to start from (left unchanged).
  @JsonKey(name: 'without_price')
  final int withoutPrice;

  Map<String, Object?> toJson() => _$BulkPricePreviewToJson(this);
}
