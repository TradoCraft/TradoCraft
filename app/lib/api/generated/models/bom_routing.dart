// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'routing_operation.dart';

part 'bom_routing.g.dart';

/// The routing of one BOM revision.
@JsonSerializable()
class BomRouting {
  const BomRouting({
    required this.bomId,
    required this.bomRevision,
    required this.bomStatus,
    required this.operations,
    required this.productId,
  });
  
  factory BomRouting.fromJson(Map<String, Object?> json) => _$BomRoutingFromJson(json);
  
  @JsonKey(name: 'bom_id')
  final String bomId;
  @JsonKey(name: 'bom_revision')
  final int bomRevision;

  /// draft | active | obsolete. Only a draft can be changed.
  @JsonKey(name: 'bom_status')
  final String bomStatus;
  final List<RoutingOperation> operations;
  @JsonKey(name: 'product_id')
  final String productId;

  Map<String, Object?> toJson() => _$BomRoutingToJson(this);
}
