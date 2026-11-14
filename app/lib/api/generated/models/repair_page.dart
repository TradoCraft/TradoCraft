// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'repair.dart';

part 'repair_page.g.dart';

@JsonSerializable()
class RepairPage {
  const RepairPage({
    required this.items,
    required this.total,
  });
  
  factory RepairPage.fromJson(Map<String, Object?> json) => _$RepairPageFromJson(json);
  
  final List<Repair> items;
  final int total;

  Map<String, Object?> toJson() => _$RepairPageToJson(this);
}
