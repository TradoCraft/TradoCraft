// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/activity.dart';
import '../models/activity_done_input.dart';
import '../models/activity_input.dart';
import '../models/chatter_note_input.dart';
import '../models/follower_input.dart';
import '../models/followers.dart';
import '../models/inbox.dart';
import '../models/thread_item.dart';
import '../models/thread_page.dart';

part 'chatter_client.g.dart';

@RestApi()
abstract class ChatterClient {
  factory ChatterClient(Dio dio, {String? baseUrl}) = _ChatterClient;

  @DELETE('/api/v1/chatter/activities/{id}')
  Future<void> chatterDeleteActivity({
    @Path('id') required String id,
  });

  @POST('/api/v1/chatter/activities/{id}/done')
  Future<void> chatterCompleteActivity({
    @Path('id') required String id,
    @Body() required ActivityDoneInput body,
  });

  @GET('/api/v1/chatter/inbox')
  Future<Inbox> chatterInbox();

  @DELETE('/api/v1/chatter/notes/{id}')
  Future<void> chatterDeleteNote({
    @Path('id') required String id,
  });

  @PATCH('/api/v1/chatter/notes/{id}')
  Future<ThreadItem> chatterEditNote({
    @Path('id') required String id,
    @Body() required ChatterNoteInput body,
  });

  @GET('/api/v1/chatter/{kind}/{id}/activities')
  Future<List<Activity>> chatterActivities({
    @Path('kind') required String kind,
    @Path('id') required String id,
  });

  @POST('/api/v1/chatter/{kind}/{id}/activities')
  Future<Activity> chatterCreateActivity({
    @Path('kind') required String kind,
    @Path('id') required String id,
    @Body() required ActivityInput body,
  });

  @PUT('/api/v1/chatter/{kind}/{id}/follow')
  Future<Followers> chatterFollow({
    @Path('kind') required String kind,
    @Path('id') required String id,
  });

  @DELETE('/api/v1/chatter/{kind}/{id}/follow')
  Future<Followers> chatterUnfollow({
    @Path('kind') required String kind,
    @Path('id') required String id,
  });

  @GET('/api/v1/chatter/{kind}/{id}/followers')
  Future<Followers> chatterFollowers({
    @Path('kind') required String kind,
    @Path('id') required String id,
  });

  @POST('/api/v1/chatter/{kind}/{id}/followers')
  Future<Followers> chatterAddFollower({
    @Path('kind') required String kind,
    @Path('id') required String id,
    @Body() required FollowerInput body,
  });

  @DELETE('/api/v1/chatter/{kind}/{id}/followers/{user_id}')
  Future<Followers> chatterRemoveFollower({
    @Path('kind') required String kind,
    @Path('id') required String id,
    @Path('user_id') required String userId,
  });

  @POST('/api/v1/chatter/{kind}/{id}/notes')
  Future<ThreadItem> chatterPostNote({
    @Path('kind') required String kind,
    @Path('id') required String id,
    @Body() required ChatterNoteInput body,
  });

  @POST('/api/v1/chatter/{kind}/{id}/read')
  Future<void> chatterMarkRead({
    @Path('kind') required String kind,
    @Path('id') required String id,
  });

  @GET('/api/v1/chatter/{kind}/{id}/thread')
  Future<ThreadPage> chatterThread({
    @Path('kind') required String kind,
    @Path('id') required String id,
    @Query('before_id') String? beforeId,
    @Query('limit') int? limit,
  });
}
