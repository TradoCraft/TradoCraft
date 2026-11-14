import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import '../shared/auth_image.dart';
import '../shared/markdown_view.dart';
import 'portal_state.dart';
import '../shared/app_icons.dart';

String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

final portalHelpCategoriesProvider = FutureProvider.autoDispose
    .family<List<ReaderCategory>, String>(
      (ref, language) => ref
          .watch(portalApiProvider)
          .listPortalKbCategories(language: language),
    );

final portalHelpEntryProvider = FutureProvider.autoDispose
    .family<ReaderEntry, (String, String)>(
      (ref, key) => ref
          .watch(portalApiProvider)
          .getPortalKbEntry(id: key.$1, language: key.$2),
    );

/// The help centre: search the articles or browse them by category.
class PortalHelpPage extends ConsumerStatefulWidget {
  const PortalHelpPage({super.key});

  @override
  ConsumerState<PortalHelpPage> createState() => _PortalHelpPageState();
}

class _PortalHelpPageState extends ConsumerState<PortalHelpPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _category;
  Future<List<ReaderSummary>>? _entries;

  Future<List<ReaderSummary>> _load(String language) => ref
      .read(portalApiProvider)
      .listPortalKbEntries(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        categoryId: _category,
        language: language,
      );

  void _reload() => setState(() {
    _entries = _load(_lang(context));
  });

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = _lang(context);
    _entries ??= _load(lang);
    final categories =
        ref.watch(portalHelpCategoriesProvider(lang)).value ??
        const <ReaderCategory>[];
    final top = categories.where((c) => c.parentId == null).toList();
    final subs = categories.where((c) => c.parentId == _category).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.kbHelpHeading, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('help-search'),
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(AppIcons.search),
            hintText: l.kbHelpSearch,
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _reload);
          },
          onSubmitted: (_) => _reload(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.kbAllCategories),
              selected: _category == null,
              onSelected: (_) {
                _category = null;
                _reload();
              },
            ),
            for (final c in top)
              ChoiceChip(
                key: ValueKey('category-${c.id}'),
                label: Text('${c.name} (${c.entryCount})'),
                selected: _category == c.id,
                onSelected: (_) {
                  _category = c.id;
                  _reload();
                },
              ),
          ],
        ),
        if (subs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final c in subs)
                  ActionChip(
                    label: Text('${c.name} (${c.entryCount})'),
                    onPressed: () {
                      _category = c.id;
                      _reload();
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FutureBuilder<List<ReaderSummary>>(
          future: _entries,
          builder: (context, snap) {
            if (snap.hasError) return Text(portalError(snap.error!));
            if (!snap.hasData) return const LinearProgressIndicator();
            final list = snap.data!;
            if (list.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.kbHelpEmpty),
                  TextButton(
                    onPressed: () => context.go('/tickets/new'),
                    child: Text(l.newTicket),
                  ),
                ],
              );
            }
            return Column(
              children: [
                for (final e in list)
                  Card(
                    child: ListTile(
                      key: ValueKey('article-${e.id}'),
                      title: Text(e.title),
                      subtitle: HighlightedSnippet(e.snippet, maxLines: 2),
                      isThreeLine: e.snippet.isNotEmpty,
                      onTap: () => context.go('/help/${e.id}'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One help article, with a yes/no on whether it helped.
class PortalHelpArticlePage extends ConsumerStatefulWidget {
  const PortalHelpArticlePage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<PortalHelpArticlePage> createState() =>
      _PortalHelpArticlePageState();
}

class _PortalHelpArticlePageState extends ConsumerState<PortalHelpArticlePage> {
  /// null = not answered (or as the server has it), set after the person votes.
  bool? _vote;
  bool _voted = false;
  bool _thanks = false;

  Future<void> _sendVote(bool helpful) async {
    try {
      await ref
          .read(portalApiProvider)
          .votePortalKbEntry(
            id: widget.id,
            body: KbVote(helpful: helpful),
          );
      if (mounted) {
        setState(() {
          _vote = helpful;
          _voted = true;
          _thanks = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(portalError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = _lang(context);
    final entry = ref.watch(portalHelpEntryProvider((widget.id, lang)));
    final dio = ref.watch(portalDioProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/help'),
              icon: const Icon(AppIcons.arrowBack),
            ),
            Text(l.kbHelp, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        entry.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(portalError(e)),
          data: (e) {
            final mine = _voted ? _vote : e.myVote;
            final fmt = DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  key: const ValueKey('article-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  l.kbUpdatedOn(fmt.format(e.updatedAt.toLocal())),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (e.fallback)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l.kbShownIn(languageName(e.language)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                MarkdownView(
                  source: e.body,
                  imageBuilder: (context, id, alt) => AuthImage(
                    dio: dio,
                    path: '/api/v1/portal/kb/entries/${e.id}/images/$id',
                    alt: alt,
                  ),
                ),
                const Divider(height: 32),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l.kbWasHelpful),
                    ChoiceChip(
                      key: const ValueKey('vote-yes'),
                      label: Text(l.kbYes),
                      selected: mine == true,
                      onSelected: (_) => _sendVote(true),
                    ),
                    ChoiceChip(
                      key: const ValueKey('vote-no'),
                      label: Text(l.kbNo),
                      selected: mine == false,
                      onSelected: (_) => _sendVote(false),
                    ),
                    if (_thanks) Text(l.kbThanks),
                  ],
                ),
                if (mine == false)
                  TextButton(
                    onPressed: () => context.go('/tickets/new'),
                    child: Text(l.kbStillNeedHelp),
                  ),
                if (e.related.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    l.kbRelatedReading,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final r in e.related)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.article),
                      title: Text(r.title),
                      onTap: () => context.go('/help/${r.id}'),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Up to three articles that may answer the question being typed, shown under the subject
/// field of the new-ticket form. Never blocks creating the ticket.
class PortalKbSuggestions extends ConsumerStatefulWidget {
  const PortalKbSuggestions({super.key, required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<PortalKbSuggestions> createState() =>
      _PortalKbSuggestionsState();
}

class _PortalKbSuggestionsState extends ConsumerState<PortalKbSuggestions> {
  Timer? _debounce;
  List<ReaderSummary> _items = const [];
  String _asked = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _debounce?.cancel();
    super.dispose();
  }

  void _changed() {
    final q = widget.controller.text.trim();
    if (q == _asked) return;
    _debounce?.cancel();
    if (q.length < 3) {
      if (_items.isNotEmpty) setState(() => _items = const []);
      _asked = q;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _ask(q));
  }

  Future<void> _ask(String q) async {
    _asked = q;
    try {
      final r = await ref
          .read(portalApiProvider)
          .suggestPortalKbEntries(q: q, language: _lang(context));
      if (mounted && widget.controller.text.trim() == q) {
        setState(() => _items = r);
      }
    } catch (_) {
      // Suggestions are a convenience: a failure must never get in the way of the ticket.
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return Card(
      key: const ValueKey('kb-deflection'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.kbDeflectionTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final e in _items)
              ListTile(
                key: ValueKey('suggestion-${e.id}'),
                dense: true,
                leading: const Icon(AppIcons.lightbulb),
                title: Text(e.title),
                subtitle: HighlightedSnippet(e.snippet, maxLines: 2),
                onTap: () => context.push('/help/${e.id}'),
              ),
          ],
        ),
      ),
    );
  }
}
