// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/favorite.dart';
import '../models/favorite_input.dart';
import '../models/favorite_remark_input.dart';
import '../models/favorite_summary.dart';

part 'favorites_client.g.dart';

@RestApi()
abstract class FavoritesClient {
  factory FavoritesClient(Dio dio, {String? baseUrl}) = _FavoritesClient;

  /// [q] - Searches the name and the code and name of the main product, ignoring case and accents.
  ///
  /// [limit] - Default 50, at most 200.
  @GET('/api/v1/favorites')
  Future<List<FavoriteSummary>> listFavorites({
    @Query('q') String? q,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/favorites')
  Future<Favorite> createFavorite({@Body() required FavoriteInput body});

  /// Adds the customer remark of an item in one language (the typed translation of a remark that.
  /// came from a favorite). A language that already has a text answers 409 unless `overwrite`.
  @PUT('/api/v1/favorites/items/{item_id}/remarks/{language}')
  Future<Favorite> putRemark({
    @Path('item_id') required String itemId,
    @Path('language') required String language,
    @Body() required FavoriteRemarkInput body,
  });

  @GET('/api/v1/favorites/{id}')
  Future<Favorite> getFavorite({@Path('id') required String id});

  /// Renames the favorite and replaces its content. Items whose `id` is sent keep it (and the lines.
  /// that point at it); items without an id are new; stored items that are not sent are deleted.
  @PUT('/api/v1/favorites/{id}')
  Future<Favorite> updateFavorite({
    @Path('id') required String id,
    @Body() required FavoriteInput body,
  });

  /// Deletes the favorite. Quotation lines loaded from it stay as they are and lose the link.
  @DELETE('/api/v1/favorites/{id}')
  Future<void> deleteFavorite({@Path('id') required String id});
}
