import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../todo/todo_repository.dart';

/// Role-aware overview screen surfacing open work items and recent workspace tabs.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final me = ref.watch(meProvider).value;
    final perms = me?.permissions ?? const <String>[];
    final tabs = ref.watch(workspaceProvider).tabs;

    final cards = <(String, Widget)>[
      if (tabs.isNotEmpty) ('tabs', _WorkspaceTabsCard(tabs: tabs)),
      if (perms.contains('todo.use')) ('todo', const _TodoSummaryCard()),
      if (perms.contains('helpdesk.read'))
        (
          'helpdesk',
          _ApiListCard(
            title: l.helpdesk,
            icon: AppIcons.supportAgent,
            path: '/api/v1/tickets',
            query: const {'status': 'open', 'limit': 5},
            seeAllRoute: '/helpdesk',
            labelOf: (item) =>
                '${item['number'] ?? ''} · ${item['subject'] ?? ''}'.trim(),
            routeOf: (item) => '/helpdesk/${item['id']}',
          ),
        ),
      if (perms.contains('quotations.read'))
        (
          'quotations',
          _ApiListCard(
            title: l.quotations,
            icon: AppIcons.requestQuote,
            path: '/api/v1/quotations',
            query: const {'limit': 5},
            seeAllRoute: '/quotations',
            labelOf: (item) =>
                '${item['number'] ?? ''} · ${item['customer_name'] ?? ''}'
                    .trim(),
            routeOf: (item) => '/quotations/${item['id']}',
          ),
        ),
      if (perms.contains('purchasing.read'))
        (
          'purchasing',
          _ApiListCard(
            title: l.purchasing,
            icon: AppIcons.shoppingCart,
            path: '/api/v1/purchase-orders',
            query: const {'limit': 5},
            seeAllRoute: '/purchasing',
            labelOf: (item) =>
                '${item['number'] ?? ''} · ${item['supplier_name'] ?? ''}'
                    .trim(),
            routeOf: (item) => '/purchase-orders/${item['id']}',
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text(
          l.workspaceOverview,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: Space.md),
        if (cards.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Text('—'),
            ),
          )
        else
          Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              for (final (id, card) in cards)
                ConstrainedBox(
                  key: ValueKey('home-card-$id'),
                  constraints: const BoxConstraints(
                    minWidth: 280,
                    maxWidth: 420,
                  ),
                  child: card,
                ),
            ],
          ),
      ],
    );
  }
}

class _WorkspaceTabsCard extends ConsumerWidget {
  const _WorkspaceTabsCard({required this.tabs});
  final List<WorkTab> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return _SectionCard(
      title: l.openTabs,
      icon: AppIcons.tab,
      children: [
        for (final t in tabs)
          ListTile(
            dense: true,
            title: Text(
              t.title?.isNotEmpty == true ? t.title! : t.location,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => ref.read(workspaceProvider.notifier).focus(t.id),
          ),
      ],
    );
  }
}

class _TodoSummaryCard extends ConsumerWidget {
  const _TodoSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(todoRepositoryProvider);
    return FutureBuilder<List<TodoItem>>(
      future: repo.list(TodoFilter.open),
      builder: (context, snap) {
        final items = (snap.data ?? const <TodoItem>[]).take(5).toList();
        return _SectionCard(
          title: l.todoTitle,
          icon: AppIcons.check,
          onHeaderTap: () => context.go('/todo'),
          children: [
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text(errorMessage(snap.error!)),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Text('—'),
              )
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  title: Text(item.title, overflow: TextOverflow.ellipsis),
                  onTap: () => context.go('/todo'),
                ),
          ],
        );
      },
    );
  }
}

class _ApiListCard extends ConsumerStatefulWidget {
  const _ApiListCard({
    required this.title,
    required this.icon,
    required this.path,
    required this.query,
    required this.seeAllRoute,
    required this.labelOf,
    required this.routeOf,
  });

  final String title;
  final IconData icon;
  final String path;
  final Map<String, Object?> query;
  final String seeAllRoute;
  final String Function(Map<String, dynamic> item) labelOf;
  final String Function(Map<String, dynamic> item) routeOf;

  @override
  ConsumerState<_ApiListCard> createState() => _ApiListCardState();
}

class _ApiListCardState extends ConsumerState<_ApiListCard> {
  late final Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await ref
        .read(dioProvider)
        .get<Object?>(widget.path, queryParameters: widget.query);
    final data = res.data;
    final raw = data is Map ? data['items'] : data;
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <Map<String, dynamic>>[];
        return _SectionCard(
          title: widget.title,
          icon: widget.icon,
          onHeaderTap: () => context.go(widget.seeAllRoute),
          children: [
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text(errorMessage(snap.error!)),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Text('—'),
              )
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  title: Text(
                    widget.labelOf(item),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push(widget.routeOf(item)),
                ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.onHeaderTap,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            trailing: onHeaderTap == null
                ? null
                : const Icon(Icons.chevron_right),
            onTap: onHeaderTap,
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}
