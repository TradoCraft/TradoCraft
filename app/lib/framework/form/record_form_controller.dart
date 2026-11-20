/// State of one record form (ADR 0085): the loaded record, unsaved edits, a running save, the last
/// error and the concurrent-edit notice of ADR 0073.
///
/// The controller holds no field values: screens keep their own controllers and build their own
/// input type. It owns what every form repeats: the dirty flag, the busy flag, 409 handling, the
/// live-change watcher and the [formKey] for validation. `RecordFormView` listens to it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../shared/live_record_watcher.dart';

/// Why the conflict banner is shown.
enum RecordNoticeKind {
  /// Another user saved the record while it was open (live push).
  updatedBy,

  /// The record changed while the connection was down, or the change has no author.
  changed,

  /// A save was refused with `409 record_changed`.
  saveRefused,
}

/// What the conflict banner says. [changedByName] is set for [RecordNoticeKind.updatedBy].
@immutable
class RecordNotice {
  const RecordNotice(this.kind, {this.changedByName});

  final RecordNoticeKind kind;
  final String? changedByName;

  /// A refused save is shown as an error, the others as a warning.
  bool get isConflict => kind == RecordNoticeKind.saveRefused;
}

class RecordFormController<T extends Object> extends ChangeNotifier {
  /// [initial] is the loaded record; null for a new one.
  RecordFormController({T? initial, required this.versionOf})
    : _record = initial;

  /// The record's `version` (ADR 0073); null when the entity has none.
  final int? Function(T record) versionOf;

  /// Validates the fields of the enclosing `RecordFormView`.
  final formKey = GlobalKey<FormState>();

  T? _record;
  bool _dirty = false;
  bool _busy = false;
  String? _error;
  RecordNotice? _notice;
  int? _notifiedVersion;
  RecordLiveWatcher? _watcher;
  bool _disposed = false;

  /// Notifies when a colleague changed the record's chatter (a note, an activity, a follower,
  /// ADR 0086). These events never move the record version, so they are not an edit conflict:
  /// they reload the chatter panel and leave the banner alone.
  final chatterTick = ChatterTick();

  /// The record as the server last returned it; null for a new record.
  T? get record => _record;
  bool get isNew => _record == null;

  /// The version to send as `expected_version`.
  int? get version => _record == null ? null : versionOf(_record as T);

  /// The form holds edits the server does not have.
  bool get dirty => _dirty;

  /// A save, transition or reload is running; fields should not be edited meanwhile, since an
  /// edit made after the payload was taken would be lost when the answer replaces the form.
  bool get busy => _busy;
  String? get error => _error;
  RecordNotice? get notice => _notice;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Marks the form as holding unsaved edits. Ignored while busy (a programmatic fill during a
  /// save is not a user edit).
  void markDirty() {
    if (_dirty || _busy) return;
    _dirty = true;
    _changed();
  }

  /// Wires a [TextEditingController] so that a changed text (not a cursor move) marks the form
  /// dirty. Returns the controller for inline use.
  TextEditingController track(TextEditingController text) {
    var last = text.text;
    text.addListener(() {
      if (text.text == last) return;
      last = text.text;
      markDirty();
    });
    return text;
  }

  /// Sets or clears the error line.
  set error(String? message) {
    if (_error == message) return;
    _error = message;
    _changed();
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    _changed();
  }

  /// Shows [record] as the server's current state: clears the dirty flag and the error, and clears
  /// a live notice unless the record is still older than the version that notice announced.
  void apply(T record) {
    _record = record;
    _dirty = false;
    _error = null;
    final v = versionOf(record);
    if (_notifiedVersion == null || (v ?? 0) >= _notifiedVersion!) {
      _notice = null;
      _notifiedVersion = null;
    }
    _changed();
  }

  /// Validates the form fields. False when a field shows an error.
  bool validate() => formKey.currentState?.validate() ?? true;

  /// Runs [action] as the one operation of the form: nothing else runs meanwhile, the error is
  /// cleared first, a `409 record_changed` becomes the conflict notice and other errors the error
  /// line. A returned record is applied. A thrown [String] is shown as is (a client-side check).
  /// Returns whether the action completed.
  Future<bool> run(Future<T?> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _changed();
    try {
      final result = await action();
      if (_disposed) return true;
      if (result != null) apply(result);
      return true;
    } catch (e) {
      if (_disposed) return false;
      if (isRecordChangedError(e)) {
        _notice = const RecordNotice(RecordNoticeKind.saveRefused);
        _error = null;
      } else {
        _error = e is String ? e : errorMessage(e);
      }
      return false;
    } finally {
      _busy = false;
      _changed();
    }
  }

  /// Validates, then saves through [save] (see [run]). Returns the saved record, or null when
  /// validation failed or the save did not complete.
  Future<T?> save(Future<T> Function(int? expectedVersion) save) async {
    if (_busy || !validate()) return null;
    T? saved;
    final ok = await run(() async => saved = await save(version));
    return ok ? saved : null;
  }

  /// Reloads the record through [load] and applies it (dropping unsaved edits).
  Future<T?> reload(Future<T> Function() load) async {
    T? fresh;
    final ok = await run(() async => fresh = await load());
    return ok ? fresh : null;
  }

  /// Watches [recordId] on the shared live channel (ADR 0073); another user's save shows the
  /// notice. Replaces an earlier watch. Call again after a new record got its id.
  void watch(
    WidgetRef ref, {
    required String entityType,
    required String recordId,
  }) {
    _watcher?.dispose();
    _watcher = watchRecordChanges(
      ref,
      entityType: entityType,
      recordId: recordId,
      currentVersion: () => version,
      onExternalChange: (ev) {
        if (_disposed) return;
        if (ev.kind.startsWith('chatter_')) {
          chatterTick.fire();
          return;
        }
        if (_notifiedVersion == null || ev.version > _notifiedVersion!) {
          _notifiedVersion = ev.version;
        }
        _notice = ev.kind == 'resync' || ev.changedByName.isEmpty
            ? const RecordNotice(RecordNoticeKind.changed)
            : RecordNotice(
                RecordNoticeKind.updatedBy,
                changedByName: ev.changedByName,
              );
        _changed();
      },
    );
  }

  /// Test hook: shows a live notice as the watcher would.
  @visibleForTesting
  void debugNotify(RecordNotice notice, {int? version}) {
    _notice = notice;
    _notifiedVersion = version;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _watcher?.dispose();
    chatterTick.dispose();
    super.dispose();
  }
}

/// Tells the chatter panel that a colleague changed the chatter of the record.
class ChatterTick extends ChangeNotifier {
  void fire() => notifyListeners();
}
