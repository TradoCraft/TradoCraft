// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'closure.dart';

part 'delivery_check.g.dart';

@JsonSerializable()
class DeliveryCheck {
  const DeliveryCheck({
    required this.closed,
    required this.date,
    required this.nextOpenDay,
    this.closure,
  });
  
  factory DeliveryCheck.fromJson(Map<String, Object?> json) => _$DeliveryCheckFromJson(json);
  
  /// True when the customer cannot receive a delivery on `date`.
  final bool closed;

  /// The closure that covers `date`, when closed.
  @JsonKey(includeIfNull: false)
  final Closure? closure;
  final DateTime date;

  /// `date` itself when open, otherwise the first day after the closure(s).
  @JsonKey(name: 'next_open_day')
  final DateTime nextOpenDay;

  Map<String, Object?> toJson() => _$DeliveryCheckToJson(this);
}
