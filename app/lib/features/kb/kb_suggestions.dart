import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/markdown_view.dart';
import 'kb_common.dart';

/// The text to put in a reply for an article: its title and text, and the portal link when
/// customers can open the article.
String kbInsertionText(RenderedEntry r) {
  final b = StringBuffer(r.title);
  if (r.text.trim().isNotEmpty) b.write('\n\n${r.text.trim()}');
  if (r.link != null) b.write('\n\n${r.link}');
  return b.toString();
}

/// Just a pointer to the article: "Title: link".
String? kbInsertionLink(RenderedEntry r) =>
    r.link == null ? null : '${r.title}: ${r.link}';

/// "Suggested articles" for a ticket: entries that fit the subject and the latest customer
/// message, each with buttons to put its text or a link into the reply.
class KbSuggestionsPanel extends ConsumerStatefulWidget {
  const KbSuggestionsPanel({
    super.key,
    required this.ticketId,
    required this.onInsert,
  });

  final String ticketId;

  /// Receives the text to add to the reply.
  final ValueChanged<String> onInsert;

  @override
  ConsumerState<KbSuggestionsPanel> createState() => _KbSuggestionsPanelState();
}

class _KbSuggestionsPanelState extends ConsumerState<KbSuggestionsPanel> {
  late final Future<List<EntrySummary>> _suggestions = ref
      .read(apiProvider)
      .kb
      .suggestKbEntries(id: widget.ticketId);

  Future<void> _insert(String entryId, {required bool link}) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref
          .read(apiProvider)
          .kb
          .renderKbEntry(id: widget.ticketId, entryId: entryId);
      final text = link ? kbInsertionLink(r) : kbInsertionText(r);
      if (text == null) {
        messenger.showSnackBar(SnackBar(content: Text(l.kbNoPortalLink)));
        return;
      }
      widget.onInsert(text);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder<List<EntrySummary>>(
      future: _suggestions,
      builder: (context, snap) {
        final list = snap.data ?? const <EntrySummary>[];
        return ExpansionTile(
          key: const ValueKey('kb-suggestions'),
          initiallyExpanded: true,
          dense: true,
          tilePadding: EdgeInsets.zero,
          title: Text(l.kbSuggestedArticles),
          children: [
            if (snap.hasError)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(errorMessage(snap.error!)),
              )
            else if (snap.hasData && list.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l.kbNoSuggestions),
              ),
            for (final e in list)
              ListTile(
                key: ValueKey('suggestion-${e.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${e.number} · ${e.title}'),
                subtitle: HighlightedSnippet(e.snippet, maxLines: 2),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(kbAudienceLabel(l, e.visibility)),
                    ),
                    TextButton(
                      key: ValueKey('insert-text-${e.id}'),
                      onPressed: () => _insert(e.id, link: false),
                      child: Text(l.kbInsertText),
                    ),
                    TextButton(
                      key: ValueKey('insert-link-${e.id}'),
                      onPressed: () => _insert(e.id, link: true),
                      child: Text(l.kbInsertLink),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
