// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'customer_counts.g.dart';

@JsonSerializable()
class CustomerCounts {
  const CustomerCounts({
    required this.closures,
    required this.contacts,
    required this.productRebates,
    this.equipment,
  });
  
  factory CustomerCounts.fromJson(Map<String, Object?> json) => _$CustomerCountsFromJson(json);
  
  final int closures;
  final int contacts;
  @JsonKey(includeIfNull: false)
  final int? equipment;
  @JsonKey(name: 'product_rebates')
  final int productRebates;

  Map<String, Object?> toJson() => _$CustomerCountsToJson(this);
}
