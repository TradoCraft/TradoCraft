// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'line.dart';
import 'trace.dart';

part 'line.g.dart';

@JsonSerializable()
class Line {
  const Line({
    required this.children,
    required this.code,
    required this.quantity,
    required this.rule,
    required this.trace,
    this.comment,
    this.description,
    this.percentBase,
    this.percentOfParent,
    this.productId,
    this.productName,
    this.section,
  });
  
  factory Line.fromJson(Map<String, Object?> json) => _$LineFromJson(json);
  
  final List<Line> children;
  final String code;
  @JsonKey(includeIfNull: false)
  final String? comment;
  @JsonKey(includeIfNull: false)
  final String? description;

  /// parent_list_unit_price | parent_net_unit_price
  @JsonKey(includeIfNull: false,name: 'percent_base')
  final String? percentBase;
  @JsonKey(includeIfNull: false,name: 'percent_of_parent')
  final String? percentOfParent;

  /// The catalogue product with this code, if there is one.
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// Its name: translated when the evaluation was asked in a language it has a translation.
  /// for, else the base name.
  @JsonKey(includeIfNull: false,name: 'product_name')
  final String? productName;
  final String quantity;
  final String rule;
  @JsonKey(includeIfNull: false)
  final String? section;
  final Trace trace;

  Map<String, Object?> toJson() => _$LineToJson(this);
}
