// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/todo_complete_input.dart';
import '../models/todo_counts.dart';
import '../models/todo_create.dart';
import '../models/todo_item.dart';
import '../models/todo_link_kind.dart';
import '../models/todo_patch.dart';
import '../models/todo_reorder_input.dart';
import '../models/todo_scope.dart';

part 'todo_client.g.dart';

@RestApi()
abstract class TodoClient {
  factory TodoClient(Dio dio, {String? baseUrl}) = _TodoClient;

  /// [scope] - Defaults to `mine`.
  ///
  /// [done] - `true`: only finished items, `false`: only open ones; absent: both.
  ///
  /// [linkId] - Needs `link_kind`.
  ///
  /// [dueBefore] - Items due strictly before this date.
  @GET('/api/v1/todo/items')
  Future<List<TodoItem>> todoList({
    @Query('scope') TodoScope? scope,
    @Query('done') bool? done,
    @Query('link_kind') TodoLinkKind? linkKind,
    @Query('link_id') String? linkId,
    @Query('due_before') DateTime? dueBefore,
  });

  @POST('/api/v1/todo/items')
  Future<TodoItem> todoCreate({
    @Body() required TodoCreate body,
  });

  @GET('/api/v1/todo/items/counts')
  Future<TodoCounts> todoCounts();

  @POST('/api/v1/todo/items/reorder')
  Future<void> todoReorder({
    @Body() required TodoReorderInput body,
  });

  @DELETE('/api/v1/todo/items/{id}')
  Future<void> todoDelete({
    @Path('id') required String id,
  });

  @PATCH('/api/v1/todo/items/{id}')
  Future<TodoItem> todoUpdate({
    @Path('id') required String id,
    @Body() required TodoPatch body,
  });

  @POST('/api/v1/todo/items/{id}/complete')
  Future<TodoItem> todoComplete({
    @Path('id') required String id,
    @Body() required TodoCompleteInput body,
  });

  @POST('/api/v1/todo/items/{id}/reopen')
  Future<TodoItem> todoReopen({
    @Path('id') required String id,
  });
}
