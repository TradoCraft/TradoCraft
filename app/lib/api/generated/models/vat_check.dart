// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'vat_duplicate.dart';
import 'vat_status.dart';
import 'vies_lookup.dart';

part 'vat_check.g.dart';

@JsonSerializable()
class VatCheck {
  const VatCheck({
    required this.duplicates,
    required this.status,
    required this.vatNumber,
    this.message,
    this.normalized,
    this.vies,
  });

  factory VatCheck.fromJson(Map<String, Object?> json) =>
      _$VatCheckFromJson(json);

  /// Other records with the same number (at most 10). A warning only: two branches of one.
  /// company share a number legitimately.
  final List<VatDuplicate> duplicates;

  /// What is wrong, in words, when `status` is `bad_format` or `bad_checksum`.
  @JsonKey(includeIfNull: false)
  final String? message;

  /// An EU number in its VIES form (`BE0428759497`), to store or look up; absent otherwise.
  @JsonKey(includeIfNull: false)
  final String? normalized;
  final VatStatus status;

  /// The number as given.
  @JsonKey(name: 'vat_number')
  final String vatNumber;

  /// VIES's answer; present only when a lookup was asked for.
  @JsonKey(includeIfNull: false)
  final ViesLookup? vies;

  Map<String, Object?> toJson() => _$VatCheckToJson(this);
}
