import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';

/// What happens when a delivery is planned on a day the customer is closed: only the
/// administrator (`delivery.admin`) decides.
class DeliverySettingsPage extends ConsumerStatefulWidget {
  const DeliverySettingsPage({super.key});

  @override
  ConsumerState<DeliverySettingsPage> createState() =>
      _DeliverySettingsPageState();
}

class _DeliverySettingsPageState extends ConsumerState<DeliverySettingsPage> {
  String? _policy;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiProvider)
        .delivery
        .getSettings()
        .then((s) {
          if (mounted) setState(() => _policy = s.closurePolicy);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = errorMessage(e));
        });
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .delivery
          .putSettings(body: DeliverySettings(closurePolicy: _policy!));
      messenger.showSnackBar(SnackBar(content: Text(l.saved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final admin =
        ref.watch(meProvider).value?.permissions.contains('delivery.admin') ??
        false;
    final help = {
      'warn': l.closurePolicyWarnHelp,
      'override': l.closurePolicyOverrideHelp,
      'block': l.closurePolicyBlockHelp,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.deliverySettingsTitle)),
      body: !admin
          ? Center(child: Text(l.noPermission))
          : _error != null
          ? Center(child: Text(_error!))
          : _policy == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l.closurePolicyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                RadioGroup<String>(
                  groupValue: _policy,
                  onChanged: (v) {
                    if (!_saving) setState(() => _policy = v ?? _policy);
                  },
                  child: Column(
                    children: [
                      for (final p in const ['warn', 'override', 'block'])
                        RadioListTile<String>(
                          key: ValueKey('policy-$p'),
                          value: p,
                          title: Text(l.closurePolicy(p)),
                          subtitle: Text(help[p]!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const ValueKey('save-settings'),
                    onPressed: _saving ? null : _save,
                    child: Text(l.save),
                  ),
                ),
              ],
            ),
    );
  }
}
