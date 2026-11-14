// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'csat_info.g.dart';

@JsonSerializable()
class CsatInfo {
  const CsatInfo({
    required this.companyName,
    required this.language,
    required this.state,
    required this.subject,
    required this.ticketNumber,
    this.rating,
  });
  
  factory CsatInfo.fromJson(Map<String, Object?> json) => _$CsatInfoFromJson(json);
  
  @JsonKey(name: 'company_name')
  final String companyName;

  /// The language of the ticket, for the page the customer lands on.
  final String language;
  @JsonKey(includeIfNull: false)
  final String? rating;

  /// open (can be rated) | rated | expired
  final String state;
  final String subject;
  @JsonKey(name: 'ticket_number')
  final String ticketNumber;

  Map<String, Object?> toJson() => _$CsatInfoToJson(this);
}
