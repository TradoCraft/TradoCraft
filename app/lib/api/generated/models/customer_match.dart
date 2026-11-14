// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'customer_match.g.dart';

/// A customer found through its main phone number or e-mail address, when no contact matches.
@JsonSerializable()
class CustomerMatch {
  const CustomerMatch({
    required this.code,
    required this.id,
    required this.language,
    required this.matchedOn,
    required this.name,
  });
  
  factory CustomerMatch.fromJson(Map<String, Object?> json) => _$CustomerMatchFromJson(json);
  
  final String code;
  final String id;
  final String language;

  /// phone | email
  @JsonKey(name: 'matched_on')
  final String matchedOn;
  final String name;

  Map<String, Object?> toJson() => _$CustomerMatchToJson(this);
}
