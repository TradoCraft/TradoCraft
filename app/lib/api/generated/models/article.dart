// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'file_info.dart';

part 'article.g.dart';

@JsonSerializable()
class Article {
  const Article({
    required this.attachments,
    required this.body,
    required this.ccAddresses,
    required this.createdAt,
    required this.fromAddress,
    required this.fromName,
    required this.id,
    required this.kind,
    required this.subject,
    required this.toAddresses,
    this.authorName,
    this.authorUserId,
    this.contactId,
    this.contactName,
    this.delivery,
    this.deliveryError,
    this.durationSeconds,
    this.language,
    this.phoneNumber,
    this.sentAt,
  });
  
  factory Article.fromJson(Map<String, Object?> json) => _$ArticleFromJson(json);
  
  /// Files sent or received with the message.
  final List<FileInfo> attachments;
  @JsonKey(includeIfNull: false,name: 'author_name')
  final String? authorName;
  @JsonKey(includeIfNull: false,name: 'author_user_id')
  final String? authorUserId;
  final String body;
  @JsonKey(name: 'cc_addresses')
  final List<String> ccAddresses;

  /// The person this message or call is from or to, when known.
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'contact_name')
  final String? contactName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// For outgoing e-mail: queued | sent | failed
  @JsonKey(includeIfNull: false)
  final String? delivery;
  @JsonKey(includeIfNull: false,name: 'delivery_error')
  final String? deliveryError;
  @JsonKey(includeIfNull: false,name: 'duration_seconds')
  final int? durationSeconds;
  @JsonKey(name: 'from_address')
  final String fromAddress;
  @JsonKey(name: 'from_name')
  final String fromName;
  final String id;

  /// email_in | email_out | note | call_in | call_out | portal_in
  final String kind;
  @JsonKey(includeIfNull: false)
  final String? language;

  /// For calls: the number as typed.
  @JsonKey(includeIfNull: false,name: 'phone_number')
  final String? phoneNumber;
  @JsonKey(includeIfNull: false,name: 'sent_at')
  final DateTime? sentAt;
  final String subject;
  @JsonKey(name: 'to_addresses')
  final List<String> toAddresses;

  Map<String, Object?> toJson() => _$ArticleToJson(this);
}
