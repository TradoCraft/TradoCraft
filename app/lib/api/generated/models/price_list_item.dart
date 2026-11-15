// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_item.g.dart';

@JsonSerializable()
class PriceListItem {
  const PriceListItem({
    required this.description,
    required this.groupId,
    required this.hidden,
    required this.id,
    required this.indicative,
    required this.net,
    required this.priceOnRequest,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.sortKey,
  });
  
  factory PriceListItem.fromJson(Map<String, Object?> json) => _$PriceListItemFromJson(json);
  
  /// Replaces the product name in that language.
  final Map<String, String> description;
  @JsonKey(name: 'group_id')
  final String groupId;
  final bool hidden;
  final String id;
  final bool indicative;
  final bool net;
  @JsonKey(name: 'price_on_request')
  final bool priceOnRequest;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// Dotted position inside the group, e.g. `2.10`.
  @JsonKey(name: 'sort_key')
  final String sortKey;

  Map<String, Object?> toJson() => _$PriceListItemToJson(this);
}
