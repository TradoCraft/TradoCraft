// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'vat_group.g.dart';

@JsonSerializable()
class VatGroup {
  const VatGroup({
    required this.baseValue,
    required this.vat,
    required this.vatRate,
  });
  
  factory VatGroup.fromJson(Map<String, Object?> json) => _$VatGroupFromJson(json);
  
  /// The name has been replaced because it contains a keyword. Original name: `base`.
  @JsonKey(name: 'base')
  final String baseValue;
  final String vat;
  @JsonKey(name: 'vat_rate')
  final String vatRate;

  Map<String, Object?> toJson() => _$VatGroupToJson(this);
}
