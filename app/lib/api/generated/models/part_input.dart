// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'part_input.g.dart';

@JsonSerializable()
class PartInput {
  const PartInput({
    required this.quantity,
    this.billable,
    this.description,
    this.id,
    this.productId,
    this.serialUnitId,
    this.unit,
  });
  
  factory PartInput.fromJson(Map<String, Object?> json) => _$PartInputFromJson(json);
  
  /// Is the part charged to the customer? Default yes.
  @JsonKey(includeIfNull: false)
  final bool? billable;

  /// Required for free text; defaults to the product's name.
  @JsonKey(includeIfNull: false)
  final String? description;

  /// Chosen by the client: sending the same id again changes nothing (offline retries).
  @JsonKey(includeIfNull: false)
  final String? id;

  /// A product from the catalogue; leave empty for free text.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  final String quantity;

  /// The unit (serial number) the part went into.
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  /// Defaults to the product's unit, or `pcs`.
  @JsonKey(includeIfNull: false)
  final String? unit;

  Map<String, Object?> toJson() => _$PartInputToJson(this);
}
