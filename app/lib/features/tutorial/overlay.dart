import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import 'controller.dart';
import 'package:flutter/services.dart';
import 'conveyor_svg.dart';
import '../../shared/glb_viewer.dart';
import 'guidance.dart';
import 'model.dart';
import 'strings.dart';
import 'targets.dart';
import '../../app/environments.dart';
import '../../app/workspace.dart';
import '../../app/shortcuts/actions.dart';

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

  bool _reviewing = false;

  void _reviewingChanged(bool reviewing) {
    if (mounted) setState(() => _reviewing = reviewing);
  }

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
        layer = _RunningLayer(
          contentBox: _contentBox,
          router: widget.router,
          onReviewChanged: _reviewingChanged,
        );
      } else if (s.activeId == null && s.finishedId != null && !onMap) {
        layer = _FinishedCard(router: widget.router);
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
        // The spotlight and card come last in the reading order of the semantics tree. Without a
        // sort key their small node is interleaved by position with the nodes of dialogs and
        // suggestion lists; when the list opens the order changes and the web engine moves the DOM
        // node of the focused text field, which drops its focus and closes the list.
        if (layer != null && !_reviewing)
          Positioned.fill(
            child: Semantics(
              container: true,
              sortKey: const OrdinalSortKey(1000),
              child: layer,
            ),
          ),
      ],
    );
  }
}

/// A target that is on screen: its id and its rectangle in the host's coordinates.
typedef VisibleTarget = ({String id, Rect rect});

/// The spotlight and narrator card of a running chapter.
class _RunningLayer extends ConsumerStatefulWidget {
  const _RunningLayer({
    required this.contentBox,
    required this.router,
    required this.onReviewChanged,
  });

  final RenderBox? Function() contentBox;
  final GoRouter? router;
  final ValueChanged<bool> onReviewChanged;

  @override
  ConsumerState<_RunningLayer> createState() => _RunningLayerState();
}

/// State of [_RunningLayer]: finds the first visible target of the step, a few times a second
/// (the page may scroll, resize or open a dialog).
class _RunningLayerState extends ConsumerState<_RunningLayer>
    with WidgetsBindingObserver {
  VisibleTarget? _target;
  MissionStep? _showingControl;
  MissionStep? _missingControl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _find());
    WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _find() {
    if (!mounted) return;
    final step = ref.read(tutorialProvider.notifier).step;
    final found = step == null || step.targets.isEmpty
        ? null
        : _firstVisible(step.targets);
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

  Future<void> _showControl(MissionStep step) async {
    final registry = ref.read(tutorialTargetsProvider);
    final targetContext = step.targets
        .map((id) => registry[id]?.currentContext)
        .whereType<BuildContext>()
        .firstOrNull;
    if (targetContext != null) {
      await Scrollable.ensureVisible(targetContext, alignment: 0.5);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted ||
        !identical(ref.read(tutorialProvider.notifier).step, step)) {
      return;
    }
    final target = _firstVisible(step.targets);
    setState(() {
      _target = target;
      _showingControl = target == null ? null : step;
      _missingControl = target == null ? step : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tutorialProvider);
    final step = ref.read(tutorialProvider.notifier).step;
    final target = _target;
    final showingControl = step != null && identical(_showingControl, step);
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 800;
    final atTop = target != null && target.rect.center.dy > size.height / 2;
    final atLeft =
        size.width >= 880 &&
        target != null &&
        target.rect.center.dx > size.width / 2;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final moveDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
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
        AnimatedAlign(
          alignment: Alignment(atLeft ? -1 : 1, atTop ? -1 : 1),
          duration: moveDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedPadding(
            duration: moveDuration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
              16,
              atTop ? (narrow ? 96 : 44) : 16,
              16,
              atTop ? 16 : (narrow ? 92 : 16),
            ),
            child: showingControl
                ? FilledButton.tonal(
                    key: const ValueKey('tutorial-show-instructions'),
                    onPressed: () => setState(() => _showingControl = null),
                    child: Text(context.l10n.tutShowInstructions),
                  )
                : NarratorCard(
                    targetVisible: target != null,
                    router: widget.router,
                    onReviewChanged: widget.onReviewChanged,
                    onShowControl: step == null || step.targets.isEmpty
                        ? null
                        : () => _showControl(step),
                    controlMissing:
                        step != null && identical(_missingControl, step),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The docked narrator card: chapter, step, text and the controls.
class NarratorCard extends ConsumerWidget {
  const NarratorCard({
    super.key,
    required this.targetVisible,
    required this.onReviewChanged,
    this.onShowControl,
    this.controlMissing = false,
    this.router,
  });

  final bool targetVisible;
  final ValueChanged<bool> onReviewChanged;
  final VoidCallback? onShowControl;
  final bool controlMissing;
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
    final menuPath = tutorialMenuPath(l, m, step);

    void takeMe() {
      final navigatorContext =
          router!.routerDelegate.navigatorKey.currentContext;
      if (menuPath != null && navigatorContext != null) {
        final messenger = ScaffoldMessenger.maybeOf(navigatorContext);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(content: Text(l.tutShortcut(menuPath))),
        );
      }
      ref.read(workspaceProvider.notifier).focusHome();
      router!.go(route!);
    }

    final reviewNavigator =
        router?.routerDelegate.navigatorKey.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);

    Future<void> reviewAssist(NavigatorState navigator) async {
      final navigatorContext = navigator.context;
      final actions = tutorialManualActions(l, m, step);
      // The tutorial layer is above the router's dialogs in the web
      // accessibility tree. Remove it while the learner reviews the action.
      onReviewChanged(true);
      bool? confirmed;
      try {
        confirmed = await showDialog<bool>(
          context: navigatorContext,
          builder: (dialog) => AlertDialog(
            title: Text(l.tutAssistManual),
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (menuPath != null)
                  Text(
                    l.tutMenuPath(menuPath),
                    style: theme.textTheme.labelLarge,
                  ),
                const SizedBox(height: 8),
                for (final (index, action) in actions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${index + 1}. $action'),
                  ),
                const SizedBox(height: 8),
                Text(body),
                const SizedBox(height: 8),
                Text(l.tutAssistConfirm),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(l.tutAssistRun),
              ),
            ],
          ),
        );
      } finally {
        onReviewChanged(false);
      }
      if (confirmed == true &&
          navigatorContext.mounted &&
          identical(c.mission, m) &&
          identical(c.step, step)) {
        await c.runAction();
      }
    }

    final completion = step.completion;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 420.0);
    return FocusTraversalGroup(
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => reduceMotion
            ? child
            : FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
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
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
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
                            if (menuPath != null) ...[
                              Text(
                                l.tutMenuPath(menuPath),
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(body, style: theme.textTheme.bodyMedium),
                            if (m.id == 'conveyors' &&
                                (step.id == 'svgPreview' ||
                                    step.id == 'bomTab')) ...[
                              const SizedBox(height: 8),
                              const ConveyorAssemblySvg(),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 240,
                                child: FutureBuilder<ByteData>(
                                  future: rootBundle.load(
                                    'assets/models/CONV-BELT-1M_assembly.glb',
                                  ),
                                  builder: (context, snap) => snap.hasData
                                      ? GlbViewer(
                                          bytes: snap.data!.buffer
                                              .asUint8List(),
                                          filename:
                                              'CONV-BELT-1M_assembly.glb',
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                            if (m.id == 'welcome' && step.id == 'controls')
                              Text(
                                l.tutShortcutHelp(
                                  ShortcutAction.help.describe(),
                                ),
                              ),
                            if (m.id == 'helpdesk' && step.id == 'escalate')
                              Text(
                                l.shortcutHint(
                                  ShortcutAction.ticketEscalate.describe(),
                                ),
                              ),
                            if (onShowControl != null &&
                                (here || route == null || targetVisible))
                              TextButton(
                                key: const ValueKey('tutorial-show-control'),
                                onPressed: onShowControl,
                                child: Text(l.tutShowControl),
                              ),
                            if (controlMissing)
                              Semantics(
                                liveRegion: true,
                                child: Text(l.tutControlUnavailable),
                              ),
                            if (c.canAssist && s.actionBusy) ...[
                              const SizedBox(height: 6),
                              Semantics(
                                liveRegion: true,
                                child: Text(l.tutAssistRunning),
                              ),
                            ],
                            if (s.actionError != null) ...[
                              const SizedBox(height: 6),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  c.canAssist
                                      ? l.tutAssistFailed(s.actionError!.reason)
                                      : s.actionError!.status == 403
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (s.actionBusy) ...[
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Text(
                                    tutorialText(l, stepKey(m, step, 'Action')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (c.canAssist)
                          FilledButton(
                            key: const ValueKey('tutorial-assist'),
                            onPressed: s.actionBusy || reviewNavigator == null
                                ? null
                                : () => reviewAssist(reviewNavigator),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (s.actionBusy) ...[
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(child: Text(l.tutAssist)),
                              ],
                            ),
                          ),
                        if (route != null &&
                            !here &&
                            (!targetVisible || completion is OnRoute) &&
                            router != null)
                          OutlinedButton(
                            key: const ValueKey('tutorial-take-me'),
                            onPressed: takeMe,
                            child: Text(l.tutTakeMe),
                          ),
                        if (s.stepIndex > 0)
                          TextButton(
                            key: const ValueKey('tutorial-back'),
                            onPressed: c.back,
                            child: Text(l.tutBack),
                          ),
                        if (completion is! ManualNext && !c.canAssist)
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

/// Tallest a bottom-right card may be: what is left of the viewport after its padding.
double _cardMaxHeight(BuildContext context, bool narrow) {
  final h =
      MediaQuery.sizeOf(context).height - 16 - _cardBottomGap(context, narrow);
  return h < 120 ? 120 : h;
}

/// Space under a card: clears the bottom navigation, unless the viewport is too short for it.
double _cardBottomGap(BuildContext context, bool narrow) =>
    narrow && MediaQuery.sizeOf(context).height >= 480 ? 92 : 16;

/// The card shown when a chapter has just been finished: what comes next, never a dead end.
class _FinishedCard extends ConsumerWidget {
  const _FinishedCard({required this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final c = ref.read(tutorialProvider.notifier);
    final done = c.finishedChapter;
    if (done == null) return const SizedBox.shrink();
    final next = c.nextChapter;
    final name = tutorialText(l, missionKey(done, 'Title'));
    final narrow = MediaQuery.sizeOf(context).width < 800;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          _cardBottomGap(context, narrow),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: _cardMaxHeight(context, narrow),
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Material(
              key: const ValueKey('tutorial-finished'),
              elevation: 8,
              color: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surfaceTint,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              liveRegion: true,
                              child: Text(
                                l.tutFinishedTitle(name),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              next == null
                                  ? l.tutFinishedLast
                                  : l.tutFinishedNext(
                                      tutorialText(
                                        l,
                                        missionKey(next, 'Title'),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (next != null)
                          FilledButton(
                            key: const ValueKey('tutorial-finished-next'),
                            onPressed: () => c.start(next.id),
                            child: Text(l.tutStartNext),
                          ),
                        OutlinedButton(
                          key: const ValueKey('tutorial-finished-map'),
                          onPressed: () {
                            c.dismissFinished();
                            router?.go(tutorialRoute);
                          },
                          child: Text(l.tutBackToMap),
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
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          _cardBottomGap(context, narrow),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            elevation: 6,
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      l.tutPaused,
                      style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('tutorial-resume'),
                    onPressed: () =>
                        ref.read(tutorialProvider.notifier).resume(),
                    child: Text(l.tutResume),
                  ),
                ],
              ),
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
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          _cardBottomGap(context, narrow),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: _cardMaxHeight(context, narrow),
          ),
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
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
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
                          ],
                        ),
                      ),
                    ),
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
