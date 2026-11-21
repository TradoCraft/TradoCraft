import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';

class LibraryPdfSelection {
  const LibraryPdfSelection(this.documentId, this.pdf);

  final String documentId;
  final Pdf pdf;

  LibraryPdf get variant => LibraryPdf(
    documentId: documentId,
    revision: pdf.revision,
    language: pdf.language,
  );
}

class LibraryPdfPicker extends ConsumerStatefulWidget {
  const LibraryPdfPicker({super.key, required this.language});

  final String language;

  @override
  ConsumerState<LibraryPdfPicker> createState() => _LibraryPdfPickerState();
}

class _LibraryPdfPickerState extends ConsumerState<LibraryPdfPicker> {
  final _query = TextEditingController();
  late Future<List<Document>> _results = _search();
  Future<DocumentDetail>? _selected;

  Future<List<Document>> _search() =>
      ref.read(apiProvider).kb.listKbDocuments(q: _query.text.trim());

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final detail = _selected;
    return AlertDialog(
      title: Text(l.attachFromDocuments),
      content: SizedBox(
        width: 440,
        height: 360,
        child: detail == null
            ? Column(
                children: [
                  TextField(
                    controller: _query,
                    decoration: InputDecoration(
                      labelText: l.search,
                      suffixIcon: TextButton(
                        onPressed: () => setState(() => _results = _search()),
                        child: Text(l.search),
                      ),
                    ),
                    onSubmitted: (_) => setState(() => _results = _search()),
                  ),
                  Expanded(
                    child: FutureBuilder<List<Document>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(errorMessage(snapshot.error!));
                        }
                        final documents = snapshot.data;
                        if (documents == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (documents.isEmpty) {
                          return Center(child: Text(l.noLibraryPdfs));
                        }
                        return ListView(
                          children: [
                            for (final document in documents)
                              ListTile(
                                title: Text(document.title),
                                onTap: () => setState(() {
                                  _selected = ref
                                      .read(apiProvider)
                                      .kb
                                      .getKbDocument(id: document.id);
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              )
            : FutureBuilder<DocumentDetail>(
                future: detail,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(errorMessage(snapshot.error!));
                  }
                  final document = snapshot.data;
                  if (document == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final published = document.pdfs.where((p) => p.published);
                  if (published.isEmpty) {
                    return Center(child: Text(l.noLibraryPdfs));
                  }
                  final latest = published
                      .map((p) => p.revision)
                      .reduce((a, b) => a > b ? a : b);
                  final variants = published
                      .where((p) => p.revision == latest)
                      .toList();
                  final preferred = variants
                      .where((p) => p.language == widget.language)
                      .firstOrNull;
                  Widget option(Pdf pdf) => ListTile(
                    title: Text(languageName(pdf.language)),
                    subtitle: Text(pdf.filename),
                    onTap: () => Navigator.pop(
                      context,
                      LibraryPdfSelection(document.document.id, pdf),
                    ),
                  );
                  return ListView(
                    children: [
                      Text(document.document.title),
                      Text(l.documentRevision(latest)),
                      if (preferred == null)
                        Text(l.libraryLanguageUnavailable)
                      else
                        option(preferred),
                      for (final pdf in variants.where((p) => p != preferred))
                        option(pdf),
                    ],
                  );
                },
              ),
      ),
      actions: [
        if (detail != null)
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: Text(l.search),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
