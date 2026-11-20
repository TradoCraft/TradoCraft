/// The generic kanban board (ADR 0087): columns of cards, moved by dragging or by a menu.
library;

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'kanban_config.dart';
import 'kanban_controller.dart';

const double _columnWidth = 280;

/// What a drag carries: the card and the column it was picked up in.
class _Drag<T> {
  const _Drag(this.item, this.from);
  final T item;
  final String from;
}

class KanbanView<T> extends StatelessWidget {
  const KanbanView({super.key, required this.controller});

  final KanbanController<T> controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final error = controller.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  0,
                ),
                child: Material(
                  key: const ValueKey('kanban-error'),
                  color: theme.colorScheme.errorContainer,
                  borderRadius: Radii.medium,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.warningAmber,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: controller.dismissError,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final def in controller.config.columns)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: _Column<T>(controller: controller, def: def),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Column<T> extends StatelessWidget {
  const _Column({required this.controller, required this.def});

  final KanbanController<T> controller;
  final KanbanColumnDef def;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = controller.columns[def.id]!;
    final summary = controller.summaries[def.id];
    final accent = def.color ?? theme.colorScheme.outline;
    final config = controller.config;
    final create = (config.canCreateIn?.call(def.id) ?? true)
        ? config.onCreate
        : null;
    return DragTarget<_Drag<T>>(
      onWillAcceptWithDetails: (d) => d.data.from != def.id,
      onAcceptWithDetails: (d) =>
          controller.move(d.data.item, d.data.from, def.id),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Semantics(
          container: true,
          label: '${def.label}, ${state.total}',
          child: Container(
            key: ValueKey('kanban-column-${def.id}'),
            width: _columnWidth,
            decoration: BoxDecoration(
              color: hovering
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: Radii.large,
              border: Border(top: BorderSide(color: accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm,
                    Space.xs,
                    Space.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    def.label,
                                    style: theme.textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Text(
                                  '${state.total}',
                                  key: ValueKey('kanban-count-${def.id}'),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (summary != null)
                              Text(
                                summary,
                                key: ValueKey('kanban-summary-${def.id}'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (create != null)
                        IconButton(
                          key: ValueKey('kanban-add-${def.id}'),
                          tooltip: l.kanbanAdd(def.label),
                          icon: const Icon(AppIcons.add),
                          onPressed: () => create(def.id),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, KanbanColumnState<T> state) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (state.failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.kanbanColumnFailed, style: theme.textTheme.bodySmall),
            TextButton(
              key: ValueKey('kanban-retry-${def.id}'),
              onPressed: () => controller.reloadColumn(def.id),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return Center(
        child: Text(
          l.kanbanEmpty,
          key: ValueKey('kanban-empty-${def.id}'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.xs,
        Space.sm,
        Space.sm,
      ),
      children: [
        for (final item in state.items)
          _Card<T>(
            key: ValueKey('kanban-card-${controller.config.idOf(item)}'),
            controller: controller,
            item: item,
            column: def.id,
          ),
        if (state.remaining > 0)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: ValueKey('kanban-more-${def.id}'),
              onPressed: state.loadingMore
                  ? null
                  : () => controller.loadMore(def.id),
              child: Text(l.kanbanMore(state.remaining)),
            ),
          ),
      ],
    );
  }
}

class _Card<T> extends StatelessWidget {
  const _Card({
    super.key,
    required this.controller,
    required this.item,
    required this.column,
  });

  final KanbanController<T> controller;
  final T item;
  final String column;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = controller.config;
    final id = config.idOf(item);
    final others = [
      for (final c in config.columns)
        if (c.id != column) c,
    ];
    final moving = controller.isMoving(item);
    final card = Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: InkWell(
        borderRadius: Radii.medium,
        onTap: config.onOpen == null ? null : () => config.onOpen!(item),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.xl + Space.sm,
                Space.sm,
              ),
              child: config.cardBuilder(context, item),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: PopupMenuButton<String>(
                key: ValueKey('kanban-menu-$id'),
                tooltip: l.kanbanMoveTo,
                icon: const Icon(AppIcons.moreVert, size: 20),
                enabled: !moving,
                onSelected: (to) => controller.move(item, column, to),
                itemBuilder: (_) => [
                  for (final c in others)
                    PopupMenuItem<String>(
                      key: ValueKey('kanban-move-$id-${c.id}'),
                      value: c.id,
                      child: Text(l.kanbanMoveToColumn(c.label)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (moving) return Opacity(opacity: 0.6, child: card);
    // A short hold picks the card up, so scrolling by touch still works (as on the planning
    // board). The menu above is the way that needs no pointer.
    return LongPressDraggable<_Drag<T>>(
      data: _Drag(item, column),
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: _columnWidth - 2 * Space.sm,
          child: Opacity(opacity: 0.9, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}
