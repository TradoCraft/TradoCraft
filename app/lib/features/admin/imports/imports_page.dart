import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/l10n.dart';
import 'check_apply_steps.dart';
import 'import_steps.dart';
import 'import_wizard.dart';
import 'job_history.dart';
import 'mapping_editor.dart';

/// Administration, tab "Import" (`imports.admin`): a new import in five numbered sections on one
/// page (file, what and where, columns, check, import), and the history of the runs.
class ImportsPage extends ConsumerStatefulWidget {
  const ImportsPage({super.key});

  @override
  ConsumerState<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends ConsumerState<ImportsPage> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Watched here, not in the sections, so that leaving the page ends the polling of a job.
    final s = ref.watch(importWizardProvider);
    final columnsReady = s.mappable;
    final checkReady = columnsReady && s.mappingOk;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              key: const ValueKey('imp-view'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l.impNew)),
                ButtonSegment(value: true, label: Text(l.impHistory)),
              ],
              selected: {_history},
              onSelectionChanged: (v) => setState(() => _history = v.first),
            ),
          ),
        ),
        Expanded(
          child: _history
              ? const JobHistory()
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Section(
                          number: 1,
                          title: l.impStepFile,
                          done: s.file != null,
                          child: const FileStep(),
                        ),
                        _Section(
                          number: 2,
                          title: l.impStepWhat,
                          done: columnsReady,
                          child: s.file == null ? null : const WhatStep(),
                        ),
                        _Section(
                          number: 3,
                          title: l.impStepColumns,
                          done: checkReady,
                          child: columnsReady ? const MappingEditor() : null,
                        ),
                        _Section(
                          number: 4,
                          title: l.impStepCheck,
                          done: s.checkedClean,
                          child: checkReady ? const CheckStep() : null,
                        ),
                        _Section(
                          number: 5,
                          title: l.impStepApply,
                          done: s.apply.job?.status == 'done',
                          child: checkReady && s.dry.job != null
                              ? const ApplyStep()
                              : null,
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

/// A numbered section; without a [child] (an earlier step is not finished) only the title shows.
class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.done,
    required this.child,
  });
  final int number;
  final String title;
  final bool done;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = child != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 14,
              backgroundColor: done
                  ? scheme.primary
                  : active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: done
                  ? scheme.onPrimary
                  : active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              child: Text('$number'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '$number. $title',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: active ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (child != null) ...[const SizedBox(height: 12), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
