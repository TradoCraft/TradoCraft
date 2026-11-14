// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_operation_actual.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOperationActual _$ProductionOperationActualFromJson(
  Map<String, dynamic> json,
) => ProductionOperationActual(
  operationId: json['operation_id'] as String,
  actualMinutes: (json['actual_minutes'] as num?)?.toInt(),
);

Map<String, dynamic> _$ProductionOperationActualToJson(
  ProductionOperationActual instance,
) => <String, dynamic>{
  'actual_minutes': ?instance.actualMinutes,
  'operation_id': instance.operationId,
};
