import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../app/shortcuts/actions.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'global_search_model.dart';

/// How long typing must pause before the server is asked.
const globalSearchDebounce = Duration(milliseconds: 250);

/// A navigation destination the search offers under "Go to".
typedef SearchDestination = ({String path, String label});

/// Opens the command-palette style search: one field, a "Go to" group of matching sections and
/// the first matches of every entity the user may read. [destinations] are the sections of the
/// shell (already filtered by permission); [onGoTo] opens one of them (default: `context.go`).
Future<void> showGlobalSearch(
  BuildContext context, {
  List<SearchDestination> destinations = const [],
  void Function(String path)? onGoTo,
}) {
  final router = GoRouter.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => GlobalSearchDialog(
      destinations: destinations,
      onGoTo: onGoTo ?? router.go,
      onOpen: router.go,
    ),
  );
}

/// The shell's search button: an icon with the shortcut in its tooltip.
class GlobalSearchButton extends StatelessWidget {
  const GlobalSearchButton({
    super.key,
    required this.destinations,
    this.onGoTo,
  });

  final List<SearchDestination> destinations;
  final void Function(String path)? onGoTo;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('global-search-button'),
      icon: const Icon(AppIcons.search),
      tooltip: context.l10n.globalSearchTooltip(
        ShortcutAction.palette.describe(),
      ),
      onPressed: () =>
          showGlobalSearch(context, destinations: destinations, onGoTo: onGoTo),
    );
  }
}

class _Row {
  const _Row.header(this.header, this.icon)
    : path = null,
      title = '',
      subtitle = null,
      go = false;
  const _Row.item(this.title, this.subtitle, this.path, {this.go = false})
    : header = null,
      icon = null;

  final String? header;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? path;

  /// True for a "Go to" destination (opened like a menu entry), false for a record.
  final bool go;
  bool get selectable => path != null;
}

class GlobalSearchDialog extends ConsumerStatefulWidget {
  const GlobalSearchDialog({
    super.key,
    required this.destinations,
    required this.onGoTo,
    required this.onOpen,
  });

  final List<SearchDestination> destinations;
  final void Function(String path) onGoTo;
  final void Function(String path) onOpen;

  @override
  ConsumerState<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  var _seq = 0;
  var _query = '';
  var _loading = false;
  List<SearchGroup> _groups = const [];
  var _selected = 0;
  final _keys = <int, GlobalKey>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    final q = text.trim();
    setState(() {
      _query = q;
      _selected = 0;
      if (q.isEmpty) {
        _seq++;
        _groups = const [];
        _loading = false;
      } else {
        _loading = true;
      }
    });
    if (q.isEmpty) return;
    _debounce = Timer(globalSearchDebounce, () => _run(q));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    final search = GlobalSearch(
      ref.read(apiProvider),
      ref.read(meProvider).value?.permissions.toSet(),
    );
    final groups = await search.search(q);
    if (!mounted || seq != _seq) return;
    setState(() {
      _groups = groups;
      _loading = false;
      _selected = 0;
    });
  }

  List<_Row> _rows() {
    final l = context.l10n;
    final folded = foldForSearch(_query);
    final rows = <_Row>[];
    if (_query.isNotEmpty) {
      final matches = [
        for (final d in widget.destinations)
          if (foldForSearch(d.label).contains(folded)) d,
      ];
      if (matches.isNotEmpty) {
        rows.add(_Row.header(l.globalSearchGoTo, AppIcons.search));
        for (final d in matches) {
          rows.add(_Row.item(d.label, null, d.path, go: true));
        }
      }
    }
    for (final g in _groups) {
      rows.add(_Row.header(g.entity.label(l), g.entity.icon));
      if (g.failed) {
        rows.add(
          _Row.item(l.globalSearchFailed(g.entity.label(l)), null, null),
        );
      }
      for (final h in g.hits) {
        rows.add(_Row.item(h.title, h.subtitle, h.path));
      }
    }
    return rows;
  }

  void _move(List<_Row> rows, int delta) {
    final sel = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].selectable) i,
    ];
    if (sel.isEmpty) return;
    setState(() => _selected = (_selected + delta) % sel.length);
    final key = _keys[sel[_selected]];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = key?.currentContext;
      if (c != null) Scrollable.ensureVisible(c);
    });
  }

  void _open(_Row row) {
    Navigator.of(context).pop();
    final p = row.path;
    if (p == null) return;
    (row.go ? widget.onGoTo : widget.onOpen)(p);
  }

  void _submit(List<_Row> rows) {
    final sel = [
      for (final r in rows)
        if (r.selectable) r,
    ];
    if (_selected < sel.length) _open(sel[_selected]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final rows = _rows();
    final selectableIdx = [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].selectable) i,
    ];
    final current = _selected < selectableIdx.length
        ? selectableIdx[_selected]
        : -1;
    _keys.clear();
    final Widget body;
    if (_query.isEmpty) {
      body = _note(l.globalSearchStart, key: 'global-search-start');
    } else if (rows.isEmpty && _loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
            key: ValueKey('global-search-loading'),
          ),
        ),
      );
    } else if (rows.isEmpty) {
      body = _note(l.globalSearchEmpty(_query), key: 'global-search-empty');
    } else {
      body = ListView(
        shrinkWrap: true,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          for (var i = 0; i < rows.length; i++)
            if (rows[i].header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      rows[i].icon,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(rows[i].header!, style: theme.textTheme.labelMedium),
                  ],
                ),
              )
            else
              KeyedSubtree(
                key: _keys[i] = GlobalKey(),
                child: ListTile(
                  key: ValueKey('global-search-row-$i'),
                  dense: true,
                  selected: i == current,
                  selectedTileColor: theme.colorScheme.primaryContainer,
                  title: Text(rows[i].title),
                  subtitle: rows[i].subtitle == null
                      ? null
                      : Text(rows[i].subtitle!),
                  enabled: rows[i].selectable,
                  onTap: () => _open(rows[i]),
                ),
              ),
        ],
      );
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _move(rows, 1);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _move(rows, -1);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('global-search-field'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(AppIcons.search),
                    hintText: l.globalSearchHint,
                  ),
                  onChanged: _changed,
                  onSubmitted: (_) => _submit(rows),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }

  Widget _note(String text, {required String key}) => Padding(
    key: ValueKey(key),
    padding: const EdgeInsets.all(24),
    child: Text(text, textAlign: TextAlign.center),
  );
}
