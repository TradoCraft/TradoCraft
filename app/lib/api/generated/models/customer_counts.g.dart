// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CustomerCounts _$CustomerCountsFromJson(Map<String, dynamic> json) =>
    CustomerCounts(
      closures: (json['closures'] as num).toInt(),
      contacts: (json['contacts'] as num).toInt(),
      productRebates: (json['product_rebates'] as num).toInt(),
      equipment: (json['equipment'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CustomerCountsToJson(CustomerCounts instance) =>
    <String, dynamic>{
      'closures': instance.closures,
      'contacts': instance.contacts,
      'equipment': ?instance.equipment,
      'product_rebates': instance.productRebates,
    };
