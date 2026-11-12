import 'package:dio/dio.dart';

import 'api_events.dart';

/// Values captured from API answers during a mission (ids of records the user just created),
/// used in routes, probe paths and route patterns written as `{name}`.
class MissionContext {
  /// Creates a context holding [values] (copied).
  MissionContext([Map<String, String> values = const {}])
    : values = Map.unmodifiable(values);

  /// The captured values by name.
  final Map<String, String> values;

  /// A copy with [more] added.
  MissionContext withValues(Map<String, String> more) =>
      MissionContext({...values, ...more});

  /// [template] with every `{name}` replaced by its value; null when one is not captured yet.
  String? resolve(String template) {
    var missing = false;
    final out = template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = values[m[1]];
      if (v == null) missing = true;
      return v ?? '';
    });
    return missing ? null : out;
  }
}

/// Replaces `{name}` by regex-escaped captured values; null when one is missing.
String? _expand(String pattern, MissionContext ctx) {
  var missing = false;
  final out = pattern.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final v = ctx.values[m[1]];
    if (v == null) missing = true;
    return RegExp.escape(v ?? '');
  });
  return missing ? null : out;
}

/// How a step is finished.
sealed class Completion {
  /// Base constructor.
  const Completion();
}

/// Done when a call of [method] on a path matching [pathPattern] (a regular expression, full
/// match, without the `/api/v1` prefix; `{name}` is replaced by a captured value) answers with
/// [status] (any 2xx when null) and [predicate] (when given) accepts the JSON answer.
class OnApi extends Completion {
  /// Creates the rule.
  const OnApi(this.method, this.pathPattern, {this.status, this.predicate});

  /// The HTTP method, upper case.
  final String method;

  /// Regular expression for the request path.
  final String pathPattern;

  /// The exact status wanted, or null for any 2xx.
  final int? status;

  /// Extra check on the parsed JSON answer and the context.
  final bool Function(Object? json, MissionContext ctx)? predicate;

  /// Whether [e] finishes the step in [ctx].
  bool matches(ApiEvent e, MissionContext ctx) {
    if (e.method.toUpperCase() != method) return false;
    final statusOk = status == null
        ? e.status >= 200 && e.status < 300
        : e.status == status;
    if (!statusOk) return false;
    final pattern = _expand(pathPattern, ctx);
    if (pattern == null || !RegExp('^$pattern\$').hasMatch(e.path)) {
      return false;
    }
    return predicate?.call(e.json, ctx) ?? true;
  }
}

/// Done when the app shows a location matching [pattern] (a regular expression, matched from
/// the start of the location including the query; `{name}` is replaced by a captured value).
class OnRoute extends Completion {
  /// Creates the rule.
  const OnRoute(this.pattern);

  /// Regular expression for the location.
  final String pattern;

  /// Whether [location] satisfies the rule in [ctx].
  bool matches(String location, MissionContext ctx) {
    final p = _expand(pattern, ctx);
    return p != null && RegExp('^$p').hasMatch(location);
  }
}

/// Done when the user presses Next (an explanation, or something the app cannot observe).
class ManualNext extends Completion {
  /// Creates the rule.
  const ManualNext();
}

String _noRetention(String kind) =>
    '<tut.${DateTime.now().microsecondsSinceEpoch}.$kind@example.test>';

/// What an [ActionCompletion] may use.
class ActionHost {
  /// Creates the host.
  const ActionHost({
    required this.dio,
    required this.context,
    this.languageCode = 'en',
    this.messageId = _noRetention,
  });

  /// A Message-ID for the simulated e-mail of [kind] that stays the same when the step's action
  /// is retried (it is reset when the step finishes or the chapter restarts).
  final String Function(String kind) messageId;

  /// The language of the app (for scripted texts such as simulated e-mails).
  final String languageCode;

  /// The HTTP client of the active environment.
  final Dio dio;

  /// What the mission captured so far.
  final MissionContext context;
}

/// Done when the user presses the step's button, which runs [run]. The label is the ARB key
/// `tut<Chapter><Step>Action`.
class ActionCompletion extends Completion {
  /// Creates the rule.
  const ActionCompletion(this.run);

  /// The work behind the button; may return values to capture.
  final Future<Map<String, String>?> Function(ActionHost host) run;
}

/// A read-only GET that tells whether a step is already done.
class Probe {
  /// Creates a probe of [path] (with optional `{name}` placeholders and [query]).
  const Probe(
    this.path, {
    this.query,
    required this.done,
    this.capture,
    this.expand,
  });

  /// Path below the API base host, e.g. `/api/v1/products`.
  final String path;

  /// Query parameters.
  final Map<String, dynamic>? query;

  /// Optional second stage: from the answer, the paths (at most 5 are read) of the records to
  /// look at in full; [done] and [capture] then get the list of those records' answers instead
  /// (a list answer carries too little to tell whether a record is the one the story made).
  final List<String> Function(Object? json, MissionContext ctx)? expand;

  /// Whether the answer shows the step is done.
  final bool Function(Object? json, MissionContext ctx) done;

  /// Values to capture when it is done.
  final Map<String, String> Function(Object? json, MissionContext ctx)? capture;
}

/// One narrator beat of a mission.
class MissionStep {
  /// Creates a step. Its texts are the ARB keys `tut<Chapter><Id>Title`, `...Body`, and
  /// `...Hint` when [hasHint].
  const MissionStep({
    required this.id,
    this.hasHint = false,
    this.targets = const [],
    this.route,
    this.completion = const ManualNext(),
    this.probe,
    this.capture,
  });

  /// Short camelCase name, unique in the mission; part of the ARB keys.
  final String id;

  /// Whether there is a hint text.
  final bool hasHint;

  /// The `TutorialTarget` ids to spotlight, in order of preference: the first one that is on
  /// screen and not covered is highlighted (so a step can point at the create button, and at the
  /// save button once its dialog is open).
  final List<String> targets;

  /// A location (may contain `{name}` placeholders) the "Take me there" button opens.
  final String? route;

  /// How the step finishes.
  final Completion completion;

  /// Tells whether the step is already done.
  final Probe? probe;

  /// Values to capture from the API answer that finished the step.
  final Map<String, String> Function(Object? json)? capture;
}

/// A chapter of the tutorial. Its title and summary are the ARB keys `tut<Id>Title` and
/// `tut<Id>Summary`.
class Mission {
  /// Creates a mission.
  const Mission({required this.id, required this.steps});

  /// Short camelCase name; part of the ARB keys.
  final String id;

  /// The steps in order.
  final List<MissionStep> steps;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The ARB key of a chapter text; [part] is `Title` or `Summary`.
String missionKey(Mission m, String part) => 'tut${_cap(m.id)}$part';

/// The ARB key of a step text; [part] is `Title`, `Body`, `Hint` or `Action`.
String stepKey(Mission m, MissionStep s, String part) =>
    'tut${_cap(m.id)}${_cap(s.id)}$part';

/// Every ARB key the missions use (for the completeness test and the string table).
List<String> allTutorialKeys(Iterable<Mission> missions) => [
  for (final m in missions) ...[
    missionKey(m, 'Title'),
    missionKey(m, 'Summary'),
    for (final s in m.steps) ...[
      stepKey(m, s, 'Title'),
      stepKey(m, s, 'Body'),
      if (s.hasHint) stepKey(m, s, 'Hint'),
      if (s.completion is ActionCompletion) stepKey(m, s, 'Action'),
    ],
  ],
];
