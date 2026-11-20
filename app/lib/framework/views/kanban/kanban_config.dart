/// What a kanban board needs to know about an entity (ADR 0087). Like the list and form views, the
/// board is configured in Dart per entity; it has no server-driven layout.
library;

import 'package:material_ui/material_ui.dart';

/// One column of the board.
class KanbanColumnDef {
  const KanbanColumnDef(this.id, this.label, {this.color});

  /// Stable identifier (a stage, a status); also what `columnOf` returns.
  final String id;
  final String label;

  /// Accent of the column header; the theme's outline colour when null.
  final Color? color;
}

/// One page of a column: the items and how many the column holds in all.
class KanbanPage<T> {
  const KanbanPage(this.items, this.total);
  final List<T> items;
  final int total;
}

/// What a move came to. A refusal is thrown (and shown), not returned.
enum MoveResult {
  /// The server applied it.
  moved,

  /// The user backed out (for example of a "reason" dialog): the card goes back.
  cancelled,
}

class KanbanConfig<T> {
  const KanbanConfig({
    required this.columns,
    required this.idOf,
    required this.cardBuilder,
    required this.loadColumn,
    required this.move,
    this.loadSummaries,
    this.onOpen,
    this.onCreate,
    this.canCreateIn,
    this.pageSize = 50,
  });

  final List<KanbanColumnDef> columns;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) cardBuilder;

  /// Loads `limit` items of a column from `offset`, in the server's order.
  final Future<KanbanPage<T>> Function(String columnId, int offset, int limit)
  loadColumn;

  /// Moves [item] to another column. May ask the user first and answer [MoveResult.cancelled].
  /// Throws when the server refuses.
  final Future<MoveResult> Function(T item, String toColumnId) move;

  /// A line under each column title (a sum), by column id. Loaded with the board and again after
  /// a move, since the numbers changed. Columns missing from the answer show no line.
  final Future<Map<String, String>> Function()? loadSummaries;

  final void Function(T item)? onOpen;

  /// The "+" in a column header. Absent: no button.
  final Future<void> Function(String columnId)? onCreate;

  /// Which columns offer the "+" (all when absent): nothing is created straight into a closed
  /// stage.
  final bool Function(String columnId)? canCreateIn;
  final int pageSize;
}

/// Thrown by a `move` that the entity refuses on its own (a missing reason). The board puts the
/// card back and shows [message].
class KanbanMoveRefused implements Exception {
  const KanbanMoveRefused(this.message);
  final String message;

  @override
  String toString() => message;
}
