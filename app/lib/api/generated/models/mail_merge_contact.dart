// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mail_merge_contact.g.dart';

@JsonSerializable()
class MailMergeContact {
  const MailMergeContact({
    required this.customerId,
    required this.id,
    required this.name,
    this.email,
    this.language,
  });

  factory MailMergeContact.fromJson(Map<String, Object?> json) => _$MailMergeContactFromJson(json);

  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false)
  final String? email;
  final String id;
  @JsonKey(includeIfNull: false)
  final String? language;
  final String name;

  Map<String, Object?> toJson() => _$MailMergeContactToJson(this);
}
