import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// The company's register of addresses that receive no mailings (ADR 0099). Returns true when the
/// register changed, so the caller knows its preview is out of date.
Future<bool> showMailingOptOutsDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      // Closing goes through the dialog itself, which waits for a write in flight.
      barrierDismissible: false,
      builder: (_) => const MailingOptOutsDialog(),
    ) ??
    false;

class MailingOptOutsDialog extends ConsumerStatefulWidget {
  const MailingOptOutsDialog({super.key});

  @override
  ConsumerState<MailingOptOutsDialog> createState() =>
      _MailingOptOutsDialogState();
}

class _MailingOptOutsDialogState extends ConsumerState<MailingOptOutsDialog> {
  final _email = TextEditingController();
  List<MailingOptOut> _items = [];
  String? _error;
  bool _busy = true;
  bool _changed = false;

  CrmClient get _api => ref.read(apiProvider).crm;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Runs a change, then reloads the list.
  Future<void> _run(Future<void> Function() change) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
      final items = await _api.listMailingOptOuts();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    await _run(() async {
      await _api.addMailingOptOut(body: MailingOptOutInput(email: email));
      _email.clear();
      _changed = true;
    });
  }

  Future<void> _remove(String email) => _run(() async {
    // The generated client puts the value in the path as it is.
    await _api.removeMailingOptOut(email: Uri.encodeComponent(email));
    _changed = true;
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Every way out returns whether the register changed; none while a write is in flight.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.pop(context, _changed);
      },
      child: AlertDialog(
        title: Text(l.mergeOptOuts),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.mergeOptOutsHelp),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('opt-out-email'),
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: l.email),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('opt-out-add'),
                    onPressed: _busy ? null : _add,
                    child: Text(l.add),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (_items.isEmpty && !_busy) Text(l.mergeOptOutsEmpty),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in _items)
                      ListTile(
                        key: ValueKey(item.email),
                        title: Text(item.email),
                        subtitle: Text(
                          [
                            MaterialLocalizations.of(context)
                                .formatMediumDate(item.optedOutAt.toLocal()),
                            item.source == 'unsubscribe_link'
                                ? l.mergeOptOutViaLink
                                : l.mergeOptOutViaStaff(
                                    item.recordedByName ?? '',
                                  ),
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: l.remove,
                          icon: const Icon(AppIcons.delete),
                          onPressed: _busy ? null : () => _remove(item.email),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('opt-out-close'),
            onPressed: _busy ? null : () => Navigator.pop(context, _changed),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}
