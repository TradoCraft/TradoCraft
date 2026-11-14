import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/csv_transfer.dart';
import 'imports_api.dart';
import 'mapping_logic.dart';

/// The chosen file has no bytes.
class EmptyFileError implements Exception {
  const EmptyFileError();
}

/// The file picker failed.
class FileReadError implements Exception {
  const FileReadError();
}

/// Sentinel for [WizardState.copyWith]: keep the current value of a nullable field.
const _keep = Object();

/// One run (the check or the import): the job as last seen, whether the request is under way
/// and what it was run for.
class RunState {
  const RunState({this.job, this.starting = false, this.error, this.signature});
  final ImportJob? job;
  final bool starting;
  final Object? error;

  /// What the run was started for, see [runSignature].
  final String? signature;

  RunState copyWith({
    Object? job = _keep,
    bool? starting,
    Object? error = _keep,
    Object? signature = _keep,
  }) => RunState(
    job: identical(job, _keep) ? this.job : job as ImportJob?,
    starting: starting ?? this.starting,
    error: identical(error, _keep) ? this.error : error,
    signature: identical(signature, _keep)
        ? this.signature
        : signature as String?,
  );
}

/// Everything the import screen shows, in the order of its steps.
class WizardState {
  const WizardState({
    this.file,
    this.uploading = false,
    this.uploadError,
    this.entity,
    this.sheet,
    this.preview,
    this.previewLoading = false,
    this.previewError,
    this.saved = const [],
    this.savedLoading = false,
    this.savedError,
    this.fields = const [],
    this.proposedFrom,
    this.dry = const RunState(),
    this.apply = const RunState(),
  });

  final ImportFile? file;
  final bool uploading;
  final Object? uploadError;
  final ImportDescription? entity;
  final String? sheet;
  final ImportPreview? preview;
  final bool previewLoading;
  final Object? previewError;

  /// Saved mappings of the chosen entity.
  final List<ImportMapping> saved;
  final bool savedLoading;
  final Object? savedError;

  /// The field chosen for each file column (null = ignore), in header order.
  final List<String?> fields;

  /// Name of the saved mapping the columns were taken from; null when paired by name.
  final String? proposedFrom;
  final RunState dry;
  final RunState apply;

  List<String> get header => preview?.columns ?? const [];

  /// The columns step can be shown: a file, an entity and a header.
  bool get mappable =>
      file != null &&
      entity != null &&
      preview != null &&
      fields.length == preview!.columns.length;

  MappingCheck? get check => mappable ? checkMapping(fields, entity!) : null;

  bool get mappingOk => mappable && !check!.blocked;

  List<ColumnPair>? get columns =>
      mappable ? columnsToSend(header, fields) : null;

  /// What a run started now would be for.
  String? get signature => mappable
      ? runSignature(
          fileId: file!.id,
          entity: entity!.key,
          sheet: sheet,
          columns: columns,
        )
      : null;

  /// The check ended `done` without errors for exactly what is chosen now.
  bool get checkedClean =>
      mappingOk &&
      dry.job?.status == 'done' &&
      dry.job!.errorCount == 0 &&
      dry.signature == signature;

  /// A check exists but was run for other settings.
  bool get checkOutdated => dry.job != null && dry.signature != signature;

  WizardState copyWith({
    Object? file = _keep,
    bool? uploading,
    Object? uploadError = _keep,
    Object? entity = _keep,
    Object? sheet = _keep,
    Object? preview = _keep,
    bool? previewLoading,
    Object? previewError = _keep,
    List<ImportMapping>? saved,
    bool? savedLoading,
    Object? savedError = _keep,
    List<String?>? fields,
    Object? proposedFrom = _keep,
    RunState? dry,
    RunState? apply,
  }) => WizardState(
    file: identical(file, _keep) ? this.file : file as ImportFile?,
    uploading: uploading ?? this.uploading,
    uploadError: identical(uploadError, _keep) ? this.uploadError : uploadError,
    entity: identical(entity, _keep)
        ? this.entity
        : entity as ImportDescription?,
    sheet: identical(sheet, _keep) ? this.sheet : sheet as String?,
    preview: identical(preview, _keep)
        ? this.preview
        : preview as ImportPreview?,
    previewLoading: previewLoading ?? this.previewLoading,
    previewError: identical(previewError, _keep)
        ? this.previewError
        : previewError,
    saved: saved ?? this.saved,
    savedLoading: savedLoading ?? this.savedLoading,
    savedError: identical(savedError, _keep) ? this.savedError : savedError,
    fields: fields ?? this.fields,
    proposedFrom: identical(proposedFrom, _keep)
        ? this.proposedFrom
        : proposedFrom as String?,
    dry: dry ?? this.dry,
    apply: apply ?? this.apply,
  );
}

/// The message for a failed upload or an unreadable file.
String uploadErrorText(AppLocalizations l, Object e) {
  if (e is EmptyFileError) return l.csvEmptyFile;
  if (e is FileReadError) return l.csvReadFailed;
  if (errorStatus(e) == 413) return l.impFileTooLarge;
  return errorMessage(e);
}

/// How often a queued or running job is asked for its progress.
const importPollInterval = Duration(seconds: 2);

final importWizardProvider =
    NotifierProvider.autoDispose<ImportWizard, WizardState>(ImportWizard.new);

/// The state and the requests of the import screen. Leaving the screen disposes it, which also
/// stops the polling of a background job (the job goes on, and shows in the history).
class ImportWizard extends Notifier<WizardState> {
  Timer? _timer;
  // Only the newest preview request may fill the table (the sheet can change while one is open).
  int _previewSeq = 0;

  ImportsClient get _api => ref.read(apiProvider).imports;

  @override
  WizardState build() {
    ref.onDispose(() => _timer?.cancel());
    return const WizardState();
  }

  /// Back to the first step; the chosen entity and its saved mappings stay.
  void reset() {
    _timer?.cancel();
    _previewSeq++;
    state = WizardState(entity: state.entity, saved: state.saved);
  }

  void fail(Object error) => state = state.copyWith(uploadError: error);

  Future<void> upload(PickedFile picked) async {
    if (picked.bytes.isEmpty) {
      fail(const EmptyFileError());
      return;
    }
    _timer?.cancel();
    _previewSeq++;
    state = WizardState(
      entity: state.entity,
      saved: state.saved,
      uploading: true,
    );
    try {
      final file = await uploadImportFile(
        ref.read(dioProvider),
        picked.name,
        picked.bytes,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        file: file,
        uploading: false,
        sheet: file.sheets.isEmpty ? null : file.sheets.first,
      );
      await _loadPreview();
    } catch (e) {
      if (ref.mounted) state = state.copyWith(uploading: false, uploadError: e);
    }
  }

  Future<void> selectEntity(ImportDescription e) async {
    if (state.entity?.key == e.key) return;
    state = state.copyWith(
      entity: e,
      saved: const [],
      savedError: null,
      fields: const [],
      proposedFrom: null,
      dry: const RunState(),
      apply: const RunState(),
    );
    await refreshSaved();
    _propose();
  }

  Future<void> selectSheet(String sheet) async {
    if (state.sheet == sheet) return;
    _timer?.cancel();
    state = state.copyWith(
      sheet: sheet,
      dry: const RunState(),
      apply: const RunState(),
    );
    await _loadPreview();
  }

  Future<void> reloadPreview() => _loadPreview();

  Future<void> _loadPreview() async {
    final file = state.file;
    if (file == null) return;
    final seq = ++_previewSeq;
    state = state.copyWith(
      preview: null,
      previewLoading: true,
      previewError: null,
      fields: const [],
    );
    try {
      final p = await _api.previewImportFile(id: file.id, sheet: state.sheet);
      if (!ref.mounted || seq != _previewSeq) return;
      state = state.copyWith(preview: p, previewLoading: false);
      _propose();
    } catch (e) {
      if (!ref.mounted || seq != _previewSeq) return;
      state = state.copyWith(previewLoading: false, previewError: e);
    }
  }

  /// Reloads the saved mappings of the chosen entity.
  Future<void> refreshSaved() async {
    final e = state.entity;
    if (e == null) return;
    state = state.copyWith(savedLoading: true, savedError: null);
    try {
      final list = await _api.listImportMappings(entity: e.key);
      if (!ref.mounted || state.entity?.key != e.key) return;
      state = state.copyWith(saved: list, savedLoading: false);
    } catch (err) {
      if (!ref.mounted || state.entity?.key != e.key) return;
      state = state.copyWith(savedLoading: false, savedError: err);
    }
  }

  /// The first proposal for the file and entity chosen.
  void _propose() {
    final e = state.entity;
    final p = state.preview;
    if (e == null || p == null) return;
    final proposal = proposeMapping(
      header: p.columns,
      entity: e,
      saved: state.saved,
    );
    state = state.copyWith(
      fields: proposal.fields,
      proposedFrom: proposal.from?.name,
    );
  }

  /// Takes the columns of a saved mapping that the file has; the others are ignored.
  void useMapping(ImportMapping m) {
    final e = state.entity;
    final p = state.preview;
    if (e == null || p == null) return;
    state = state.copyWith(
      fields: fieldsFromMapping(p.columns, e, m),
      proposedFrom: m.name,
    );
  }

  void setField(int index, String? field) {
    final f = [...state.fields];
    f[index] = field;
    state = state.copyWith(fields: f, proposedFrom: null);
  }

  /// Saves the current pairs under [name] (an existing mapping with that name is replaced).
  Future<void> saveMapping(String name) async {
    final e = state.entity!;
    final pairs = [
      for (var i = 0; i < state.header.length; i++)
        if (state.fields[i] != null)
          ColumnPair(column: state.header[i], field: state.fields[i]!),
    ];
    await _api.saveImportMapping(
      body: MappingInput(columns: pairs, entity: e.key, name: name),
    );
    if (ref.mounted) await refreshSaved();
  }

  Future<void> deleteMapping(ImportMapping m) async {
    await _api.deleteImportMapping(id: m.id);
    if (ref.mounted) await refreshSaved();
  }

  /// Runs the file through the importer: a check ([dryRun]) or the real import. A finished job
  /// comes back at once; a queued one is polled until it ends.
  Future<void> run({required bool dryRun}) async {
    final sig = state.signature;
    final file = state.file;
    final e = state.entity;
    if (sig == null || file == null || e == null || !state.mappingOk) return;
    RunState slot() => dryRun ? state.dry : state.apply;
    void put(RunState r) =>
        state = dryRun ? state.copyWith(dry: r) : state.copyWith(apply: r);
    _timer?.cancel();
    put(const RunState(starting: true));
    try {
      final job = await _api.createImportJob(
        body: CreateJob(
          fileId: file.id,
          entity: e.key,
          sheet: state.sheet,
          columns: state.columns,
          dryRun: dryRun,
        ),
      );
      if (!ref.mounted) return;
      put(RunState(job: job, signature: sig));
      if (jobIsActive(job)) _schedulePoll(dryRun);
    } catch (err) {
      if (ref.mounted) put(slot().copyWith(starting: false, error: err));
    }
  }

  void _schedulePoll(bool dryRun) {
    _timer?.cancel();
    _timer = Timer(importPollInterval, () => _poll(dryRun));
  }

  Future<void> _poll(bool dryRun) async {
    final run = dryRun ? state.dry : state.apply;
    final id = run.job?.id;
    if (id == null) return;
    try {
      final job = await _api.getImportJob(id: id);
      if (!ref.mounted) return;
      final r = (dryRun ? state.dry : state.apply).copyWith(
        job: job,
        error: null,
      );
      state = dryRun ? state.copyWith(dry: r) : state.copyWith(apply: r);
      if (jobIsActive(job)) _schedulePoll(dryRun);
    } catch (err) {
      if (!ref.mounted) return;
      // A failed poll (a network blip) is shown and tried again; the job itself goes on.
      final r = (dryRun ? state.dry : state.apply).copyWith(error: err);
      state = dryRun ? state.copyWith(dry: r) : state.copyWith(apply: r);
      _schedulePoll(dryRun);
    }
  }

  /// Cancels the job of a run that is still queued.
  Future<void> cancel({required bool dryRun}) async {
    final id = (dryRun ? state.dry : state.apply).job?.id;
    if (id == null) return;
    try {
      final job = await _api.cancelImportJob(id: id);
      if (!ref.mounted) return;
      _timer?.cancel();
      final r = (dryRun ? state.dry : state.apply).copyWith(
        job: job,
        error: null,
      );
      state = dryRun ? state.copyWith(dry: r) : state.copyWith(apply: r);
    } catch (err) {
      if (!ref.mounted) return;
      // 409: the worker picked it up in the meantime. Show why and look at the job again.
      final r = (dryRun ? state.dry : state.apply).copyWith(error: err);
      state = dryRun ? state.copyWith(dry: r) : state.copyWith(apply: r);
      _schedulePoll(dryRun);
    }
  }
}
