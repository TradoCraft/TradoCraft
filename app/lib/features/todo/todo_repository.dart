import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/photos.dart' show newClientId;

/// Which items the to-do page lists.
enum TodoFilter { open, done, all }

/// The to-do endpoints (ADR 0061) as the page needs them. Online only: nothing is queued, every
/// call goes to the server and the page reloads the list afterwards.
class TodoRepository {
  const TodoRepository(this._api);

  final TradocraftApi _api;

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
      _api.todo.todoUpdate(id: id, body: patch);

  /// Completes an item. With [completeChildren] its open sub-items are completed too; without it
  /// the server answers 409 (`open_sub_items`) when there are any.
  Future<TodoItem> complete(String id, {bool completeChildren = false}) =>
      _api.todo.todoComplete(
        id: id,
        body: TodoCompleteInput(completeChildren: completeChildren),
      );

  Future<TodoItem> reopen(String id) => _api.todo.todoReopen(id: id);

  Future<void> delete(String id) => _api.todo.todoDelete(id: id);

  /// Puts the siblings under [parentId] (null: the root items) in the order of [ids].
  Future<void> reorder(String? parentId, List<String> ids) =>
      _api.todo.todoReorder(
        body: TodoReorderInput(parentId: parentId, ids: ids),
      );
}

final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => TodoRepository(ref.watch(apiProvider)),
);

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
