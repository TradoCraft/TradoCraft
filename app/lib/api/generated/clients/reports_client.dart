// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/report_catalog.dart';
import '../models/report_run_request.dart';
import '../models/report_run_result.dart';
import '../models/report_schedule.dart';
import '../models/report_schedule_input.dart';
import '../models/saved_report.dart';
import '../models/saved_report_input.dart';
import '../models/send_now_result.dart';

part 'reports_client.g.dart';

@RestApi()
abstract class ReportsClient {
  factory ReportsClient(Dio dio, {String? baseUrl}) = _ReportsClient;

  @GET('/api/v1/custom-reports')
  Future<List<SavedReport>> reportsList();

  @POST('/api/v1/custom-reports')
  Future<SavedReport> reportsCreate({
    @Body() required SavedReportInput body,
  });

  @GET('/api/v1/custom-reports/catalog')
  Future<ReportCatalog> reportsCatalog();

  @POST('/api/v1/custom-reports/run')
  Future<ReportRunResult> reportsRunDefinition({
    @Body() required ReportRunRequest body,
  });

  @GET('/api/v1/custom-reports/{id}')
  Future<SavedReport> reportsGet({
    @Path('id') required String id,
  });

  @PUT('/api/v1/custom-reports/{id}')
  Future<SavedReport> reportsUpdate({
    @Path('id') required String id,
    @Body() required SavedReportInput body,
  });

  @DELETE('/api/v1/custom-reports/{id}')
  Future<void> reportsDelete({
    @Path('id') required String id,
  });

  /// [format] - `csv` (default) or `pdf`.
  ///
  /// [asOf] - Resolve relative dates as of this day (`YYYY-MM-DD`), same bounds as for running.
  /// Default today.
  @GET('/api/v1/custom-reports/{id}/export')
  Future<void> reportsExport({
    @Path('id') required String id,
    @Query('format') String? format,
    @Query('as_of') String? asOf,
  });

  /// [limit] - Rows per page (default 100, at most 500).
  ///
  /// [asOf] - Resolve relative dates as of this day (`YYYY-MM-DD`): send the `as_of` of the first page.
  /// back for later pages. Not older than 366 days, not more than 1 day ahead. Default today.
  @GET('/api/v1/custom-reports/{id}/run')
  Future<ReportRunResult> reportsRun({
    @Path('id') required String id,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
    @Query('as_of') String? asOf,
  });

  @GET('/api/v1/report-schedules')
  Future<List<ReportSchedule>> reportSchedulesList();

  @POST('/api/v1/report-schedules')
  Future<ReportSchedule> reportSchedulesCreate({
    @Body() required ReportScheduleInput body,
  });

  @PUT('/api/v1/report-schedules/{id}')
  Future<ReportSchedule> reportSchedulesUpdate({
    @Path('id') required String id,
    @Body() required ReportScheduleInput body,
  });

  @DELETE('/api/v1/report-schedules/{id}')
  Future<void> reportSchedulesDelete({
    @Path('id') required String id,
  });

  /// Builds the report now and queues the mail, as the schedule's owner would get it. The next.
  /// scheduled run does not change. A refusal (the owner lost access, too many rows) is a 422 with.
  /// the reason.
  @POST('/api/v1/report-schedules/{id}/send')
  Future<SendNowResult> reportSchedulesSend({
    @Path('id') required String id,
  });
}
