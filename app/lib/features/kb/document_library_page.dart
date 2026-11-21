import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/file_export.dart';

class DocumentLibraryPage extends ConsumerStatefulWidget {
  const DocumentLibraryPage({super.key});

  @override
  ConsumerState<DocumentLibraryPage> createState() =>
      _DocumentLibraryPageState();
}

class _DocumentLibraryPageState extends ConsumerState<DocumentLibraryPage> {
  static const _path = '/api/v1/kb/documents';
  String _query = '';
  String? _documentId;
  String _language = 'en';
  bool _busy = false;
  String? _error;
  late Future<List<dynamic>> _list = _loadList();
  Future<Map<String, dynamic>>? _detail;

  Dio get _dio => ref.read(dioProvider);

  Future<List<dynamic>> _loadList() async => (await _dio.get<List<dynamic>>(
    _path,
    queryParameters: {'q': _query},
  )).data!;

  void _open(String id) {
    setState(() {
      _documentId = id;
      _detail = _dio
          .get<Map<String, dynamic>>('$_path/$id')
          .then((r) => r.data!);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final l = context.l10n;
    final form = GlobalKey<FormState>();
    var title = '', keywords = '', products = '', kind = 'technical_memo';
    final input = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.documentNew),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autofocus: true,
                  decoration: InputDecoration(labelText: l.documentTitle),
                  onChanged: (v) => title = v,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l.documentTitle : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  items: [
                    DropdownMenuItem(
                      value: 'technical_memo',
                      child: Text(l.documentMemo),
                    ),
                    DropdownMenuItem(
                      value: 'product_presentation',
                      child: Text(l.documentPresentation),
                    ),
                  ],
                  onChanged: (v) => kind = v!,
                ),
                TextField(
                  decoration: InputDecoration(labelText: l.documentKeywords),
                  onChanged: (v) => keywords = v,
                ),
                TextField(
                  decoration: InputDecoration(
                    labelText: l.documentProductCodes,
                  ),
                  onChanged: (v) => products = v,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              List<String> values(String text) => text
                  .split(',')
                  .map((v) => v.trim())
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .toList();
              Navigator.pop(context, {
                'title': title,
                'kind': kind,
                'keywords': values(keywords),
                'product_codes': values(products),
              });
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (!mounted || input == null) return;
    await _run(() async {
      final result = await _dio.post<Map<String, dynamic>>(_path, data: input);
      if (mounted) _open(result.data!['id'] as String);
    });
  }

  Future<void> _upload(String id) => _run(() async {
    final language = _language;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
          uniformTypeIdentifiers: ['com.adobe.pdf'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _dio.put<void>(
      '$_path/$id/draft/$language',
      data: bytes,
      queryParameters: {'filename': file.name},
      options: Options(contentType: 'application/pdf'),
    );
    if (mounted && _documentId == id) _open(id);
  });

  Future<void> _publish(String id) => _run(() async {
    await _dio.post<void>('$_path/$id/publish');
    if (mounted && _documentId == id) _open(id);
  });

  Future<void> _download(String id, Map<String, dynamic> pdf) => _run(() async {
    final bytes = await downloadBytes(
      _dio,
      '$_path/$id/revisions/${pdf['revision']}/${pdf['language']}',
    );
    if (!mounted) return;
    await saveExport(
      context,
      ref,
      pdf['filename'] as String,
      Uint8List.fromList(bytes),
    );
  });

  Future<void> _preview(String id, Map<String, dynamic> pdf) => _run(() async {
    final bytes = await downloadBytes(
      _dio,
      '$_path/$id/revisions/${pdf['revision']}/${pdf['language']}',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 800,
          height: 700,
          child: Column(
            children: [
              ListTile(
                title: Text(pdf['filename'] as String),
                trailing: CloseButton(onPressed: () => Navigator.pop(context)),
              ),
              Expanded(
                child: PdfPreview(
                  build: (_) => Uint8List.fromList(bytes),
                  useActions: false,
                  onError: (_, error) =>
                      Center(child: Text(errorMessage(error))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final publisher =
        ref.watch(meProvider).value?.permissions.contains('kb.admin') ?? false;
    final id = _documentId;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.documentLibrary),
        leading: id == null
            ? null
            : BackButton(
                onPressed: () {
                  setState(() {
                    _documentId = null;
                    _error = null;
                    _list = _loadList();
                  });
                },
              ),
        actions: [
          if (publisher && id == null)
            TextButton(
              onPressed: _busy ? null : _create,
              child: Text(l.documentNew),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
          if (id == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(labelText: l.search),
                controller: _search,
                onSubmitted: (query) => setState(() {
                  _query = query;
                  _list = _loadList();
                }),
              ),
            ),
          Expanded(
            child: id == null
                ? FutureBuilder<List<dynamic>>(
                    future: _list,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(errorMessage(snapshot.error!)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ListView(
                        children: [
                          for (final document in snapshot.data!)
                            ListTile(
                              title: Text(document['title'] as String),
                              subtitle: Text(
                                document['kind'] == 'technical_memo'
                                    ? l.documentMemo
                                    : l.documentPresentation,
                              ),
                              onTap: () => _open(document['id'] as String),
                            ),
                        ],
                      );
                    },
                  )
                : FutureBuilder<Map<String, dynamic>>(
                    future: _detail,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(errorMessage(snapshot.error!)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!;
                      final pdfs = (data['pdfs'] as List)
                          .cast<Map<String, dynamic>>();
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            data['document']['title'] as String,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (publisher)
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                DropdownButton<String>(
                                  value: _language,
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(() => _language = v!),
                                  items: [
                                    for (final code in [
                                      'en',
                                      'nl',
                                      'fr',
                                      'de',
                                      'es',
                                    ])
                                      DropdownMenuItem(
                                        value: code,
                                        child: Text(languageName(code)),
                                      ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: _busy ? null : () => _upload(id),
                                  child: Text(l.documentUpload),
                                ),
                                FilledButton(
                                  onPressed:
                                      _busy ||
                                          !pdfs.any(
                                            (p) => p['published'] == false,
                                          )
                                      ? null
                                      : () => _publish(id),
                                  child: Text(l.documentPublish),
                                ),
                              ],
                            ),
                          for (final pdf in pdfs)
                            ListTile(
                              title: Text(pdf['filename'] as String),
                              subtitle: Text(
                                '${languageName(pdf['language'] as String)} · ${l.documentRevision(pdf['revision'] as int)}${pdf['published'] == true ? '' : ' · ${l.documentDraft}'}',
                              ),
                              trailing: Wrap(
                                children: [
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _preview(id, pdf),
                                    child: Text(l.documentPreview),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _download(id, pdf),
                                    child: Text(l.documentDownload),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
