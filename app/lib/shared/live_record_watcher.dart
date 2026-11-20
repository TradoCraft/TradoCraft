import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// Whether [error] is a `409 record_changed` optimistic-concurrency conflict.
bool isRecordChangedError(Object error) => errorCode(error) == 'record_changed';

/// A live record-change notification pushed over `GET /api/v1/events/records`.
class RecordChangeEvent {
  const RecordChangeEvent({
    required this.entityType,
    required this.recordId,
    required this.version,
    required this.changedById,
    required this.changedByName,
    required this.kind,
    this.summary,
    required this.at,
    this.isReconnect = false,
  });

  final String entityType;
  final String recordId;
  final int version;
  final String changedById;
  final String changedByName;
  final String kind;
  final String? summary;
  final DateTime at;
  final bool isReconnect;

  factory RecordChangeEvent.fromJson(
    Map<String, dynamic> json, {
    bool isReconnect = false,
  }) => RecordChangeEvent(
    entityType: json['entity_type'] as String? ?? '',
    recordId: json['record_id'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 0,
    changedById: json['changed_by_id'] as String? ?? '',
    changedByName: json['changed_by_name'] as String? ?? '',
    kind: json['kind'] as String? ?? 'updated',
    summary: json['summary'] as String?,
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    isReconnect: isReconnect,
  );
}

/// Subscribes to the shared SSE channel (`GET /api/v1/events/records`) for one record and calls
/// [onChange] whenever another user updates it. Safe to attach in `initState` / `didChangeDependencies`
/// and dispose in `dispose`; connection errors are retried with backoff and never thrown.
class RecordLiveWatcher {
  RecordLiveWatcher({
    required this.dio,
    required this.entityType,
    required this.recordId,
    required this.onChange,
  });

  final Dio dio;
  final String entityType;
  final String recordId;
  final void Function(RecordChangeEvent event) onChange;

  CancelToken? _cancel;
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;
  bool _disposed = false;

  void start() {
    if (_disposed || _cancel != null) return;
    _runLoop();
  }

  Future<void> _runLoop() async {
    var backoffSeconds = 2;
    var isReconnect = false;
    while (!_disposed) {
      final cancel = CancelToken();
      _cancel = cancel;
      try {
        final response = await dio.get<ResponseBody>(
          '/api/v1/events/records',
          queryParameters: {'entity_type': entityType, 'record_id': recordId},
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
            headers: const {'Accept': 'text/event-stream'},
          ),
        );
        final body = response.data;
        if (body == null) break;
        backoffSeconds = 2;
        await _checkVersion(isReconnect: isReconnect);
        isReconnect = true;
        await _consumeStream(body.stream);
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 401 || code == 403 || code == 404) break;
      } catch (_) {
        // Connection refused or cancelled: back off and retry.
      } finally {
        isReconnect = true;
        cancel.cancel();
      }
      if (_disposed) break;
      final wait = Completer<void>();
      _retryCompleter = wait;
      _retryTimer = Timer(Duration(seconds: backoffSeconds), () {
        if (!wait.isCompleted) wait.complete();
      });
      await wait.future;
      if (backoffSeconds < 16) backoffSeconds *= 2;
    }
  }

  // Use the existing read models and the same onChange version filter as push events.
  // Check on every connection too: a disconnected client can have missed updates.
  Future<void> _checkVersion({bool isReconnect = false}) async {
    final resource = switch (entityType) {
      'customer' => 'customers',
      'quotation' => 'quotations',
      'order' => 'orders',
      'opportunity' => 'opportunities',
      'ticket' => 'tickets',
      _ => null,
    };
    if (resource == null) return;
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/$resource/$recordId',
      cancelToken: _cancel,
    );
    if (_disposed) return;
    final data = response.data!;
    final record = entityType == 'ticket'
        ? data['ticket'] as Map<String, dynamic>
        : data;
    onChange(
      RecordChangeEvent.fromJson({
        ...record,
        'entity_type': entityType,
        'record_id': recordId,
        'kind': 'resync',
      }, isReconnect: isReconnect),
    );
  }

  Future<void> _consumeStream(Stream<List<int>> byteStream) async {
    String currentEvent = '';
    final dataLines = <String>[];
    final lines = byteStream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (_disposed) break;
      if (line.isEmpty) {
        if (currentEvent == 'resync') await _checkVersion(isReconnect: true);
        if (currentEvent == 'record_changed' && dataLines.isNotEmpty) {
          try {
            final map =
                jsonDecode(dataLines.join('\n')) as Map<String, dynamic>;
            onChange(RecordChangeEvent.fromJson(map));
          } catch (_) {
            // Ignore malformed event payloads.
          }
        }
        currentEvent = '';
        dataLines.clear();
      } else if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_retryCompleter != null && !_retryCompleter!.isCompleted) {
      _retryCompleter!.complete();
    }
    _cancel?.cancel('disposed');
    _cancel = null;
  }
}

/// Whether an event of [kind] always carries a new record version, so one that is not newer than
/// the loaded version is something the screen already has.
bool isVersionedChange(String kind) => kind == 'updated' || kind == 'note';

/// Convenience helper for screens using Riverpod [WidgetRef] to watch a record's SSE channel.
RecordLiveWatcher watchRecordChanges(
  WidgetRef ref, {
  required String entityType,
  required String recordId,
  required int? Function() currentVersion,
  required void Function(RecordChangeEvent event) onExternalChange,
}) {
  final watcher = RecordLiveWatcher(
    dio: ref.read(dioProvider),
    entityType: entityType,
    recordId: recordId,
    onChange: (ev) {
      final meId = ref.read(meProvider).value?.userId;
      if (meId != null && ev.changedById == meId) return;
      final cur = currentVersion();
      if (ev.kind == 'resync') {
        if (cur == null || ev.version <= 0 || ev.version < cur) return;
        // On a ticket, reconnect resync with the same version can still reflect missed
        // unversioned changes (tags, time entries, attachments, checklist).
        final allowSameVersion = entityType == 'ticket' && ev.isReconnect;
        if (ev.version == cur && !allowSameVersion) return;
      } else if (isVersionedChange(ev.kind) &&
          cur != null &&
          ev.version <= cur) {
        // Only saves move the record version. Timeline-only changes (a tag, a time entry, an
        // attachment) and presence (A8) leave it as it was, so they must not be filtered by it.
        return;
      }
      onExternalChange(ev);
    },
  );
  watcher.start();
  return watcher;
}

/// Banner shown when another user updated the open record (live SSE warning or 409 on save).
/// Keeps unsaved edits intact and offers a one-click reload.
class RecordConflictBanner extends StatelessWidget {
  const RecordConflictBanner({
    super.key,
    required this.message,
    required this.isConflict,
    required this.onReload,
    this.onDismiss,
    this.actionLabel,
    this.actionIcon,
  });

  final String message;
  final bool isConflict;
  final VoidCallback? onReload;
  final VoidCallback? onDismiss;

  /// Replaces the "Reload" label, for example "Compare" when the user has unsaved edits.
  final String? actionLabel;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    final bg = isConflict ? cs.errorContainer : cs.tertiaryContainer;
    final fg = isConflict ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isConflict ? AppIcons.syncProblem : AppIcons.warningAmber,
            color: fg,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: fg),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onReload,
            icon: Icon(actionIcon ?? AppIcons.refresh, size: 18),
            label: Text(actionLabel ?? l.reloadRecord),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: fg, size: 18),
              tooltip: l.cancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps editor controllers intact while preventing pointer and keyboard edits.
extension RecordEditorLock on Widget {
  Widget lockRecordEditing(bool locked) => ExcludeFocus(
    excluding: locked,
    child: AbsorbPointer(absorbing: locked, child: this),
  );
}
