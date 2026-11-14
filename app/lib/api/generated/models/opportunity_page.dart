// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'opportunity.dart';

part 'opportunity_page.g.dart';

@JsonSerializable()
class OpportunityPage {
  const OpportunityPage({
    required this.items,
    required this.total,
  });
  
  factory OpportunityPage.fromJson(Map<String, Object?> json) => _$OpportunityPageFromJson(json);
  
  final List<Opportunity> items;
  final int total;

  Map<String, Object?> toJson() => _$OpportunityPageToJson(this);
}
