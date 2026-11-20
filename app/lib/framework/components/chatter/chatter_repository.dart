import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api.dart';

/// The kinds of record that carry a chatter (ADR 0086). [read] and [write] are the permissions
/// the server checks; the panel hides what the caller cannot do.
enum ChatterKind {
  customer('customer', 'customers', 'customers.read', 'customers.write'),
  quotation('quotation', 'quotations', 'quotations.read', 'quotations.write'),
  order('order', 'orders', 'orders.read', 'orders.write'),
  opportunity(
    'opportunity',
    'opportunities',
    'opportunities.read',
    'opportunities.write',
  );

  const ChatterKind(this.api, this.path, this.read, this.write);

  /// The `{kind}` segment of the API.
  final String api;

  /// The app location segment, `/<path>/<id>`.
  final String path;
  final String read;
  final String write;

  String location(String id) => '/$path/$id';

  static ChatterKind? parse(String api) {
    for (final k in values) {
      if (k.api == api) return k;
    }
    return null;
  }
}

/// The chatter of one record over the generated client (ADR 0078 pattern). Errors pass through
/// unchanged.
class ChatterRepository {
  const ChatterRepository(this._c);
  final ChatterClient _c;

  Future<ThreadPage> thread(
    ChatterKind kind,
    String id, {
    String? beforeId,
    int limit = 30,
  }) => _c.chatterThread(
    kind: kind.api,
    id: id,
    beforeId: beforeId,
    limit: limit,
  );

  Future<ThreadItem> post(
    ChatterKind kind,
    String id,
    String body, {
    String? clientId,
  }) => _c.chatterPostNote(
    kind: kind.api,
    id: id,
    body: ChatterNoteInput(body: body, clientId: clientId),
  );

  Future<ThreadItem> edit(String noteId, String body) => _c.chatterEditNote(
    id: noteId,
    body: ChatterNoteInput(body: body),
  );

  Future<void> delete(String noteId) => _c.chatterDeleteNote(id: noteId);

  Future<List<Activity>> activities(ChatterKind kind, String id) =>
      _c.chatterActivities(kind: kind.api, id: id);

  Future<Activity> schedule(ChatterKind kind, String id, ActivityInput input) =>
      _c.chatterCreateActivity(kind: kind.api, id: id, body: input);

  Future<void> complete(String activityId, String note) =>
      _c.chatterCompleteActivity(
        id: activityId,
        body: ActivityDoneInput(note: note),
      );

  Future<void> deleteActivity(String activityId) =>
      _c.chatterDeleteActivity(id: activityId);

  Future<Followers> followers(ChatterKind kind, String id) =>
      _c.chatterFollowers(kind: kind.api, id: id);

  Future<Followers> follow(ChatterKind kind, String id) =>
      _c.chatterFollow(kind: kind.api, id: id);

  Future<Followers> unfollow(ChatterKind kind, String id) =>
      _c.chatterUnfollow(kind: kind.api, id: id);

  Future<void> markRead(ChatterKind kind, String id) =>
      _c.chatterMarkRead(kind: kind.api, id: id);

  Future<Inbox> inbox() => _c.chatterInbox();
}

final chatterRepositoryProvider = Provider<ChatterRepository>(
  (ref) => ChatterRepository(ref.watch(apiProvider).chatter),
);

/// What needs attention across records, for the notifications centre. Empty when the call
/// fails: the bell must work without it.
final chatterInboxProvider = FutureProvider.autoDispose<Inbox?>((ref) async {
  try {
    return await ref.watch(chatterRepositoryProvider).inbox();
  } catch (_) {
    return null;
  }
});
