import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../app/interface_languages.dart';
import '../../l10n/icu.dart';
import '../../l10n/l10n.dart';
import '../../l10n/runtime_localizations.dart';
import '../../shared/actions.dart';
import '../field/offline/kv_store.dart' show kvStoreProvider;
import '../../shared/csv_transfer.dart'
    show PickedFile, csvSaverProvider, pickFileWithRememberedDirectory;
import 'company_languages_section.dart' show LanguageSearchDialog;

/// The translation domains an administrator manages here (ADR 0101).
const translationDomains = ['app', 'documents', 'mail'];

/// A language that has texts in a domain (`GET /translations/{domain}`).
typedef CatalogueInfo = ({String language, bool shipped, int companyEntries});

final cataloguesProvider = FutureProvider.autoDispose
    .family<List<CatalogueInfo>, String>((ref, domain) async {
      final res = await ref
          .watch(dioProvider)
          .get<List<dynamic>>('/api/v1/translations/$domain');
      return [
        for (final c in res.data ?? const [])
          (
            language: (c as Map)['language'] as String,
            shipped: c['shipped'] == true,
            companyEntries: (c['company_entries'] as num? ?? 0).toInt(),
          ),
      ];
    });

/// One catalogue as the server holds it.
typedef CatalogueDetail = ({
  Map<String, String> entries,
  Map<String, String> shipped,
  Map<String, String> source,
});

Map<String, String> _strings(Object? m) => {
  for (final e in ((m as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
};

final catalogueDetailProvider = FutureProvider.autoDispose
    .family<CatalogueDetail, (String, String)>((ref, key) async {
      final (domain, language) = key;
      final res = await ref
          .watch(dioProvider)
          .get<Map<String, dynamic>>('/api/v1/translations/$domain/$language');
      final d = res.data ?? const {};
      return (
        entries: _strings(d['entries']),
        shipped: _strings(d['shipped']),
        source: _strings(d['source']),
      );
    });

/// The English source texts of the app (`key → text`), from the bundled template ARB.
final appSourceProvider = FutureProvider<Map<String, String>>((ref) async {
  final arb = await rootBundle.loadString('lib/l10n/app_en.arb');
  return parseCatalogueFile(utf8.encode(arb));
});

/// The texts of an ARB or flat JSON file (`key → text`); `@` metadata and non-text values are
/// left out. Throws [FormatException] when the file is not a JSON object.
Map<String, String> parseCatalogueFile(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) throw const FormatException('not a JSON object');
  return {
    for (final e in decoded.entries)
      if (!'${e.key}'.startsWith('@') && e.value is String)
        '${e.key}': e.value as String,
  };
}

/// Problems of an uploaded `app` catalogue: unknown keys and malformed ICU messages.
List<String> checkAppCatalogue(Map<String, String> entries) {
  final known = runtimeMessageKeys.toSet();
  return [
    for (final e in entries.entries)
      if (!known.contains(e.key))
        e.key
      else if (!isValidIcu(e.value))
        e.key,
  ];
}

/// An ARB (app) or JSON (documents, mail) file of [entries] for [language].
Uint8List catalogueFile(
  String domain,
  String language,
  Map<String, String> entries,
) {
  final body = domain == 'app'
      ? {'@@locale': language, ...entries}
      : entries;
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(body)),
  );
}

String catalogueFileName(String domain, String language) =>
    domain == 'app' ? 'app_$language.arb' : '${domain}_$language.json';

const _translationTypes = [
  XTypeGroup(
    label: 'ARB, JSON',
    extensions: ['arb', 'json'],
    mimeTypes: ['application/json'],
  ),
];

/// Administration of translation catalogues: interface texts of the app and the texts of
/// printed documents and system mails, per language (ADR 0101).
class TranslationsPage extends ConsumerStatefulWidget {
  const TranslationsPage({super.key});

  @override
  ConsumerState<TranslationsPage> createState() => _TranslationsPageState();
}

class _TranslationsPageState extends ConsumerState<TranslationsPage> {
  String _domain = 'app';

  Future<Map<String, String>> _source() async {
    if (_domain == 'app') return ref.read(appSourceProvider.future);
    final d = await ref.read(catalogueDetailProvider((_domain, 'en')).future);
    return d.source;
  }

  void _fail(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _refresh() {
    ref.invalidate(cataloguesProvider(_domain));
    ref.invalidate(installedInterfaceLanguagesProvider);
  }

  Future<void> _exportTemplate() async {
    final l = context.l10n;
    await runAction(context, () async {
      final source = await _source();
      await ref.read(csvSaverProvider)(
        catalogueFileName(_domain, 'en'),
        catalogueFile(_domain, 'en', source),
      );
    }, success: l.translationsExported);
  }

  Future<void> _export(String language) async {
    final l = context.l10n;
    await runAction(context, () async {
      final d = await ref.read(
        catalogueDetailProvider((_domain, language)).future,
      );
      await ref.read(csvSaverProvider)(
        catalogueFileName(_domain, language),
        catalogueFile(_domain, language, {...d.shipped, ...d.entries}),
      );
    }, success: l.translationsExported);
  }

  Future<void> _import(String language) async {
    final l = context.l10n;
    final PickedFile? file;
    try {
      file = await pickFileWithRememberedDirectory(
        _translationTypes,
        store: ref.read(kvStoreProvider),
      );
    } catch (e) {
      if (mounted) _fail(errorMessage(e));
      return;
    }
    if (file == null || !mounted) return;
    final Map<String, String> entries;
    try {
      entries = parseCatalogueFile(file.bytes);
    } on FormatException {
      _fail(l.translationsBadFile);
      return;
    }
    if (_domain == 'app') {
      final bad = checkAppCatalogue(entries);
      if (bad.isNotEmpty) {
        _fail(l.translationsBadKeys(bad.take(5).join(', ')));
        return;
      }
    }
    await _save(language, entries);
  }

  Future<void> _save(String language, Map<String, String> entries) async {
    final l = context.l10n;
    final ok = await runAction(
      context,
      () => ref
          .read(dioProvider)
          .put<Map<String, dynamic>>(
            '/api/v1/admin/translations/$_domain/$language',
            data: {'entries': entries},
          ),
      success: l.translationsSaved,
    );
    if (ok && mounted) {
      ref.invalidate(catalogueDetailProvider((_domain, language)));
      ref.invalidate(interfaceCatalogueProvider(language));
      _refresh();
    }
  }

  Future<void> _delete(String language) async {
    final l = context.l10n;
    final ok = await runAction(
      context,
      () => ref
          .read(dioProvider)
          .delete<void>('/api/v1/admin/translations/$_domain/$language'),
      success: l.translationsDeleted,
    );
    if (ok && mounted) {
      ref.invalidate(interfaceCatalogueProvider(language));
      _refresh();
    }
  }

  Future<void> _edit(String language) async {
    final source = await _source();
    if (!mounted) return;
    final detail = await ref.read(
      catalogueDetailProvider((_domain, language)).future,
    );
    if (!mounted) return;
    final edited = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _CatalogueEditor(
        title: '${languageName(language)} · $_domain',
        source: source,
        shipped: detail.shipped,
        entries: detail.entries,
        checkIcu: _domain == 'app',
      ),
    );
    if (edited != null && mounted) await _save(language, edited);
  }

  Future<void> _add(List<CatalogueInfo> existing) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) =>
          LanguageSearchDialog(exclude: {for (final c in existing) c.language}),
    );
    if (code != null && mounted) await _edit(code);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final catalogues = ref.watch(cataloguesProvider(_domain));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.translationsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(l.translationsHelp),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              key: const ValueKey('translations-domain'),
              showSelectedIcon: false,
              segments: [
                for (final d in translationDomains)
                  ButtonSegment(
                    value: d,
                    label: Text(switch (d) {
                      'app' => l.translationsDomainApp,
                      'documents' => l.translationsDomainDocuments,
                      _ => l.translationsDomainMail,
                    }),
                  ),
              ],
              selected: {_domain},
              onSelectionChanged: (s) => setState(() => _domain = s.first),
            ),
            OutlinedButton.icon(
              key: const ValueKey('translations-export-template'),
              onPressed: _exportTemplate,
              icon: const Icon(Icons.download),
              label: Text(l.translationsExportTemplate),
            ),
            OutlinedButton.icon(
              key: const ValueKey('translations-add'),
              onPressed: () => _add(catalogues.value ?? const []),
              icon: const Icon(Icons.add),
              label: Text(l.adminLanguagesAdd),
            ),
          ],
        ),
        const SizedBox(height: 12),
        catalogues.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => Column(
            children: [
              for (final c in list)
                ListTile(
                  key: ValueKey('translations-${c.language}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${languageName(c.language)} (${c.language})',
                  ),
                  subtitle: Text(
                    [
                      if (c.shipped) l.translationsShipped,
                      l.translationsCompanyTexts(c.companyEntries),
                    ].join(' · '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: ValueKey('translations-edit-${c.language}'),
                        tooltip: l.edit,
                        onPressed: () => _edit(c.language),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: ValueKey('translations-import-${c.language}'),
                        tooltip: l.translationsImport,
                        onPressed: () => _import(c.language),
                        icon: const Icon(Icons.upload_file),
                      ),
                      IconButton(
                        key: ValueKey('translations-export-${c.language}'),
                        tooltip: l.translationsExport,
                        onPressed: () => _export(c.language),
                        icon: const Icon(Icons.download),
                      ),
                      if (c.companyEntries > 0)
                        IconButton(
                          key: ValueKey('translations-delete-${c.language}'),
                          tooltip: l.translationsDelete,
                          onPressed: () => _delete(c.language),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Edits the company texts of one catalogue next to the English source; returns the texts to
/// save, or null when cancelled.
class _CatalogueEditor extends StatefulWidget {
  const _CatalogueEditor({
    required this.title,
    required this.source,
    required this.shipped,
    required this.entries,
    required this.checkIcu,
  });

  final String title;
  final Map<String, String> source;
  final Map<String, String> shipped;
  final Map<String, String> entries;
  final bool checkIcu;

  @override
  State<_CatalogueEditor> createState() => _CatalogueEditorState();
}

class _CatalogueEditorState extends State<_CatalogueEditor> {
  late final Map<String, String> _texts = {...widget.entries};
  String _q = '';
  bool _missingOnly = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final q = _q.trim().toLowerCase();
    final keys = [
      for (final k in widget.source.keys)
        if ((q.isEmpty ||
                k.toLowerCase().contains(q) ||
                widget.source[k]!.toLowerCase().contains(q) ||
                (_texts[k] ?? '').toLowerCase().contains(q)) &&
            (!_missingOnly ||
                ((_texts[k] ?? '').isEmpty && !widget.shipped.containsKey(k))))
          k,
    ];
    final invalid = widget.checkIcu
        ? [
            for (final e in _texts.entries)
              if (e.value.isNotEmpty && !isValidIcu(e.value)) e.key,
          ]
        : const <String>[];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('translations-search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: l.search,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  key: const ValueKey('translations-missing-only'),
                  label: Text(l.translationsMissingOnly),
                  selected: _missingOnly,
                  onSelected: (v) => setState(() => _missingOnly = v),
                ),
              ],
            ),
            if (invalid.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.translationsBadKeys(invalid.take(5).join(', ')),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: keys.length,
                itemBuilder: (context, i) {
                  final k = keys[i];
                  return Padding(
                    key: ValueKey('translations-row-$k'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: TextFormField(
                      key: ValueKey('translations-text-$k'),
                      initialValue: _texts[k] ?? '',
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: k,
                        helperText: widget.source[k],
                        helperMaxLines: 3,
                        hintText: widget.shipped[k],
                      ),
                      onChanged: (v) => setState(() => _texts[k] = v),
                    ),
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
        FilledButton(
          key: const ValueKey('translations-save'),
          onPressed: invalid.isNotEmpty
              ? null
              : () => Navigator.pop(context, {
                  for (final e in _texts.entries)
                    if (e.value.trim().isNotEmpty) e.key: e.value,
                }),
          child: Text(l.save),
        ),
      ],
    );
  }
}
