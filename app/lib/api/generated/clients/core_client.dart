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
import '../models/company_user.dart';
import '../models/environment_info.dart';
import '../models/me.dart';
import '../models/module_info.dart';
import '../models/modules_input.dart';
import '../models/role_info.dart';
import '../models/setup_status.dart';
import '../models/worker_status.dart';

part 'core_client.g.dart';

@RestApi()
abstract class CoreClient {
  factory CoreClient(Dio dio, {String? baseUrl}) = _CoreClient;

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

  /// The background worker's heartbeat: whether it is running, and its last outage.
  @GET('/api/v1/admin/worker')
  Future<WorkerStatus> getWorker();

  @GET('/api/v1/me')
  Future<Me> me();

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
}
