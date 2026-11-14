// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'portal_order.dart';
import 'portal_order_line.dart';

part 'portal_order_detail.g.dart';

@JsonSerializable()
class PortalOrderDetail {
  const PortalOrderDetail({
    required this.lines,
    required this.order,
  });
  
  factory PortalOrderDetail.fromJson(Map<String, Object?> json) => _$PortalOrderDetailFromJson(json);
  
  final List<PortalOrderLine> lines;
  final PortalOrder order;

  Map<String, Object?> toJson() => _$PortalOrderDetailToJson(this);
}
