// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'component_history.dart';
import 'serial_component.dart';
import 'serial_unit.dart';

part 'serial_unit_detail.g.dart';

@JsonSerializable()
class SerialUnitDetail {
  const SerialUnitDetail({
    required this.components,
    required this.history,
    required this.unit,
  });
  
  factory SerialUnitDetail.fromJson(Map<String, Object?> json) => _$SerialUnitDetailFromJson(json);
  
  final List<SerialComponent> components;
  final List<ComponentHistory> history;
  final SerialUnit unit;

  Map<String, Object?> toJson() => _$SerialUnitDetailToJson(this);
}
