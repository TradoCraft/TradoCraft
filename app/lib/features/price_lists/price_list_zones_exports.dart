import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import 'price_list_groups.dart';
import 'price_lists_api.dart';

/// Body of `PUT /price-lists/{id}/zones` for [zones] in their current order.
List<PriceListZoneInput> zoneInputs(List<PriceListZone> zones) => [
  for (final z in zones)
    PriceListZoneInput(priceZoneId: z.priceZoneId, languages: z.languages),
];

/// The zones a list is published for, in print order, with the languages of each.
class ZonesPanel extends ConsumerStatefulWidget {
  const ZonesPanel({super.key, required this.list, required this.canWrite});
  final PriceList list;
  final bool canWrite;

  @override
  ConsumerState<ZonesPanel> createState() => _ZonesPanelState();
}

class _ZonesPanelState extends ConsumerState<ZonesPanel> {
  String? _toAdd;

  /// True from the click until the refreshed list has arrived: a second edit built from the old
  /// list would overwrite the first, so the zone controls stay disabled meanwhile.
  bool _saving = false;

  List<PriceListZone> get _zones => [...widget.list.zones]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<void> _save(List<PriceListZoneInput> body) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final id = widget.list.id;
      final ok = await runAction(
        context,
        () => ref.read(apiProvider).products.replaceZones(id: id, body: body),
      );
      if (ok && mounted) {
        ref.invalidate(priceListsProvider);
        ref.invalidate(priceListProvider(id));
        try {
          await ref.read(priceListProvider(id).future);
        } catch (_) {
          // The page shows its own load error.
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setLanguage(int i, String code, bool on) {
    final body = zoneInputs(_zones);
    final cur = body[i].languages;
    final next = on ? [...cur, code] : cur.where((c) => c != code).toList();
    // Keep the app's order; the first language is the zone's default.
    body[i] = PriceListZoneInput(
      priceZoneId: body[i].priceZoneId,
      languages: [
        for (final c in priceListLanguages)
          if (next.contains(c)) c,
      ],
    );
    return _save(body);
  }

  Future<void> _move(int i, int delta) {
    final body = zoneInputs(_zones);
    final j = i + delta;
    if (j < 0 || j >= body.length) return Future.value();
    body.insert(j, body.removeAt(i));
    return _save(body);
  }

  Future<void> _remove(int i) {
    final body = zoneInputs(_zones)..removeAt(i);
    return _save(body);
  }

  Future<void> _add() async {
    final id = _toAdd;
    if (id == null) return;
    final zones = _zones;
    final body = zoneInputs(zones)
      ..add(
        PriceListZoneInput(
          priceZoneId: id,
          languages: zones.isEmpty ? const ['nl'] : zones.first.languages,
        ),
      );
    setState(() => _toAdd = null);
    await _save(body);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zones = _zones;
    final all = ref.watch(priceZonesProvider).value ?? const <PriceZone>[];
    final free = [
      for (final z in all)
        if (!zones.any((x) => x.priceZoneId == z.id)) z,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.plZones, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.plZonesHint, style: Theme.of(context).textTheme.bodySmall),
            if (zones.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.plNoZones, key: const ValueKey('plz-none')),
              ),
            for (var i = 0; i < zones.length; i++)
              Padding(
                key: ValueKey('plz-${zones[i].priceZoneCode}'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: Text(
                        '${zones[i].priceZoneCode}  ${zones[i].priceZoneName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final c in priceListLanguages)
                      FilterChip(
                        key: ValueKey('plz-${zones[i].priceZoneCode}-$c'),
                        label: Text(c.toUpperCase()),
                        tooltip: languageName(c),
                        selected: zones[i].languages.contains(c),
                        // A zone keeps at least one language.
                        onSelected:
                            !widget.canWrite ||
                                _saving ||
                                (zones[i].languages.length == 1 &&
                                    zones[i].languages.contains(c))
                            ? null
                            : (on) => _setLanguage(i, c, on),
                      ),
                    if (widget.canWrite) ...[
                      IconButton(
                        key: ValueKey('plz-up-${zones[i].priceZoneCode}'),
                        tooltip: l.moveUp,
                        icon: const Icon(AppIcons.arrowUpward),
                        onPressed: _saving || i == 0 ? null : () => _move(i, -1),
                      ),
                      IconButton(
                        key: ValueKey('plz-down-${zones[i].priceZoneCode}'),
                        tooltip: l.moveDown,
                        icon: const Icon(AppIcons.arrowDownward),
                        onPressed: _saving || i == zones.length - 1
                            ? null
                            : () => _move(i, 1),
                      ),
                      IconButton(
                        key: ValueKey('plz-del-${zones[i].priceZoneCode}'),
                        tooltip: l.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _saving ? null : () => _remove(i),
                      ),
                    ],
                  ],
                ),
              ),
            if (widget.canWrite && free.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('plz-pick'),
                      initialValue: free.any((z) => z.id == _toAdd)
                          ? _toAdd
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.priceZone),
                      items: [
                        for (final z in free)
                          DropdownMenuItem(
                            value: z.id,
                            child: Text('${z.code}  ${z.name}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _toAdd = v),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('plz-add'),
                    onPressed: _saving || _toAdd == null ? null : _add,
                    icon: const Icon(AppIcons.add),
                    label: Text(l.plAddZone),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholders a file name template may use.
const exportFilePlaceholders = ['{list}', '{zone}', '{lang}', '{name}', '{code}'];

/// The export profiles of a list: which chapters go into which file.
class ExportsPanel extends ConsumerWidget {
  const ExportsPanel({
    super.key,
    required this.list,
    required this.groups,
    required this.canWrite,
  });

  final PriceList list;
  final List<PriceListGroup> groups;
  final bool canWrite;

  String get _lang => list.publishedLanguages.first;

  List<PriceListGroup> get _chapters => groups;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PriceListExport? profile,
  ]) async {
    final body = await showDialog<PriceListExportInput>(
      context: context,
      builder: (_) =>
          ExportDialog(profile: profile, chapters: _chapters, lang: _lang),
    );
    if (body == null || !context.mounted) return;
    final products = ref.read(apiProvider).products;
    final ok = await runAction(
      context,
      () async => profile == null
          ? await products.createExport(id: list.id, body: body)
          : await products.updateExport(
              id: list.id,
              exportId: profile.id,
              body: body,
            ),
      success: context.l10n.saved,
    );
    if (ok) ref.invalidate(priceListExportsProvider(list.id));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PriceListExport e,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.plExportDeleteConfirm(e.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('ple-exp-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .products
          .deleteExport(id: list.id, exportId: e.id),
    );
    if (ok) ref.invalidate(priceListExportsProvider(list.id));
  }

  Future<void> _perChapter(BuildContext context, WidgetRef ref) async {
    final level = await showDialog<int>(
      context: context,
      builder: (_) => const PerLevelDialog(),
    );
    if (level == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .products
          .createPerChapterExports(id: list.id, level: level),
      success: context.l10n.saved,
    );
    if (ok) ref.invalidate(priceListExportsProvider(list.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final exports = ref.watch(priceListExportsProvider(list.id));
    final titles = {for (final g in groups) g.id: groupTitle(g, _lang)};
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
                    l.plExports,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (canWrite) ...[
                  OutlinedButton(
                    key: const ValueKey('ple-exp-per-chapter'),
                    onPressed: _chapters.isEmpty
                        ? null
                        : () => _perChapter(context, ref),
                    child: Text(l.plPerChapter),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    key: const ValueKey('ple-exp-add'),
                    onPressed: () => _edit(context, ref),
                    icon: const Icon(AppIcons.add),
                    label: Text(l.plAddExport),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(l.plExportsHint, style: Theme.of(context).textTheme.bodySmall),
            exports.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Row(
                children: [
                  Expanded(child: Text(errorMessage(e))),
                  TextButton(
                    key: const ValueKey('ple-exp-retry'),
                    onPressed: () =>
                        ref.invalidate(priceListExportsProvider(list.id)),
                    child: Text(l.retry),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l.plNoExports,
                        key: const ValueKey('ple-exp-none'),
                      ),
                    )
                  : Column(
                      children: [
                        for (final e in items)
                          ListTile(
                            key: ValueKey('ple-exp-${e.code}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text('${e.name}  (${e.code})'),
                            subtitle: Text(
                              [
                                e.groupIds.isEmpty
                                    ? l.plWholeList
                                    : e.groupIds
                                          .map((g) => titles[g] ?? g)
                                          .join(', '),
                                if (e.fileName != null && e.fileName!.isNotEmpty)
                                  e.fileName!,
                              ].join(' · '),
                            ),
                            trailing: canWrite
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: ValueKey('ple-exp-edit-${e.code}'),
                                        tooltip: l.edit,
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _edit(context, ref, e),
                                      ),
                                      IconButton(
                                        key: ValueKey('ple-exp-del-${e.code}'),
                                        tooltip: l.delete,
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () =>
                                            _delete(context, ref, e),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create ([profile] null) or edit dialog of an export profile; pops the [PriceListExportInput].
class ExportDialog extends StatefulWidget {
  const ExportDialog({
    super.key,
    this.profile,
    required this.chapters,
    required this.lang,
  });
  final PriceListExport? profile;

  /// All groups of the list; shown as an indented tree.
  final List<PriceListGroup> chapters;
  final String lang;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late final _name = TextEditingController(text: widget.profile?.name);
  late final _code = TextEditingController(text: widget.profile?.code);
  late final _file = TextEditingController(text: widget.profile?.fileName);
  late final Set<String> _groups = {...?widget.profile?.groupIds};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _file.dispose();
    super.dispose();
  }

  void _save() {
    final l = context.l10n;
    final code = _code.text.trim();
    if (_name.text.trim().isEmpty || code.isEmpty) {
      setState(() => _error = l.codeNameRequired);
      return;
    }
    if (code.length > 32) {
      setState(() => _error = l.plExportCodeLength);
      return;
    }
    final file = _file.text.trim();
    Navigator.pop(
      context,
      PriceListExportInput(
        code: code,
        name: _name.text.trim(),
        // Print order, whatever the order of ticking was.
        groupIds: [
          for (final n in flattenGroups(widget.chapters))
            if (_groups.contains(n.group.id)) n.group.id,
        ],
        fileName: file.isEmpty ? null : file,
        sortOrder: widget.profile?.sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.profile == null ? l.plAddExport : l.plEditExport),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('pe-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: l.name),
              ),
              TextField(
                key: const ValueKey('pe-code'),
                controller: _code,
                decoration: InputDecoration(labelText: l.code),
              ),
              const SizedBox(height: 12),
              Text(l.plChapters, style: Theme.of(context).textTheme.labelLarge),
              Text(
                l.plChaptersHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // Ticking a group does not tick the groups below it: they are included by the server.
              for (final n in flattenGroups(widget.chapters))
                CheckboxListTile(
                  key: ValueKey('pe-group-${n.group.id}'),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.only(left: n.depth * 20.0),
                  title: Text(
                    groupTitle(n.group, widget.lang),
                    style: n.group.showTitle
                        ? null
                        : const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  value: _groups.contains(n.group.id),
                  onChanged: (on) => setState(
                    () => on == true
                        ? _groups.add(n.group.id)
                        : _groups.remove(n.group.id),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('pe-file'),
                controller: _file,
                decoration: InputDecoration(
                  labelText: l.plFileName,
                  helperText: l.plFileNameHint(exportFilePlaceholders.join(' ')),
                  helperMaxLines: 3,
                ),
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
          key: const ValueKey('pe-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Asks the level (1 = top level) of the groups that get a profile each; pops the level.
class PerLevelDialog extends StatefulWidget {
  const PerLevelDialog({super.key});

  @override
  State<PerLevelDialog> createState() => _PerLevelDialogState();
}

class _PerLevelDialogState extends State<PerLevelDialog> {
  int _level = 1;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.plPerLevelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.plPerLevelHint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (var n = 1; n <= 4; n++)
                ChoiceChip(
                  key: ValueKey('ple-level-$n'),
                  label: Text(l.plLevelN(n)),
                  selected: _level == n,
                  onSelected: (_) => setState(() => _level = n),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('ple-level-ok'),
          onPressed: () => Navigator.pop(context, _level),
          child: Text(l.plPerChapter),
        ),
      ],
    );
  }
}
