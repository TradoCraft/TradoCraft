// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'confirm_portal_order.g.dart';

@JsonSerializable()
class ConfirmPortalOrder {
  const ConfirmPortalOrder({
    required this.revision,
    this.note,
  });
  
  factory ConfirmPortalOrder.fromJson(Map<String, Object?> json) => _$ConfirmPortalOrderFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? note;

  /// The revision the customer is looking at; refused when it is no longer the latest.
  final int revision;

  Map<String, Object?> toJson() => _$ConfirmPortalOrderToJson(this);
}
