// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_question_input.g.dart';

/// A question from production about an order, routed to the salesperson who sold it.
@JsonSerializable()
class ProductionQuestionInput {
  const ProductionQuestionInput({
    required this.body,
    required this.orderId,
    required this.subject,
  });
  
  factory ProductionQuestionInput.fromJson(Map<String, Object?> json) => _$ProductionQuestionInputFromJson(json);
  
  final String body;
  @JsonKey(name: 'order_id')
  final String orderId;
  final String subject;

  Map<String, Object?> toJson() => _$ProductionQuestionInputToJson(this);
}
