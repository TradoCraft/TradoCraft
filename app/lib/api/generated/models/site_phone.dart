// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'site_phone.g.dart';

@JsonSerializable()
class SitePhone {
  const SitePhone({
    required this.label,
    required this.number,
  });
  
  factory SitePhone.fromJson(Map<String, Object?> json) => _$SitePhoneFromJson(json);
  
  final String label;
  final String number;

  Map<String, Object?> toJson() => _$SitePhoneToJson(this);
}
