// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_capacity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionCapacity _$ProductionCapacityFromJson(Map<String, dynamic> json) =>
    ProductionCapacity(
      centres: (json['centres'] as List<dynamic>)
          .map(
            (e) => ProductionCapacityCentre.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
    );

Map<String, dynamic> _$ProductionCapacityToJson(ProductionCapacity instance) =>
    <String, dynamic>{
      'centres': instance.centres,
      'from': instance.from.toIso8601String(),
      'to': instance.to.toIso8601String(),
    };
