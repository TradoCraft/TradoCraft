import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';

/// Moves chosen messages of a ticket into a new ticket. Returns the new ticket, or null.
Future<TicketDetail?> showSplitDialog(
  BuildContext context, {
  required Ticket ticket,
  required List<Article> articles,
}) => showDialog<TicketDetail>(
  context: context,
  builder: (_) => SplitDialog(ticket: ticket, articles: articles),
);

class SplitDialog extends ConsumerStatefulWidget {
  const SplitDialog({super.key, required this.ticket, required this.articles});
  final Ticket ticket;
  final List<Article> articles;

  @override
  ConsumerState<SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends ConsumerState<SplitDialog> {
  final _selected = <String>{};
  final _subject = TextEditingController();
  String? _error;
  bool _busy = false;

  /// At least one message moves and at least one stays.
  bool get _valid =>
      _selected.isNotEmpty && _selected.length < widget.articles.length;

  Future<void> _split() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(apiProvider)
          .helpdesk
          .splitTicket(
            id: widget.ticket.id,
            body: SplitInput(
              articleIds: _selected.toList(),
              subject: _subject.text.trim().isEmpty
                  ? null
                  : _subject.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  String _who(Article a) =>
      a.authorName ?? (a.fromName.isEmpty ? a.fromAddress : a.fromName);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.splitTicket} · ${widget.ticket.number}'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.splitHelp),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('split-subject'),
              controller: _subject,
              decoration: InputDecoration(labelText: l.splitSubjectOptional),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final a in widget.articles)
                    CheckboxListTile(
                      key: ValueKey('split-${a.id}'),
                      dense: true,
                      value: _selected.contains(a.id),
                      onChanged: _busy
                          ? null
                          : (v) => setState(
                              () => v == true
                                  ? _selected.add(a.id)
                                  : _selected.remove(a.id),
                            ),
                      title: Text(
                        a.body.trim().replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_who(a)} · ${date(a.createdAt)}'
                        '${a.attachments.isEmpty ? '' : ' · ${l.splitFiles(a.attachments.length)}'}',
                      ),
                    ),
                ],
              ),
            ),
            if (_selected.length == widget.articles.length)
              Text(
                l.splitKeepOne,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirm-split'),
          onPressed: _valid && !_busy ? _split : null,
          child: Text(l.splitAction),
        ),
      ],
    );
  }
}
