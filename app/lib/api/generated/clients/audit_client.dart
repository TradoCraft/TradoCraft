// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/audit_facets.dart';
import '../models/audit_page.dart';

part 'audit_client.g.dart';

@RestApi()
abstract class AuditClient {
  factory AuditClient(Dio dio, {String? baseUrl}) = _AuditClient;

  /// The company-wide audit trail, newest first, with filters.
  ///
  /// [entity] - The kind of record.
  ///
  /// [entityId] - One record.
  ///
  /// [action] - Exactly this action.
  ///
  /// [userId] - Events by this user.
  ///
  /// [from] - From this moment on (inclusive).
  ///
  /// [to] - Until this moment (exclusive).
  ///
  /// [beforeId] - Only events older than this id: the `next_before_id` of the previous page.
  ///
  /// [limit] - Page size, 50 by default, at most 200.
  @GET('/api/v1/audit/events')
  Future<AuditPage> listAuditEvents({
    @Query('entity') String? entity,
    @Query('entity_id') String? entityId,
    @Query('action') String? action,
    @Query('user_id') String? userId,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
    @Query('before_id') int? beforeId,
    @Query('limit') int? limit,
  });

  /// The kinds of record the trail has events for, to fill the filter of the viewer.
  @GET('/api/v1/audit/facets')
  Future<AuditFacets> getAuditFacets();

  /// The history of one record, newest first.
  ///
  /// [entity] - The kind of record, e.g. `customer`.
  ///
  /// [id] - The record.
  ///
  /// [limit] - Page size, 50 by default, at most 200.
  @GET('/api/v1/audit/records/{entity}/{id}')
  Future<AuditPage> getRecordHistory({
    @Path('entity') required String entity,
    @Path('id') required String id,
    @Query('before_id') int? beforeId,
    @Query('limit') int? limit,
  });
}
