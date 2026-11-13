// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'vies_state.dart';

part 'vies_lookup.g.dart';

/// The outcome of a lookup, ready to pre-fill a form.
@JsonSerializable()
class ViesLookup {
  const ViesLookup({
    required this.state,
    this.address,
    this.city,
    this.name,
    this.postalCode,
    this.reason,
    this.street,
  });
  
  factory ViesLookup.fromJson(Map<String, Object?> json) => _$ViesLookupFromJson(json);
  
  /// The registered address as VIES wrote it, lines joined by a line break.
  @JsonKey(includeIfNull: false)
  final String? address;
  @JsonKey(includeIfNull: false)
  final String? city;

  /// The registered name; absent when VIES does not disclose it.
  @JsonKey(includeIfNull: false)
  final String? name;
  @JsonKey(includeIfNull: false,name: 'postal_code')
  final String? postalCode;

  /// Why `state` is `unavailable`: `disabled`, `timeout`, `network`, `bad_response`, `http_NNN`,.
  /// or the code VIES gave (`ms_unavailable`, `server_busy`, ...).
  @JsonKey(includeIfNull: false)
  final String? reason;
  final ViesState state;

  /// The address split as well as it can be: street lines, postal code and city. Absent parts.
  /// were not recognised; `address` has the full text.
  @JsonKey(includeIfNull: false)
  final String? street;

  Map<String, Object?> toJson() => _$ViesLookupToJson(this);
}
