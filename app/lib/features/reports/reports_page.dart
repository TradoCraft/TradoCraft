import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// The reports the person may open: their own and the ones shared in the company.
final savedReportsProvider = FutureProvider.autoDispose<List<SavedReport>>(
  (ref) => ref.watch(apiProvider).reports.reportsList(),
);

/// The objects, fields and relations the person can build reports from.
final reportCatalogProvider = FutureProvider.autoDispose<ReportCatalog>(
  (ref) => ref.watch(apiProvider).reports.reportsCatalog(),
);

/// Saved reports: open one to run it, or build a new one.
class SavedReportsPage extends ConsumerWidget {
  const SavedReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final reports = ref.watch(savedReportsProvider);
    final canWrite = can(ref, 'reports.write');
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.crTitle, style: Theme.of(context).textTheme.headlineSmall),
              if (canWrite)
                FilledButton.icon(
                  key: const ValueKey('new-report'),
                  icon: const Icon(AppIcons.add),
                  label: Text(l.crNew),
                  onPressed: () => context.go('/reports/new'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          reports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Column(
              children: [
                Text(errorMessage(e)),
                TextButton(
                  onPressed: () => ref.invalidate(savedReportsProvider),
                  child: Text(l.retry),
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(l.crEmpty),
                  )
                : Column(
                    children: [
                      for (final r in list)
                        Card(
                          child: ListTile(
                            key: ValueKey('report-${r.id}'),
                            leading: const Icon(AppIcons.tableChart),
                            title: Text(r.name),
                            subtitle: Text(
                              [
                                if (r.description.isNotEmpty) r.description,
                                l.crOwnedBy(r.ownerName),
                              ].join(' · '),
                            ),
                            trailing: Chip(
                              avatar: Icon(
                                r.shared ? AppIcons.people : AppIcons.lock,
                                size: 16,
                              ),
                              label: Text(r.shared ? l.crShared : l.crPrivate),
                            ),
                            onTap: () => context.go('/reports/${r.id}'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
