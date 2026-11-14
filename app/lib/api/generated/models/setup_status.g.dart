// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setup_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetupStatus _$SetupStatusFromJson(Map<String, dynamic> json) => SetupStatus(
  authMode: json['auth_mode'] as String,
  needsSetup: json['needs_setup'] as bool,
  tokenRequired: json['token_required'] as bool,
);

Map<String, dynamic> _$SetupStatusToJson(SetupStatus instance) =>
    <String, dynamic>{
      'auth_mode': instance.authMode,
      'needs_setup': instance.needsSetup,
      'token_required': instance.tokenRequired,
    };
