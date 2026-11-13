// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'routing_operation_input.dart';

part 'bom_routing_input.g.dart';

/// Replaces the whole routing of a draft BOM revision. The order of the list is the order of the.
/// operations.
@JsonSerializable()
class BomRoutingInput {
  const BomRoutingInput({
    required this.operations,
  });
  
  factory BomRoutingInput.fromJson(Map<String, Object?> json) => _$BomRoutingInputFromJson(json);
  
  final List<RoutingOperationInput> operations;

  Map<String, Object?> toJson() => _$BomRoutingInputToJson(this);
}
