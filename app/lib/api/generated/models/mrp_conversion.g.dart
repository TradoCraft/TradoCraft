// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mrp_conversion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MrpConversion _$MrpConversionFromJson(Map<String, dynamic> json) =>
    MrpConversion(
      convertedTo: json['converted_to'] as String,
      number: json['number'] as String,
      proposal: MrpProposal.fromJson(json['proposal'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MrpConversionToJson(MrpConversion instance) =>
    <String, dynamic>{
      'converted_to': instance.convertedTo,
      'number': instance.number,
      'proposal': instance.proposal,
    };
