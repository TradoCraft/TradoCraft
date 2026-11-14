// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'closure.g.dart';

@JsonSerializable()
class Closure {
  const Closure({
    required this.createdAt,
    required this.customerCode,
    required this.customerId,
    required this.customerName,
    required this.endsOn,
    required this.id,
    required this.kind,
    required this.notes,
    required this.source,
    required this.startsOn,
  });
  
  factory Closure.fromJson(Map<String, Object?> json) => _$ClosureFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_code')
  final String customerCode;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;

  /// Last closed day (inclusive).
  @JsonKey(name: 'ends_on')
  final DateTime endsOn;
  final String id;

  /// holiday | collective_leave | inventory | works | other
  final String kind;
  final String notes;

  /// staff | portal
  final String source;

  /// First closed day.
  @JsonKey(name: 'starts_on')
  final DateTime startsOn;

  Map<String, Object?> toJson() => _$ClosureToJson(this);
}
