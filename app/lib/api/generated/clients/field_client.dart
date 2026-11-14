// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/complete_input.dart';
import '../models/contract_detail.dart';
import '../models/contract_input.dart';
import '../models/contract_summary.dart';
import '../models/customer_equipment.dart';
import '../models/declined_input.dart';
import '../models/done_input.dart';
import '../models/equipment_input.dart';
import '../models/job.dart';
import '../models/job_detail.dart';
import '../models/job_input.dart';
import '../models/part_input.dart';
import '../models/reason_input.dart';
import '../models/task_input.dart';
import '../models/upcoming_visit.dart';
import '../models/work_log_input.dart';

part 'field_client.g.dart';

@RestApi()
abstract class FieldClient {
  factory FieldClient(Dio dio, {String? baseUrl}) = _FieldClient;

  /// [q] - Searches number, title and customer.
  ///
  /// [status] - draft | active | suspended | ended.
  @GET('/api/v1/field/contracts')
  Future<List<ContractSummary>> listContracts({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('customer_id') String? customerId,
  });

  @POST('/api/v1/field/contracts')
  Future<ContractDetail> createContract({
    @Body() required ContractInput body,
  });

  @GET('/api/v1/field/contracts/{id}')
  Future<ContractDetail> getContract({
    @Path('id') required String id,
  });

  @PUT('/api/v1/field/contracts/{id}')
  Future<ContractDetail> updateContract({
    @Path('id') required String id,
    @Body() required ContractInput body,
  });

  /// Starts a draft contract, or resumes a suspended one: planned jobs are generated again.
  @POST('/api/v1/field/contracts/{id}/activate')
  Future<ContractDetail> activateContract({
    @Path('id') required String id,
  });

  /// Ends a contract for good. Jobs already generated stay.
  @POST('/api/v1/field/contracts/{id}/end')
  Future<ContractDetail> endContract({
    @Path('id') required String id,
  });

  /// The jobs generated for (or linked to) a contract, newest first.
  @GET('/api/v1/field/contracts/{id}/jobs')
  Future<List<Job>> listContractJobs({
    @Path('id') required String id,
  });

  /// Pauses a contract: no jobs are generated until it is activated again.
  @POST('/api/v1/field/contracts/{id}/suspend')
  Future<ContractDetail> suspendContract({
    @Path('id') required String id,
  });

  /// The visits due from today on, from the active templates, and whether their job exists.
  ///
  /// [until] - Look ahead to this date (YYYY-MM-DD). Default: twelve months from today (at most 36).
  @GET('/api/v1/field/contracts/{id}/upcoming')
  Future<List<UpcomingVisit>> listContractUpcoming({
    @Path('id') required String id,
    @Query('until') String? until,
  });

  /// The installed units of a customer (delivered or installed, not scrapped) with their job history.
  @GET('/api/v1/field/customers/{id}/equipment')
  Future<List<CustomerEquipment>> listCustomerEquipment({
    @Path('id') required String id,
  });

  /// All jobs the user may see, for planning.
  ///
  /// [q] - Searches number, title, customer and city.
  ///
  /// [status] - A status, or `active` for planned and in progress.
  ///
  /// [technician] - `me`, `none` (unassigned) or a user id.
  ///
  /// [contractId] - Jobs generated for this maintenance contract.
  ///
  /// [from] - Jobs scheduled from this moment on.
  ///
  /// [to] - Jobs scheduled before this moment.
  @GET('/api/v1/field/jobs')
  Future<List<Job>> listJobs({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('technician') String? technician,
    @Query('customer_id') String? customerId,
    @Query('contract_id') String? contractId,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  @POST('/api/v1/field/jobs')
  Future<JobDetail> createJob({
    @Body() required JobInput body,
  });

  @GET('/api/v1/field/jobs/{id}')
  Future<JobDetail> getJob({
    @Path('id') required String id,
  });

  @PUT('/api/v1/field/jobs/{id}')
  Future<JobDetail> updateJob({
    @Path('id') required String id,
    @Body() required JobInput body,
  });

  /// Cancels a job (planners only).
  @POST('/api/v1/field/jobs/{id}/cancel')
  Future<JobDetail> cancelJob({
    @Path('id') required String id,
    @Body() required ReasonInput body,
  });

  /// Completing a job that is already completed with the same text changes nothing (safe to retry);.
  /// with other text it is a 409.
  @POST('/api/v1/field/jobs/{id}/complete')
  Future<JobDetail> completeJob({
    @Path('id') required String id,
    @Body() required CompleteInput body,
  });

  /// Links a unit of the job's customer to the job. Linking it twice changes nothing.
  @POST('/api/v1/field/jobs/{id}/equipment')
  Future<JobDetail> addJobEquipment({
    @Path('id') required String id,
    @Body() required EquipmentInput body,
  });

  @DELETE('/api/v1/field/jobs/{id}/equipment/{serial_unit_id}')
  Future<JobDetail> removeJobEquipment({
    @Path('id') required String id,
    @Path('serial_unit_id') required String serialUnitId,
  });

  /// Records a part used on a job. No stock is deducted.
  @POST('/api/v1/field/jobs/{id}/parts')
  Future<JobDetail> addJobPart({
    @Path('id') required String id,
    @Body() required PartInput body,
  });

  /// Removes a part. Removing one that is already gone changes nothing.
  @DELETE('/api/v1/field/jobs/{id}/parts/{part_id}')
  Future<JobDetail> removeJobPart({
    @Path('id') required String id,
    @Path('part_id') required String partId,
  });

  /// Adds a photo: the request body is the image (JPEG, PNG or WebP, at most 12 MB).
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload.
  @POST('/api/v1/field/jobs/{id}/photos')
  Future<JobDetail> uploadJobPhoto({
    @Path('id') required String id,
    @Body() required String body,
    @Query('caption') String? caption,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  @GET('/api/v1/field/jobs/{id}/photos/{photo_id}')
  Future<String> getJobPhoto({
    @Path('id') required String id,
    @Path('photo_id') required String photoId,
  });

  /// Takes a completed or cancelled job back into work (planners only).
  @POST('/api/v1/field/jobs/{id}/reopen')
  Future<JobDetail> reopenJob({
    @Path('id') required String id,
  });

  /// The service report of a job as PDF (a watermark marks it as draft until the job is completed).
  ///
  /// [language] - nl, fr, en, de or es. Default: the language of the contact, else of the customer.
  @GET('/api/v1/field/jobs/{id}/report')
  Future<List<int>> getJobReport({
    @Path('id') required String id,
    @Query('language') String? language,
  });

  /// E-mails the service report of a completed job to its contact (or the customer's main address).
  /// and records when and to whom. Sending again is allowed. Refused (409) when there is no.
  /// address or the job is not completed.
  @POST('/api/v1/field/jobs/{id}/report/send')
  Future<JobDetail> sendJobReport({
    @Path('id') required String id,
  });

  /// The signature image (PNG).
  @GET('/api/v1/field/jobs/{id}/signature')
  Future<String> getJobSignature({
    @Path('id') required String id,
  });

  /// Stores the customer's signature: the request body is a PNG image. A job has one signature;.
  /// a new one replaces the old one until the service report is sent.
  ///
  /// [signerName] - Who signed, as they wrote it.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again changes nothing.
  @POST('/api/v1/field/jobs/{id}/signature')
  Future<JobDetail> signJob({
    @Path('id') required String id,
    @Query('signer_name') required String signerName,
    @Body() required String body,
    @Query('client_id') String? clientId,
  });

  /// Records that the customer declined to sign. Replaces an earlier signature.
  @POST('/api/v1/field/jobs/{id}/signature/declined')
  Future<JobDetail> declineJobSignature({
    @Path('id') required String id,
    @Body() required DeclinedInput body,
  });

  /// Starts the job: the technician has arrived and begins. Starting twice changes nothing.
  @POST('/api/v1/field/jobs/{id}/start')
  Future<JobDetail> startJob({
    @Path('id') required String id,
  });

  @POST('/api/v1/field/jobs/{id}/tasks')
  Future<JobDetail> addJobTask({
    @Path('id') required String id,
    @Body() required TaskInput body,
  });

  /// Ticks or unticks a task. Setting the state it already has changes nothing, so retries are safe.
  @POST('/api/v1/field/jobs/{id}/tasks/{task_id}/done')
  Future<JobDetail> setJobTaskDone({
    @Path('id') required String id,
    @Path('task_id') required String taskId,
    @Body() required DoneInput body,
  });

  /// Logs time and notes of work (or travel) on a job, for the logged-in technician.
  @POST('/api/v1/field/jobs/{id}/work-logs')
  Future<JobDetail> addWorkLog({
    @Path('id') required String id,
    @Body() required WorkLogInput body,
  });

  /// The jobs assigned to me that still have to be done (plus those finished in the last week),.
  /// in the order of their appointment.
  @GET('/api/v1/field/my-jobs')
  Future<List<Job>> listMyJobs();
}
