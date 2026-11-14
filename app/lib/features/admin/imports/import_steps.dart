import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/csv_transfer.dart';
import 'import_wizard.dart';
import 'imports_api.dart';
import 'job_widgets.dart';

/// Step 1: choose a file and upload it.
class FileStep extends ConsumerWidget {
  const FileStep({super.key});

  Future<void> _choose(WidgetRef ref) async {
    final wizard = ref.read(importWizardProvider.notifier);
    final picker = ref.read(importFilePickerProvider);
    PickedFile? picked;
    try {
      picked = await picker();
    } catch (_) {
      wizard.fail(const FileReadError());
      return;
    }
    if (picked != null) await wizard.upload(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    final scheme = Theme.of(context).colorScheme;
    final file = s.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.impFileHelp),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('imp-choose-file'),
              onPressed: s.uploading ? null : () => _choose(ref),
              icon: const Icon(AppIcons.fileUpload),
              label: Text(file == null ? l.impChooseFile : l.impChooseOther),
            ),
            if (s.uploading)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l.impUploading),
                ],
              ),
          ],
        ),
        if (s.uploadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                uploadErrorText(l, s.uploadError!),
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        if (file != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(AppIcons.attachFile, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.filename,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        l.impFileFormatSize(
                          formatName(file.format),
                          fileSize(file.sizeBytes),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Step 2: the entity, the sheet and a preview of the file.
class WhatStep extends ConsumerWidget {
  const WhatStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    final wizard = ref.read(importWizardProvider.notifier);
    final entities = ref.watch(importEntitiesProvider);
    final file = s.file!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        entities.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _Failure(
            message: errorMessage(e),
            onRetry: () => ref.invalidate(importEntitiesProvider),
          ),
          data: (list) => list.isEmpty
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(AppIcons.info, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(l.impNoEntities),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  key: ValueKey('imp-entity-${s.entity?.key}'),
                  isExpanded: true,
                  initialValue: s.entity?.key,
                  decoration: InputDecoration(labelText: l.impEntity),
                  items: [
                    for (final e in list)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          entityLabel(l, e.key),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (k) {
                    if (k != null) {
                      wizard.selectEntity(list.firstWhere((e) => e.key == k));
                    }
                  },
                ),
        ),
        if (file.sheets.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('imp-sheet-${s.sheet}'),
            isExpanded: true,
            initialValue: s.sheet,
            decoration: InputDecoration(labelText: l.impSheet),
            items: [
              for (final name in file.sheets)
                DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) wizard.selectSheet(v);
            },
          ),
        ],
        const SizedBox(height: 16),
        Text(l.impPreview, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (s.previewLoading) const LinearProgressIndicator(),
        if (s.previewError != null)
          _Failure(
            message: errorMessage(s.previewError!),
            onRetry: wizard.reloadPreview,
          ),
        if (s.preview != null) PreviewTable(preview: s.preview!),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l.retry)),
      ],
    );
  }
}

/// The header, the row count and the first rows of the file, scrolling sideways when wide.
class PreviewTable extends StatelessWidget {
  const PreviewTable({super.key, required this.preview});
  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cols = preview.columns;
    if (cols.isEmpty) return Text(l.impNoHeader);
    String cell(List<String> row, int i) => i < row.length ? row[i] : '';
    Widget text(String s, {bool bold = false}) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            l.impRowCount(preview.rowCount),
            if (preview.rows.length < preview.rowCount)
              l.impFirstRows(preview.rows.length),
          ].join('. '),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: DataTable(
                key: const ValueKey('imp-preview'),
                columnSpacing: 20,
                headingRowHeight: 40,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 34,
                columns: [
                  for (final c in cols) DataColumn(label: text(c, bold: true)),
                ],
                rows: [
                  for (final r in preview.rows)
                    DataRow(
                      cells: [
                        for (var i = 0; i < cols.length; i++)
                          DataCell(text(cell(r, i))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
