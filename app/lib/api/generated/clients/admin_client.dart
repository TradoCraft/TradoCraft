// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/identity_provider_info.dart';
import '../models/identity_provider_input.dart';
import '../models/identity_provider_test.dart';
import '../models/identity_provider_test_result.dart';
import '../models/oidc_subject_input.dart';

part 'admin_client.g.dart';

@RestApi()
abstract class AdminClient {
  factory AdminClient(Dio dio, {String? baseUrl}) = _AdminClient;

  /// The identity providers: the database ones and, read-only, the one from the environment.
  @GET('/api/v1/admin/identity-providers')
  Future<List<IdentityProviderInfo>> listProviders();

  /// Adds an identity provider. Discovery and signing keys must be readable and the discovery.
  /// issuer must match, or the answer is 422 with the reason.
  @POST('/api/v1/admin/identity-providers')
  Future<IdentityProviderInfo> createProvider({
    @Body() required IdentityProviderInput body,
  });

  /// Tries a configuration without saving anything: reads discovery and keys and, with a sample.
  /// token, checks it and shows how its claims map to a user, without binding or storing anything.
  @POST('/api/v1/admin/identity-providers/test')
  Future<IdentityProviderTestResult> testProvider({
    @Body() required IdentityProviderTest body,
  });

  /// Replaces the settings of an identity provider. Enabled providers are probed like on create.
  /// Disabling it or changing its issuer is refused (409) when it is the last provider or the.
  /// caller's own, unless `confirm_lockout` is true.
  @PUT('/api/v1/admin/identity-providers/{id}')
  Future<IdentityProviderInfo> updateProvider({
    @Path('id') required String id,
    @Body() required IdentityProviderInput body,
  });

  /// Deletes an identity provider; refused (409) for the last provider without an environment.
  /// fallback and for the caller's own provider, unless `confirm_lockout=true`. The environment.
  /// provider cannot be deleted (it is not a database row: 404).
  ///
  /// [confirmLockout] - Acknowledge that deleting can lock people out.
  @DELETE('/api/v1/admin/identity-providers/{id}')
  Future<void> deleteProvider({
    @Path('id') required String id,
    @Query('confirm_lockout') bool? confirmLockout,
  });

  /// Sets or clears the identity a user signs in with, for providers with the `subject_only`.
  /// policy. The value stored is `<issuer>|<subject>`.
  @PUT('/api/v1/admin/users/{id}/oidc-subject')
  Future<void> setOidcSubject({
    @Path('id') required String id,
    @Body() required OidcSubjectInput body,
  });
}
