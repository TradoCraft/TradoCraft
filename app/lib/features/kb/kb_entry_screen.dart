import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/attachments.dart';
import '../../shared/auth_image.dart';
import '../../shared/markdown_view.dart';
import '../../shared/photos.dart';
import 'kb_common.dart';
import '../../shared/app_icons.dart';

/// Chooses image files to upload; replaced in tests.
typedef ImagePicker = Future<List<PickedPhoto>> Function(BuildContext context);

class _LangText {
  final title = TextEditingController();
  final summary = TextEditingController();
  final body = TextEditingController();
  bool preview = false;

  bool get isEmpty =>
      title.text.trim().isEmpty &&
      summary.text.trim().isEmpty &&
      body.text.trim().isEmpty;

  void dispose() {
    title.dispose();
    summary.dispose();
    body.dispose();
  }
}

/// Reads and edits one article: a tab per language, Markdown with a preview, category, audience,
/// tags, related articles, pictures, publishing and the version history. [id] is `new` for a
/// new article.
class KbEntryScreen extends ConsumerStatefulWidget {
  const KbEntryScreen({super.key, required this.id, this.pickImages});
  final String id;
  final ImagePicker? pickImages;

  @override
  ConsumerState<KbEntryScreen> createState() => _KbEntryScreenState();
}

class _KbEntryScreenState extends ConsumerState<KbEntryScreen>
    with SingleTickerProviderStateMixin {
  Entry? _entry;
  List<EntryVersion> _versions = [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  late final _tabs = TabController(length: languageCodes.length, vsync: this);
  final _texts = {for (final c in languageCodes) c: _LangText()};
  final _tags = TextEditingController();
  String? _category;
  String _audience = 'internal';
  List<RelatedEntry> _related = [];

  bool get _isNew => widget.id == 'new';
  KbClient get _api => ref.read(apiProvider).kb;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _loading = false;
    } else {
      _load();
    }
  }

  bool _tabChosen = false;

  /// Opens the tab of the reader's own language, else the first language that has a text.
  void _chooseTab() {
    final ui = Localizations.localeOf(context).languageCode;
    final filled = [
      for (final c in languageCodes)
        if (!_texts[c]!.isEmpty) c,
    ];
    final pick = filled.isEmpty || filled.contains(ui) ? ui : filled.first;
    final i = languageCodes.indexOf(pick);
    if (i >= 0) _tabs.index = i;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tabChosen && !_loading) {
      _tabChosen = true;
      _chooseTab();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _tags.dispose();
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _fill(Entry e) {
    _entry = e;
    _category = e.categoryId;
    _audience = e.visibility;
    _tags.text = e.tags.join(', ');
    _related = [...e.related];
    for (final c in languageCodes) {
      final t = e.texts.where((x) => x.language == c).firstOrNull;
      _texts[c]!.title.text = t?.title ?? '';
      _texts[c]!.summary.text = t?.summary ?? '';
      _texts[c]!.body.text = t?.body ?? '';
    }
  }

  Future<void> _load() async {
    try {
      final e = await _api.getKbEntry(id: widget.id);
      final v = await _api.listKbVersions(id: widget.id);
      if (!mounted) return;
      setState(() {
        _fill(e);
        _versions = v;
        _loading = false;
        _tabChosen = true;
        _chooseTab();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _loading = false;
        });
      }
    }
  }

  EntryInput _input() => EntryInput(
    categoryId: _category,
    visibility: _audience,
    texts: [
      for (final c in languageCodes)
        if (!_texts[c]!.isEmpty)
          EntryText(
            language: c,
            title: _texts[c]!.title.text.trim(),
            summary: _texts[c]!.summary.text.trim(),
            body: _texts[c]!.body.text,
          ),
    ],
    tags: _tags.text
        .split(RegExp(r'[,;]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(),
    relatedIds: [for (final r in _related) r.id],
    productIds: _entry?.productIds ?? const [],
    ticketCategories: _entry?.ticketCategories ?? const [],
  );

  Future<void> _refreshVersions() async {
    if (_entry == null) return;
    final v = await _api.listKbVersions(id: _entry!.id);
    if (mounted) setState(() => _versions = v);
  }

  Future<void> _save() async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = _isNew
          ? await _api.createKbEntry(body: _input())
          : await _api.updateKbEntry(id: _entry!.id, body: _input());
      if (!mounted) return;
      setState(() => _fill(saved));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saved)));
      if (_isNew) {
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go('/kb/${saved.id}');
        }
      } else {
        await _refreshVersions();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transition(Future<Entry> Function(String id) action) async {
    final id = _entry!.id;
    await runAction(context, () async {
      final e = await action(id);
      if (mounted) setState(() => _fill(e));
      await _refreshVersions();
    });
  }

  Future<void> _restore(EntryVersion v) async {
    final id = _entry!.id;
    await runAction(context, () async {
      final e = await _api.restoreKbVersion(id: id, version: v.version);
      if (mounted) setState(() => _fill(e));
      await _refreshVersions();
    }, success: context.l10n.saved);
  }

  Future<void> _uploadImage() async {
    final pick = widget.pickImages ?? pickPhotos;
    final files = await pick(context);
    if (files.isEmpty || !mounted) return;
    await runAction(context, () async {
      for (final f in files) {
        await uploadPhoto(
          ref.read(dioProvider),
          '/api/v1/kb/entries/${_entry!.id}/images',
          f,
        );
      }
      final e = await _api.getKbEntry(id: _entry!.id);
      if (mounted) setState(() => _entry = e);
    });
  }

  void _insertImage(FileInfo f) {
    final body = _texts[languageCodes[_tabs.index]]!.body;
    final text = '![${f.filename}](image:${f.id})';
    final sel = body.selection;
    final start = sel.isValid ? sel.start : body.text.length;
    final end = sel.isValid ? sel.end : body.text.length;
    body.value = TextEditingValue(
      text: body.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    setState(() {});
  }

  Future<void> _addRelated() async {
    final picked = await showDialog<EntrySummary>(
      context: context,
      builder: (_) => KbArticlePicker(excludeId: _entry?.id),
    );
    if (picked == null || _related.any((r) => r.id == picked.id)) return;
    setState(
      () => _related = [
        ..._related,
        RelatedEntry(
          id: picked.id,
          number: picked.number,
          status: picked.status,
          title: picked.title,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = perms.contains('kb.write');
    final canAdmin = perms.contains('kb.admin');
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(kbCategoriesProvider).value ?? const [];
    final e = _entry;
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (e == null && !_isNew) {
      return Center(child: Text(_error ?? l.kbNoArticles));
    }
    const gap = SizedBox(width: 12, height: 12);
    final readOnly = !canWrite;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/kb'),
              icon: const Icon(AppIcons.arrowBack),
            ),
            Text(
              e == null ? l.kbNewArticle : '${e.number} · v${e.version}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(width: 12),
            if (e != null)
              Chip(
                backgroundColor: kbStatusColor(context, e.status),
                label: Text(kbStatusLabel(l, e.status)),
              ),
            const Spacer(),
            if (e != null && canAdmin) ...[
              if (e.status != 'published')
                OutlinedButton(
                  onPressed: () =>
                      _transition((id) => _api.publishKbEntry(id: id)),
                  child: Text(l.kbPublish),
                ),
              if (e.status == 'published')
                OutlinedButton(
                  onPressed: () =>
                      _transition((id) => _api.unpublishKbEntry(id: id)),
                  child: Text(l.kbUnpublish),
                ),
              if (e.status != 'archived')
                TextButton(
                  onPressed: () =>
                      _transition((id) => _api.archiveKbEntry(id: id)),
                  child: Text(l.kbArchive),
                ),
            ],
            if (canWrite)
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(l.save),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        gap,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('category-$_category'),
                isExpanded: true,
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: l.category,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.kbNoCategory)),
                  for (final (c, label) in categoryTree(categories, lang))
                    DropdownMenuItem(value: c.id, child: Text(label)),
                ],
                onChanged: readOnly
                    ? null
                    : (v) => setState(() => _category = v),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey('audience-$_audience'),
                isExpanded: true,
                initialValue: _audience,
                decoration: InputDecoration(
                  labelText: l.kbAudience,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final a in kbAudiences)
                    DropdownMenuItem(
                      value: a,
                      child: Text(kbAudienceLabel(l, a)),
                    ),
                ],
                onChanged: readOnly
                    ? null
                    : (v) => setState(() => _audience = v!),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _tags,
                readOnly: readOnly,
                decoration: InputDecoration(
                  labelText: l.kbTagsLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        gap,
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            for (final c in languageCodes)
              Tab(text: '${languageName(c)}${_texts[c]!.isEmpty ? '' : ' ✓'}'),
          ],
        ),
        SizedBox(
          height: 520,
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final c in languageCodes)
                _languageTab(context, c, readOnly, e),
            ],
          ),
        ),
        gap,
        if (e == null)
          Text(l.kbMarkdownHelp, style: theme.textTheme.bodySmall)
        else ...[
          _relatedSection(context, readOnly),
          gap,
          _imagesSection(context, e, canWrite),
          gap,
          Text(
            '${l.kbFeedback(e.helpfulYes, e.helpfulNo)} · ${l.kbViews(e.viewCount)}',
            style: theme.textTheme.bodySmall,
          ),
          gap,
          _historySection(context, canWrite),
        ],
      ],
    );
  }

  Widget _languageTab(BuildContext context, String c, bool readOnly, Entry? e) {
    final l = context.l10n;
    final t = _texts[c]!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          TextField(
            key: ValueKey('title-$c'),
            controller: t.title,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: l.kbArticleTitle,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('summary-$c'),
            controller: t.summary,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: l.kbSummary,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l.kbWriteTab)),
                ButtonSegment(value: true, label: Text(l.kbPreview)),
              ],
              selected: {t.preview},
              onSelectionChanged: (s) => setState(() => t.preview = s.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: t.preview
                ? SingleChildScrollView(
                    key: ValueKey('preview-$c'),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: MarkdownView(
                        source: t.body.text,
                        imageBuilder: (context, id, alt) => AuthImage(
                          dio: ref.read(dioProvider),
                          path: '/api/v1/kb/entries/${e?.id}/images/$id',
                          alt: alt,
                        ),
                      ),
                    ),
                  )
                : TextField(
                    key: ValueKey('body-$c'),
                    controller: t.body,
                    readOnly: readOnly,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      labelText: l.kbBody,
                      helperText: l.kbMarkdownHelp,
                      helperMaxLines: 2,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _relatedSection(BuildContext context, bool readOnly) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.kbRelated, style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            for (final r in _related)
              InputChip(
                label: Text('${r.number} ${r.title}'),
                onPressed: () => context.go('/kb/${r.id}'),
                onDeleted: readOnly
                    ? null
                    : () => setState(() => _related.remove(r)),
              ),
            if (!readOnly)
              ActionChip(
                avatar: const Icon(AppIcons.add, size: 18),
                label: Text(l.kbAddRelated),
                onPressed: _addRelated,
              ),
          ],
        ),
      ],
    );
  }

  Widget _imagesSection(BuildContext context, Entry e, bool canWrite) {
    final l = context.l10n;
    final dio = ref.read(dioProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.kbImages, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 12),
            if (canWrite)
              OutlinedButton.icon(
                onPressed: _uploadImage,
                icon: const Icon(AppIcons.addPhotoAlternate),
                label: Text(l.kbUploadImage),
              ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final f in e.images)
              SizedBox(
                width: 150,
                child: Column(
                  children: [
                    AuthImage(
                      dio: dio,
                      path: '/api/v1/kb/entries/${e.id}/images/${f.id}',
                      alt: f.filename,
                      maxHeight: 90,
                    ),
                    Text(
                      '${f.filename} · ${fileSize(f.sizeBytes)}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (canWrite)
                      TextButton(
                        key: ValueKey('insert-${f.id}'),
                        onPressed: () => _insertImage(f),
                        child: Text(l.kbInsertImage),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _historySection(BuildContext context, bool canWrite) {
    final l = context.l10n;
    final fmt = DateFormat.yMd(Localizations.localeOf(context).toString())
        .add_Hm();
    return ExpansionTile(
      key: const ValueKey('history'),
      title: Text('${l.kbHistory} (${_versions.length})'),
      children: [
        for (final v in _versions)
          ListTile(
            dense: true,
            title: Text(
              l.kbVersionLine(
                v.version,
                v.editorName ?? '',
                fmt.format(v.editedAt.toLocal()),
              ),
            ),
            subtitle: Text(
              [
                if (v.restoredFrom != null) l.kbRestoredFrom(v.restoredFrom!),
                v.texts.map((t) => t.title).join(' / '),
              ].join(' · '),
            ),
            trailing: canWrite
                ? TextButton(
                    key: ValueKey('restore-${v.version}'),
                    onPressed: () => _restore(v),
                    child: Text(l.kbRestore),
                  )
                : null,
          ),
      ],
    );
  }
}

/// Searches the articles and returns the chosen one.
class KbArticlePicker extends ConsumerStatefulWidget {
  const KbArticlePicker({
    super.key,
    this.excludeId,
    this.publishedOnly = false,
    this.language,
  });
  final String? excludeId;
  final bool publishedOnly;
  final String? language;

  @override
  ConsumerState<KbArticlePicker> createState() => _KbArticlePickerState();
}

class _KbArticlePickerState extends ConsumerState<KbArticlePicker> {
  String _q = '';
  late Future<List<EntrySummary>> _list = _load();

  Future<List<EntrySummary>> _load() => ref
      .read(apiProvider)
      .kb
      .listKbEntries(
        q: _q.isEmpty ? null : _q,
        status: widget.publishedOnly ? 'published' : null,
        language: widget.language,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.kbTitle),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(AppIcons.search),
                hintText: l.kbSearchHint,
              ),
              onSubmitted: (v) => setState(() {
                _q = v.trim();
                _list = _load();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<EntrySummary>>(
                future: _list,
                builder: (context, snap) {
                  if (snap.hasError) return Text(errorMessage(snap.error!));
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final list = snap.data!
                      .where((e) => e.id != widget.excludeId)
                      .toList();
                  if (list.isEmpty) return Text(l.kbNoArticles);
                  return ListView(
                    children: [
                      for (final e in list)
                        ListTile(
                          key: ValueKey('pick-${e.id}'),
                          title: Text(e.title),
                          subtitle: Text(
                            '${e.number} · ${kbStatusLabel(l, e.status)}',
                          ),
                          onTap: () => Navigator.pop(context, e),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
