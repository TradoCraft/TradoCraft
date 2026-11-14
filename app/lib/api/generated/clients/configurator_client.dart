// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/configuration.dart';
import '../models/configuration_input.dart';
import '../models/configuration_summary.dart';
import '../models/configured_import_result.dart';
import '../models/evaluation.dart';
import '../models/expression_check_input.dart';
import '../models/expression_check_result.dart';
import '../models/inputs.dart';
import '../models/model.dart';
import '../models/model_export.dart';
import '../models/model_summary.dart';
import '../models/model_update.dart';
import '../models/new_model_input.dart';
import '../models/new_revision_input.dart';
import '../models/quote_input.dart';
import '../models/revision.dart';
import '../models/revision_update.dart';
import '../models/signature.dart';

part 'configurator_client.g.dart';

@RestApi()
abstract class ConfiguratorClient {
  factory ConfiguratorClient(Dio dio, {String? baseUrl}) = _ConfiguratorClient;

  @GET('/api/v1/configurator/configurations')
  Future<List<ConfigurationSummary>> listConfigurations({
    @Query('model_id') String? modelId,
    @Query('customer_id') String? customerId,
  });

  /// Saves a configuration (with the active revision) and its evaluation.
  @POST('/api/v1/configurator/configurations')
  Future<Configuration> createConfiguration({
    @Body() required ConfigurationInput body,
  });

  @GET('/api/v1/configurator/configurations/{id}')
  Future<Configuration> getConfiguration({
    @Path('id') required String id,
  });

  /// Saves new inputs (and name and customer). The configuration stays on its revision unless.
  /// `revision_id` names the model's active revision (the upgrade).
  @PUT('/api/v1/configurator/configurations/{id}')
  Future<Configuration> updateConfiguration({
    @Path('id') required String id,
    @Body() required ConfigurationInput body,
  });

  /// Deletes a saved configuration. Quotations made from it stay.
  @DELETE('/api/v1/configurator/configurations/{id}')
  Future<void> deleteConfiguration({
    @Path('id') required String id,
  });

  /// Creates or updates the quotation of a configuration: evaluates it on its own revision.
  /// (refused while it has errors) and imports the lines with source `configurator` and the.
  /// configuration id as reference. Quoting again updates the draft quotation, or creates its next.
  /// revision once it was sent (ADR 0033).
  @POST('/api/v1/configurator/configurations/{id}/quote')
  Future<ConfiguredImportResult> quoteConfiguration({
    @Path('id') required String id,
    @Body() required QuoteInput body,
  });

  /// Parses and type-checks one formula or template, for the editor.
  @POST('/api/v1/configurator/expressions/check')
  Future<ExpressionCheckResult> checkExpression({
    @Body() required ExpressionCheckInput body,
  });

  /// The functions of the formula language (for autocompletion).
  @GET('/api/v1/configurator/functions')
  Future<List<Signature>> listFunctions();

  /// The configurators of the company, with their active and draft revision.
  @GET('/api/v1/configurator/models')
  Future<List<ModelSummary>> listModels();

  /// Creates a configurator with a first draft revision.
  @POST('/api/v1/configurator/models')
  Future<Model> createModel({
    @Body() required NewModelInput body,
  });

  /// Imports an export as a new draft: of the configurator with the same code (409 if it already.
  /// has a draft), or of a new configurator.
  @POST('/api/v1/configurator/models/import')
  Future<Revision> importModel({
    @Body() required ModelExport body,
  });

  @GET('/api/v1/configurator/models/{id}')
  Future<Model> getModel({
    @Path('id') required String id,
  });

  /// Changes the name, description, translations, product and active flag of a configurator.
  @PUT('/api/v1/configurator/models/{id}')
  Future<Model> updateModel({
    @Path('id') required String id,
    @Body() required ModelUpdate body,
  });

  /// Starts a new draft revision, copied from `copy_from` or from the active revision.
  @POST('/api/v1/configurator/models/{id}/revisions')
  Future<Revision> createRevision({
    @Path('id') required String id,
    @Body() required NewRevisionInput body,
  });

  /// A revision with its definition and the problems that block its activation.
  @GET('/api/v1/configurator/revisions/{id}')
  Future<Revision> getRevision({
    @Path('id') required String id,
  });

  /// Replaces the definition of a draft. A definition with problems is saved (they are listed in.
  /// `errors`) so work in progress is never lost; it only cannot be activated. It must be a.
  /// well-formed definition document, though (422 otherwise).
  @PUT('/api/v1/configurator/revisions/{id}')
  Future<Revision> updateRevision({
    @Path('id') required String id,
    @Body() required RevisionUpdate body,
  });

  /// Makes a draft the active revision (refused while the definition has problems). The previous.
  /// active revision becomes obsolete; saved configurations stay on the revision they were made with.
  @POST('/api/v1/configurator/revisions/{id}/activate')
  Future<Revision> activateRevision({
    @Path('id') required String id,
  });

  /// Evaluates a revision with the given inputs: values, visibility, lines (with their products),.
  /// issues and traces. Drafts can only be evaluated by designers (the builder's test panel).
  ///
  /// [language] - ISO 639-1 language for the product names of the lines (base names when absent or.
  /// untranslated).
  @POST('/api/v1/configurator/revisions/{id}/evaluate')
  Future<Evaluation> evaluateRevision({
    @Path('id') required String id,
    @Body() required Inputs body,
    @Query('language') String? language,
  });

  /// A revision as a JSON file for another installation or the private repository.
  @GET('/api/v1/configurator/revisions/{id}/export')
  Future<ModelExport> exportRevision({
    @Path('id') required String id,
  });
}
