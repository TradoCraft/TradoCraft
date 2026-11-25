// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/mrp_conversion.dart';
import '../models/mrp_convert_input.dart';
import '../models/mrp_proposal.dart';
import '../models/mrp_run.dart';
import '../models/mrp_run_input.dart';

part 'mrp_client.g.dart';

@RestApi()
abstract class MrpClient {
  factory MrpClient(Dio dio, {String? baseUrl}) = _MrpClient;

  /// The proposals, by the day to order. What the user may not read (production or purchasing) is.
  /// left out.
  ///
  /// [status] - `open` (default), `converted`, `dismissed`, `superseded` or `all`.
  ///
  /// [kind] - `purchase` or `production`.
  @GET('/api/v1/mrp/proposals')
  Future<List<MrpProposal>> listProposals({
    @Query('status') String? status,
    @Query('kind') String? kind,
    @Query('product_id') String? productId,
    @Query('run_id') String? runId,
  });

  /// Turns an open proposal into a draft purchase order (for the supplier of the proposal, at the.
  /// price of its supplier product, or the standard cost) or a released production order (for stock,.
  /// ready on the need date). Nothing is approved or sent.
  @POST('/api/v1/mrp/proposals/{id}/convert')
  Future<MrpConversion> convertProposal({
    @Path('id') required String id,
    @Body() required MrpConvertInput body,
  });

  /// Dismisses an open proposal: it stays in the list of dismissed ones and is not proposed again.
  /// by itself (a later run looks at the requirements afresh).
  @POST('/api/v1/mrp/proposals/{id}/dismiss')
  Future<MrpProposal> dismissProposal({
    @Path('id') required String id,
  });

  /// The latest runs, newest first (at most 20).
  @GET('/api/v1/mrp/runs')
  Future<List<MrpRun>> listRuns();

  /// Plans the requirements of the company: what customers wait for and what production uses, against.
  /// stock and what is on order, and proposes what to buy or build. The open proposals of earlier runs.
  /// are replaced. Nothing is ordered until a proposal is converted.
  @POST('/api/v1/mrp/runs')
  Future<MrpRun> startRun({
    @Body() required MrpRunInput body,
  });
}
