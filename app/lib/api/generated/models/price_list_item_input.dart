// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_item_input.g.dart';

@JsonSerializable()
class PriceListItemInput {
  const PriceListItemInput({
    required this.groupId,
    required this.productId,
    this.description,
    this.hidden,
    this.indicative,
    this.net,
    this.priceOnRequest,
    this.sortKey,
  });
  
  factory PriceListItemInput.fromJson(Map<String, Object?> json) => _$PriceListItemInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final Map<String, String>? description;
  @JsonKey(name: 'group_id')
  final String groupId;
  @JsonKey(includeIfNull: false)
  final bool? hidden;
  @JsonKey(includeIfNull: false)
  final bool? indicative;
  @JsonKey(includeIfNull: false)
  final bool? net;
  @JsonKey(includeIfNull: false,name: 'price_on_request')
  final bool? priceOnRequest;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(includeIfNull: false,name: 'sort_key')
  final String? sortKey;

  Map<String, Object?> toJson() => _$PriceListItemInputToJson(this);
}
