// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/category.dart';
import '../models/category_input.dart';
import '../models/entry.dart';
import '../models/entry_input.dart';
import '../models/entry_summary.dart';
import '../models/entry_version.dart';
import '../models/file_info.dart';
import '../models/reader_category.dart';
import '../models/reader_entry.dart';
import '../models/reader_summary.dart';
import '../models/rendered_entry.dart';

part 'kb_client.g.dart';

@RestApi()
abstract class KbClient {
  factory KbClient(Dio dio, {String? baseUrl}) = _KbClient;

  @GET('/api/v1/kb/categories')
  Future<List<Category>> listKbCategories();

  @POST('/api/v1/kb/categories')
  Future<Category> createKbCategory({
    @Body() required CategoryInput body,
  });

  @PUT('/api/v1/kb/categories/{id}')
  Future<Category> updateKbCategory({
    @Path('id') required String id,
    @Body() required CategoryInput body,
  });

  /// Deletes a category that has no entries and no sub-categories; otherwise deactivate it.
  @DELETE('/api/v1/kb/categories/{id}')
  Future<void> deleteKbCategory({
    @Path('id') required String id,
  });

  /// Lists or searches entries. With `q` the best match comes first and each entry has a snippet.
  ///
  /// [q] - Search words (several words must all occur; "quoted phrases" and -excluded words work).
  ///
  /// [categoryId] - Includes the sub-categories of this category.
  ///
  /// [language] - Language to search and show; entries without it show English, then another language.
  ///
  /// [visibility] - internal | portal | public.
  ///
  /// [status] - draft | published | archived.
  @GET('/api/v1/kb/entries')
  Future<List<EntrySummary>> listKbEntries({
    @Query('q') String? q,
    @Query('category_id') String? categoryId,
    @Query('tag') String? tag,
    @Query('language') String? language,
    @Query('visibility') String? visibility,
    @Query('status') String? status,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/kb/entries')
  Future<Entry> createKbEntry({
    @Body() required EntryInput body,
  });

  @GET('/api/v1/kb/entries/{id}')
  Future<Entry> getKbEntry({
    @Path('id') required String id,
  });

  /// Edits an entry. Editing a published entry saves a new version when the texts changed, and.
  /// changing the visibility of a published entry needs the right to publish.
  @PUT('/api/v1/kb/entries/{id}')
  Future<Entry> updateKbEntry({
    @Path('id') required String id,
    @Body() required EntryInput body,
  });

  /// Retires an entry: hidden from readers, kept for staff.
  @POST('/api/v1/kb/entries/{id}/archive')
  Future<Entry> archiveKbEntry({
    @Path('id') required String id,
  });

  /// Uploads an image for an entry: the request body is the file (JPEG, PNG or WebP, at most.
  /// 12 MB). Use it in the text as `![description](image:<id>)`.
  ///
  /// [filename] - The original file name.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload.
  @POST('/api/v1/kb/entries/{id}/images')
  Future<FileInfo> uploadKbImage({
    @Path('id') required String id,
    @Body() required String body,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  @GET('/api/v1/kb/entries/{id}/images/{file_id}')
  Future<String> getKbImage({
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  @DELETE('/api/v1/kb/entries/{id}/images/{file_id}')
  Future<void> deleteKbImage({
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  /// Makes a draft or archived entry visible to its audience; saves the first version.
  @POST('/api/v1/kb/entries/{id}/publish')
  Future<Entry> publishKbEntry({
    @Path('id') required String id,
  });

  /// Takes a published entry back to draft.
  @POST('/api/v1/kb/entries/{id}/unpublish')
  Future<Entry> unpublishKbEntry({
    @Path('id') required String id,
  });

  @GET('/api/v1/kb/entries/{id}/versions')
  Future<List<EntryVersion>> listKbVersions({
    @Path('id') required String id,
  });

  /// Puts the texts of an earlier version back as a new version. History is never rewritten.
  @POST('/api/v1/kb/entries/{id}/versions/{version}/restore')
  Future<Entry> restoreKbVersion({
    @Path('id') required String id,
    @Path('version') required int version,
  });

  /// All tags in use, for suggestions in filters and the editor.
  @GET('/api/v1/kb/tags')
  Future<List<String>> listKbTags();

  /// Categories that have public entries.
  ///
  /// [language] - nl | fr | en | de | es (default: the company's language).
  @GET('/api/v1/public/kb/{company_id}/categories')
  Future<List<ReaderCategory>> listPublicKbCategories({
    @Path('company_id') required String companyId,
    @Query('language') String? language,
  });

  /// Public entries, or the best matches for the search words.
  ///
  /// [q] - Search words.
  ///
  /// [categoryId] - Includes the sub-categories of this category.
  ///
  /// [language] - nl | fr | en | de | es (default: the company's language).
  @GET('/api/v1/public/kb/{company_id}/entries')
  Future<List<ReaderSummary>> listPublicKbEntries({
    @Path('company_id') required String companyId,
    @Query('q') String? q,
    @Query('category_id') String? categoryId,
    @Query('tag') String? tag,
    @Query('language') String? language,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  /// One public entry. Counts one view. Internal, portal-only, draft and archived entries are.
  /// "not found".
  ///
  /// [language] - nl | fr | en | de | es (default: the company's language).
  @GET('/api/v1/public/kb/{company_id}/entries/{id}')
  Future<ReaderEntry> getPublicKbEntry({
    @Path('company_id') required String companyId,
    @Path('id') required String id,
    @Query('language') String? language,
  });

  @GET('/api/v1/public/kb/{company_id}/entries/{id}/images/{file_id}')
  Future<String> getPublicKbImage({
    @Path('company_id') required String companyId,
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  /// An entry in the ticket's language as plain text and a link, to put in a reply. Nothing is sent.
  @GET('/api/v1/tickets/{id}/kb-entries/{entry_id}/render')
  Future<RenderedEntry> renderKbEntry({
    @Path('id') required String id,
    @Path('entry_id') required String entryId,
  });

  /// Published entries that fit a ticket: the words of the subject and the latest customer.
  /// message, searched in the ticket's language. Internal entries are included; entries linked.
  /// to the ticket's category rank higher.
  ///
  /// [limit] - At most this many entries (default 5, at most 10).
  @GET('/api/v1/tickets/{id}/kb-suggestions')
  Future<List<EntrySummary>> suggestKbEntries({
    @Path('id') required String id,
    @Query('limit') int? limit,
  });
}
