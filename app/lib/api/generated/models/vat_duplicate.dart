// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'vat_duplicate.g.dart';

/// A record that carries the same VAT number.
@JsonSerializable()
class VatDuplicate {
  const VatDuplicate({
    required this.active,
    required this.code,
    required this.id,
    required this.name,
  });

  factory VatDuplicate.fromJson(Map<String, Object?> json) =>
      _$VatDuplicateFromJson(json);

  final bool active;
  final String code;
  final String id;
  final String name;

  Map<String, Object?> toJson() => _$VatDuplicateToJson(this);
}
