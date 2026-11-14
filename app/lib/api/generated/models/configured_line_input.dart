// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'configured_line_input.dart';
import 'percent_base.dart';

part 'configured_line_input.g.dart';

/// One line of a configuration: a product by code, with its options or sub-lines as `children`.
@JsonSerializable()
class ConfiguredLineInput {
  const ConfiguredLineInput({
    required this.code,
    required this.quantity,
    this.children,
    this.comment,
    this.description,
    this.percentBase,
    this.percentOfParent,
    this.section,
    this.unitPrice,
  });
  
  factory ConfiguredLineInput.fromJson(Map<String, Object?> json) => _$ConfiguredLineInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final List<ConfiguredLineInput>? children;

  /// Product code, matched exactly against active products.
  final String code;

  /// Extra text printed below the line.
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// Overrides the product name on the document.
  @JsonKey(includeIfNull: false)
  final String? description;

  /// Defaults to `parent_list_unit_price`.
  @JsonKey(includeIfNull: false,name: 'percent_base')
  final PercentBase? percentBase;

  /// Prices the line as this percentage of its parent line's unit price (only on children).
  @JsonKey(includeIfNull: false,name: 'percent_of_parent')
  final String? percentOfParent;
  final String quantity;

  /// Heading on the document; children without one are shown under their parent's.
  @JsonKey(includeIfNull: false)
  final String? section;

  /// Confirmed unit price for an indicative product (as on `QuotationLineInput`).
  @JsonKey(includeIfNull: false,name: 'unit_price')
  final String? unitPrice;

  Map<String, Object?> toJson() => _$ConfiguredLineInputToJson(this);
}
