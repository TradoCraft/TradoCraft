// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_item_update.g.dart';

/// Change of an item; the product of an item never changes (remove and add instead).
@JsonSerializable()
class PriceListItemUpdate {
  const PriceListItemUpdate({
    required this.groupId,
    this.description,
    this.hidden,
    this.indicative,
    this.net,
    this.priceOnRequest,
    this.sortKey,
  });
  
  factory PriceListItemUpdate.fromJson(Map<String, Object?> json) => _$PriceListItemUpdateFromJson(json);
  
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
  @JsonKey(includeIfNull: false,name: 'sort_key')
  final String? sortKey;

  Map<String, Object?> toJson() => _$PriceListItemUpdateToJson(this);
}
