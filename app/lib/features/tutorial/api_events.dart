import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';

/// Request option that keeps a request (a probe) out of the event stream.
const tutorialProbeExtra = 'tutorialProbe';

/// Request option that carries the identity of the session that sent the request.
const tutorialScopeExtra = 'tutorialScope';

/// Identifies who a request was sent as (server, user, company): events of another session or
/// environment must not finish a step of this one.
String tutorialSessionId(Session s) =>
    '${s.serverUrl}|${s.devUser ?? ''}|${s.companyId ?? ''}|'
    '${(s.accessToken?.isNotEmpty ?? false) ? 'token' : ''}';

/// A finished API call, as seen by the tutorial.
class ApiEvent {
  /// Creates an event.
  const ApiEvent(this.method, this.path, this.status, this.json, {this.scope});

  /// The HTTP method, upper case.
  final String method;

  /// The request path without host and without the `/api/v1` prefix.
  final String path;

  /// The HTTP status.
  final int status;

  /// The parsed JSON answer (null for an empty or non-JSON answer).
  final Object? json;

  /// The [tutorialSessionId] the request was sent with (null when not stamped).
  final String? scope;
}

/// Broadcasts [ApiEvent]s, but only while [active] (a mission is running): otherwise nothing is
/// parsed and nothing is retained.
class ApiEventBus {
  final _controller = StreamController<ApiEvent>.broadcast(sync: true);

  /// Whether events are emitted at all.
  bool active = false;

  /// The events.
  Stream<ApiEvent> get stream => _controller.stream;

  /// Emits [event] when active.
  void emit(ApiEvent event) {
    if (active && !_controller.isClosed) _controller.add(event);
  }

  /// Closes the stream.
  void dispose() => _controller.close();
}

/// The bus the Dio interceptor writes to and the tutorial controller reads from.
final apiEventBusProvider = Provider<ApiEventBus>((ref) {
  final bus = ApiEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// Turns finished calls into [ApiEvent]s on [bus].
class ApiEventInterceptor extends Interceptor {
  /// Creates the interceptor.
  ApiEventInterceptor(this.bus, {this.scope});

  /// Where events go.
  final ApiEventBus bus;

  /// The [tutorialSessionId] of the client this interceptor belongs to.
  final String? scope;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (scope != null) options.extra[tutorialScopeExtra] = scope;
    handler.next(options);
  }

  void _emit(Response<dynamic> r) {
    if (!bus.active || r.requestOptions.extra[tutorialProbeExtra] == true) {
      return;
    }
    var path = r.requestOptions.path;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) path = uri.path;
    if (path.startsWith('/api/v1')) path = path.substring('/api/v1'.length);
    final data = r.data;
    bus.emit(
      ApiEvent(
        r.requestOptions.method.toUpperCase(),
        path,
        r.statusCode ?? 0,
        data is Map || data is List ? data : null,
        scope: r.requestOptions.extra[tutorialScopeExtra] as String?,
      ),
    );
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _emit(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final r = err.response;
    if (r != null) _emit(r);
    handler.next(err);
  }
}
