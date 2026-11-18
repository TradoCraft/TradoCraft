// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LinkInput _$LinkInputFromJson(Map<String, dynamic> json) => LinkInput(
  relation: LinkRelation.fromJson(json['relation'] as String),
  targetId: json['target_id'] as String,
);

Map<String, dynamic> _$LinkInputToJson(LinkInput instance) => <String, dynamic>{
  'relation': instance.relation,
  'target_id': instance.targetId,
};
