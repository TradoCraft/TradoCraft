import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart' show dioProvider, errorMessage;
import '../../app/environments.dart';
import '../../app/session.dart';
import '../../l10n/app_localizations.dart';
import '../field/offline/kv_store.dart';
import 'api_events.dart';
import 'missions.dart';
import 'model.dart';
import 'simulated_mail.dart' show newMessageId;

/// Where the tutorial's progress lives: one environment and one user.
class TutorialScope {
  /// Creates a scope.
  const TutorialScope({
    required this.envId,
    required this.kind,
    required this.who,
  });

  /// The environment's id.
  final String envId;

  /// What the environment is for; the tutorial refuses to run on live.
  final EnvironmentKind kind;

  /// The signed-in user (dev e-mail, or the company for a token), empty when signed out.
  final String who;

  /// Whether a mission may run here (never on live data).
  bool get canRun => kind != EnvironmentKind.live;

  /// The key in the device storage.
  String get storageKey => 'tutorial.v1.$envId.$who';

  @override
  bool operator ==(Object other) =>
      other is TutorialScope &&
      other.envId == envId &&
      other.kind == kind &&
      other.who == who;

  @override
  int get hashCode => Object.hash(envId, kind, who);
}

/// The `sub` claim of a JWT access token (the stable user id), or null when [token] is not one.
/// Sessions carry no user id of their own; without a readable subject the scope falls back to
/// the company alone.
String? tokenSubject(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final sub = json is Map ? json['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}

/// The environment and user the tutorial currently belongs to.
final tutorialScopeProvider = Provider<TutorialScope>((ref) {
  final env = ref.watch(activeEnvironmentProvider);
  final s = ref.watch(sessionProvider);
  final who = (s.devUser?.isNotEmpty ?? false)
      ? 'dev:${s.devUser}'
      : (s.accessToken?.isNotEmpty ?? false)
      ? 'token:${tokenSubject(s.accessToken!) ?? ''}:${s.companyId ?? ''}'
      : '';
  return TutorialScope(envId: env.id, kind: env.kind, who: who);
});

/// The chapters; tests may override this.
final tutorialMissionsProvider = Provider<List<Mission>>((ref) => allMissions);

/// What came of asking to start a chapter.
enum StartResult {
  /// Running now.
  started,

  /// Refused: the environment is live.
  refusedLive,

  /// Refused: an earlier chapter is not done (or skipped) yet.
  locked,

  /// Refused: no such chapter, or nobody is signed in.
  unavailable,
}

/// Everything the tutorial remembers and shows.
/// Why a step's action failed: the HTTP status when there was one, and a readable reason.
class TutorialActionError {
  /// Creates the error.
  const TutorialActionError(this.status, this.reason);

  /// The HTTP status, or null.
  final int? status;

  /// The reason in words.
  final String reason;
}

/// The language the app shows, as one of the supported ones: the user's choice when there is
/// one, else the first language of the device's list that the app has (so an unsupported first
/// device language falls through to the next one), else English.
String resolveTutorialLanguage(Locale? chosen, List<Locale> device) {
  final supported = {
    for (final l in AppLocalizations.supportedLocales) l.languageCode,
  };
  if (chosen != null) {
    return supported.contains(chosen.languageCode) ? chosen.languageCode : 'en';
  }
  for (final l in device) {
    if (supported.contains(l.languageCode)) return l.languageCode;
  }
  return 'en';
}

class TutorialState {
  /// Creates a state.
  const TutorialState({
    this.loaded = false,
    this.completed = const {},
    this.skipped = const {},
    this.progress = const {},
    this.values = const {},
    this.activeId,
    this.stepIndex = 0,
    this.paused = false,
    this.offered = false,
    this.location = '',
    this.actionBusy = false,
    this.actionError,
  });

  /// Whether the stored progress has been read.
  final bool loaded;

  /// Chapters finished.
  final Set<String> completed;

  /// Chapters skipped.
  final Set<String> skipped;

  /// The step each started chapter had reached (for resuming).
  final Map<String, int> progress;

  /// Captured values (see [MissionContext]).
  final Map<String, String> values;

  /// The chapter in progress (running or paused), if any.
  final String? activeId;

  /// The current step of [activeId].
  final int stepIndex;

  /// Whether the running chapter is paused.
  final bool paused;

  /// Whether the first-sign-in offer was answered.
  final bool offered;

  /// The location the app shows (not stored).
  final String location;

  /// Whether the step's action button is running (it is disabled meanwhile; not stored).
  final bool actionBusy;

  /// Why the last run of the action button failed (not stored); null when it did not.
  final TutorialActionError? actionError;

  /// A chapter is on and not paused.
  bool get running => activeId != null && !paused;

  /// The captured values as a context.
  MissionContext get context => MissionContext(values);

  /// Whether [id] is finished or skipped.
  bool isDone(String id) => completed.contains(id) || skipped.contains(id);

  /// A copy with the given fields replaced.
  TutorialState copyWith({
    bool? loaded,
    Set<String>? completed,
    Set<String>? skipped,
    Map<String, int>? progress,
    Map<String, String>? values,
    Object? activeId = _keep,
    int? stepIndex,
    bool? paused,
    bool? offered,
    String? location,
    bool? actionBusy,
    Object? actionError = _keep,
  }) => TutorialState(
    loaded: loaded ?? this.loaded,
    completed: completed ?? this.completed,
    skipped: skipped ?? this.skipped,
    progress: progress ?? this.progress,
    values: values ?? this.values,
    activeId: identical(activeId, _keep) ? this.activeId : activeId as String?,
    stepIndex: stepIndex ?? this.stepIndex,
    paused: paused ?? this.paused,
    offered: offered ?? this.offered,
    location: location ?? this.location,
    actionBusy: actionBusy ?? this.actionBusy,
    actionError: identical(actionError, _keep)
        ? this.actionError
        : actionError as TutorialActionError?,
  );

  static const Object _keep = Object();

  /// The stored form.
  Map<String, Object?> toJson() => {
    'completed': completed.toList(),
    'skipped': skipped.toList(),
    'progress': progress,
    'values': values,
    'active': activeId,
    'step': stepIndex,
    'offered': offered,
  };
}

/// Runs the story missions: which step is current, what is done, and how steps finish.
///
/// A step finishes when an API event, a route, a probe, the Next button or an action says so.
/// The state is stored per environment and user; a restart comes back paused.
class TutorialController extends Notifier<TutorialState> {
  late TutorialScope _scope;
  late Future<void> _ready;
  int _gen = 0;

  /// Completes when the stored progress has been read (for tests).
  Future<void> get ready => _ready;

  List<Mission> get _missions => ref.read(tutorialMissionsProvider);

  /// The chapter in progress.
  Mission? get mission =>
      _missions.where((m) => m.id == state.activeId).firstOrNull;

  /// The current step.
  MissionStep? get step {
    final m = mission;
    if (m == null || state.stepIndex < 0 || state.stepIndex >= m.steps.length) {
      return null;
    }
    return m.steps[state.stepIndex];
  }

  /// The scope (environment and user) this state belongs to.
  TutorialScope get scope => _scope;

  @override
  TutorialState build() {
    _scope = ref.watch(tutorialScopeProvider);
    final bus = ref.read(apiEventBusProvider);
    final sub = bus.stream.listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      bus.active = false;
      _gen++;
    });
    bus.active = false;
    _ready = _load();
    return const TutorialState();
  }

  Future<void> _load() async {
    final scope = _scope;
    var loaded = const TutorialState(loaded: true);
    try {
      final raw = await ref.read(kvStoreProvider).get(scope.storageKey);
      if (raw != null) loaded = _parse(raw);
    } catch (_) {
      // Unreadable progress is ignored: the tutorial starts from the beginning.
    }
    if (!ref.mounted || scope != _scope) return;
    // A restart comes back paused, and never on live data.
    state = loaded.copyWith(
      paused: loaded.activeId != null,
      activeId: scope.canRun ? loaded.activeId : null,
      location: state.location,
    );
  }

  TutorialState _parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const TutorialState(loaded: true);
      Set<String> strings(Object? v) => v is List
          ? {
              for (final e in v)
                if (e is String) e,
            }
          : <String>{};
      final ids = _missions.map((m) => m.id).toSet();
      final active = j['active'];
      return TutorialState(
        loaded: true,
        completed: strings(j['completed']).intersection(ids),
        skipped: strings(j['skipped']).intersection(ids),
        progress: {
          if (j['progress'] is Map)
            for (final e in (j['progress'] as Map).entries)
              if (e.key is String && e.value is int)
                e.key as String: e.value as int,
        },
        values: {
          if (j['values'] is Map)
            for (final e in (j['values'] as Map).entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        },
        activeId: active is String && ids.contains(active) ? active : null,
        stepIndex: j['step'] is int ? j['step'] as int : 0,
        offered: j['offered'] == true,
      );
    } catch (_) {
      return const TutorialState(loaded: true);
    }
  }

  void _set(TutorialState s) {
    state = s;
    final bus = ref.read(apiEventBusProvider);
    bus.active = s.running && step != null;
    final scope = _scope;
    // Fire and forget: failing to store progress must not stop the tutorial.
    unawaited(
      ref
          .read(kvStoreProvider)
          .set(scope.storageKey, jsonEncode(s.toJson()))
          .catchError((Object _) {}),
    );
  }

  /// Whether the chapter at [index] may be started: every chapter before it is done or skipped.
  bool isUnlocked(int index) {
    final ms = _missions;
    for (var i = 0; i < index && i < ms.length; i++) {
      if (!state.isDone(ms[i].id)) return false;
    }
    return true;
  }

  /// The first chapter that is not done or skipped.
  Mission? get currentChapter =>
      _missions.where((m) => !state.isDone(m.id)).firstOrNull;

  /// Starts chapter [id] from its first step (also to replay a finished one).
  Future<StartResult> start(String id) async {
    await _ready;
    final index = _missions.indexWhere((m) => m.id == id);
    if (index < 0 || _scope.who.isEmpty) return StartResult.unavailable;
    if (!_scope.canRun) return StartResult.refusedLive;
    if (!isUnlocked(index) && !state.isDone(id)) return StartResult.locked;
    _begin(id, 0);
    return StartResult.started;
  }

  /// Carries on with chapter [id] where it stopped (or the paused one when [id] is null).
  Future<StartResult> resume([String? id]) async {
    await _ready;
    final target = id ?? state.activeId;
    final index = _missions.indexWhere((m) => m.id == target);
    if (index < 0 || _scope.who.isEmpty) return StartResult.unavailable;
    if (!_scope.canRun) return StartResult.refusedLive;
    if (!isUnlocked(index) && !state.isDone(target!)) return StartResult.locked;
    final m = _missions[index];
    final at = target == state.activeId
        ? state.stepIndex
        : (state.progress[target] ?? 0);
    _begin(target!, at.clamp(0, m.steps.length - 1));
    return StartResult.started;
  }

  void _begin(String id, int at, {bool probe = true}) {
    _gen++;
    final samePending = _actionKey == '$id/$at';
    if (!samePending) {
      _actionKey = null;
      _actionOwner = null;
      _retained.clear();
    }
    _set(
      state.copyWith(
        activeId: id,
        stepIndex: at,
        paused: false,
        actionBusy: samePending ? state.actionBusy : false,
        actionError: samePending ? state.actionError : null,
      ),
    );
    _enterStep(probe: probe);
  }

  /// Checks what the new current step needs: an already satisfied location, then the probe.
  void _enterStep({bool probe = true}) {
    final s = step;
    if (s == null || !state.running) return;
    final c = s.completion;
    if (c is OnRoute && state.location.isNotEmpty) {
      if (c.matches(state.location, state.context)) {
        _complete(const {});
        return;
      }
    }
    final p = s.probe;
    if (probe && p != null) unawaited(_runProbe(s, p, _gen));
  }

  Future<void> _runProbe(MissionStep s, Probe p, int gen) async {
    final path = state.context.resolve(p.path);
    if (path == null) return;
    // Query values may hold `{name}` placeholders too.
    Map<String, dynamic>? query;
    if (p.query != null) {
      query = {};
      for (final e in p.query!.entries) {
        final v = e.value;
        final r = v is String ? state.context.resolve(v) : v;
        if (r == null) return;
        query[e.key] = r;
      }
    }
    try {
      final res = await ref
          .read(dioProvider)
          .get<Object?>(
            path,
            queryParameters: query,
            options: Options(extra: {tutorialProbeExtra: true}),
          );
      if (!ref.mounted || gen != _gen || step != s || !state.running) return;
      final ctx = state.context;
      Object? data = res.data;
      if (p.expand != null) {
        // At most 20 records, read in batches of 5 until one of the batches settles the probe.
        final details = <Object?>[];
        final paths = p.expand!(data, ctx).take(20).toList();
        for (var i = 0; i < paths.length; i += 5) {
          for (final path in paths.skip(i).take(5)) {
            final d = await ref
                .read(dioProvider)
                .get<Object?>(
                  path,
                  options: Options(extra: {tutorialProbeExtra: true}),
                );
            details.add(d.data);
          }
          if (!ref.mounted || gen != _gen || step != s || !state.running) return;
          if (p.done(details, ctx)) break;
        }
        if (!ref.mounted || gen != _gen || step != s || !state.running) return;
        data = details;
      }
      if (p.done(data, ctx)) {
        _complete(p.capture?.call(data, ctx) ?? const {});
      }
    } catch (_) {
      // A failed probe only means "not known to be done".
    }
  }

  void _onEvent(ApiEvent e) {
    // Calls made as another session (an environment switch in flight) do not count.
    if (e.scope != null &&
        e.scope != tutorialSessionId(ref.read(sessionProvider))) {
      return;
    }
    final s = step;
    if (s == null || !state.running) return;
    final c = s.completion;
    if (c is OnApi && c.matches(e, state.context)) {
      _complete({...?s.capture?.call(e.json)});
    }
  }

  /// Tells the tutorial which location the app shows (completes route steps).
  void routeChanged(String location) {
    if (location == state.location) return;
    state = state.copyWith(location: location);
    final s = step;
    if (s == null || !state.running) return;
    final c = s.completion;
    if (c is OnRoute && c.matches(location, state.context)) _complete(const {});
  }

  void _complete(Map<String, String> captured) {
    final m = mission;
    if (m == null) return;
    var values = state.values;
    if (captured.isNotEmpty) values = {...values, ...captured};
    final next = state.stepIndex + 1;
    _gen++;
    _actionKey = null;
    _actionOwner = null;
    _retained.clear();
    if (next >= m.steps.length) {
      _set(
        state.copyWith(
          actionBusy: false,
          actionError: null,
          values: values,
          completed: {...state.completed, m.id},
          progress: {...state.progress, m.id: 0},
          activeId: null,
          stepIndex: 0,
          paused: false,
        ),
      );
      return;
    }
    _set(
      state.copyWith(
        actionBusy: false,
        actionError: null,
        values: values,
        stepIndex: next,
        progress: {...state.progress, m.id: next},
      ),
    );
    _enterStep();
  }

  /// Finishes a manual step (Next).
  void next() {
    if (!state.running || step == null) return;
    _complete(const {});
  }

  /// Leaves the current step undone and moves on.
  void skipStep() => next();

  /// Goes back one step (without probing, so it does not jump forward again).
  void back() {
    final m = mission;
    if (m == null || !state.running || state.stepIndex == 0) return;
    _gen++;
    _actionKey = null;
    _actionOwner = null;
    _retained.clear();
    final at = state.stepIndex - 1;
    _set(
      state.copyWith(
        stepIndex: at,
        progress: {...state.progress, m.id: at},
        actionBusy: false,
        actionError: null,
      ),
    );
  }

  /// Marks the running chapter as skipped and stops.
  Future<void> skipChapter([String? id]) async {
    await _ready;
    if (!ref.mounted) return;
    final target = id ?? state.activeId;
    if (target == null) return;
    // Skipping another chapter leaves the active step as it is, so a pending action stays valid.
    if (target == state.activeId) {
      _gen++;
      _actionKey = null;
      _actionOwner = null;
      _retained.clear();
    }
    _set(
      state.copyWith(
        actionBusy: target == state.activeId ? false : state.actionBusy,
        skipped: {...state.skipped, target},
        activeId: target == state.activeId ? null : state.activeId,
        stepIndex: target == state.activeId ? 0 : state.stepIndex,
        paused: target == state.activeId ? false : state.paused,
      ),
    );
  }

  /// Pauses the running chapter (its place is kept).
  void pause() {
    if (!state.running) return;
    _gen++;
    _set(state.copyWith(paused: true));
  }

  /// Stores that the first-sign-in offer was answered.
  void markOffered() {
    if (state.offered) return;
    _set(state.copyWith(offered: true));
  }

  /// Message ids of the simulated e-mails of the running step, kept so that a retry after an
  /// uncertain answer sends the same Message-ID (the server then drops the duplicate).
  final _retained = <String, String>{};

  /// The step (`chapter/index`) whose action request is in flight, or null. It survives pause and
  /// resume of that step, so the pending request keeps its busy flag and its Message-ID; any other
  /// step change forgets it.
  String? _actionKey;

  /// Identifies the one request that owns the action flags; a request that no longer is the
  /// owner (its step was left or restarted meanwhile) must not touch them.
  Object? _actionOwner;

  String get _stepKey => '${state.activeId}/${state.stepIndex}';
  final _random = Random();

  String _retainedId(String kind) => _retained.putIfAbsent(
    kind,
    () => newMessageId(DateTime.now(), kind, _random.nextInt(1 << 30)),
  );

  /// Runs the current step's action button. Ignored while a run is in progress; a failure is
  /// shown in the narrator card and the step stays available for another attempt.
  Future<void> runAction() async {
    final s = step;
    final c = s?.completion;
    if (s == null || c is! ActionCompletion || !state.running) return;
    if (state.actionBusy) return;
    final gen = _gen;
    final owner = Object();
    _actionOwner = owner;
    _actionKey = _stepKey;
    _set(state.copyWith(actionBusy: true, actionError: null));
    Map<String, String>? captured;
    try {
      captured = await c.run(
        ActionHost(
          dio: ref.read(dioProvider),
          context: state.context,
          languageCode: resolveTutorialLanguage(
            ref.read(localeProvider),
            PlatformDispatcher.instance.locales,
          ),
          messageId: _retainedId,
        ),
      );
    } catch (e) {
      // Another step (or a restarted chapter) owns the flags now: leave them alone.
      if (!ref.mounted || _actionOwner != owner) return;
      _actionKey = null;
      _actionOwner = null;
      _set(
        state.copyWith(
          actionBusy: false,
          actionError: gen == _gen
              ? TutorialActionError(
                  e is DioException ? e.response?.statusCode : null,
                  errorMessage(e),
                )
              : null,
        ),
      );
      return;
    }
    if (!ref.mounted || _actionOwner != owner) return;
    _actionKey = null;
    _actionOwner = null;
    if (gen != _gen || step != s) {
      // Paused and resumed meanwhile: the answer is not used, the button is free again and a
      // new press sends the same Message-ID (kept in _retained), so the server drops a duplicate.
      _set(state.copyWith(actionBusy: false));
      return;
    }
    _retained.clear();
    _set(state.copyWith(actionBusy: false, actionError: null));
    _complete({...?captured});
  }
}

/// The tutorial's state and commands.
final tutorialProvider = NotifierProvider<TutorialController, TutorialState>(
  TutorialController.new,
);
