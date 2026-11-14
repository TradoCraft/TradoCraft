// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_close_input.g.dart';

@JsonSerializable()
class PackageCloseInput {
  const PackageCloseInput({
    required this.note,
  });
  
  factory PackageCloseInput.fromJson(Map<String, Object?> json) => _$PackageCloseInputFromJson(json);
  
  /// Why: refused at the dock, sent back, nothing to repair.
  final String note;

  Map<String, Object?> toJson() => _$PackageCloseInputToJson(this);
}
