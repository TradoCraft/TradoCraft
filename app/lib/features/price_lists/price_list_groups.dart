import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import 'price_lists_api.dart';

/// A group with its depth (0 = chapter) in the depth-first order of the tree.
typedef GroupNode = ({PriceListGroup group, int depth});

int _compareGroups(PriceListGroup a, PriceListGroup b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// The children of [parentId] in print order.
List<PriceListGroup> childrenOf(List<PriceListGroup> all, String? parentId) =>
    [
      for (final g in all)
        if (g.parentId == parentId) g,
    ]..sort(_compareGroups);

/// The groups depth-first, each with its depth. Groups whose parent is missing are ignored.
List<GroupNode> flattenGroups(List<PriceListGroup> all) {
  final out = <GroupNode>[];
  void walk(String? parent, int depth) {
    for (final g in childrenOf(all, parent)) {
      out.add((group: g, depth: depth));
      if (depth < 16) walk(g.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

/// Levels of [g] and everything below it (a group without children is 1).
int subtreeHeight(List<PriceListGroup> all, PriceListGroup g) {
  var h = 0;
  for (final c in childrenOf(all, g.id)) {
    final ch = subtreeHeight(all, c);
    if (ch > h) h = ch;
  }
  return h + 1;
}

/// The depth of [g] counted from 1 for a chapter.
int levelOf(List<PriceListGroup> all, PriceListGroup g) {
  var level = 1;
  var p = g.parentId;
  while (p != null && level < 20) {
    level++;
    p = all.where((x) => x.id == p).firstOrNull?.parentId;
  }
  return level;
}

/// The title of [g] for display: [lang], else the first language that has one.
String groupTitle(PriceListGroup g, String lang) {
  final t = g.title[lang];
  if (t != null && t.isNotEmpty) return t;
  for (final v in g.title.values) {
    if (v.isNotEmpty) return v;
  }
  return '—';
}

final _digits = RegExp(r'^[0-9]+$');

/// Orders dotted sort keys like the server: an empty key first; segment by segment, numbers
/// numerically and before text, text case-insensitively (then case-sensitively); a key before the
/// keys it is a prefix of.
int compareSortKeys(String a, String b) {
  if (a.isEmpty || b.isEmpty) {
    return a.isEmpty == b.isEmpty ? 0 : (a.isEmpty ? -1 : 1);
  }
  final x = a.split('.'), y = b.split('.');
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = _digits.hasMatch(x[i]) ? BigInt.parse(x[i]) : null;
    final ny = _digits.hasMatch(y[i]) ? BigInt.parse(y[i]) : null;
    final int c;
    if (nx != null && ny != null) {
      c = nx.compareTo(ny);
    } else if (nx != null) {
      c = -1;
    } else if (ny != null) {
      c = 1;
    } else {
      final ci = x[i].toLowerCase().compareTo(y[i].toLowerCase());
      c = ci != 0 ? ci : x[i].compareTo(y[i]);
    }
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// What the group editor needs to write a group back.
PriceListGroupInput groupInput(
  PriceListGroup g, {
  Object? parentId = _keep,
  int? sortOrder,
  Map<String, String>? title,
  bool? pageBreak,
  bool? showTitle,
  String? gapMm,
}) {
  final parent = identical(parentId, _keep) ? g.parentId : parentId as String?;
  return PriceListGroupInput(
    parentId: parent,
    sortOrder: sortOrder ?? g.sortOrder,
    title: title ?? g.title,
    pageBreak: pageBreak ?? g.pageBreak,
    showTitle: showTitle ?? g.showTitle,
    gapMm: gapMm ?? g.gapMm,
  );
}

const Object _keep = Object();

/// The tree of groups of one list with its editing actions.
class PriceListGroupsPanel extends ConsumerWidget {
  const PriceListGroupsPanel({
    super.key,
    required this.list,
    required this.groups,
    required this.canWrite,
  });

  final PriceList list;
  final List<PriceListGroup> groups;
  final bool canWrite;

  String get _lang => list.publishedLanguages.first;

  void _refresh(WidgetRef ref) {
    ref.invalidate(priceListGroupsProvider(list.id));
    ref.invalidate(priceListItemsProvider(list.id));
    ref.invalidate(priceListExportsProvider(list.id));
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(ProductsClient api) action,
  ) async {
    final api = ref.read(apiProvider).products;
    await runAction(context, () => action(api));
    if (context.mounted) _refresh(ref);
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup? parent,
  ) async {
    if (parent != null && levelOf(groups, parent) >= maxGroupDepth) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.plDepthMax)));
      return;
    }
    final edited = await showDialog<GroupEdit>(
      context: context,
      builder: (_) => GroupDialog(languages: list.publishedLanguages, parent: parent),
    );
    if (edited == null || !context.mounted) return;
    final siblings = childrenOf(groups, parent?.id);
    final next = siblings.isEmpty ? 10 : siblings.last.sortOrder + 10;
    await _run(
      context,
      ref,
      (api) async => api.createGroup(
        id: list.id,
        body: PriceListGroupInput(
          parentId: parent?.id,
          sortOrder: next,
          title: edited.title,
          pageBreak: edited.pageBreak,
          showTitle: edited.showTitle,
          gapMm: edited.gapMm,
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup g,
  ) async {
    final edited = await showDialog<GroupEdit>(
      context: context,
      builder: (_) => GroupDialog(languages: list.publishedLanguages, group: g),
    );
    if (edited == null || !context.mounted) return;
    await _run(
      context,
      ref,
      (api) async => api.updateGroup(
        id: list.id,
        groupId: g.id,
        body: groupInput(
          g,
          title: edited.title,
          pageBreak: edited.pageBreak,
          showTitle: edited.showTitle,
          gapMm: edited.gapMm,
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup g,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.plDeleteGroupConfirm(groupTitle(g, _lang))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('plg-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final api = ref.read(apiProvider).products;
    try {
      await api.deleteGroup(id: list.id, groupId: g.id);
      if (context.mounted) _refresh(ref);
    } catch (e) {
      if (!context.mounted) return;
      if (e is DioException && e.response?.statusCode == 409) {
        // The server names the export profiles that still use the group.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.plGroupInUseTitle),
            content: SelectableText(
              key: const ValueKey('plg-in-use'),
              errorMessage(e),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.close),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Swaps [g] with its neighbour and renumbers the siblings 10, 20, 30 ...
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup g,
    int delta,
  ) async {
    final sibs = childrenOf(groups, g.parentId);
    final i = sibs.indexWhere((s) => s.id == g.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= sibs.length) return;
    final order = [...sibs];
    order.insert(j, order.removeAt(i));
    await _run(context, ref, (api) async {
      for (var n = 0; n < order.length; n++) {
        final want = (n + 1) * 10;
        if (order[n].sortOrder != want) {
          await api.updateGroup(
            id: list.id,
            groupId: order[n].id,
            body: groupInput(order[n], sortOrder: want),
          );
        }
      }
    });
  }

  /// Makes [g] the last subgroup of the group above it.
  Future<void> _indent(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup g,
  ) async {
    final sibs = childrenOf(groups, g.parentId);
    final i = sibs.indexWhere((s) => s.id == g.id);
    if (i <= 0) return;
    final target = sibs[i - 1];
    if (levelOf(groups, target) + subtreeHeight(groups, g) > maxGroupDepth) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.plDepthMax)));
      return;
    }
    final kids = childrenOf(groups, target.id);
    await _run(
      context,
      ref,
      (api) async => api.updateGroup(
        id: list.id,
        groupId: g.id,
        body: groupInput(
          g,
          parentId: target.id,
          sortOrder: kids.isEmpty ? 10 : kids.last.sortOrder + 10,
        ),
      ),
    );
  }

  /// Moves [g] next to its parent, right after it.
  Future<void> _outdent(
    BuildContext context,
    WidgetRef ref,
    PriceListGroup g,
  ) async {
    final parent = groups.where((x) => x.id == g.parentId).firstOrNull;
    if (parent == null) return;
    final sibs = childrenOf(groups, parent.parentId);
    final after = sibs.where((s) => s.sortOrder > parent.sortOrder).toList();
    await _run(context, ref, (api) async {
      // Room for one more between the parent and the next sibling: renumber from the parent on.
      var n = parent.sortOrder;
      await api.updateGroup(
        id: list.id,
        groupId: g.id,
        body: groupInput(g, parentId: parent.parentId, sortOrder: n + 1),
      );
      for (final s in after) {
        if (s.sortOrder <= n + 1) {
          n = n + 2;
          await api.updateGroup(
            id: list.id,
            groupId: s.id,
            body: groupInput(s, sortOrder: n),
          );
        } else {
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final nodes = flattenGroups(groups);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.plGroups,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (canWrite)
                  FilledButton.tonalIcon(
                    key: const ValueKey('plg-add'),
                    onPressed: () => _add(context, ref, null),
                    icon: const Icon(AppIcons.add),
                    label: Text(l.plAddGroup),
                  ),
              ],
            ),
            if (nodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l.plNoGroups),
              ),
            for (final n in nodes) _row(context, ref, n, nodes),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    GroupNode n,
    List<GroupNode> nodes,
  ) {
    final l = context.l10n;
    final g = n.group;
    final sibs = childrenOf(groups, g.parentId);
    final i = sibs.indexWhere((s) => s.id == g.id);
    final tag = g.id;
    Widget btn(String key, String tip, IconData icon, VoidCallback? on) =>
        IconButton(
          key: ValueKey('plg-$key-$tag'),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          onPressed: on,
        );
    return Padding(
      key: ValueKey('plg-row-$tag'),
      padding: EdgeInsets.only(left: n.depth * 20.0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 320),
            child: Text(
              groupTitle(g, _lang),
              style: g.showTitle
                  ? null
                  : const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
          if (g.pageBreak) const Icon(Icons.insert_page_break_outlined, size: 16),
          if (!g.showTitle)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${l.plTitleHidden} · ${g.gapMm} mm'),
            ),
          if (canWrite) ...[
            btn('up', l.moveUp, AppIcons.arrowUpward,
                i > 0 ? () => _move(context, ref, g, -1) : null),
            btn('down', l.moveDown, AppIcons.arrowDownward,
                i < sibs.length - 1 ? () => _move(context, ref, g, 1) : null),
            btn('in', l.plIndent, Icons.format_indent_increase,
                i > 0 ? () => _indent(context, ref, g) : null),
            btn('out', l.plOutdent, Icons.format_indent_decrease,
                g.parentId != null ? () => _outdent(context, ref, g) : null),
            btn('sub', l.plAddSubgroup, AppIcons.subdirectoryArrowRight,
                () => _add(context, ref, g)),
            btn('edit', l.edit, Icons.edit_outlined, () => _edit(context, ref, g)),
            btn('del', l.delete, Icons.delete_outline,
                () => _delete(context, ref, g)),
          ],
        ],
      ),
    );
  }
}

/// The result of the group dialog.
typedef GroupEdit = ({
  Map<String, String> title,
  bool pageBreak,
  bool showTitle,
  String gapMm,
});

/// Title per language, page break, print-title switch and the gap used when the title is hidden.
class GroupDialog extends StatefulWidget {
  const GroupDialog({
    super.key,
    required this.languages,
    this.group,
    this.parent,
  });

  final List<String> languages;
  final PriceListGroup? group;

  /// The parent of a new group (null: a top-level group).
  final PriceListGroup? parent;

  @override
  State<GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<GroupDialog> {
  late final Map<String, TextEditingController> _titles = {
    for (final c in widget.languages)
      c: TextEditingController(text: widget.group?.title[c] ?? ''),
  };
  late final _gap = TextEditingController(text: widget.group?.gapMm ?? '0');
  late bool _pageBreak = widget.group?.pageBreak ?? false;
  late bool _showTitle = widget.group?.showTitle ?? true;
  String? _error;

  @override
  void dispose() {
    for (final c in _titles.values) {
      c.dispose();
    }
    _gap.dispose();
    super.dispose();
  }

  void _ok() {
    final l = context.l10n;
    // Titles in languages the list does not use are kept as they are.
    final title = <String, String>{
      ...?widget.group?.title,
      for (final e in _titles.entries) e.key: e.value.text.trim(),
    }..removeWhere((_, v) => v.isEmpty);
    if (title.isEmpty) {
      setState(() => _error = l.plGroupTitleRequired);
      return;
    }
    final gap = double.tryParse(_gap.text.trim().replaceAll(',', '.'));
    if (!_showTitle && (gap == null || gap < 0 || gap > 50)) {
      setState(() => _error = l.plGapInvalid);
      return;
    }
    Navigator.pop<GroupEdit>(context, (
      title: title,
      pageBreak: _pageBreak,
      showTitle: _showTitle,
      // Kept as it was while the title is printed (the server ignores it then).
      gapMm: _showTitle || gap == null ? (widget.group?.gapMm ?? '0') : gap.toStringAsFixed(2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.plGroupTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in _titles.entries)
                TextField(
                  key: ValueKey('plg-title-${e.key}'),
                  controller: e.value,
                  autofocus: e.key == widget.languages.first,
                  decoration: InputDecoration(
                    labelText: '${l.plGroupTitle} (${languageName(e.key)})',
                  ),
                ),
              SwitchListTile(
                key: const ValueKey('plg-page-break'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.plPageBreak),
                value: _pageBreak,
                onChanged: (v) => setState(() => _pageBreak = v),
              ),
              SwitchListTile(
                key: const ValueKey('plg-show-title'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.plShowTitle),
                value: _showTitle,
                onChanged: (v) => setState(() => _showTitle = v),
              ),
              TextField(
                key: const ValueKey('plg-gap'),
                controller: _gap,
                enabled: !_showTitle,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l.plGapMm),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('plg-ok'),
          onPressed: _ok,
          child: Text(l.save),
        ),
      ],
    );
  }
}
