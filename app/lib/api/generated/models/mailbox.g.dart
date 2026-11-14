// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mailbox.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Mailbox _$MailboxFromJson(Map<String, dynamic> json) => Mailbox(
  active: json['active'] as bool,
  address: json['address'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  id: json['id'] as String,
  imapFolder: json['imap_folder'] as String,
  imapTls: json['imap_tls'] as bool,
  inboundEnabled: json['inbound_enabled'] as bool,
  isDefault: json['is_default'] as bool,
  kind: json['kind'] as String,
  name: json['name'] as String,
  secretRef: json['secret_ref'] as String,
  smtpSecurity: json['smtp_security'] as String,
  clientId: json['client_id'] as String?,
  imapHost: json['imap_host'] as String?,
  imapPort: (json['imap_port'] as num?)?.toInt(),
  lastError: json['last_error'] as String?,
  lastOkAt: json['last_ok_at'] == null
      ? null
      : DateTime.parse(json['last_ok_at'] as String),
  lastPollAt: json['last_poll_at'] == null
      ? null
      : DateTime.parse(json['last_poll_at'] as String),
  smtpHost: json['smtp_host'] as String?,
  smtpPort: (json['smtp_port'] as num?)?.toInt(),
  teamId: json['team_id'] as String?,
  teamName: json['team_name'] as String?,
  tenantId: json['tenant_id'] as String?,
  username: json['username'] as String?,
);

Map<String, dynamic> _$MailboxToJson(Mailbox instance) => <String, dynamic>{
  'active': instance.active,
  'address': instance.address,
  'client_id': ?instance.clientId,
  'created_at': instance.createdAt.toIso8601String(),
  'id': instance.id,
  'imap_folder': instance.imapFolder,
  'imap_host': ?instance.imapHost,
  'imap_port': ?instance.imapPort,
  'imap_tls': instance.imapTls,
  'inbound_enabled': instance.inboundEnabled,
  'is_default': instance.isDefault,
  'kind': instance.kind,
  'last_error': ?instance.lastError,
  'last_ok_at': ?instance.lastOkAt?.toIso8601String(),
  'last_poll_at': ?instance.lastPollAt?.toIso8601String(),
  'name': instance.name,
  'secret_ref': instance.secretRef,
  'smtp_host': ?instance.smtpHost,
  'smtp_port': ?instance.smtpPort,
  'smtp_security': instance.smtpSecurity,
  'team_id': ?instance.teamId,
  'team_name': ?instance.teamName,
  'tenant_id': ?instance.tenantId,
  'username': ?instance.username,
};
