import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import 'controller.dart';
import 'model.dart';
import 'strings.dart';
import 'targets.dart';
import '../../app/environments.dart';
import '../../app/workspace.dart';

/// Where tutorial pages live (the chapter map); the narrator card stays out of the way there.
const tutorialRoute = '/tutorial';

/// Paints the dimmed scrim with a rounded cut-out over [hole], and a ring around the cut-out.
class SpotlightPainter extends CustomPainter {
  /// Creates a painter for [hole] (in the painted area's coordinates).
  const SpotlightPainter({
    required this.hole,
    required this.scrim,
    required this.ring,
  });

  /// The rectangle to leave clear (already inflated by the caller).
  final Rect hole;

  /// The colour of the dimmed area.
  final Color scrim;

  /// The colour of the ring around the hole.
  final Color ring;

  /// The corner radius of the cut-out.
  static const radius = Radius.circular(10);

  /// How far the cut-out extends beyond the target.
  static const padding = 6.0;

  /// The rounded rectangle that is cut out.
  RRect get cutOut => RRect.fromRectAndRadius(hole, radius);

  /// The scrim: everything except the cut-out (even-odd fill).
  Path scrimPath(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addRRect(cutOut);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(scrimPath(size), Paint()..color = scrim);
    canvas.drawRRect(
      cutOut,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(SpotlightPainter old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}

/// Wraps the app: paints the spotlight and the narrator card above everything, dialogs included.
/// Put it in `MaterialApp.builder`. [router] lets it follow the location and navigate; without
/// one route steps are only completed through `TutorialController.routeChanged`.
class TutorialHost extends ConsumerStatefulWidget {
  /// Creates the host around [child].
  const TutorialHost({super.key, required this.child, this.router});

  /// The app.
  final Widget child;

  /// The app's router, if any.
  final GoRouter? router;

  @override
  ConsumerState<TutorialHost> createState() => _TutorialHostState();
}

/// State of [TutorialHost]: follows the router's location.
class _TutorialHostState extends ConsumerState<TutorialHost> {
  final _content = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.router?.routeInformationProvider.addListener(_located);
    WidgetsBinding.instance.addPostFrameCallback((_) => _located());
  }

  @override
  void didUpdateWidget(TutorialHost old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routeInformationProvider.removeListener(_located);
      widget.router?.routeInformationProvider.addListener(_located);
    }
  }

  @override
  void dispose() {
    widget.router?.routeInformationProvider.removeListener(_located);
    super.dispose();
  }

  void _located() {
    final r = widget.router;
    if (!mounted) return;
    final routed = r?.routeInformationProvider.value.uri.toString();
    // A focused workspace tab shows its own location; the main area follows the router (and the
    // chapter map, a top-level page, always counts as where the router is).
    final tab = ref.read(workspaceProvider).activeTab;
    final onMap = routed?.startsWith(tutorialRoute) ?? false;
    final loc = onMap ? routed : (tab?.location ?? routed);
    if (loc == null) return;
    // Not while the framework is building: the listener can fire from a navigation.
    scheduleMicrotask(() {
      if (mounted) ref.read(tutorialProvider.notifier).routeChanged(loc);
    });
  }

  /// The render box of the app below the host (what a tap would reach).
  RenderBox? _contentBox() {
    final ro = _content.currentContext?.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceProvider, (_, _) => _located());
    final s = ref.watch(tutorialProvider);
    final scope = ref.watch(tutorialScopeProvider);
    final onMap = s.location.startsWith(tutorialRoute);
    final signedIn = scope.who.isNotEmpty;
    Widget? layer;
    if (s.loaded && signedIn) {
      if (s.activeId != null && !s.paused && !onMap) {
        layer = _RunningLayer(contentBox: _contentBox, router: widget.router);
      } else if (s.activeId != null && s.paused && !onMap) {
        layer = const _PausedPill();
      } else if (s.activeId == null &&
          !s.offered &&
          scope.kind == EnvironmentKind.tutorial &&
          !onMap) {
        layer = _OfferCard(router: widget.router);
      }
    }
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(key: _content, child: widget.child),
        ),
        // No full-screen Material here: it would take every tap meant for the app.
        if (layer != null) Positioned.fill(child: layer),
      ],
    );
  }
}

/// A target that is on screen: its id and its rectangle in the host's coordinates.
typedef VisibleTarget = ({String id, Rect rect});

/// The spotlight and narrator card of a running chapter.
class _RunningLayer extends ConsumerStatefulWidget {
  const _RunningLayer({required this.contentBox, required this.router});

  final RenderBox? Function() contentBox;
  final GoRouter? router;

  @override
  ConsumerState<_RunningLayer> createState() => _RunningLayerState();
}

/// State of [_RunningLayer]: finds the first visible target of the step, a few times a second
/// (the page may scroll, resize or open a dialog).
class _RunningLayerState extends ConsumerState<_RunningLayer> {
  VisibleTarget? _target;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _find());
    WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _find() {
    if (!mounted) return;
    final step = ref.read(tutorialProvider.notifier).step;
    final found = step == null ? null : _firstVisible(step.targets);
    if (found?.id != _target?.id || found?.rect != _target?.rect) {
      setState(() => _target = found);
    }
  }

  VisibleTarget? _firstVisible(List<String> ids) {
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.hasSize) return null;
    final registry = ref.read(tutorialTargetsProvider);
    final screen = Offset.zero & host.size;
    final content = widget.contentBox();
    for (final id in ids) {
      final ro = registry[id]?.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final rect = (ro.localToGlobal(Offset.zero, ancestor: host) & ro.size)
          .intersect(screen);
      if (rect.isEmpty) continue;
      if (content != null) {
        // Covered (by a dialog) or in a hidden tab: a tap there would not reach the target.
        final result = BoxHitTestResult();
        final global = host.localToGlobal(rect.center);
        content.hitTest(result, position: content.globalToLocal(global));
        if (!result.path.any((e) => e.target == ro)) continue;
      }
      return (id: id, rect: rect);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 800;
    final atTop = target != null && target.rect.center.dy > size.height * 0.55;
    return Stack(
      children: [
        if (target != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('tutorial-scrim'),
                painter: SpotlightPainter(
                  hole: target.rect.inflate(SpotlightPainter.padding),
                  scrim: Colors.black.withValues(alpha: 0.55),
                  ring: theme.colorScheme.primaryContainer,
                ),
              ),
            ),
          ),
        Align(
          alignment: atTop ? Alignment.topRight : Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              atTop ? (narrow ? 96 : 44) : 16,
              16,
              atTop ? 16 : (narrow ? 92 : 16),
            ),
            child: NarratorCard(
              targetVisible: target != null,
              router: widget.router,
            ),
          ),
        ),
      ],
    );
  }
}

/// The docked narrator card: chapter, step, text and the controls.
class NarratorCard extends ConsumerWidget {
  /// Creates the card; [targetVisible] tells whether the spotlight found its target.
  const NarratorCard({super.key, required this.targetVisible, this.router});

  /// Whether the step's target is on screen (otherwise the card offers to take the user there).
  final bool targetVisible;

  /// For "Take me there".
  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(tutorialProvider);
    final c = ref.read(tutorialProvider.notifier);
    final m = c.mission;
    final step = c.step;
    if (m == null || step == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final title = tutorialText(l, stepKey(m, step, 'Title'));
    final body = tutorialText(l, stepKey(m, step, 'Body'));
    final hint = step.hasHint
        ? tutorialText(l, stepKey(m, step, 'Hint'))
        : null;
    final route = step.route == null ? null : s.context.resolve(step.route!);
    final here = route != null && s.location == route;
    final completion = step.completion;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 420.0);
    return FocusTraversalGroup(
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: Semantics(
          key: ValueKey('${m.id}/${step.id}'),
          container: true,
          explicitChildNodes: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              minWidth: width,
              maxHeight: (MediaQuery.sizeOf(context).height * 0.55).clamp(
                180.0,
                double.infinity,
              ),
            ),
            child: Material(
              key: const ValueKey('tutorial-card'),
              elevation: 8,
              color: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surfaceTint,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The text scrolls when the screen is short or the text enlarged; the
                    // buttons below it stay reachable.
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tutorialText(l, missionKey(m, 'Title'))} · '
                              '${l.tutStepOf(s.stepIndex + 1, m.steps.length)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Semantics(
                              header: true,
                              liveRegion: true,
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(body, style: theme.textTheme.bodyMedium),
                            if (s.actionError != null) ...[
                              const SizedBox(height: 6),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  s.actionError!.status == 403
                                      ? l.tutActionForbidden
                                      : l.tutActionFailed(
                                          s.actionError!.reason,
                                        ),
                                  key: const ValueKey('tutorial-action-error'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                            if (hint != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                hint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (completion is ManualNext)
                          FilledButton(
                            key: const ValueKey('tutorial-next'),
                            onPressed: c.next,
                            child: Text(l.tutNext),
                          ),
                        if (completion is ActionCompletion)
                          FilledButton(
                            key: const ValueKey('tutorial-action'),
                            onPressed: s.actionBusy ? null : c.runAction,
                            child: Text(
                              tutorialText(l, stepKey(m, step, 'Action')),
                            ),
                          ),
                        if (route != null &&
                            !here &&
                            (!targetVisible || completion is OnRoute) &&
                            router != null)
                          OutlinedButton(
                            key: const ValueKey('tutorial-take-me'),
                            onPressed: () => router!.go(route),
                            child: Text(l.tutTakeMe),
                          ),
                        if (s.stepIndex > 0)
                          TextButton(
                            key: const ValueKey('tutorial-back'),
                            onPressed: c.back,
                            child: Text(l.tutBack),
                          ),
                        if (completion is! ManualNext)
                          TextButton(
                            key: const ValueKey('tutorial-skip'),
                            onPressed: c.skipStep,
                            child: Text(l.tutSkipStep),
                          ),
                        TextButton(
                          key: const ValueKey('tutorial-pause'),
                          onPressed: c.pause,
                          child: Text(l.tutPause),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small "Resume" pill shown while a chapter is paused.
class _PausedPill extends ConsumerWidget {
  const _PausedPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 800;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, narrow ? 92 : 16),
        child: Material(
          elevation: 6,
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.tutPaused,
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                TextButton(
                  key: const ValueKey('tutorial-resume'),
                  onPressed: () => ref.read(tutorialProvider.notifier).resume(),
                  child: Text(l.tutResume),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The offer on first sign-in in a tutorial environment.
class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final c = ref.read(tutorialProvider.notifier);
    final narrow = MediaQuery.sizeOf(context).width < 800;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, narrow ? 92 : 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Material(
              key: const ValueKey('tutorial-offer'),
              elevation: 8,
              color: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surfaceTint,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.tutOfferTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(l.tutOfferBody),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          key: const ValueKey('tutorial-offer-start'),
                          onPressed: () async {
                            c.markOffered();
                            final first = c.currentChapter?.id;
                            if (first != null) await c.start(first);
                          },
                          child: Text(l.tutOfferStart),
                        ),
                        TextButton(
                          key: const ValueKey('tutorial-offer-later'),
                          onPressed: c.markOffered,
                          child: Text(l.tutOfferLater),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
