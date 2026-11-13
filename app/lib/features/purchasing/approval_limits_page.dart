import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';

/// The Purchasing "approval limits" segment (ADR 0062): the largest order, excluding VAT, each role
/// may approve. An empty field means the role has no limit. Shown to administrators of users only.
class ApprovalLimitsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const ApprovalLimitsPage({super.key});

  @override
  ConsumerState<ApprovalLimitsPage> createState() => _ApprovalLimitsPageState();
}

class _ApprovalLimitsPageState extends ConsumerState<ApprovalLimitsPage> {
  final _fields = <String, TextEditingController>{};
  String _currency = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(ApprovalLimits s) {
    _currency = s.currency;
    for (final r in s.roles) {
      final c = _fields.putIfAbsent(r.role, TextEditingController.new);
      c.text = r.maxAmount == null ? '' : number(r.maxAmount!);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await ref.read(apiProvider).purchasing.getApprovalLimits();
      if (mounted) _apply(s);
    } catch (e) {
      if (mounted) setState(() => _loadError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    final limits = <RoleLimitInput>[];
    for (final e in _fields.entries) {
      final text = e.value.text.trim();
      if (text.isEmpty) {
        limits.add(RoleLimitInput(role: e.key));
        continue;
      }
      final v = parseDecimalInput(text);
      if (v == null || double.parse(v) < 0) {
        setState(() => _error = l.purchLimitInvalid);
        return;
      }
      limits.add(RoleLimitInput(role: e.key, maxAmount: v));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await ref
          .read(apiProvider)
          .purchasing
          .updateApprovalLimits(
            body: UpdateApprovalLimitsInput(limits: limits),
          );
      if (!mounted) return;
      _apply(s);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.purchLimitsSaved)));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!),
            TextButton(
              key: const ValueKey('limits-retry'),
              onPressed: _load,
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.purchApprovalLimits,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l.purchApprovalLimitsHelp(_currency)),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 360,
            child: Column(
              children: [
                for (final e in _fields.entries) ...[
                  TextField(
                    key: ValueKey('limit-${e.key}'),
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${l.roleName(e.key)} ($_currency)',
                      hintText: l.purchNoLimit,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              key: const ValueKey('limits-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('limits-save'),
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
