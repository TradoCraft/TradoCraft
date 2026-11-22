// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rebate_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RebateSettings _$RebateSettingsFromJson(Map<String, dynamic> json) =>
    RebateSettings(
      showOnInvoices: json['show_on_invoices'] as bool,
      wording: (json['wording'] as List<dynamic>)
          .map((e) => RebateWording.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RebateSettingsToJson(RebateSettings instance) =>
    <String, dynamic>{
      'show_on_invoices': instance.showOnInvoices,
      'wording': instance.wording,
    };
