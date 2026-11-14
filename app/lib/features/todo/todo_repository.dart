import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../app/session.dart';
import '../../shared/photos.dart' show newClientId;

/// Which items the to-do page lists.
enum TodoFilter { open, done, all }

/// The to-do endpoints (ADR 0061) as the page needs them. Online only: nothing is queued, every
/// call goes to the server and the page reloads the list afterwards.
class TodoRepository {
  const TodoRepository(this._api, [this._onChanged]);

  final TradocraftApi _api;

  /// Called after every successful change of an item, so the shell badge can refresh.
  final void Function()? _onChanged;

  Future<T> _changed<T>(Future<T> call) async {
    final result = await call;
    _onChanged?.call();
    return result;
  }

  /// What is on my plate (handed to me, or mine and not handed on), as a flat list ordered by
  /// parent and position.
  Future<List<TodoItem>> list(TodoFilter filter) => _api.todo.todoList(
    done: switch (filter) {
      TodoFilter.open => false,
      TodoFilter.done => true,
      TodoFilter.all => null,
    },
  );

  /// Adds an item, or a sub-item of [parentId]. The client id makes a retried call harmless.
  Future<TodoItem> add({
    required String title,
    String? parentId,
    DateTime? dueDate,
    TodoLinkKind? linkKind,
    String? linkId,
    String? linkLabel,
    String? linkLocation,
  }) => _api.todo.todoCreate(
    body: TodoCreate(
      clientId: newClientId(),
      title: title,
      parentId: parentId,
      dueDate: dueDate,
      linkKind: linkKind,
      linkId: linkId,
      linkLabel: linkLabel,
      linkLocation: linkLocation,
    ),
  );

  /// My open items linked to one record, for the to-dos button on a detail screen. The list is the
  /// caller's own (ADR 0061: privacy); finished items are left out.
  Future<List<TodoItem>> openFor(TodoLinkKind kind, String id) =>
      _api.todo.todoList(done: false, linkKind: kind, linkId: id);

  Future<TodoItem> update(String id, TodoPatch patch) =>
      _changed(_api.todo.todoUpdate(id: id, body: patch));

  /// Completes an item. With [completeChildren] its open sub-items are completed too; without it
  /// the server answers 409 (`open_sub_items`) when there are any.
  Future<TodoItem> complete(String id, {bool completeChildren = false}) =>
      _changed(
        _api.todo.todoComplete(
          id: id,
          body: TodoCompleteInput(completeChildren: completeChildren),
        ),
      );

  Future<TodoItem> reopen(String id) => _changed(_api.todo.todoReopen(id: id));

  Future<void> delete(String id) => _changed(_api.todo.todoDelete(id: id));

  /// Puts the siblings under [parentId] (null: the root items) in the order of [ids].
  Future<void> reorder(String? parentId, List<String> ids) => _changed(
    _api.todo.todoReorder(
      body: TodoReorderInput(parentId: parentId, ids: ids),
    ),
  );

  /// The open, finished and handed-on items of mine that point at a record: what the not-found
  /// state of a record screen offers to unlink.
  Future<List<TodoItem>> linkedTo(TodoLinkKind kind, String id) =>
      _api.todo.todoList(scope: TodoScope.allMine, linkKind: kind, linkId: id);

  /// Clears the link of every item in [items] (the record is gone).
  Future<void> clearLinks(Iterable<TodoItem> items) async {
    for (final i in items) {
      await _api.todo.todoUpdate(
        id: i.id,
        body: const TodoPatch(clearLink: true),
      );
    }
    _onChanged?.call();
  }

  /// Open root items on my plate, overdue and due today (the shell badge).
  Future<TodoCounts> counts() => _api.todo.todoCounts();

  Future<TodoSettings> settings() => _api.todo.todoSettingsGet();

  Future<TodoSettings> setEmailReminders(bool on) =>
      _api.todo.todoSettingsPut(body: TodoSettingsInput(emailReminders: on));
}

final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => TodoRepository(
    ref.watch(apiProvider),
    () => ref.read(todoMutationProvider.notifier).bump(),
  ),
);

/// Counts every change made to a to-do in this app; the shell badge refreshes when it moves.
class TodoMutationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final todoMutationProvider = NotifierProvider<TodoMutationNotifier, int>(
  TodoMutationNotifier.new,
);

/// The reminder switch of the signed-in user (stored on the server).
final todoSettingsProvider = FutureProvider.autoDispose<TodoSettings>(
  (ref) => ref.watch(todoRepositoryProvider).settings(),
);

/// How often the badge asks the server again while the app is in the foreground.
const todoBadgeInterval = Duration(minutes: 3);

/// A burst of changes (a parent and its sub-items) makes one request.
const todoBadgeDebounce = Duration(milliseconds: 500);

/// The numbers on the shell badge, or null when the user has no to-do list (no `todo.use`, the
/// module is off, or signed out): then nothing is requested.
final todoCountsProvider = FutureProvider<TodoCounts?>((ref) async {
  final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
  final allowed = ref.watch(
    meProvider.select(
      (m) => m.value?.permissions.contains('todo.use') ?? false,
    ),
  );
  if (!signedIn || !allowed) return null;
  return ref.watch(todoRepositoryProvider).counts();
});

/// Keeps [todoCountsProvider] fresh: after every to-do change made in the app (debounced), every
/// [todoBadgeInterval] while the app is in the foreground, and when the app resumes. Watched by the
/// shell; does nothing when signed out or without `todo.use`, and stops when either ends.
final todoBadgeSyncProvider = Provider.autoDispose<void>((ref) {
  final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
  final allowed = ref.watch(
    meProvider.select(
      (m) => m.value?.permissions.contains('todo.use') ?? false,
    ),
  );
  if (!signedIn || !allowed) return;
  var foreground = true;
  Timer? debounce;
  void refresh() => ref.invalidate(todoCountsProvider);
  ref.listen(todoMutationProvider, (_, _) {
    debounce?.cancel();
    debounce = Timer(todoBadgeDebounce, refresh);
  });
  final timer = Timer.periodic(todoBadgeInterval, (_) {
    if (foreground) refresh();
  });
  final observer = _LifecycleObserver((state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed && !foreground) refresh();
    foreground = resumed;
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    timer.cancel();
    debounce?.cancel();
    WidgetsBinding.instance.removeObserver(observer);
  });
});

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._onState);

  final void Function(AppLifecycleState) _onState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onState(state);
}

/// The filter of the to-do page: open items by default.
class TodoFilterNotifier extends Notifier<TodoFilter> {
  @override
  TodoFilter build() => TodoFilter.open;

  void set(TodoFilter filter) => state = filter;
}

final todoFilterProvider = NotifierProvider<TodoFilterNotifier, TodoFilter>(
  TodoFilterNotifier.new,
);

/// My items for the chosen filter.
final todoItemsProvider = FutureProvider.autoDispose<List<TodoItem>>(
  (ref) =>
      ref.watch(todoRepositoryProvider).list(ref.watch(todoFilterProvider)),
);

/// My open items linked to a record (kind and id): the to-dos button of a detail screen.
final objectTodosProvider = FutureProvider.autoDispose
    .family<List<TodoItem>, ({TodoLinkKind kind, String id})>(
      (ref, o) => ref.watch(todoRepositoryProvider).openFor(o.kind, o.id),
    );

/// My to-dos that link to a record (kind and id), whatever their state: what the not-found state
/// of a record screen offers to unlink.
final linkedTodosProvider = FutureProvider.autoDispose
    .family<List<TodoItem>, ({TodoLinkKind kind, String id})>(
      (ref, o) => ref.watch(todoRepositoryProvider).linkedTo(o.kind, o.id),
    );
