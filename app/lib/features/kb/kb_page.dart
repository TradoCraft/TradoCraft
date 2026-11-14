import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show OpenInTab;
import '../../l10n/l10n.dart';
import '../../shared/markdown_view.dart';
import 'kb_common.dart';
import '../../shared/app_icons.dart';

/// The knowledge base: search and filter the articles, open one to read or edit it.
class KbPage extends ConsumerStatefulWidget {
  const KbPage({super.key});

  @override
  ConsumerState<KbPage> createState() => _KbPageState();
}

class _KbPageState extends ConsumerState<KbPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _category;
  String? _status;
  String? _audience;
  String? _language;
  late Future<List<EntrySummary>> _entries = _load();

  Future<List<EntrySummary>> _load() => ref
      .read(apiProvider)
      .kb
      .listKbEntries(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        categoryId: _category,
        status: _status,
        visibility: _audience,
        language: _language,
      );

  void _reload() => setState(() {
    _entries = _load();
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
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final canWrite = perms.contains('kb.write');
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(kbCategoriesProvider).value ?? const [];
    const gap = SizedBox(width: 12, height: 12);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(l.kbTitle, style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.go('/kb/categories'),
              icon: const Icon(AppIcons.folder),
              label: Text(l.kbManageCategories),
            ),
            if (canWrite)
              FilledButton.icon(
                onPressed: () => context.go('/kb/new'),
                icon: const Icon(AppIcons.add),
                label: Text(l.kbNewArticle),
              ),
          ],
        ),
        gap,
        TextField(
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(AppIcons.search),
            hintText: l.kbSearchHint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _reload);
          },
          onSubmitted: (_) => _reload(),
        ),
        gap,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _filter<String?>(
              key: 'category',
              width: 240,
              label: l.category,
              value: _category,
              items: [
                DropdownMenuItem(value: null, child: Text(l.kbAllCategories)),
                for (final (c, label) in categoryTree(categories, lang))
                  DropdownMenuItem(value: c.id, child: Text(label)),
              ],
              onChanged: (v) {
                _category = v;
                _reload();
              },
            ),
            _filter<String?>(
              key: 'status',
              width: 180,
              label: l.status,
              value: _status,
              items: [
                DropdownMenuItem(value: null, child: Text(l.kbAllStatuses)),
                for (final s in kbStatuses)
                  DropdownMenuItem(value: s, child: Text(kbStatusLabel(l, s))),
              ],
              onChanged: (v) {
                _status = v;
                _reload();
              },
            ),
            _filter<String?>(
              key: 'audience',
              width: 220,
              label: l.kbAudience,
              value: _audience,
              items: [
                DropdownMenuItem(value: null, child: Text(l.kbAllAudiences)),
                for (final a in kbAudiences)
                  DropdownMenuItem(
                    value: a,
                    child: Text(kbAudienceLabel(l, a)),
                  ),
              ],
              onChanged: (v) {
                _audience = v;
                _reload();
              },
            ),
            _filter<String?>(
              key: 'language',
              width: 170,
              label: l.language,
              value: _language,
              items: [
                DropdownMenuItem(value: null, child: Text(languageName(lang))),
                for (final c in languageCodes)
                  if (c != lang)
                    DropdownMenuItem(value: c, child: Text(languageName(c))),
              ],
              onChanged: (v) {
                _language = v;
                _reload();
              },
            ),
          ],
        ),
        gap,
        FutureBuilder<List<EntrySummary>>(
          future: _entries,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorMessage(snap.error!));
            if (!snap.hasData) return const LinearProgressIndicator();
            final list = snap.data!;
            if (list.isEmpty) return Text(l.kbNoArticles);
            return Column(
              children: [
                for (final e in list)
                  OpenInTab(
                    key: ValueKey('kb-${e.id}'),
                    location: '/kb/${e.id}',
                    child: Card(
                      child: ListTile(
                        title: Text(e.title),
                        subtitle: HighlightedSnippet(e.snippet, maxLines: 2),
                        isThreeLine: e.snippet.isNotEmpty,
                        trailing: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (e.fallback)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(e.language.toUpperCase()),
                              ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: kbStatusColor(context, e.status),
                              label: Text(kbStatusLabel(l, e.status)),
                            ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(kbAudienceLabel(l, e.visibility)),
                            ),
                          ],
                        ),
                        leading: Text(e.number),
                        onTap: () => context.push('/kb/${e.id}'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _filter<T>({
    required String key,
    required double width,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      key: ValueKey('filter-$key'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items,
      onChanged: onChanged,
    ),
  );
}
