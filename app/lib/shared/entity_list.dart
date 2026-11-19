import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../app/workspace.dart' show OpenInTab;
import '../features/field/offline/kv_store.dart';
import '../features/tutorial/targets.dart';
import '../framework/data/repository.dart';
import '../framework/search/favourite.dart';
import '../framework/search/filter_model.dart';
import '../framework/search/filter_widgets.dart';
import '../l10n/l10n.dart';
import 'actions.dart';
import 'app_icons.dart';
import 'grid_key_nav.dart';

/// Column of a generic entity list.
class EntityColumn<T> {
  const EntityColumn(
    this.label,
    this.value, {
    this.numeric = false,
    this.flex = 1,
    this.cell,
    this.sortKey,
    this.id,
    this.hideable = true,
    this.defaultVisible = true,
  });
  final String label;

  /// The API sort key of this column; null: the header is not sortable.
  final String? sortKey;

  /// Stable id for persisted layouts; defaults to [sortKey], then [label].
  final String? id;

  /// Whether the columns menu may hide this column.
  final bool hideable;

  /// Whether the column is shown until the user hides it.
  final bool defaultVisible;
  final String Function(T item) value;

  /// Optional widget for the wide table (e.g. a chip); [value] is still used on narrow screens.
  final Widget Function(BuildContext context, T item)? cell;
  final bool numeric;
  final int flex;
}

typedef PageLoader<T> = Future<(List<T>, int)> Function(
  String? query,
  int offset,
  int limit,
);

/// A bulk action on the selected rows of an [EntityList] (`selectable: true`).
class BulkAction<T> {
  const BulkAction({
    required this.label,
    required this.icon,
    required this.run,
    this.confirm,
    this.enabled,
  });
  final String label;
  final IconData icon;

  /// Runs on the selected items. A thrown error is shown as a snack bar; the selection stays.
  final Future<void> Function(List<T> items) run;

  /// When set, a dialog with this text asks before [run].
  final String? confirm;

  /// Whether the action applies to this selection; null: always.
  final bool Function(List<T> items)? enabled;
}

/// Encodes a sort as the API wants it: `field` or `-field`, comma separated; null when empty.
String? encodeListSort(List<(String, bool)> sort) =>
    sort.isEmpty ? null : sort.map((s) => s.$2 ? '-${s.$1}' : s.$1).join(',');

/// Searchable, paged list used for every master-data and document list.
///
/// One widget, configured per entity, instead of a hand-written screen per table.
/// [onOpen] and [onCreate] return `true` when data changed, which reloads the list.
class EntityList<T> extends StatefulWidget {
  const EntityList({
    super.key,
    required this.title,
    this.load,
    this.loadQuery,
    required this.columns,
    this.onOpen,
    this.locationOf,
    this.onCreate,
    this.createLabel,
    this.createTargetId,
    this.filters,
    this.filterDefs = const [],
    this.moreFilters,
    this.actions = const [],
    this.emptyText,
    this.emptyAction,
    this.resizableColumns = false,
    this.columnMenu = false,
    this.prefsKey,
    this.prefsStore,
    this.selectable = false,
    this.idOf,
    this.bulkActions = const [],
    this.onSelectionChanged,
  }) : assert(
         (load == null) != (loadQuery == null),
         'Pass exactly one of load and loadQuery',
       ),
       assert(!selectable || idOf != null, 'selectable needs idOf');

  final String title;

  /// The simple loader (search, offset, limit). Exactly one of [load] and [loadQuery].
  final PageLoader<T>? load;

  /// The richer loader that also gets the sort. Exactly one of [load] and [loadQuery].
  final Future<(List<T>, int)> Function(ListQuery query)? loadQuery;

  /// Wide layout: columns get explicit widths with drag handles and horizontal scroll.
  final bool resizableColumns;

  /// Shows the columns menu (show / hide, reset layout) in the wide header.
  final bool columnMenu;

  /// When set, the column visibility, widths and sort are stored per user under this key.
  final String? prefsKey;

  /// Store for [prefsKey]; default: the signed-in user's store from the enclosing scope.
  final KvStore? prefsStore;

  /// Adds a checkbox column (long-press on narrow screens) and row selection.
  final bool selectable;

  /// The identity of an item, so a selection survives paging; required when [selectable].
  final Object Function(T item)? idOf;
  final List<BulkAction<T>> bulkActions;
  final void Function(List<T> selected)? onSelectionChanged;
  final List<EntityColumn<T>> columns;
  final Future<bool?> Function(T item)? onOpen;

  /// The detail location of a row (e.g. `/orders/<id>`): enables middle-click, ctrl-click and
  /// "open in new tab" for it.
  final String? Function(T item)? locationOf;
  final Future<bool?> Function()? onCreate;
  final String? createLabel;

  /// Tutorial target id of the create button (null: not a tutorial target).
  final String? createTargetId;
  final Widget? filters;

  /// Declared filters (ADR 0083): a menu button, removable chips and, with [prefsKey], favourites.
  /// The selection goes to [loadQuery] as `ListQuery.filters` (key to the set of selected values).
  /// Needs [loadQuery]. Empty (default): the list looks and behaves as before.
  final List<FilterDef> filterDefs;

  /// More filters, on a line of their own under the search box (for lists with many).
  final Widget? moreFilters;

  /// Extra buttons next to the create button.
  final List<Widget> actions;

  /// Shown instead of the rows when a finished load found nothing.
  final String? emptyText;

  /// Shown under [emptyText], for example a button that widens the view.
  final Widget? emptyAction;

  @override
  State<EntityList<T>> createState() => EntityListState<T>();
}

/// Whether the stored favourites were read (see [EntityListState._favRead]).
enum _FavRead { pending, ready, failed }

class EntityListState<T> extends State<EntityList<T>> {
  static const _pageSize = 50;

  /// The most rows a reload re-reads to keep the selection of rows loaded by "load more".
  static const _maxRefresh = 500;
  static const _minColumnWidth = 64.0;
  static const _maxSorts = 3;
  static const _selectWidth = 48.0;
  static const _menuWidth = 48.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();

  /// One focus node per row index, so the arrow keys can move between rows ([GridKeyNav]).
  final _rowNodes = <int, FocusNode>{};
  Timer? _debounce;
  List<T> _items = [];
  int _total = 0;
  bool _loading = false;
  String? _error;

  List<(String, bool)> _sort = [];
  final _hidden = <String>{};
  final _widths = <String, double>{};

  /// The widths of the last layout, so a drag starts from what is on the screen.
  final _live = <String, double>{};
  final _selected = <Object>{};
  int? _anchor;
  bool _bulkBusy = false;
  String? _lastQueryKey;

  /// The search and sort that produced [_items]; "load more" only appends while it still matches.
  String? _loadedKey;

  /// Set once the user changed the layout, so a saved layout that arrives late is not applied.
  bool _layoutEdited = false;
  KvStore? _store;

  FilterSelection _filterSel = FilterSelection.empty;
  List<Favourite> _favs = const [];

  /// Favourites may only be written after the stored list was read successfully, else a
  /// list built from the empty [_favs] would overwrite it.
  _FavRead _favRead = _FavRead.pending;

  /// Counts favourite changes, so a failed write only restores when nothing newer happened.
  int _favSeq = 0;
  final _searchFocus = FocusNode();

  String _cid(EntityColumn<T> c) => c.id ?? c.sortKey ?? c.label;

  List<EntityColumn<T>> get _visible => [
    for (final c in widget.columns)
      if (!_hidden.contains(_cid(c))) c,
  ];

  String? get _sortString => encodeListSort(_sort);

  bool get _hasMenu => widget.columnMenu;

  @override
  void initState() {
    super.initState();
    assert(
      widget.filterDefs.isEmpty || widget.loadQuery != null,
      'filterDefs needs loadQuery',
    );
    _searchFocus.onKeyEvent = _searchKey;
    _resetVisibility();
    if (widget.prefsKey != null) {
      _store = widget.prefsStore ?? _lookupStore();
      if (_store != null) {
        _loading = true;
        _loadPrefs();
        return;
      }
    }
    reload();
  }

  KvStore? _lookupStore() {
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(userKvStoreProvider);
    } catch (_) {
      return null;
    }
  }

  void _resetVisibility() {
    _hidden
      ..clear()
      ..addAll([
        for (final c in widget.columns)
          if (!c.defaultVisible && c.hideable) _cid(c),
      ]);
    if (_visible.isEmpty) _hidden.clear();
  }

  String get _prefsName => 'entity_list:${widget.prefsKey}';

  static const _prefsTimeout = Duration(seconds: 2);

  String get _favName => 'entity_list_fav:${widget.prefsKey}';

  /// Reads one entry; a store that is slow, never answers or fails gives null.
  Future<String?> _readPref(String name) async {
    try {
      return await _store!.get(name).timeout(_prefsTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Reads the favourites into [_favs]; a null value from a working store is an empty list.
  Future<void> _readFavourites() async {
    try {
      final raw = await _store!.get(_favName).timeout(_prefsTimeout);
      if (!mounted) return;
      _favs = Favourite.decodeList(raw);
      _favRead = _FavRead.ready;
    } catch (_) {
      if (!mounted) return;
      _favRead = _FavRead.failed;
    }
  }

  Future<void> _retryFavourites() async {
    setState(() => _favRead = _FavRead.pending);
    await _readFavourites();
    if (mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    // A store that is slow or never answers must not hold the list back: default layout then.
    // Both entries are read at the same time, so the wait is at most one timeout.
    final (raw, _) = await (_readPref(_prefsName), _readFavourites()).wait;
    if (!mounted) return;
    if (raw != null && !_layoutEdited) {
      try {
        _applyPrefs(jsonDecode(raw));
      } catch (_) {
        // A damaged entry just means the default layout.
      }
    }
    await reload();
  }

  void _applyPrefs(Object? j) {
    if (j is! Map) return;
    final ids = {for (final c in widget.columns) _cid(c): c};
    final hidden = j['hidden'];
    if (hidden is List) {
      _hidden
        ..clear()
        ..addAll([
          for (final h in hidden)
            if (h is String && (ids[h]?.hideable ?? false)) h,
        ]);
      if (_visible.isEmpty) _resetVisibility();
    }
    final widths = j['widths'];
    if (widths is Map) {
      _widths.clear();
      widths.forEach((k, v) {
        if (ids.containsKey(k) && v is num && v.isFinite) {
          _widths[k as String] = math.max(_minColumnWidth, v.toDouble());
        }
      });
    }
    final sort = j['sort'];
    if (sort is String && sort.isNotEmpty) {
      final keys = {
        for (final c in widget.columns)
          if (c.sortKey != null) c.sortKey!,
      };
      final parsed = <(String, bool)>[];
      for (final part in sort.split(',')) {
        final desc = part.startsWith('-');
        final key = desc ? part.substring(1) : part;
        if (keys.contains(key) && !parsed.any((p) => p.$1 == key)) {
          parsed.add((key, desc));
        }
      }
      _sort = parsed.take(_maxSorts).toList();
    }
  }

  void _savePrefs() {
    // A layout read that is still pending must not overwrite what the user just chose.
    _layoutEdited = true;
    final store = _store;
    if (widget.prefsKey == null || store == null) return;
    store
        .set(
          _prefsName,
          jsonEncode({
            'hidden': _hidden.toList()..sort(),
            'widths': _widths,
            if (_sortString != null) 'sort': _sortString,
          }),
        )
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    for (final n in _rowNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  int _generation = 0;

  Future<void> reload() => _fetch(reset: true);

  List<T> get _selectedList => widget.idOf == null
      ? const []
      : [
          for (final i in _items)
            if (_selected.contains(widget.idOf!(i))) i,
        ];

  Future<void> _fetch({required bool reset}) async {
    final generation = ++_generation;
    final q = _search.text.trim();
    final sort = _sortString;
    final filters = _filterSel;
    final queryKey = '$q\u0000${sort ?? ''}\u0000${filters.stableKey}';
    // The search or sort changed since these rows were loaded (a debounce still pending): the
    // next page of the new query must not be appended to the old rows.
    if (!reset && queryKey != _loadedKey) reset = true;
    var cleared = false;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        if (_lastQueryKey != null &&
            queryKey != _lastQueryKey &&
            _selected.isNotEmpty) {
          _selected.clear();
          _anchor = null;
          cleared = true;
        }
        _lastQueryKey = queryKey;
      }
    });
    if (cleared) _emitSelection();
    try {
      final offset = reset ? 0 : _items.length;
      // With rows selected, a reload of the same query refreshes everything loaded so far, so a
      // selected row on a later page is still found (and kept) afterwards.
      final keepSelection =
          reset && queryKey == _loadedKey && _selected.isNotEmpty;
      final limit = keepSelection
          ? math.min(math.max(_pageSize, _items.length), _maxRefresh)
          : _pageSize;
      final (items, total) = widget.loadQuery != null
          ? await widget.loadQuery!(
              ListQuery(
                search: q.isEmpty ? null : q,
                offset: offset,
                limit: limit,
                sort: sort,
                filters: filters.toQuery(),
              ),
            )
          : await widget.load!(q.isEmpty ? null : q, offset, limit);
      if (!mounted || generation != _generation) return;
      var pruned = false;
      setState(() {
        _items = reset ? items : [..._items, ...items];
        _total = total;
        if (reset) _loadedKey = queryKey;
        // Only prune when the reload covered the whole range that was loaded; a server that cut
        // the page short leaves the selection alone instead of dropping rows it did not return.
        final covered = items.length >= total || items.length >= limit;
        if (reset && covered && widget.idOf != null && _selected.isNotEmpty) {
          final present = {for (final i in items) widget.idOf!(i)};
          final before = _selected.length;
          _selected.removeWhere((id) => !present.contains(id));
          pruned = _selected.length != before;
          if (pruned) _anchor = null;
        }
      });
      if (pruned) _emitSelection();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), reload);
  }

  // ---- filters and favourites ----

  void _setFilters(FilterSelection next) {
    if (next == _filterSel) return;
    _debounce?.cancel();
    setState(() => _filterSel = next);
    reload();
  }

  void _removeLastChip() {
    final k = _filterSel.lastKey(widget.filterDefs);
    if (k != null) _setFilters(_filterSel.without(k));
  }

  KeyEventResult _searchKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        _search.text.isEmpty &&
        _filterSel.lastKey(widget.filterDefs) != null) {
      _removeLastChip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _storeFavourites(List<Favourite> next) async {
    final store = _store;
    if (widget.prefsKey == null ||
        store == null ||
        _favRead != _FavRead.ready) {
      return;
    }
    final previous = _favs;
    final seq = ++_favSeq;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _favs = next);
    try {
      await store.set(_favName, Favourite.encodeList(next));
    } catch (e) {
      if (!mounted) return;
      if (seq == _favSeq) setState(() => _favs = previous);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(errorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _saveFavourite() async {
    final name = await askFavouriteName(context);
    if (name == null || !mounted) return;
    _storeFavourites(
      Favourite.upsert(
        _favs,
        Favourite(
          name: name,
          search: _search.text.trim(),
          filters: _filterSel.sanitized(widget.filterDefs),
        ),
      ),
    );
  }

  void _applyFavourite(Favourite f) {
    final fav = f.sanitized(widget.filterDefs);
    _debounce?.cancel();
    setState(() {
      _search.text = fav.search;
      _filterSel = fav.filters;
    });
    reload();
  }

  Widget _filterMenu() => FilterMenuButton(
    defs: widget.filterDefs,
    selection: _filterSel,
    onToggle: (k, v) => _setFilters(_filterSel.toggle(k, v)),
    onClear: () => _setFilters(FilterSelection.empty),
    favourites: widget.prefsKey == null ? null : _favs,
    onSaveFavourite: _favRead == _FavRead.ready ? _saveFavourite : null,
    onRetryFavourites: _favRead == _FavRead.failed ? _retryFavourites : null,
    onApplyFavourite: _applyFavourite,
    onDeleteFavourite: (f) => _storeFavourites([
      for (final o in _favs)
        if (o.name != f.name) o,
    ]),
  );

  // ---- sorting ----

  void _tapSort(String key) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final i = _sort.indexWhere((s) => s.$1 == key);
    final next = [..._sort];
    if (shift) {
      if (i < 0) {
        if (next.length >= _maxSorts) return;
        next.add((key, false));
      } else if (!next[i].$2) {
        next[i] = (key, true);
      } else {
        next.removeAt(i);
      }
    } else if (i >= 0 && next.length == 1) {
      if (!next[0].$2) {
        next[0] = (key, true);
      } else {
        next.clear();
      }
    } else {
      next
        ..clear()
        ..add((key, false));
    }
    setState(() => _sort = next);
    _savePrefs();
    reload();
  }

  // ---- columns ----

  void _toggleColumn(String id) {
    setState(() {
      if (_hidden.contains(id)) {
        _hidden.remove(id);
      } else if (_visible.length > 1) {
        _hidden.add(id);
      }
    });
    _savePrefs();
  }

  void _resetLayout() {
    setState(() {
      _resetVisibility();
      _widths.clear();
    });
    _savePrefs();
  }

  void _resizeBy(String id, double dx) {
    setState(() {
      final cur = _widths[id] ?? _live[id] ?? _minColumnWidth;
      _widths[id] = math.max(_minColumnWidth, cur + dx);
      _live[id] = _widths[id]!;
    });
  }

  void _resetWidth(String id) {
    setState(() => _widths.remove(id));
    _savePrefs();
  }

  /// Width of each visible column for a row area of [inner] pixels: stored widths are fixed, the
  /// rest share what is left by their flex (never below the minimum).
  Map<String, double> _computeWidths(double inner) {
    final cols = _visible;
    var fixed = 0.0;
    var flexSum = 0;
    for (final c in cols) {
      final w = _widths[_cid(c)];
      if (w != null) {
        fixed += math.max(_minColumnWidth, w);
      } else {
        flexSum += c.flex;
      }
    }
    final left = math.max(0.0, inner - fixed);
    final result = <String, double>{};
    for (final c in cols) {
      final id = _cid(c);
      final w = _widths[id];
      result[id] = w != null
          ? math.max(_minColumnWidth, w)
          : math.max(_minColumnWidth, left * c.flex / math.max(1, flexSum));
    }
    _live.addAll(result);
    return result;
  }

  // ---- selection ----

  void _emitSelection() => widget.onSelectionChanged?.call(_selectedList);

  void _toggleRow(int i, bool on) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final id = widget.idOf!;
    setState(() {
      final anchor = _anchor;
      if (shift && anchor != null && anchor < _items.length) {
        for (var j = math.min(anchor, i); j <= math.max(anchor, i); j++) {
          on ? _selected.add(id(_items[j])) : _selected.remove(id(_items[j]));
        }
      } else {
        on ? _selected.add(id(_items[i])) : _selected.remove(id(_items[i]));
      }
      _anchor = i;
    });
    _emitSelection();
  }

  void _toggleAll() {
    final id = widget.idOf!;
    setState(() {
      final all =
          _items.isNotEmpty && _items.every((i) => _selected.contains(id(i)));
      for (final i in _items) {
        all ? _selected.remove(id(i)) : _selected.add(id(i));
      }
      _anchor = null;
    });
    _emitSelection();
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _anchor = null;
    });
    _emitSelection();
  }

  Future<void> _runBulk(BulkAction<T> a) async {
    final items = _selectedList;
    if (a.confirm != null) {
      final l = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(a.label),
          content: Text(a.confirm!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.listConfirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _bulkBusy = true);
    final ok = await runAction(context, () => a.run(items));
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      if (ok) {
        _selected.clear();
        _anchor = null;
      }
    });
    if (ok) _emitSelection();
    await reload();
  }

  // ---- build ----

  Widget _createButton(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: () => _after(widget.onCreate!()),
      icon: const Icon(AppIcons.add),
      label: Text(widget.createLabel ?? context.l10n.newItem),
    );
    final id = widget.createTargetId;
    return id == null ? button : TutorialTarget(id: id, child: button);
  }

  Future<void> _after(Future<bool?>? action) async {
    if (action != null && await action == true) await reload();
  }

  @override
  Widget build(BuildContext context) => GridKeyNav(
    include: _rowNodes.containsValue,
    scrollController: _scroll,
    enterFromOutside: true,
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final resizable = wide && widget.resizableColumns;
    final selecting = widget.selectable && _selected.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(widget.title, style: theme.textTheme.headlineSmall),
              const Spacer(),
              for (final a in widget.actions)
                Padding(padding: const EdgeInsets.only(right: 8), child: a),
              if (widget.onCreate != null) _createButton(context),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: Icon(AppIcons.search),
                    hintText: context.l10n.search,
                  ),
                ),
              ),
              if (widget.filterDefs.isNotEmpty) ...[
                const SizedBox(width: 4),
                _filterMenu(),
              ],
              if (widget.filters != null) ...[
                const SizedBox(width: 12),
                widget.filters!,
              ],
              const SizedBox(width: 12),
              if (selecting && wide)
                Flexible(flex: 2, child: _bulkBar(theme))
              else if (!selecting)
                Text(
                  context.l10n.countOf(_items.length, _total),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (widget.filterDefs.isNotEmpty && _filterSel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChips(
                  defs: widget.filterDefs,
                  selection: _filterSel,
                  onRemove: (k) => _setFilters(_filterSel.without(k)),
                ),
              ),
            ),
          if (selecting && !wide) ...[
            const SizedBox(height: 8),
            _bulkBar(theme),
          ],
          if (widget.moreFilters != null) ...[
            const SizedBox(height: 8),
            widget.moreFilters!,
          ],
          const SizedBox(height: 8),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: reload, child: Text(context.l10n.retry)),
              ],
            ),
          if (_loading) const LinearProgressIndicator(),
          if (resizable)
            Expanded(child: _resizableArea(theme))
          else ...[
            if (wide) _header(theme, null),
            ?_empty(),
            Expanded(child: _list(wide, null)),
          ],
        ],
      ),
    );
  }

  Widget? _empty() {
    if (widget.emptyText == null ||
        _loading ||
        _error != null ||
        _items.isNotEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.emptyText!, textAlign: TextAlign.center),
            if (widget.emptyAction != null) widget.emptyAction!,
          ],
        ),
      ),
    );
  }

  Widget _resizableArea(ThemeData theme) => LayoutBuilder(
    builder: (context, cons) {
      final extras =
          (widget.selectable ? _selectWidth : 0) + (_hasMenu ? _menuWidth : 0);
      final widths = _computeWidths(cons.maxWidth - 24 - extras);
      final total =
          widths.values.fold<double>(0, (a, b) => a + b) + 24 + extras;
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme, widths),
          ?_empty(),
          Expanded(child: _list(true, widths)),
        ],
      );
      if (total <= cons.maxWidth + 0.5) return body;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: total, height: cons.maxHeight, child: body),
      );
    },
  );

  Widget _list(bool wide, Map<String, double>? widths) => ListView.separated(
    controller: _scroll,
    itemCount: _items.length + 1,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) {
      if (i == _items.length) return _footer();
      final item = _items[i];
      final selecting = widget.selectable && _selected.isNotEmpty;
      final onTap = widget.selectable && selecting && !wide
          ? () => _toggleRow(i, !_isSelected(item))
          : (widget.onOpen == null ? null : () => _after(widget.onOpen!(item)));
      final node = _rowNodes.putIfAbsent(i, FocusNode.new);
      final row = wide
          ? _row(i, item, onTap, node, widths)
          : _tile(i, item, onTap, node);
      return OpenInTab(location: widget.locationOf?.call(item), child: row);
    },
  );

  bool _isSelected(T item) =>
      widget.idOf != null && _selected.contains(widget.idOf!(item));

  Widget _cell(EntityColumn<T> c, Widget child, [double? width]) {
    final aligned = Align(
      alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    return width == null
        ? Expanded(flex: c.flex, child: aligned)
        : SizedBox(width: width, child: aligned);
  }

  Widget _headerCell(ThemeData theme, EntityColumn<T> c) {
    final label = Text(
      c.label,
      style: theme.textTheme.labelLarge,
      overflow: TextOverflow.ellipsis,
    );
    final key = c.sortKey;
    if (key == null) {
      return widget.resizableColumns
          ? label
          : Text(c.label, style: theme.textTheme.labelLarge);
    }
    final l = context.l10n;
    final idx = _sort.indexWhere((s) => s.$1 == key);
    final desc = idx < 0 ? null : _sort[idx].$2;
    final state = desc == null
        ? l.listNotSorted
        : (desc ? l.listSortedDescending : l.listSortedAscending);
    return Semantics(
      button: true,
      label: '${c.label}, $state',
      excludeSemantics: true,
      onTap: () => _tapSort(key),
      child: Tooltip(
        message: l.listSortBy(c.label),
        child: InkWell(
          onTap: () => _tapSort(key),
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: label),
                  if (desc != null) ...[
                    const SizedBox(width: 2),
                    Icon(
                      desc ? AppIcons.arrowDownward : AppIcons.arrowUpward,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    if (_sort.length > 1)
                      Text(
                        '${idx + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectAllBox() {
    final id = widget.idOf!;
    final n = _items.where((i) => _selected.contains(id(i))).length;
    final all = _items.isNotEmpty && n == _items.length;
    final l = context.l10n;
    return SizedBox(
      width: _selectWidth,
      child: Center(
        child: Semantics(
          label: l.listSelectAll,
          child: Tooltip(
            message: l.listSelectAll,
            child: Checkbox(
              tristate: true,
              value: all ? true : (n == 0 ? false : null),
              onChanged: _items.isEmpty ? null : (_) => _toggleAll(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _columnsMenu() {
    final l = context.l10n;
    final visible = _visible;
    return SizedBox(
      width: _menuWidth,
      child: PopupMenuButton<String>(
        tooltip: l.listColumns,
        icon: const Icon(AppIcons.tune),
        onSelected: (v) {
          if (v == '\u0000reset') {
            _resetLayout();
          } else {
            _toggleColumn(v);
          }
        },
        itemBuilder: (_) => [
          for (final c in widget.columns)
            CheckedPopupMenuItem<String>(
              value: _cid(c),
              checked: !_hidden.contains(_cid(c)),
              enabled:
                  c.hideable && !(visible.length == 1 && visible.first == c),
              child: Text(c.label),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '\u0000reset',
            child: Text(l.listResetLayout),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, Map<String, double>? widths) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        if (widget.selectable) _selectAllBox(),
        for (final c in _visible)
          _cell(
            c,
            widths == null
                ? _headerCell(theme, c)
                : _resizableHeaderCell(theme, c, widths[_cid(c)]!),
            widths?[_cid(c)],
          ),
        if (_hasMenu) _columnsMenu(),
      ],
    ),
  );

  Widget _resizableHeaderCell(ThemeData theme, EntityColumn<T> c, double w) {
    final id = _cid(c);
    return SizedBox(
      width: w,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Align(
              alignment: c.numeric
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: _headerCell(theme, c),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _ResizeHandle(
              label: context.l10n.listResizeColumn(c.label),
              onDelta: (dx) => _resizeBy(id, dx),
              onEnd: _savePrefs,
              onReset: () => _resetWidth(id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkbox(int i, T item) => SizedBox(
    width: _selectWidth,
    child: Center(
      child: Semantics(
        label: context.l10n.listSelectRow(widget.columns.first.value(item)),
        child: Checkbox(
          value: _isSelected(item),
          onChanged: (v) => _toggleRow(i, v ?? false),
        ),
      ),
    ),
  );

  Widget _row(
    int i,
    T item,
    VoidCallback? onTap,
    FocusNode node,
    Map<String, double>? widths,
  ) {
    final ink = InkWell(
      focusNode: node,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (widget.selectable) _checkbox(i, item),
            for (final c in _visible)
              _cell(
                c,
                c.cell?.call(context, item) ??
                    Text(
                      c.value(item),
                      overflow: TextOverflow.ellipsis,
                      style: c.numeric
                          ? const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            )
                          : null,
                    ),
                widths?[_cid(c)],
              ),
            if (_hasMenu) const SizedBox(width: _menuWidth),
          ],
        ),
      ),
    );
    if (!widget.selectable) return ink;
    return Material(
      color: _isSelected(item)
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.space &&
              identical(FocusManager.instance.primaryFocus, node)) {
            _toggleRow(i, !_isSelected(item));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ink,
      ),
    );
  }

  Widget _tile(int i, T item, VoidCallback? onTap, FocusNode node) {
    final cols = _visible.isEmpty ? widget.columns : _visible;
    final titleCol = cols.length > 1 ? cols[1] : cols[0];
    final selecting = widget.selectable && _selected.isNotEmpty;
    final selected = _isSelected(item);
    final tile = ListTile(
      focusNode: node,
      onTap: onTap,
      onLongPress: widget.selectable && !selecting
          ? () => _toggleRow(i, true)
          : null,
      minTileHeight: widget.selectable ? 56 : null,
      selected: selected,
      leading: selecting
          ? Semantics(
              label: context.l10n.listSelectRow(titleCol.value(item)),
              child: Checkbox(
                value: selected,
                onChanged: (v) => _toggleRow(i, v ?? false),
              ),
            )
          : null,
      title: Text(titleCol.value(item)),
      subtitle: Text(
        cols
            .where((c) => c != titleCol)
            .map((c) => c.value(item))
            .where((s) => s.isNotEmpty)
            .join(' · '),
      ),
    );
    return tile;
  }

  Widget _bulkBar(ThemeData theme) {
    final l = context.l10n;
    final sel = _selectedList;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          l.listSelectedCount(sel.length),
          style: theme.textTheme.labelLarge,
        ),
        IconButton(
          tooltip: l.listClearSelection,
          icon: const Icon(AppIcons.close),
          onPressed: _clearSelection,
        ),
        for (final a in widget.bulkActions)
          TextButton.icon(
            onPressed: _bulkBusy || !(a.enabled?.call(sel) ?? true)
                ? null
                : () => _runBulk(a),
            icon: Icon(a.icon),
            label: Text(a.label),
          ),
      ],
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(
      child: _items.length < _total
          ? TextButton(
              onPressed: _loading ? null : () => _fetch(reset: false),
              child: Text(context.l10n.loadMore),
            )
          : const SizedBox.shrink(),
    ),
  );
}

/// The drag handle on a column border: drag or Left/Right to resize, double-click to reset.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.label,
    required this.onDelta,
    required this.onEnd,
    required this.onReset,
  });
  final String label;
  final void Function(double dx) onDelta;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _focused || _hover;
    return Semantics(
      label: widget.label,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (_, e) {
          if (e is KeyUpEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft ||
              k == LogicalKeyboardKey.arrowRight) {
            widget.onDelta(k == LogicalKeyboardKey.arrowLeft ? -16 : 16);
            widget.onEnd();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.enter) {
            widget.onReset();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => widget.onDelta(d.delta.dx),
            onHorizontalDragEnd: (_) => widget.onEnd(),
            onDoubleTap: widget.onReset,
            child: SizedBox(
              width: 12,
              child: Center(
                child: Container(
                  width: active ? 3 : 1,
                  color: active ? cs.primary : cs.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
