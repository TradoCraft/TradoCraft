// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PublicProvider _$PublicProviderFromJson(Map<String, dynamic> json) =>
    PublicProvider(
      issuer: json['issuer'] as String,
      name: json['name'] as String,
      scopes: json['scopes'] as String,
      clientId: json['client_id'] as String?,
    );

Map<String, dynamic> _$PublicProviderToJson(PublicProvider instance) =>
    <String, dynamic>{
      'client_id': ?instance.clientId,
      'issuer': instance.issuer,
      'name': instance.name,
      'scopes': instance.scopes,
    };
