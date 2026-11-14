// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mailbox.g.dart';

@JsonSerializable()
class Mailbox {
  const Mailbox({
    required this.active,
    required this.address,
    required this.createdAt,
    required this.id,
    required this.imapFolder,
    required this.imapTls,
    required this.inboundEnabled,
    required this.isDefault,
    required this.kind,
    required this.name,
    required this.secretRef,
    required this.smtpSecurity,
    this.clientId,
    this.imapHost,
    this.imapPort,
    this.lastError,
    this.lastOkAt,
    this.lastPollAt,
    this.smtpHost,
    this.smtpPort,
    this.teamId,
    this.teamName,
    this.tenantId,
    this.username,
  });

  factory Mailbox.fromJson(Map<String, Object?> json) =>
      _$MailboxFromJson(json);

  final bool active;

  /// The address customers write to and replies are sent from.
  final String address;
  @JsonKey(includeIfNull: false, name: 'client_id')
  final String? clientId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  @JsonKey(name: 'imap_folder')
  final String imapFolder;
  @JsonKey(includeIfNull: false, name: 'imap_host')
  final String? imapHost;
  @JsonKey(includeIfNull: false, name: 'imap_port')
  final int? imapPort;
  @JsonKey(name: 'imap_tls')
  final bool imapTls;

  /// Fetch incoming mail; off for a mailbox that only sends.
  @JsonKey(name: 'inbound_enabled')
  final bool inboundEnabled;

  /// Used for system mail and for replies on tickets without a mailbox.
  @JsonKey(name: 'is_default')
  final bool isDefault;

  /// graph | imap_smtp
  final String kind;

  /// Why the last attempt failed; empty after a success.
  @JsonKey(includeIfNull: false, name: 'last_error')
  final String? lastError;
  @JsonKey(includeIfNull: false, name: 'last_ok_at')
  final DateTime? lastOkAt;

  /// When the worker last tried to fetch mail, and when that last succeeded.
  @JsonKey(includeIfNull: false, name: 'last_poll_at')
  final DateTime? lastPollAt;
  final String name;

  /// The secret is the worker environment variable `MAILBOX_SECRET_<secret_ref>`; it is never.
  /// stored or returned.
  @JsonKey(name: 'secret_ref')
  final String secretRef;
  @JsonKey(includeIfNull: false, name: 'smtp_host')
  final String? smtpHost;
  @JsonKey(includeIfNull: false, name: 'smtp_port')
  final int? smtpPort;

  /// starttls | tls | none
  @JsonKey(name: 'smtp_security')
  final String smtpSecurity;

  /// New tickets from this mailbox start in this team (else the default team).
  @JsonKey(includeIfNull: false, name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false, name: 'team_name')
  final String? teamName;
  @JsonKey(includeIfNull: false, name: 'tenant_id')
  final String? tenantId;
  @JsonKey(includeIfNull: false)
  final String? username;

  Map<String, Object?> toJson() => _$MailboxToJson(this);
}
