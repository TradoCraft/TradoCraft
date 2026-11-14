import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'import_wizard.dart';
import 'imports_api.dart';
import 'job_widgets.dart';

/// Step 4: a dry run of the file, as a finished job or a background job that is followed.
class CheckStep extends ConsumerWidget {
  const CheckStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    final wizard = ref.read(importWizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final run = s.dry;
    final job = run.job;
    final busy = run.starting || (job != null && jobIsActive(job));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(AppIcons.info, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(l.impBackgroundNote)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey('imp-run-check'),
              onPressed: busy || !s.mappingOk
                  ? null
                  : () => wizard.run(dryRun: true),
              icon: const Icon(AppIcons.factCheck),
              label: Text(l.impRunCheck),
            ),
            if (run.starting)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l.impChecking),
                ],
              ),
          ],
        ),
        if (run.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorMessage(run.error!),
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        if (job != null) ...[
          const SizedBox(height: 12),
          if (s.checkOutdated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.warningAmber, size: 18, color: scheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(l.impOutdated),
                    ),
                  ),
                ],
              ),
            ),
          JobOutcome(
            job: job,
            planned: true,
            onCancel: () => wizard.cancel(dryRun: true),
          ),
        ],
      ],
    );
  }
}

/// Step 5: the real import, possible only after a clean check of the same settings.
class ApplyStep extends ConsumerWidget {
  const ApplyStep({super.key});

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final s = ref.read(importWizardProvider);
    final dry = s.dry.job!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.impApplyConfirmTitle(entityLabel(l, s.entity!.key))),
        content: Text(l.impApplyConfirmBody(dry.created, dry.updated)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('imp-apply-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.csvImportAction),
          ),
        ],
      ),
    );
    if (sure == true) {
      await ref.read(importWizardProvider.notifier).run(dryRun: false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    final wizard = ref.read(importWizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final run = s.apply;
    final job = run.job;
    final busy = run.starting || (job != null && jobIsActive(job));
    final started = job != null || run.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!started && !s.checkedClean) Text(l.impApplyHint),
        if (!started)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('imp-apply'),
                onPressed: s.checkedClean ? () => _apply(context, ref) : null,
                icon: const Icon(AppIcons.fileUpload),
                label: Text(l.impApplyAction),
              ),
            ),
          ),
        if (run.starting)
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(l.csvImporting),
            ],
          ),
        if (run.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorMessage(run.error!),
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        if (job != null) ...[
          const SizedBox(height: 12),
          JobOutcome(
            job: job,
            planned: false,
            onCancel: () => wizard.cancel(dryRun: false),
          ),
          if (!busy) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('imp-another'),
              onPressed: wizard.reset,
              icon: const Icon(AppIcons.refresh),
              label: Text(l.impImportAnother),
            ),
          ],
        ],
      ],
    );
  }
}
