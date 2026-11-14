import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../app/workspace.dart' show OpenInTab;
import '../l10n/l10n.dart';
import '../features/tutorial/targets.dart';
import 'app_icons.dart';

/// Column of a generic entity list.
class EntityColumn<T> {
  const EntityColumn(
    this.label,
    this.value, {
    this.numeric = false,
    this.flex = 1,
    this.cell,
  });
  final String label;
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

/// Searchable, paged list used for every master-data and document list.
///
/// One widget, configured per entity, instead of a hand-written screen per table.
/// [onOpen] and [onCreate] return `true` when data changed, which reloads the list.
class EntityList<T> extends StatefulWidget {
  const EntityList({
    super.key,
    required this.title,
    required this.load,
    required this.columns,
    this.onOpen,
    this.locationOf,
    this.onCreate,
    this.createLabel,
    this.createTargetId,
    this.filters,
    this.moreFilters,
    this.actions = const [],
    this.emptyText,
    this.emptyAction,
  });

  final String title;
  final PageLoader<T> load;
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

class EntityListState<T> extends State<EntityList<T>> {
  static const _pageSize = 50;
  final _search = TextEditingController();
  Timer? _debounce;
  List<T> _items = [];
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  int _generation = 0;

  Future<void> reload() => _fetch(reset: true);

  Future<void> _fetch({required bool reset}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final (items, total) = await widget.load(
        q.isEmpty ? null : q,
        reset ? 0 : _items.length,
        _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = reset ? items : [..._items, ...items];
        _total = total;
      });
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
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
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: Icon(AppIcons.search),
                    hintText: context.l10n.search,
                  ),
                ),
              ),
              if (widget.filters != null) ...[
                const SizedBox(width: 12),
                widget.filters!,
              ],
              const SizedBox(width: 12),
              Text(context.l10n.countOf(_items.length, _total)),
            ],
          ),
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
          if (wide) _header(theme),
          if (widget.emptyText != null &&
              !_loading &&
              _error == null &&
              _items.isEmpty)
            Padding(
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
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == _items.length) return _footer();
                final item = _items[i];
                final onTap = widget.onOpen == null
                    ? null
                    : () => _after(widget.onOpen!(item));
                final row = wide ? _row(item, onTap) : _tile(item, onTap);
                return OpenInTab(
                  location: widget.locationOf?.call(item),
                  child: row,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(EntityColumn<T> c, Widget child) => Expanded(
    flex: c.flex,
    child: Align(
      alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    ),
  );

  Widget _header(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        for (final c in widget.columns)
          _cell(c, Text(c.label, style: theme.textTheme.labelLarge)),
      ],
    ),
  );

  Widget _row(T item, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final c in widget.columns)
            _cell(
              c,
              c.cell?.call(context, item) ??
                  Text(c.value(item), overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    ),
  );

  Widget _tile(T item, VoidCallback? onTap) {
    final cols = widget.columns;
    return ListTile(
      onTap: onTap,
      title: Text(cols.length > 1 ? cols[1].value(item) : cols[0].value(item)),
      subtitle: Text(
        cols
            .where((c) => c != cols[1])
            .map((c) => c.value(item))
            .where((s) => s.isNotEmpty)
            .join(' · '),
      ),
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
