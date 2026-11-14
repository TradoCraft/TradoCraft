import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api.dart';

/// Uploads the file as raw bytes (`application/octet-stream`). The generated client sends a
/// string body, which would corrupt a spreadsheet, so this call goes through Dio directly.
Future<ImportFile> uploadImportFile(
  Dio dio,
  String filename,
  Uint8List bytes,
) async {
  final res = await dio.post<Map<String, dynamic>>(
    '/api/v1/imports/files',
    data: bytes,
    queryParameters: {'filename': filename},
    options: Options(contentType: 'application/octet-stream'),
  );
  return ImportFile.fromJson(res.data!);
}

/// The error report of a job as CSV bytes (the generated client would decode it as text).
Future<Uint8List> downloadImportErrors(Dio dio, String jobId) async =>
    Uint8List.fromList(
      await downloadBytes(dio, '/api/v1/imports/jobs/$jobId/errors'),
    );

/// The entities the user may import (those whose write permission they hold).
final importEntitiesProvider =
    FutureProvider.autoDispose<List<ImportDescription>>(
      (ref) => ref.watch(apiProvider).imports.listImportEntities(),
    );

/// The newest [limit] runs of the company.
final importJobsProvider = FutureProvider.autoDispose
    .family<ImportJobPage, int>(
      (ref, limit) =>
          ref.watch(apiProvider).imports.listImportJobs(limit: limit),
    );

/// One run with its progress and first errors.
final importJobProvider = FutureProvider.autoDispose.family<ImportJob, String>(
  (ref, id) => ref.watch(apiProvider).imports.getImportJob(id: id),
);

/// A job that is not finished: it is polled until it is.
bool jobIsActive(ImportJob j) => j.status == 'queued' || j.status == 'running';

/// Human name of a detected format.
String formatName(String format) => switch (format) {
  'csv' => 'CSV',
  'xlsx' => 'Excel (XLSX)',
  'ods' => 'OpenDocument (ODS)',
  _ => format,
};

/// `1.5 MB`, for the size of an uploaded file.
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
