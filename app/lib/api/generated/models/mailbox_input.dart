// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mailbox_input.g.dart';

@JsonSerializable()
class MailboxInput {
  const MailboxInput({
    required this.address,
    required this.kind,
    required this.name,
    required this.secretRef,
    this.active,
    this.clientId,
    this.imapFolder,
    this.imapHost,
    this.imapPort,
    this.imapTls,
    this.inboundEnabled,
    this.isDefault,
    this.smtpHost,
    this.smtpPort,
    this.smtpSecurity,
    this.teamId,
    this.tenantId,
    this.username,
  });
  
  factory MailboxInput.fromJson(Map<String, Object?> json) => _$MailboxInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  final String address;
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;
  @JsonKey(includeIfNull: false,name: 'imap_folder')
  final String? imapFolder;
  @JsonKey(includeIfNull: false,name: 'imap_host')
  final String? imapHost;
  @JsonKey(includeIfNull: false,name: 'imap_port')
  final int? imapPort;
  @JsonKey(includeIfNull: false,name: 'imap_tls')
  final bool? imapTls;
  @JsonKey(includeIfNull: false,name: 'inbound_enabled')
  final bool? inboundEnabled;
  @JsonKey(includeIfNull: false,name: 'is_default')
  final bool? isDefault;

  /// graph | imap_smtp
  final String kind;
  final String name;

  /// Upper-case letters, digits and underscores, e.g. `SUPPORT`.
  @JsonKey(name: 'secret_ref')
  final String secretRef;
  @JsonKey(includeIfNull: false,name: 'smtp_host')
  final String? smtpHost;
  @JsonKey(includeIfNull: false,name: 'smtp_port')
  final int? smtpPort;
  @JsonKey(includeIfNull: false,name: 'smtp_security')
  final String? smtpSecurity;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false,name: 'tenant_id')
  final String? tenantId;
  @JsonKey(includeIfNull: false)
  final String? username;

  Map<String, Object?> toJson() => _$MailboxInputToJson(this);
}
