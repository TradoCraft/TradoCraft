import 'package:material_ui/material_ui.dart';

import '../../api/generated/models/ticket.dart';
import '../../l10n/l10n.dart';

/// The ticket properties that can be edited in the side panel and that a colleague's save can
/// change underneath an open form (A8). The contact link (`contactId`) is not a field of its
/// own: it follows the contact name.
enum TicketField {
  subject,
  status,
  priority,
  category,
  language,
  owner,
  customer,
  contactName,
  contactEmail,
  quotation,
  opportunity,
}

typedef TicketValues = Map<TicketField, String?>;

/// The saved values of [t] for the editable fields.
TicketValues ticketValues(Ticket t) => {
  TicketField.subject: t.subject,
  TicketField.status: t.status,
  TicketField.priority: t.priority,
  TicketField.category: t.category,
  TicketField.language: t.language,
  TicketField.owner: t.ownerUserId,
  TicketField.customer: t.customerId,
  TicketField.contactName: t.contactName,
  TicketField.contactEmail: t.contactEmail,
  TicketField.quotation: t.quotationId,
  TicketField.opportunity: t.opportunityId,
};

/// Whether two field values are the same; an empty text and no value are the same thing.
bool sameValue(String? a, String? b) => (a ?? '') == (b ?? '');

/// Fields on which [a] and [b] differ.
List<TicketField> changedFields(TicketValues a, TicketValues b) => [
  for (final f in TicketField.values)
    if (!sameValue(a[f], b[f])) f,
];

/// The outcome of laying a colleague's saved changes over an unsaved form.
class TicketMerge {
  const TicketMerge({
    required this.resolved,
    required this.conflicts,
    required this.takenFromTheirs,
  });

  /// The value of every field after the merge. Conflicts default to the user's own value.
  final TicketValues resolved;

  /// Fields both people changed, to different values: the user decides.
  final List<TicketField> conflicts;

  /// Fields only the colleague changed: taken over without asking.
  final List<TicketField> takenFromTheirs;
}

/// Three-way merge per field. [base] is the ticket as the form was opened (the last version the
/// user saw), [mine] the form as it stands, [theirs] the ticket as it is on the server now.
/// * only the colleague changed a field: take theirs;
/// * only the user changed it, or both made the same change: keep mine;
/// * both changed it differently: a conflict, mine until the user chooses.
TicketMerge mergeTicketFields({
  required TicketValues base,
  required TicketValues mine,
  required TicketValues theirs,
}) {
  final resolved = <TicketField, String?>{};
  final conflicts = <TicketField>[];
  final taken = <TicketField>[];
  for (final f in TicketField.values) {
    final b = base[f], m = mine[f], t = theirs[f];
    if (sameValue(t, b) || sameValue(m, t)) {
      resolved[f] = m;
    } else if (sameValue(m, b)) {
      resolved[f] = t;
      taken.add(f);
    } else {
      resolved[f] = m;
      conflicts.add(f);
    }
  }
  return TicketMerge(
    resolved: resolved,
    conflicts: conflicts,
    takenFromTheirs: taken,
  );
}

/// The label of a field in the property panel.
String ticketFieldLabel(BuildContext context, TicketField f) {
  final l = context.l10n;
  return switch (f) {
    TicketField.subject => l.subject,
    TicketField.status => l.status,
    TicketField.priority => l.priority,
    TicketField.category => l.category,
    TicketField.language => l.language,
    TicketField.owner => l.owner,
    TicketField.customer => l.customer,
    TicketField.contactName => l.contactName,
    TicketField.contactEmail => l.email,
    TicketField.quotation => l.quotation,
    TicketField.opportunity => l.opportunity,
  };
}

/// Shows the conflicting fields side by side and asks which value to keep for each. Returns the
/// chosen value per conflicting field, or null when the user backs out (nothing changes).
Future<TicketValues?> showTicketMergeDialog(
  BuildContext context, {
  required String theirName,
  required TicketMerge merge,
  required TicketValues mine,
  required TicketValues theirs,
  required String Function(TicketField field, String? value) valueLabel,
}) => showDialog<TicketValues>(
  context: context,
  builder: (_) => _TicketMergeDialog(
    theirName: theirName,
    merge: merge,
    mine: mine,
    theirs: theirs,
    valueLabel: valueLabel,
  ),
);

class _TicketMergeDialog extends StatefulWidget {
  const _TicketMergeDialog({
    required this.theirName,
    required this.merge,
    required this.mine,
    required this.theirs,
    required this.valueLabel,
  });

  final String theirName;
  final TicketMerge merge;
  final TicketValues mine;
  final TicketValues theirs;
  final String Function(TicketField field, String? value) valueLabel;

  @override
  State<_TicketMergeDialog> createState() => _TicketMergeDialogState();
}

class _TicketMergeDialogState extends State<_TicketMergeDialog> {
  /// Fields for which the user chose the colleague's value; every other conflict keeps theirs.
  final _takeTheirs = <TicketField>{};

  String _shown(TicketField f, String? v) {
    final text = widget.valueLabel(f, v);
    return text.isEmpty ? context.l10n.ticketMergeEmpty : text;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('ticket-merge-dialog'),
      title: Text(l.ticketMergeTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.ticketMergeIntro(widget.theirName)),
              const SizedBox(height: 12),
              for (final f in widget.merge.conflicts) ...[
                Text(
                  ticketFieldLabel(context, f),
                  style: theme.textTheme.titleSmall,
                ),
                RadioGroup<bool>(
                  groupValue: _takeTheirs.contains(f),
                  onChanged: (theirs) => setState(() {
                    if (theirs ?? false) {
                      _takeTheirs.add(f);
                    } else {
                      _takeTheirs.remove(f);
                    }
                  }),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        key: ValueKey('merge-mine-${f.name}'),
                        dense: true,
                        value: false,
                        title: Text(l.ticketMergeMine),
                        subtitle: Text(_shown(f, widget.mine[f])),
                      ),
                      RadioListTile<bool>(
                        key: ValueKey('merge-theirs-${f.name}'),
                        dense: true,
                        value: true,
                        title: Text(l.ticketMergeTheirs(widget.theirName)),
                        subtitle: Text(_shown(f, widget.theirs[f])),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.merge.takenFromTheirs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l.ticketMergeTakenOver(
                    widget.merge.takenFromTheirs
                        .map((f) => ticketFieldLabel(context, f))
                        .join(', '),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
          key: const ValueKey('ticket-merge-apply'),
          onPressed: () => Navigator.pop(context, {
            for (final f in widget.merge.conflicts)
              f: _takeTheirs.contains(f) ? widget.theirs[f] : widget.mine[f],
          }),
          child: Text(l.ticketMergeApply),
        ),
      ],
    );
  }
}
