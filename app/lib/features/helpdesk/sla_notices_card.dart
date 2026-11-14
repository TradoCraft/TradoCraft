import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import 'ticket_screen.dart' show teamsProvider;
import 'tickets_page.dart' show ticketPriorities;

final _noticesProvider = FutureProvider.autoDispose<SlaNoticeSettings>(
  (ref) => ref.watch(apiProvider).helpdesk.getSlaNotices(),
);

/// Which customers get an acknowledgement and a "your request is late" notice, per team and
/// priority (helpdesk administrators). Nothing is sent until a rule is added.
class SlaNoticesCard extends ConsumerStatefulWidget {
  const SlaNoticesCard({super.key});

  @override
  ConsumerState<SlaNoticesCard> createState() => _SlaNoticesCardState();
}

class _SlaNoticesCardState extends ConsumerState<SlaNoticesCard> {
  List<SlaNoticeRule>? _rules;

  Future<void> _save() => runAction(context, () async {
    await ref
        .read(apiProvider)
        .helpdesk
        .putSlaNotices(body: SlaNoticeSettings(rules: _rules ?? const []));
    ref.invalidate(_noticesProvider);
  }, success: context.l10n.saved);

  void _replace(
    int i, {
    required String? team,
    required String? priority,
    required bool ack,
    required bool breach,
  }) => setState(
    () => _rules![i] = SlaNoticeRule(
      teamId: team,
      priority: priority,
      ackEnabled: ack,
      breachEnabled: breach,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final notices = ref.watch(_noticesProvider);
    return Card(
      key: const ValueKey('sla-notices'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: notices.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (loaded) {
            final rules = _rules ??= [...loaded.rules];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.slaNotices, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l.slaNoticesHelp, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                if (rules.isEmpty) Text(l.slaNoticesNone),
                for (var i = 0; i < rules.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('notice-team-$i'),
                            initialValue:
                                teams.any((t) => t.id == rules[i].teamId)
                                ? rules[i].teamId
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.team,
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(l.slaNoticesAllTeams),
                              ),
                              for (final t in teams)
                                DropdownMenuItem<String?>(
                                  value: t.id,
                                  child: Text(t.name),
                                ),
                            ],
                            onChanged: (v) => _replace(
                              i,
                              team: v,
                              priority: rules[i].priority,
                              ack: rules[i].ackEnabled,
                              breach: rules[i].breachEnabled,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('notice-priority-$i'),
                            initialValue: rules[i].priority,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.priority,
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(l.slaNoticesAllPriorities),
                              ),
                              for (final p in ticketPriorities)
                                DropdownMenuItem<String?>(
                                  value: p,
                                  child: Text(l.ticketPriority(p)),
                                ),
                            ],
                            onChanged: (v) => _replace(
                              i,
                              team: rules[i].teamId,
                              priority: v,
                              ack: rules[i].ackEnabled,
                              breach: rules[i].breachEnabled,
                            ),
                          ),
                        ),
                        FilterChip(
                          key: ValueKey('notice-ack-$i'),
                          label: Text(l.slaNoticeAck),
                          selected: rules[i].ackEnabled,
                          onSelected: (v) => _replace(
                            i,
                            team: rules[i].teamId,
                            priority: rules[i].priority,
                            ack: v,
                            breach: rules[i].breachEnabled,
                          ),
                        ),
                        FilterChip(
                          key: ValueKey('notice-breach-$i'),
                          label: Text(l.slaNoticeBreach),
                          selected: rules[i].breachEnabled,
                          onSelected: (v) => _replace(
                            i,
                            team: rules[i].teamId,
                            priority: rules[i].priority,
                            ack: rules[i].ackEnabled,
                            breach: v,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('notice-remove-$i'),
                          tooltip: l.remove,
                          icon: const Icon(AppIcons.close),
                          onPressed: () => setState(() => rules.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      key: const ValueKey('notice-add'),
                      icon: const Icon(AppIcons.add),
                      label: Text(l.slaNoticesAdd),
                      onPressed: () => setState(
                        () => rules.add(
                          SlaNoticeRule(ackEnabled: true, breachEnabled: false),
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('notice-save'),
                      onPressed: _save,
                      child: Text(l.save),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
