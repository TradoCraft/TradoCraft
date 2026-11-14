// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'order_revision_info.g.dart';

@JsonSerializable()
class OrderRevisionInfo {
  const OrderRevisionInfo({
    required this.createdAt,
    required this.revision,
    required this.status,
    required this.subtotal,
    required this.total,
    this.sentAt,
    this.sentTo,
  });
  
  factory OrderRevisionInfo.fromJson(Map<String, Object?> json) => _$OrderRevisionInfoFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final int revision;
  @JsonKey(includeIfNull: false,name: 'sent_at')
  final DateTime? sentAt;

  /// The address the order confirmation was e-mailed to.
  @JsonKey(includeIfNull: false,name: 'sent_to')
  final String? sentTo;

  /// draft | sent | confirmed | superseded
  final String status;
  final String subtotal;
  final String total;

  Map<String, Object?> toJson() => _$OrderRevisionInfoToJson(this);
}
