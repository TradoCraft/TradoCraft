// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/admin_user.dart';
import '../models/admin_user_create.dart';
import '../models/admin_user_update.dart';
import '../models/bootstrap_request.dart';
import '../models/bootstrap_result.dart';
import '../models/company_logo_info.dart';
import '../models/company_user.dart';
import '../models/country_vat_rate.dart';
import '../models/country_vat_rate_input.dart';
import '../models/environment_info.dart';
import '../models/me.dart';
import '../models/module_info.dart';
import '../models/modules_input.dart';
import '../models/public_provider.dart';
import '../models/role_info.dart';
import '../models/setup_status.dart';
import '../models/user_preferences.dart';
import '../models/worker_status.dart';

part 'core_client.g.dart';

@RestApi()
abstract class CoreClient {
  factory CoreClient(Dio dio, {String? baseUrl}) = _CoreClient;

  /// The company logo image. 404 when none was uploaded.
  @GET('/api/v1/admin/company/logo')
  Future<String> getLogo();

  /// Sets or replaces the company logo: the request body is the image file (PNG, JPEG or SVG, at.
  /// most 512 KB). The type is taken from the file's content, not from the request headers.
  @PUT('/api/v1/admin/company/logo')
  Future<CompanyLogoInfo> putLogo({
    @Body() required String body,
  });

  /// Removes the company logo. 404 when there is none.
  @DELETE('/api/v1/admin/company/logo')
  Future<void> deleteLogo();

  /// The module catalogue with the company's switches.
  @GET('/api/v1/admin/modules')
  Future<List<ModuleInfo>> getModules();

  /// Switches modules off (or on again) for the whole company. A module cannot stay on when one.
  /// it requires is switched off.
  @PUT('/api/v1/admin/modules')
  Future<List<ModuleInfo>> setModules({
    @Body() required ModulesInput body,
  });

  /// All members of the active company, deactivated ones included.
  @GET('/api/v1/admin/users')
  Future<List<AdminUser>> listAdminUsers();

  /// Gives a person access to the company and queues an invitation e-mail. A new e-mail address.
  /// creates the user; an address that already exists (in another company) only gets the.
  /// membership and keeps its name.
  @POST('/api/v1/admin/users')
  Future<AdminUser> createAdminUser({
    @Body() required AdminUserCreate body,
  });

  /// Changes a member's name, roles, module switches and whether the membership is active.
  /// Deactivating only affects this company. You cannot deactivate yourself or drop your own.
  /// admin role, and the company always keeps an active admin.
  @PUT('/api/v1/admin/users/{id}')
  Future<AdminUser> updateAdminUser({
    @Path('id') required String id,
    @Body() required AdminUserUpdate body,
  });

  /// Sends the invitation e-mail again. Refused (409) once the person has signed in, because.
  /// there is nothing left to invite them to, and for deactivated members.
  @POST('/api/v1/admin/users/{id}/invite')
  Future<void> inviteAdminUser({
    @Path('id') required String id,
  });

  @POST('/api/v1/admin/vat-rates')
  Future<CountryVatRate> createVatRate({
    @Body() required CountryVatRateInput body,
  });

  /// [id] - VAT rate rule id
  @PUT('/api/v1/admin/vat-rates/{id}')
  Future<CountryVatRate> updateVatRate({
    @Path('id') required String id,
    @Body() required CountryVatRateInput body,
  });

  /// [id] - VAT rate rule id
  @DELETE('/api/v1/admin/vat-rates/{id}')
  Future<void> deleteVatRate({
    @Path('id') required String id,
  });

  /// The background worker's heartbeat: whether it is running, and its last outage.
  @GET('/api/v1/admin/worker')
  Future<WorkerStatus> getWorker();

  /// The enabled identity providers, for the sign-in page. No sign-in needed; only these six.
  /// fields are exposed. Empty in dev mode.
  @GET('/api/v1/auth/providers')
  Future<List<PublicProvider>> publicProviders();

  /// [entityType] - `customer` | `quotation` | `order` | `opportunity` | `ticket`
  @GET('/api/v1/events/records')
  Future<void> streamRecordEvents({
    @Query('entity_type') required String entityType,
    @Query('record_id') required String recordId,
  });

  @GET('/api/v1/me')
  Future<Me> me();

  /// Returns the authenticated user's preferences.
  @GET('/api/v1/me/preferences')
  Future<UserPreferences> getPreferences();

  /// Replaces the authenticated user's preferences.
  @PUT('/api/v1/me/preferences')
  Future<UserPreferences> putPreferences({
    @Body() required UserPreferences body,
  });

  /// Describes this instance: the configured name and kind, plus the database it is connected to.
  @GET('/api/v1/meta/environment')
  Future<EnvironmentInfo> getEnvironment();

  /// The roles that exist, with what each grants. Drives the role pickers of the user admin.
  @GET('/api/v1/roles')
  Future<List<RoleInfo>> listRoles();

  /// `POST /setup/bootstrap`: creates the first company of an empty database.
  @POST('/api/v1/setup/bootstrap')
  Future<BootstrapResult> bootstrap({
    @Body() required BootstrapRequest body,
  });

  /// `GET /setup/status`: no sign-in needed.
  @GET('/api/v1/setup/status')
  Future<SetupStatus> setupStatus();

  @GET('/api/v1/users')
  Future<List<CompanyUser>> listUsers();

  @GET('/api/v1/vat-rates')
  Future<List<CountryVatRate>> listVatRates({
    @Query('country_code') String? countryCode,
    @Query('category') String? category,
    @Query('as_of') DateTime? asOf,
  });
}
