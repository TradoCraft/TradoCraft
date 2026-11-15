import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Spreadsheet-style keys for a table or list: wrap the region and its rows and fields move with
/// the arrows (ADR 0060).
///
/// - Up / Down: the same column in the next / previous row.
/// - Ctrl+Up / Ctrl+Down: the first / last row. Ctrl+Left / Ctrl+Right: the first / last field
///   of the row.
/// - Home / End on a row that is not a text field: the first / last row. In a text field they stay
///   caret keys.
/// - Left / Right alone stay with the field (the caret).
///
/// The targets are the focus nodes below [child] that [include] accepts (default: single-line text
/// fields). Rows are the targets that share a line on the screen, so any layout works. Enter on a
/// focused row is the row's own business (an `InkWell` opens on Enter).
///
/// A lazily built list passes its [scrollController]: when the wanted row is not built yet, the
/// list scrolls and the key is tried once more. With [enterFromOutside], Down from anywhere else in
/// the region (the search field above a list) focuses the first target.
class GridKeyNav extends StatefulWidget {
  /// Creates the region.
  const GridKeyNav({
    super.key,
    required this.child,
    this.include,
    this.scrollController,
    this.enterFromOutside = false,
  });

  /// The table or list with its fields.
  final Widget child;

  /// Which focus nodes are cells; null: single-line text fields.
  final bool Function(FocusNode node)? include;

  /// The controller of the list that scrolls under the region, for rows not built yet.
  final ScrollController? scrollController;

  /// Whether Down from another control of the region focuses the first target.
  final bool enterFromOutside;

  @override
  State<GridKeyNav> createState() => _GridKeyNavState();
}

class _GridKeyNavState extends State<GridKeyNav> {
  final _node = FocusNode(
    debugLabel: 'GridKeyNav',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  bool _isField(FocusNode n) =>
      n.context?.findAncestorStateOfType<EditableTextState>() != null;

  bool _isCell(FocusNode n) {
    if (!n.canRequestFocus || n.skipTraversal || n.context == null) {
      return false;
    }
    // A focused row that scrolled out is kept alive by the list but not laid out: its position is
    // not a number. It is not a cell on the screen, so it must not take part in the ordering.
    if (!n.rect.isFinite) return false;
    final include = widget.include;
    if (include != null) return include(n);
    final es = n.context!.findAncestorStateOfType<EditableTextState>();
    return es != null && es.widget.maxLines == 1;
  }

  /// The cells grouped into rows, top to bottom, each row left to right.
  List<List<FocusNode>> _rows() {
    final cells = _node.descendants.where(_isCell).toList()
      ..sort((a, b) {
        final c = a.rect.center.dy.compareTo(b.rect.center.dy);
        return c != 0 ? c : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    final rows = <List<FocusNode>>[];
    for (final c in cells) {
      if (rows.isNotEmpty) {
        final last = rows.last.first.rect;
        if ((c.rect.center.dy - last.center.dy).abs() <
            math.min(c.rect.height, last.height) / 2) {
          rows.last.add(c);
          continue;
        }
      }
      rows.add([c]);
    }
    for (final r in rows) {
      r.sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    }
    return rows;
  }

  FocusNode _sameColumn(List<FocusNode> row, FocusNode from) {
    final x = from.rect.center.dx;
    return row.reduce(
      (a, b) =>
          (a.rect.center.dx - x).abs() <= (b.rect.center.dx - x).abs() ? a : b,
    );
  }

  void _go(FocusNode n) {
    n.requestFocus();
    final c = n.context;
    if (c != null) Scrollable.ensureVisible(c, duration: Duration.zero);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) =>
      _handle(e) ? KeyEventResult.handled : KeyEventResult.ignored;

  bool _handle(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final kb = HardwareKeyboard.instance;
    if (kb.isAltPressed || kb.isMetaPressed || kb.isShiftPressed) return false;
    final ctrl = kb.isControlPressed;
    final key = e.logicalKey;
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return false;
    final editing = _isField(current);
    final field = current.context?.findAncestorStateOfType<EditableTextState>();
    final multiline = field?.widget.maxLines != 1;
    // An accent or a CJK character is being composed: the arrows belong to the input method.
    final composing = field?.textEditingValue.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      return false;
    }

    final vertical = key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp;
    final horizontal = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final homeEnd = key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end;
    if (!vertical && !homeEnd && !(horizontal && ctrl)) return false;
    if (homeEnd && (editing || ctrl)) return false;
    if (vertical && !ctrl && editing && multiline) return false;

    final rows = _rows();
    if (rows.isEmpty) return false;
    final r = rows.indexWhere((row) => row.contains(current));
    if (r < 0) {
      // Focus is elsewhere in the region (a search field above the rows).
      if (widget.enterFromOutside && key == LogicalKeyboardKey.arrowDown) {
        _go(rows.first.first);
        return true;
      }
      return false;
    }
    final row = rows[r];
    final down = key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.end;
    FocusNode? target;
    var wantEdge = false;
    if (horizontal) {
      target = key == LogicalKeyboardKey.arrowLeft ? row.first : row.last;
    } else if (ctrl || homeEnd) {
      wantEdge = true;
      target = _sameColumn(down ? rows.last : rows.first, current);
    } else {
      final next = down ? r + 1 : r - 1;
      if (next >= 0 && next < rows.length) {
        target = _sameColumn(rows[next], current);
      }
    }

    final controller = widget.scrollController;
    final atEdge = down ? r == rows.length - 1 : r == 0;
    if (controller != null && controller.hasClients) {
      // The row wanted may not be built yet: scroll toward it and look again.
      if (wantEdge || (target == null && atEdge)) {
        final p = controller.position;
        final to = wantEdge
            ? (down ? p.maxScrollExtent : p.minScrollExtent)
            : (down
                  ? math.min(p.maxScrollExtent, p.pixels + p.viewportDimension / 2)
                  : math.max(p.minScrollExtent, p.pixels - p.viewportDimension / 2));
        if (to != p.pixels) {
          // The focused row may scroll out and be disposed, so remember where it was: the column,
          // and the line it sat on once the content has moved by the scroll.
          final x = current.rect.center.dx, y = current.rect.center.dy;
          final before = p.pixels;
          controller.jumpTo(to);
          final moved = controller.position.pixels - before;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _afterScroll(down: down, edge: wantEdge, x: x, y: y - moved);
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
          return true;
        }
      }
    }
    if (target == null || identical(target, current)) return target != null;
    _go(target);
    return true;
  }

  /// Focuses the wanted cell once the list has scrolled and built its new rows: the last or first
  /// row for an edge key, else the first row below (above) the line where the focused row was.
  void _afterScroll({
    required bool down,
    required bool edge,
    required double x,
    required double y,
  }) {
    final rows = _rows();
    if (rows.isEmpty) return;
    List<FocusNode>? row;
    if (edge) {
      row = down ? rows.last : rows.first;
    } else {
      double dy(List<FocusNode> r) => r.first.rect.center.dy;
      final beyond = rows.where((r) => down ? dy(r) > y + 1 : dy(r) < y - 1);
      row = beyond.isEmpty ? null : (down ? beyond.first : beyond.last);
    }
    if (row == null) return;
    _go(
      row.reduce(
        (a, b) =>
            (a.rect.center.dx - x).abs() <= (b.rect.center.dx - x).abs() ? a : b,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    onKeyEvent: _onKey,
    child: widget.child,
  );
}
