// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'warranty_input.g.dart';

@JsonSerializable()
class WarrantyInput {
  const WarrantyInput({
    this.warrantyNote,
    this.warrantyUntil,
  });
  
  factory WarrantyInput.fromJson(Map<String, Object?> json) => _$WarrantyInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'warranty_note')
  final String? warrantyNote;

  /// The last day of the warranty; empty when unknown.
  @JsonKey(includeIfNull: false,name: 'warranty_until')
  final DateTime? warrantyUntil;

  Map<String, Object?> toJson() => _$WarrantyInputToJson(this);
}
