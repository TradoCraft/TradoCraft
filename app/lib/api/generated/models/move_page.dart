// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'stock_move.dart';

part 'move_page.g.dart';

@JsonSerializable()
class MovePage {
  const MovePage({
    required this.items,
    required this.total,
  });
  
  factory MovePage.fromJson(Map<String, Object?> json) => _$MovePageFromJson(json);
  
  final List<StockMove> items;
  final int total;

  Map<String, Object?> toJson() => _$MovePageToJson(this);
}
