// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mrp_peg.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MrpPeg _$MrpPegFromJson(Map<String, dynamic> json) => MrpPeg(
  kind: json['kind'] as String,
  number: json['number'] as String,
  quantity: json['quantity'] as String,
  id: json['id'] as String?,
);

Map<String, dynamic> _$MrpPegToJson(MrpPeg instance) => <String, dynamic>{
  'id': ?instance.id,
  'kind': instance.kind,
  'number': instance.number,
  'quantity': instance.quantity,
};
