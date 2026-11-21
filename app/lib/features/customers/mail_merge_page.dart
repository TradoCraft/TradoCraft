import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/file_export.dart';

class MailMergePage extends ConsumerStatefulWidget {
  const MailMergePage({super.key});

  @override
  ConsumerState<MailMergePage> createState() => _MailMergePageState();
}

class _MailMergePageState extends ConsumerState<MailMergePage> {
  static const _path = '/api/v1/customers/mail-merge';
  static const _languages = ['en', 'nl', 'fr', 'de', 'es'];
  final _subjects = {for (final l in _languages) l: TextEditingController()};
  final _bodies = {for (final l in _languages) l: TextEditingController()};
  final _recipients = <String, String>{};
  List<Document> _documents = [];
  List<int> _revisions = [];
  List<dynamic> _audience = [];
  List<dynamic> _history = [];
  String? _approvalId;
  String? _document;
  int? _revision;
  String _language = 'en';
  String? _error;
  bool _busy = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<int>> _publishedRevisions(String id) async {
    final detail = await ref.read(apiProvider).kb.getKbDocument(id: id);
    return detail.pdfs
        .where((p) => p.published)
        .map((p) => p.revision)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiProvider);
      final dio = ref.read(dioProvider);
      final documents = await api.kb.listKbDocuments();
      final response = await dio.get<Map<String, dynamic>>(_path);
      final history = await dio.get<List<dynamic>>('$_path/history');
      if (!mounted) return;
      final draft = response.data?['draft'] as Map<String, dynamic>?;
      final id = draft?['document_id'] as String?;
      final revisions = id == null ? <int>[] : await _publishedRevisions(id);
      if (!mounted) return;
      for (final l in _languages) {
        final message = draft?['messages']?[l];
        _subjects[l]!.text = message?['subject'] as String? ?? '';
        _bodies[l]!.text = message?['body'] as String? ?? '';
      }
      setState(() {
        _documents = documents;
        _document = id;
        _revisions = revisions;
        _revision = draft?['revision'] as int?;
        _audience = response.data?['audience'] as List<dynamic>? ?? [];
        _approvalId = response.data?['approval_id'] as String?;
        _history = history.data ?? [];
        _recipients.addAll(
          Map<String, String>.from(draft?['recipients'] as Map? ?? {}),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(String id) async {
    setState(() {
      _busy = true;
      _dirty = true;
      _document = id;
      _revision = null;
      _revisions = [];
      _error = null;
    });
    try {
      final revisions = await _publishedRevisions(id);
      if (mounted) {
        setState(() {
          _revisions = revisions;
          _revision = revisions.firstOrNull;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(dioProvider)
          .put<Map<String, dynamic>>(
            _path,
            data: {
              'document_id': _document,
              'revision': _revision,
              'messages': {
                for (final l in _languages)
                  l: {'subject': _subjects[l]!.text, 'body': _bodies[l]!.text},
              },
              'recipients': _recipients,
            },
          );
      if (mounted) {
        setState(() {
          _audience = response.data!['audience'] as List<dynamic>;
          _approvalId = response.data!['approval_id'] as String?;
          _dirty = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshHistory() async {
    try {
      final response = await ref
          .read(dioProvider)
          .get<List<dynamic>>('$_path/history');
      if (mounted) setState(() => _history = response.data ?? []);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  Future<void> _confirm(int count) async {
    final approval = _approvalId;
    if (approval == null || _dirty || _busy) return;
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.mergeConfirm),
        content: Text(l.mergeConfirmBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.mergeQueue),
          ),
        ],
      ),
    );
    if (!mounted || ok != true || _busy || _dirty || _approvalId != approval) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dioProvider).post<void>('$_path/$approval/confirm');
      if (mounted) await _refreshHistory();
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPdf(Map row, String? document, int? revision) async {
    try {
      final bytes = await downloadBytes(
        ref.read(dioProvider),
        '/api/v1/kb/documents/$document/revisions/$revision/${row['language']}',
      );
      if (!mounted) return;
      await saveExport(
        context,
        ref,
        row['pdf'] as String,
        Uint8List.fromList(bytes),
      );
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String issue(String code) => switch (code) {
      'select_contact' => l.mergeSelectContact,
      'missing_address' => l.mergeMissingAddress,
      'missing_translation' => l.mergeMissingTranslation,
      'missing_pdf' => l.mergeMissingPdf,
      'duplicate_address' => l.mergeDuplicateAddress,
      _ => code,
    };
    final rowsByLanguage = <String, List<Map>>{};
    for (final row in _audience.cast<Map>()) {
      rowsByLanguage.putIfAbsent(row['language'] as String, () => []).add(row);
    }
    final canSend =
        ref.watch(meProvider).value?.permissions.contains('mail_merge.send') ??
        false;
    final eligible = _audience
        .where((row) => (row['issues'] as List).isEmpty)
        .length;
    String deliveryLabel(String value) => switch (value) {
      'queued' => l.mergeQueued,
      'sent' => l.mergeSent,
      'failed' => l.mergeFailed,
      _ => value,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.mailMerge)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          DropdownButtonFormField<String>(
            key: ValueKey(_document),
            initialValue: _documents.any((d) => d.id == _document)
                ? _document
                : null,
            decoration: InputDecoration(labelText: l.documentLibrary),
            items: [
              for (final d in _documents)
                DropdownMenuItem(value: d.id, child: Text(d.title)),
            ],
            onChanged: _busy ? null : (id) => _select(id!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey(_revision),
            initialValue: _revision,
            decoration: InputDecoration(labelText: l.mergeRevision),
            items: [
              for (final rev in _revisions)
                DropdownMenuItem(
                  value: rev,
                  child: Text(l.documentRevision(rev)),
                ),
            ],
            onChanged: _busy
                ? null
                : (rev) => setState(() {
                    _revision = rev;
                    _dirty = true;
                  }),
          ),
          if (_document != null && _revisions.isEmpty && !_busy)
            Text(l.noLibraryPdfs),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(labelText: l.language),
            items: [
              for (final lang in _languages)
                DropdownMenuItem(value: lang, child: Text(languageName(lang))),
            ],
            onChanged: _busy
                ? null
                : (lang) => setState(() => _language = lang!),
          ),
          TextField(
            key: ValueKey('subject-$_language'),
            controller: _subjects[_language],
            enabled: !_busy,
            decoration: InputDecoration(labelText: l.subject),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          TextField(
            key: ValueKey('body-$_language'),
            controller: _bodies[_language],
            enabled: !_busy,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: l.message,
              helperText: '{{customer.name}} · {{contact.name}}',
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _busy || _revision == null ? null : _save,
              child: Text(l.mergeSavePreview),
            ),
          ),
          if (canSend && _approvalId != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                onPressed: _busy || _dirty || eligible == 0
                    ? null
                    : () => _confirm(eligible),
                child: Text(l.mergeConfirm),
              ),
            ),
          if (_dirty && _audience.isNotEmpty) Text(l.mergePreviewStale),
          if (_audience.isNotEmpty) ...[
            const Divider(),
            Text(
              l.mergeAudience,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final entry in rowsByLanguage.entries) ...[
              Text('${languageName(entry.key)} · ${entry.value.length}'),
              for (final row in entry.value)
                ExpansionTile(
                  key: ValueKey(row['customer_id']),
                  title: Text(row['customer_name'] as String),
                  subtitle: Text(
                    [
                      if (row['email'] case final String email) email,
                      for (final code in (row['issues'] as List).cast<String>())
                        issue(code),
                    ].join(' · '),
                  ),
                  children: [
                    if ((row['contacts'] as List).isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: row['contact_id'] as String?,
                        decoration: InputDecoration(
                          labelText: l.mergeSelectContact,
                        ),
                        items: [
                          for (final contact in row['contacts'] as List)
                            DropdownMenuItem(
                              value: contact['id'] as String,
                              child: Text(contact['name'] as String),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (contact) => setState(() {
                                _recipients[row['customer_id'] as String] =
                                    contact!;
                                _dirty = true;
                              }),
                      ),
                    if (row['subject'] case final String subject) Text(subject),
                    if (row['body'] case final String body)
                      SelectableText(body),
                    if (row['pdf'] case final String filename)
                      TextButton(
                        onPressed: _busy || _dirty
                            ? null
                            : () => _openPdf(row, _document, _revision),
                        child: Text(filename),
                      ),
                  ],
                ),
            ],
          ],
          const Divider(),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.mergeHistory,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: _busy ? null : _refreshHistory,
                child: Text(l.mergeRefresh),
              ),
            ],
          ),
          for (final row in _history.cast<Map>())
            ListTile(
              title: Text('${row['customer_name']} · ${row['subject']}'),
              subtitle: Text(
                [
                  row['email'] as String,
                  languageName(row['language'] as String),
                  l.documentRevision(row['revision'] as int),
                  deliveryLabel(row['delivery'] as String),
                  if (row['delivery_error'] case final String error) error,
                ].join(' · '),
              ),
              trailing: row['pdf'] == ''
                  ? null
                  : TextButton(
                      onPressed: () => _openPdf(
                        row,
                        row['document_id'] as String,
                        row['revision'] as int,
                      ),
                      child: Text(row['pdf'] as String),
                    ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [..._subjects.values, ..._bodies.values]) {
      c.dispose();
    }
    super.dispose();
  }
}
