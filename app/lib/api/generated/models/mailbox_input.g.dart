// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mailbox_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailboxInput _$MailboxInputFromJson(Map<String, dynamic> json) => MailboxInput(
  address: json['address'] as String,
  kind: json['kind'] as String,
  name: json['name'] as String,
  secretRef: json['secret_ref'] as String,
  active: json['active'] as bool?,
  clientId: json['client_id'] as String?,
  imapFolder: json['imap_folder'] as String?,
  imapHost: json['imap_host'] as String?,
  imapPort: (json['imap_port'] as num?)?.toInt(),
  imapTls: json['imap_tls'] as bool?,
  inboundEnabled: json['inbound_enabled'] as bool?,
  isDefault: json['is_default'] as bool?,
  smtpHost: json['smtp_host'] as String?,
  smtpPort: (json['smtp_port'] as num?)?.toInt(),
  smtpSecurity: json['smtp_security'] as String?,
  teamId: json['team_id'] as String?,
  tenantId: json['tenant_id'] as String?,
  username: json['username'] as String?,
);

Map<String, dynamic> _$MailboxInputToJson(MailboxInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'address': instance.address,
      'client_id': ?instance.clientId,
      'imap_folder': ?instance.imapFolder,
      'imap_host': ?instance.imapHost,
      'imap_port': ?instance.imapPort,
      'imap_tls': ?instance.imapTls,
      'inbound_enabled': ?instance.inboundEnabled,
      'is_default': ?instance.isDefault,
      'kind': instance.kind,
      'name': instance.name,
      'secret_ref': instance.secretRef,
      'smtp_host': ?instance.smtpHost,
      'smtp_port': ?instance.smtpPort,
      'smtp_security': ?instance.smtpSecurity,
      'team_id': ?instance.teamId,
      'tenant_id': ?instance.tenantId,
      'username': ?instance.username,
    };
