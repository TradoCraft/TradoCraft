// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'complete_production_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompleteProductionInput _$CompleteProductionInputFromJson(
  Map<String, dynamic> json,
) => CompleteProductionInput(
  output: ProductionOutputInput.fromJson(
    json['output'] as Map<String, dynamic>,
  ),
  components: (json['components'] as List<dynamic>?)
      ?.map(
        (e) => ProductionComponentActual.fromJson(e as Map<String, dynamic>),
      )
      .toList(),
  note: json['note'] as String?,
  operations: (json['operations'] as List<dynamic>?)
      ?.map(
        (e) => ProductionOperationActual.fromJson(e as Map<String, dynamic>),
      )
      .toList(),
);

Map<String, dynamic> _$CompleteProductionInputToJson(
  CompleteProductionInput instance,
) => <String, dynamic>{
  'components': ?instance.components,
  'note': ?instance.note,
  'operations': ?instance.operations,
  'output': instance.output,
};
