// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'serial_unit.dart';

part 'serial_unit_page.g.dart';

@JsonSerializable()
class SerialUnitPage {
  const SerialUnitPage({
    required this.items,
    required this.total,
  });
  
  factory SerialUnitPage.fromJson(Map<String, Object?> json) => _$SerialUnitPageFromJson(json);
  
  final List<SerialUnit> items;
  final int total;

  Map<String, Object?> toJson() => _$SerialUnitPageToJson(this);
}
