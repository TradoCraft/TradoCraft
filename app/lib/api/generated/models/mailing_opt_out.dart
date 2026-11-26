// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mailing_opt_out.g.dart';

/// An address on the company's opt-out register.
@JsonSerializable()
class MailingOptOut {
  const MailingOptOut({
    required this.email,
    required this.optedOutAt,
    required this.source,
    this.recordedBy,
    this.recordedByName,
  });
  
  factory MailingOptOut.fromJson(Map<String, Object?> json) => _$MailingOptOutFromJson(json);
  
  final String email;
  @JsonKey(name: 'opted_out_at')
  final DateTime optedOutAt;
  @JsonKey(includeIfNull: false,name: 'recorded_by')
  final String? recordedBy;
  @JsonKey(includeIfNull: false,name: 'recorded_by_name')
  final String? recordedByName;

  /// staff | unsubscribe_link
  final String source;

  Map<String, Object?> toJson() => _$MailingOptOutToJson(this);
}
