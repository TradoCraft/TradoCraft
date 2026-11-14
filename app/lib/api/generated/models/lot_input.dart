// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'lot_input.g.dart';

@JsonSerializable()
class LotInput {
  const LotInput({
    this.expiryDate,
    this.notes,
  });
  
  factory LotInput.fromJson(Map<String, Object?> json) => _$LotInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'expiry_date')
  final DateTime? expiryDate;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$LotInputToJson(this);
}
