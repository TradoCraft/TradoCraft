import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/format.dart';
import '../definition.dart';
import '../runner_state.dart';

/// The evaluation's issues grouped by severity; tapping one with a field focuses that field.
class IssuesPanel extends StatelessWidget {
  const IssuesPanel({super.key, required this.issues, required this.onTap});

  final List<Issue> issues;
  final void Function(Issue issue) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (issues.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.checkCircle, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(l10n.cfgNoIssues),
            ],
          ),
        ),
      );
    }
    final groups = [
      (
        IssueSeverity.error,
        l10n.cfgErrors,
        AppIcons.error,
        theme.colorScheme.error,
      ),
      (
        IssueSeverity.warning,
        l10n.cfgWarnings,
        AppIcons.warningAmber,
        Colors.orange.shade800,
      ),
      (
        IssueSeverity.info,
        l10n.cfgInfo,
        AppIcons.info,
        theme.colorScheme.primary,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final (severity, title, icon, color) in groups)
          if (issues.any((i) => _sev(i) == severity)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '$title (${issues.where((i) => _sev(i) == severity).length})',
                style: theme.textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
            for (final i in issues.where((i) => _sev(i) == severity))
              ListTile(
                dense: true,
                leading: Icon(icon, color: color, size: 20),
                title: Text(i.message),
                subtitle: Text(
                  [i.code, i.scope].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                trailing: FieldRef.ofIssue(i) == null
                    ? null
                    : const Icon(AppIcons.chevronRight, size: 18),
                onTap: FieldRef.ofIssue(i) == null ? null : () => onTap(i),
              ),
          ],
      ],
    );
  }

  /// Unknown severities count as information.
  static IssueSeverity _sev(Issue i) =>
      i.severity == IssueSeverity.$unknown ? IssueSeverity.info : i.severity;
}

/// The generated line tree by section, with options nested under their line and prices for the
/// chosen customer. Selecting a line shows its trace in the Why? panel.
class LinesPanel extends StatelessWidget {
  const LinesPanel({
    super.key,
    required this.lines,
    required this.onSelect,
    this.selected,
    this.pricing,
    this.positions = const {},
    this.pricingError,
    this.hasCustomer = false,
  });

  final List<Line> lines;
  final List<int>? selected;
  final void Function(List<int> path) onSelect;
  final PricingPreview? pricing;
  final Map<String, int> positions;
  final String? pricingError;
  final bool hasCustomer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (lines.isEmpty) {
      return Center(child: Text(l10n.cfgNoLines));
    }
    final sections = <String, List<int>>{};
    for (var i = 0; i < lines.length; i++) {
      (sections[lines[i].section ?? ''] ??= []).add(i);
    }
    final p = pricing;
    final rows = <Widget>[];
    void add(Line l, List<int> path, int depth) {
      final key = linePath(path);
      final priced = positions[key];
      final pl = (p != null && priced != null && priced < p.lines.length)
          ? p.lines[priced]
          : null;
      final isSelected = selected != null && linePath(selected!) == key;
      rows.add(
        InkWell(
          key: ValueKey('line-$key'),
          onTap: () => onSelect(path),
          child: Container(
            color: isSelected ? theme.colorScheme.secondaryContainer : null,
            padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 6, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Text(number(l.quantity), textAlign: TextAlign.end),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          l.code,
                          if ((l.productName ?? '').isNotEmpty)
                            l.productName!
                          else if (pl != null && pl.description.isNotEmpty)
                            pl.description,
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: depth == 0 ? FontWeight.w500 : null,
                        ),
                      ),
                      if (l.percentOfParent != null)
                        Text(
                          '${number(l.percentOfParent)} %',
                          style: theme.textTheme.bodySmall,
                        ),
                      if ((l.comment ?? '').isNotEmpty)
                        Text(l.comment!, style: theme.textTheme.bodySmall),
                      if (l.productId == null)
                        Text(
                          l10n.cfgNotInCatalogue,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                if (pl != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(pl.lineTotal)),
                      Text(
                        '× ${money(pl.netUnitPrice)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      for (final (i, c) in l.children.indexed) {
        add(c, [...path, i], depth + 1);
      }
    }

    for (final s in sections.entries) {
      if (s.key.isNotEmpty || sections.length > 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              s.key.isEmpty ? '—' : s.key,
              style: theme.textTheme.titleSmall,
            ),
          ),
        );
      }
      for (final i in s.value) {
        add(lines[i], [i], 0);
      }
    }
    return Column(
      children: [
        Expanded(child: ListView(children: rows)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: !hasCustomer
              ? Text(
                  l10n.cfgPricesNeedCustomer,
                  style: theme.textTheme.bodySmall,
                )
              : pricingError != null
              ? Text(
                  pricingError!,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              : Row(
                  children: [
                    Text(l10n.totalExclVat, style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(
                      p == null ? '…' : money(p.subtotal),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Where the selected line comes from: the rule and, per contributing scope, the values read.
class WhyPanel extends StatelessWidget {
  const WhyPanel({super.key, required this.line});

  final Line? line;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final l = line;
    if (l == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.cfgSelectLine, textAlign: TextAlign.center),
        ),
      );
    }
    final t = l.trace;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${number(l.quantity)} × ${l.code}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(l10n.cfgRule(t.rule), style: theme.textTheme.bodyMedium),
        Text(
          t.rulePath,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
        for (final s in t.sources) ...[
          const Divider(height: 24),
          Text(s.label ?? s.scope, style: theme.textTheme.titleSmall),
          if (s.label != null) Text(s.scope, style: theme.textTheme.bodySmall),
          if (s.each != null) Text(l10n.cfgEach(displayValue(s.each))),
          const SizedBox(height: 4),
          Table(
            columnWidths: const {0: IntrinsicColumnWidth()},
            children: [
              for (final e
                  in (s.values is Map
                      ? (s.values as Map).entries
                      : const <MapEntry<Object?, Object?>>[]))
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16, bottom: 2),
                      child: Text(
                        '${e.key}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      displayValue(e.value),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
