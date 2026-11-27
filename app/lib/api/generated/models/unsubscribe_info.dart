// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'unsubscribe_info.g.dart';

@JsonSerializable()
class UnsubscribeInfo {
  const UnsubscribeInfo({
    required this.companyName,
    required this.email,
    required this.language,
    required this.unsubscribed,
  });
  
  factory UnsubscribeInfo.fromJson(Map<String, Object?> json) => _$UnsubscribeInfoFromJson(json);
  
  @JsonKey(name: 'company_name')
  final String companyName;

  /// The address the mailing went to, masked (`j***@example.com`).
  final String email;

  /// The language of the mailing, for the page the recipient lands on.
  final String language;

  /// Whether the address is already on the company's opt-out register.
  final bool unsubscribed;

  Map<String, Object?> toJson() => _$UnsubscribeInfoToJson(this);
}
