import 'package:flutter/foundation.dart';

import '../../../app/api.dart' show errorMessage;
import 'kanban_config.dart';

/// The state of one column.
class KanbanColumnState<T> {
  KanbanColumnState();

  List<T> items = [];
  int total = 0;
  bool loading = true;
  bool loadingMore = false;
  bool failed = false;

  /// How many items of the server's order have been read. Optimistic moves add and remove cards
  /// on screen, so the next page starts here and not at `items.length`.
  int serverOffset = 0;

  /// What the moves still under way have added to [total] (+1 for a card going in, -1 for one
  /// going out). A page that arrives meanwhile carries the server's total, which does not know
  /// about them yet.
  int pendingDelta = 0;

  /// Identifies the page request that may still clear [loadingMore].
  int moreToken = 0;

  /// Items the column holds beyond those loaded.
  int get remaining => (total - items.length).clamp(0, total);
}

/// Loads the columns of a board, one by one and in parallel, and moves cards between them.
///
/// A move is optimistic: the card is in its new column at once and goes back when the move is
/// cancelled or refused (ADR 0087). Answers that arrive after a reload are dropped.
class KanbanController<T> extends ChangeNotifier {
  KanbanController(this.config)
    : columns = {for (final c in config.columns) c.id: KanbanColumnState<T>()};

  /// Replaced when the presentation changes (the language, the user's rights) without losing the
  /// cards or a move under way. The columns of the new config must be the same.
  KanbanConfig<T> config;
  final Map<String, KanbanColumnState<T>> columns;
  Map<String, String> summaries = const {};

  /// The last failed move, for the board to show.
  String? error;
  int _generation = 0;
  int _summarySeq = 0;
  final _moving = <String>{};
  bool _disposed = false;

  /// Swaps the config. Does not notify: the caller is rebuilding the board anyway.
  void updateConfig(KanbanConfig<T> next) => config = next;

  /// Reads the column summaries again (their text may be in another language now).
  Future<void> refreshSummaries() => _loadSummaries(_generation);

  bool isMoving(T item) => _moving.contains(config.idOf(item));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void dismissError() {
    if (error == null) return;
    error = null;
    _changed();
  }

  /// Loads every column afresh.
  Future<void> load() async {
    final gen = ++_generation;
    for (final c in columns.values) {
      c
        ..loading = true
        ..failed = false
        // A page of the old load must not leave this one waiting, and moves under way belong to
        // the old load.
        ..loadingMore = false
        ..moreToken += 1
        ..pendingDelta = 0;
    }
    _changed();
    await Future.wait([
      for (final def in config.columns) _loadFirstPage(def.id, gen),
      _loadSummaries(gen),
    ]);
  }

  Future<void> reloadColumn(String id) async {
    final gen = _generation;
    columns[id]!
      ..loading = true
      ..failed = false;
    _changed();
    await _loadFirstPage(id, gen);
  }

  Future<void> _loadFirstPage(String id, int gen) async {
    final state = columns[id]!;
    try {
      final page = await config.loadColumn(id, 0, config.pageSize);
      if (_disposed || gen != _generation) return;
      state
        ..items = [...page.items]
        ..total = page.total
        ..serverOffset = page.items.length
        ..failed = false;
    } catch (_) {
      if (_disposed || gen != _generation) return;
      state
        ..items = []
        ..total = 0
        ..failed = true;
    } finally {
      if (!_disposed && gen == _generation) {
        state.loading = false;
        _changed();
      }
    }
  }

  Future<void> _loadSummaries(int gen) async {
    final load = config.loadSummaries;
    if (load == null) return;
    final seq = ++_summarySeq;
    try {
      final s = await load();
      // Only the latest request counts: an older answer may predate a move.
      if (_disposed || gen != _generation || seq != _summarySeq) return;
      summaries = s;
      _changed();
    } catch (_) {
      // The board works without the numbers under the titles.
    }
  }

  /// The next page of a column.
  Future<void> loadMore(String id) async {
    final state = columns[id]!;
    if (state.loadingMore || state.remaining == 0) return;
    final gen = _generation;
    final token = ++state.moreToken;
    state.loadingMore = true;
    _changed();
    try {
      final page = await config.loadColumn(
        id,
        state.serverOffset,
        config.pageSize,
      );
      if (_disposed || gen != _generation || token != state.moreToken) return;
      // A card moved in meanwhile may also be on the server's page: show it once.
      final have = {for (final i in state.items) config.idOf(i)};
      state
        ..items = [
          ...state.items,
          ...page.items.where((i) => !have.contains(config.idOf(i))),
        ]
        ..serverOffset += page.items.length
        // The server does not know about the moves still under way.
        ..total = page.total + state.pendingDelta;
    } catch (e) {
      if (!_disposed && gen == _generation && token == state.moreToken) {
        error = errorMessage(e);
      }
    } finally {
      if (!_disposed && token == state.moreToken) {
        state.loadingMore = false;
        _changed();
      }
    }
  }

  /// Moves [item], which the board shows in column [from], to [toColumn]. The column is the
  /// board's own: after an earlier move the item itself still describes where it came from.
  /// Returns whether it moved.
  Future<bool> move(T item, String from, String toColumn) async {
    final id = config.idOf(item);
    if (from == toColumn || _moving.contains(id)) return false;
    final source = columns[from];
    final target = columns[toColumn];
    if (source == null || target == null) return false;
    final index = source.items.indexWhere((i) => config.idOf(i) == id);
    if (index < 0) return false;
    final gen = _generation;
    _moving.add(id);
    error = null;
    source.items.removeAt(index);
    source.total = (source.total - 1).clamp(0, source.total);
    target.items.insert(0, item);
    target.total += 1;
    source.pendingDelta -= 1;
    target.pendingDelta += 1;
    _changed();
    var kept = false;
    try {
      kept = await config.move(item, toColumn) == MoveResult.moved;
    } catch (e) {
      error = errorMessage(e);
    }
    _moving.remove(id);
    if (_disposed) return kept;
    if (gen != _generation) {
      // The board was reloaded while the move ran. That reload may have read the columns before
      // the server applied the move, so read the two columns again; the optimistic cards of the
      // old load are not put back.
      if (kept) {
        await Future.wait([
          reloadColumn(from),
          reloadColumn(toColumn),
          _loadSummaries(_generation),
        ]);
      }
      _changed();
      return kept;
    }
    source.pendingDelta += 1;
    target.pendingDelta -= 1;
    if (!kept) {
      target.items.removeWhere((i) => config.idOf(i) == id);
      target.total = (target.total - 1).clamp(0, target.total);
      source.items.insert(index.clamp(0, source.items.length), item);
      source.total += 1;
    } else {
      // The server holds one item fewer in the source: the next page starts one earlier.
      if (source.serverOffset > 0) source.serverOffset -= 1;
      await _loadSummaries(gen);
    }
    _changed();
    return kept;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
