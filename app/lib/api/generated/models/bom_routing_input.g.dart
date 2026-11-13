// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bom_routing_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BomRoutingInput _$BomRoutingInputFromJson(Map<String, dynamic> json) =>
    BomRoutingInput(
      operations: (json['operations'] as List<dynamic>)
          .map((e) => RoutingOperationInput.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$BomRoutingInputToJson(BomRoutingInput instance) =>
    <String, dynamic>{'operations': instance.operations};
