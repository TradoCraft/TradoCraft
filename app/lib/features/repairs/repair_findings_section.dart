import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';

/// What was found when the product was looked at, and the conclusion. Anyone who may work on the
/// repair edits it; others read it.
class RepairFindingsSection extends ConsumerStatefulWidget {
  const RepairFindingsSection({
    super.key,
    required this.repair,
    required this.editable,
    required this.onChanged,
  });
  final Repair repair;
  final bool editable;

  /// Called with the repair as the server returned it after saving.
  final void Function(RepairDetail) onChanged;

  @override
  ConsumerState<RepairFindingsSection> createState() =>
      _RepairFindingsSectionState();
}

class _RepairFindingsSectionState extends ConsumerState<RepairFindingsSection> {
  late final _findings = TextEditingController(text: widget.repair.findings);
  late final _diagnosis = TextEditingController(text: widget.repair.diagnosis);
  bool _busy = false;

  @override
  void dispose() {
    _findings.dispose();
    _diagnosis.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    RepairDetail? d;
    final ok = await runAction(
      context,
      () async => d = await ref
          .read(apiProvider)
          .repairs
          .setRepairFindings(
            id: widget.repair.id,
            body: FindingsInput(
              findings: _findings.text.trim(),
              diagnosis: _diagnosis.text.trim(),
            ),
          ),
      success: context.l10n.saved,
    );
    if (mounted) setState(() => _busy = false);
    if (ok && d != null) widget.onChanged(d!);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final r = widget.repair;
    if (!widget.editable) {
      if (r.findings.isEmpty && r.diagnosis.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.findingsSection, style: theme.textTheme.titleSmall),
          if (r.findings.isNotEmpty) SelectableText(r.findings),
          if (r.diagnosis.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.diagnosisLabel, style: theme.textTheme.labelMedium),
            SelectableText(r.diagnosis),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.findingsSection, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _findings,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(labelText: l.findingsLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _diagnosis,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.diagnosisLabel),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(AppIcons.save, size: 18),
            label: Text(l.saveFindings),
          ),
        ),
      ],
    );
  }
}
