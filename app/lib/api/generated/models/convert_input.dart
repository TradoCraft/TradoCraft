// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'convert_input.g.dart';

@JsonSerializable()
class ConvertInput {
  const ConvertInput({
    this.customerReference,
    this.notes,
  });
  
  factory ConvertInput.fromJson(Map<String, Object?> json) => _$ConvertInputFromJson(json);
  
  /// The customer's purchase order number or reference.
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$ConvertInputToJson(this);
}
