// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_operation_finish.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionOperationFinish _$ProductionOperationFinishFromJson(
  Map<String, dynamic> json,
) => ProductionOperationFinish(
  actualMinutes: (json['actual_minutes'] as num?)?.toInt(),
  note: json['note'] as String?,
);

Map<String, dynamic> _$ProductionOperationFinishToJson(
  ProductionOperationFinish instance,
) => <String, dynamic>{
  'actual_minutes': ?instance.actualMinutes,
  'note': ?instance.note,
};
