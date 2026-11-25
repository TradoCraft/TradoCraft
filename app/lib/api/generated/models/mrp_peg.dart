// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mrp_peg.g.dart';

/// What a proposed quantity is for.
@JsonSerializable()
class MrpPeg {
  const MrpPeg({
    required this.kind,
    required this.number,
    required this.quantity,
    this.id,
  });
  
  factory MrpPeg.fromJson(Map<String, Object?> json) => _$MrpPegFromJson(json);
  
  /// The order, when the requirement is one.
  @JsonKey(includeIfNull: false)
  final String? id;

  /// `sales_order`, `production_order`, `purchase_order` or `planned` (a component of a proposed.
  /// build).
  final String kind;
  final String number;

  /// The quantity of that requirement.
  final String quantity;

  Map<String, Object?> toJson() => _$MrpPegToJson(this);
}
