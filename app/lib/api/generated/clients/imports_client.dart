// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/create_job.dart';
import '../models/import_description.dart';
import '../models/import_file.dart';
import '../models/import_job.dart';
import '../models/import_job_page.dart';
import '../models/import_mapping.dart';
import '../models/import_preview.dart';
import '../models/mapping_input.dart';

part 'imports_client.g.dart';

@RestApi()
abstract class ImportsClient {
  factory ImportsClient(Dio dio, {String? baseUrl}) = _ImportsClient;

  /// The entities the caller may import, with their columns.
  @GET('/api/v1/imports/entities')
  Future<List<ImportDescription>> listImportEntities();

  /// Uploads a file (CSV, XLSX or ODS, at most 50 MiB): the request body is the file itself. A file.
  /// of another type, or one that exceeds the archive limits, is refused and not stored.
  ///
  /// [filename] - The original file name.
  ///
  /// [body] - The raw bytes of a file.
  @POST('/api/v1/imports/files')
  Future<ImportFile> uploadImportFile({
    @Body() required File body,
    @Query('filename') String? filename,
  });

  /// The header, the number of rows and the first 20 rows of an uploaded file.
  ///
  /// [sheet] - The sheet to read; the first one when absent. Ignored for CSV.
  @GET('/api/v1/imports/files/{id}/preview')
  Future<ImportPreview> previewImportFile({
    @Path('id') required String id,
    @Query('sheet') String? sheet,
  });

  /// The runs of the company, newest first.
  ///
  /// [status] - Only jobs in this status.
  ///
  /// [limit] - Page size, 50 by default, at most 200.
  @GET('/api/v1/imports/jobs')
  Future<ImportJobPage> listImportJobs({
    @Query('status') String? status,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// Starts an import. A file within the limits of one request runs now and the finished job is.
  /// returned (200); a larger one is queued for the worker (202).
  @POST('/api/v1/imports/jobs')
  Future<ImportJob> createImportJob({
    @Body() required CreateJob body,
  });

  /// One run with its progress and the first 100 errors.
  @GET('/api/v1/imports/jobs/{id}')
  Future<ImportJob> getImportJob({
    @Path('id') required String id,
  });

  /// Cancels a job that is still queued.
  @POST('/api/v1/imports/jobs/{id}/cancel')
  Future<ImportJob> cancelImportJob({
    @Path('id') required String id,
  });

  /// The errors of a run as CSV (`row`, `column`, `message`).
  @GET('/api/v1/imports/jobs/{id}/errors')
  Future<String> downloadImportErrors({
    @Path('id') required String id,
  });

  /// The saved mappings of the company, by name.
  ///
  /// [entity] - Only the mappings of this entity.
  @GET('/api/v1/imports/mappings')
  Future<List<ImportMapping>> listImportMappings({
    @Query('entity') String? entity,
  });

  /// Saves a mapping; an existing one with the same entity and name is replaced.
  @PUT('/api/v1/imports/mappings')
  Future<ImportMapping> saveImportMapping({
    @Body() required MappingInput body,
  });

  /// Deletes a saved mapping.
  @DELETE('/api/v1/imports/mappings/{id}')
  Future<void> deleteImportMapping({
    @Path('id') required String id,
  });
}
