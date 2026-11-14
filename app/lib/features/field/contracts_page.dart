import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import '../../shared/app_icons.dart';

extension ContractLabels on AppLocalizations {
  String contractStatus(String s) => switch (s) {
    'draft' => statusDraft,
    'active' => active,
    'suspended' => contractSuspended,
    _ => contractEnded,
  };
}

/// Maintenance contracts: who is covered, and the visits that become planned jobs by themselves.
class ContractsPage extends ConsumerStatefulWidget {
  const ContractsPage({super.key});

  @override
  ConsumerState<ContractsPage> createState() => _ContractsPageState();
}

class _ContractsPageState extends ConsumerState<ContractsPage> {
  Future<List<ContractSummary>>? _contracts;
  String _status = 'all';

  void _reload() => setState(
    () => _contracts = ref
        .read(apiProvider)
        .field
        .listContracts(status: _status == 'all' ? null : _status),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final planner =
        ref.watch(meProvider).value?.permissions.contains('field.plan') ??
        false;
    _contracts ??= ref
        .read(apiProvider)
        .field
        .listContracts(status: _status == 'all' ? null : _status);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.contracts),
        actions: [
          if (planner)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.newContract),
                onPressed: () async {
                  await context.push('/jobs/contracts/new');
                  if (mounted) _reload();
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in [
                  'all',
                  'draft',
                  'active',
                  'suspended',
                  'ended',
                ])
                  ChoiceChip(
                    label: Text(s == 'all' ? l.all : l.contractStatus(s)),
                    selected: _status == s,
                    onSelected: (_) {
                      _status = s;
                      _reload();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ContractSummary>>(
              future: _contracts,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(child: Text(errorMessage(s.error!)));
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = s.data!;
                if (list.isEmpty) return Center(child: Text(l.noContracts));
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in list)
                      Card(
                        child: ListTile(
                          onTap: () async {
                            await context.push('/jobs/contracts/${c.id}');
                            if (mounted) _reload();
                          },
                          title: Text('${c.number} · ${c.title}'),
                          subtitle: Text(
                            [
                              c.customerName,
                              '${date(c.startDate)} – ${date(c.endDate)}',
                              if (c.openJobs > 0)
                                l.contractOpenJobs('${c.openJobs}'),
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                          trailing: Chip(
                            label: Text(l.contractStatus(c.status)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
