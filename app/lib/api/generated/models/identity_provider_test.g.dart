// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_provider_test.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IdentityProviderTest _$IdentityProviderTestFromJson(
  Map<String, dynamic> json,
) => IdentityProviderTest(
  config: json['config'] == null
      ? null
      : IdentityProviderInput.fromJson(json['config'] as Map<String, dynamic>),
  id: json['id'] as String?,
  sampleToken: json['sample_token'] as String?,
);

Map<String, dynamic> _$IdentityProviderTestToJson(
  IdentityProviderTest instance,
) => <String, dynamic>{
  'config': ?instance.config,
  'id': ?instance.id,
  'sample_token': ?instance.sampleToken,
};
