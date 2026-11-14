import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment_ui.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'controller.dart';
import 'model.dart';
import 'strings.dart';

/// The chapter map: every chapter with its state (done, current, locked), and start, resume,
/// replay and skip. On a live environment it explains why the tutorial does not run and offers
/// to switch to a test or tutorial environment, or to add one.
class TutorialMapPage extends ConsumerWidget {
  /// Creates the page.
  const TutorialMapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scope = ref.watch(tutorialScopeProvider);
    final state = ref.watch(tutorialProvider);
    final controller = ref.read(tutorialProvider.notifier);
    final missions = ref.watch(tutorialMissionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tutTitle),
        leading: IconButton(
          icon: const Icon(AppIcons.arrowBack),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/quotations'),
        ),
      ),
      body: Column(
        children: [
          const EnvironmentBanner(),
          Expanded(
            child: scope.canRun
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(l.tutMapIntro),
                      const SizedBox(height: 12),
                      for (final (i, m) in missions.indexed)
                        _ChapterTile(
                          mission: m,
                          index: i,
                          state: state,
                          controller: controller,
                        ),
                    ],
                  )
                : const _LiveRefusal(),
          ),
        ],
      ),
    );
  }
}

/// Why the tutorial does not run on live data, and the ways out.
class _LiveRefusal extends StatelessWidget {
  const _LiveRefusal();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          key: const ValueKey('tutorial-live-refusal'),
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.lock, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l.tutLiveTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l.tutLiveBody),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('tutorial-switch-env'),
                      onPressed: () => showEnvironmentSwitcher(context),
                      child: Text(l.tutSwitchEnv),
                    ),
                    OutlinedButton(
                      key: const ValueKey('tutorial-add-env'),
                      onPressed: () => showAddEnvironmentDialog(context),
                      child: Text(l.tutAddEnv),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One chapter: state, summary and its buttons.
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.mission,
    required this.index,
    required this.state,
    required this.controller,
  });

  final Mission mission;
  final int index;
  final TutorialState state;
  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final m = mission;
    final done = state.completed.contains(m.id);
    final skipped = state.skipped.contains(m.id) && !done;
    final active = state.activeId == m.id;
    final unlocked = controller.isUnlocked(index);
    final started = (state.progress[m.id] ?? 0) > 0;
    final status = done
        ? l.tutStatusDone
        : skipped
        ? l.tutStatusSkipped
        : active
        ? l.tutStatusPaused
        : unlocked
        ? l.tutStatusCurrent
        : l.tutStatusLocked;
    final icon = done
        ? AppIcons.checkCircle
        : skipped
        ? AppIcons.skipNext
        : unlocked
        ? AppIcons.school
        : AppIcons.lock;

    Future<void> go(Future<StartResult> Function() action) async {
      final router = GoRouter.of(context);
      final result = await action();
      if (!context.mounted) return;
      if (result == StartResult.started) {
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/products');
        }
      }
    }

    return Card(
      key: ValueKey('tutorial-chapter-${m.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          container: true,
          label: '${tutorialText(l, missionKey(m, 'Title'))}, $status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(child: Icon(icon)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$index · ${tutorialText(l, missionKey(m, 'Title'))}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    key: ValueKey('tutorial-status-${m.id}'),
                    label: Text(status),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(tutorialText(l, missionKey(m, 'Summary'))),
              if (active || started && !done) ...[
                const SizedBox(height: 6),
                Text(
                  l.tutStepOf(
                    (active ? state.stepIndex : state.progress[m.id] ?? 0) + 1,
                    m.steps.length,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!done && unlocked && (active || started))
                    FilledButton(
                      key: ValueKey('tutorial-resume-${m.id}'),
                      onPressed: () => go(() => controller.resume(m.id)),
                      child: Text(l.tutResume),
                    ),
                  if (!done && unlocked && !active && !started)
                    FilledButton(
                      key: ValueKey('tutorial-start-${m.id}'),
                      onPressed: () => go(() => controller.start(m.id)),
                      child: Text(l.tutStart),
                    ),
                  if (done || skipped || started || active)
                    OutlinedButton(
                      key: ValueKey('tutorial-replay-${m.id}'),
                      onPressed: () => go(() => controller.start(m.id)),
                      child: Text(l.tutReplay),
                    ),
                  if (!done && !skipped && unlocked)
                    TextButton(
                      key: ValueKey('tutorial-skip-${m.id}'),
                      onPressed: state.loaded
                          ? () => controller.skipChapter(m.id)
                          : null,
                      child: Text(l.tutSkipChapter),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
