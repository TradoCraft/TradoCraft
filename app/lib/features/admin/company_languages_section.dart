import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';

/// The company's content languages (ADR 0101): an ordered list with one default, edited by an
/// administrator. Saved with `PUT /admin/company/languages`.
class CompanyLanguagesSection extends ConsumerStatefulWidget {
  const CompanyLanguagesSection({super.key});

  @override
  ConsumerState<CompanyLanguagesSection> createState() =>
      _CompanyLanguagesSectionState();
}

class _CompanyLanguagesSectionState
    extends ConsumerState<CompanyLanguagesSection> {
  /// The edited list and default; null until the person changes something.
  List<String>? _languages;
  String? _default;
  bool _busy = false;

  List<String> _current(Company? c) =>
      _languages ?? companyLanguagesOf(c);

  String _currentDefault(Company? c) =>
      _default ?? c?.defaultLanguage ?? 'en';

  void _edit(Company? c, void Function(List<String> l) change) {
    final next = [..._current(c)];
    change(next);
    setState(() {
      _languages = next;
      _default ??= _currentDefault(c);
    });
  }

  Future<void> _add(Company? company) async {
    final taken = _current(company).toSet();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => LanguageSearchDialog(exclude: taken),
    );
    if (code == null || !mounted) return;
    _edit(company, (l) => l.add(code));
  }

  Future<void> _save(Company? company) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final ok = await runAction(
        context,
        () => ref
            .read(dioProvider)
            .put<Map<String, dynamic>>(
              '/api/v1/admin/company/languages',
              data: {
                'languages': _current(company),
                'default_language': _currentDefault(company),
              },
            ),
        success: l.adminLanguagesSaved,
      );
      if (ok && mounted) {
        setState(() {
          _languages = null;
          _default = null;
        });
        ref.invalidate(meProvider);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final company = ref.watch(meProvider).value?.company;
    final languages = _current(company);
    final def = _currentDefault(company);
    final dirty = _languages != null || _default != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.adminLanguagesTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(l.adminLanguagesHelp),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ReorderableListView(
            key: const ValueKey('company-languages-list'),
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (from, to) => _edit(company, (list) {
              list.insert(to, list.removeAt(from));
            }),
            children: [
              for (final (i, code) in languages.indexed)
                ListTile(
                  key: ValueKey('company-language-$code'),
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text(languageName(code)),
                  subtitle: Text('${languageEnglishName(code)} · $code'),
                  trailing: Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (code == def)
                        Chip(label: Text(l.adminLanguagesDefault))
                      else
                        TextButton(
                          key: ValueKey('company-language-default-$code'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _languages ??= [...languages];
                                  _default = code;
                                }),
                          child: Text(l.adminLanguagesMakeDefault),
                        ),
                      IconButton(
                        key: ValueKey('company-language-remove-$code'),
                        tooltip: l.adminLanguagesRemove,
                        onPressed: _busy || code == def
                            ? null
                            : () => _edit(company, (list) => list.remove(code)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('company-language-add'),
              onPressed: _busy ? null : () => _add(company),
              icon: const Icon(Icons.add),
              label: Text(l.adminLanguagesAdd),
            ),
            FilledButton(
              key: const ValueKey('company-languages-save'),
              onPressed: _busy || !dirty ? null : () => _save(company),
              child: Text(l.save),
            ),
          ],
        ),
      ],
    );
  }
}

/// Picks one ISO 639-1 language by its own or English name or code; returns the code.
class LanguageSearchDialog extends StatefulWidget {
  const LanguageSearchDialog({super.key, this.exclude = const {}});

  /// Codes not offered (already chosen).
  final Set<String> exclude;

  @override
  State<LanguageSearchDialog> createState() => _LanguageSearchDialogState();
}

class _LanguageSearchDialogState extends State<LanguageSearchDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final q = _q.trim().toLowerCase();
    final hits = [
      for (final MapEntry(key: code, value: (english, own))
          in languageNames.entries)
        if (!widget.exclude.contains(code) &&
            (q.isEmpty ||
                code == q ||
                english.toLowerCase().contains(q) ||
                own.toLowerCase().contains(q)))
          (code, english, own),
    ];
    return AlertDialog(
      title: Text(l.adminLanguagesAdd),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('language-search'),
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: l.adminLanguagesSearch,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final (code, english, own) in hits)
                    ListTile(
                      key: ValueKey('language-pick-$code'),
                      dense: true,
                      title: Text(own),
                      subtitle: Text('$english · $code'),
                      onTap: () => Navigator.pop(context, code),
                    ),
                ],
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
