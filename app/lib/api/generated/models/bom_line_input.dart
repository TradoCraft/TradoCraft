// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'bom_line_input.g.dart';

@JsonSerializable()
class BomLineInput {
  const BomLineInput({
    required this.componentProductId,
    required this.quantity,
    this.notes,
    this.scrapPercent,
  });
  
  factory BomLineInput.fromJson(Map<String, Object?> json) => _$BomLineInputFromJson(json);
  
  @JsonKey(name: 'component_product_id')
  final String componentProductId;
  @JsonKey(includeIfNull: false)
  final String? notes;
  final String quantity;
  @JsonKey(includeIfNull: false,name: 'scrap_percent')
  final String? scrapPercent;

  Map<String, Object?> toJson() => _$BomLineInputToJson(this);
}
