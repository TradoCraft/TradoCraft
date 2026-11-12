import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/setup/setup_api.dart';
import '../l10n/l10n.dart';
import 'api.dart' show errorMessage;
import 'environments.dart';
import 'workspace.dart';
import '../features/tutorial/targets.dart';

/// The word for a kind in the user's language.
String environmentKindLabel(AppLocalizations l, EnvironmentKind kind) =>
    switch (kind) {
      EnvironmentKind.live => l.envLive,
      EnvironmentKind.test => l.envTest,
      EnvironmentKind.tutorial => l.envTutorial,
    };

/// Background and text colour of a kind: red for live, amber for test, blue for tutorial.
/// Dark mode uses deeper shades so the strip does not glare; text contrast stays above 4.5:1.
({Color background, Color foreground}) environmentColors(
  EnvironmentKind kind,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  return switch (kind) {
    EnvironmentKind.live => (
      background: dark ? const Color(0xFF8C1D18) : const Color(0xFFB3261E),
      foreground: Colors.white,
    ),
    EnvironmentKind.test => (
      background: dark ? const Color(0xFFC79100) : const Color(0xFFFFB300),
      foreground: Colors.black,
    ),
    EnvironmentKind.tutorial => (
      background: dark ? const Color(0xFF0D47A1) : const Color(0xFF1565C0),
      foreground: Colors.white,
    ),
  };
}

/// A slim strip across the top of the app that always says which environment is in use: the name
/// and the kind written out (the colour is a second signal, not the only one). Tapping it opens
/// the environment switcher.
class EnvironmentBanner extends ConsumerWidget {
  const EnvironmentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(activeEnvironmentProvider);
    final l = context.l10n;
    final kind = environmentKindLabel(l, env.kind);
    final colors = environmentColors(env.kind, Theme.of(context).brightness);
    return TutorialTarget(
      id: 'env-banner',
      child: Semantics(
        container: true,
        button: true,
        label: l.envBannerSemantics(env.name, kind),
        onTapHint: l.envSwitchTooltip,
        // The same action as tapping the strip, for screen readers.
        onTap: () => showEnvironmentSwitcher(context),
        child: ExcludeSemantics(
          child: Material(
            key: ValueKey('env-banner-${env.kind.name}'),
            color: colors.background,
            child: InkWell(
              onTap: () => showEnvironmentSwitcher(context),
              child: SizedBox(
                width: double.infinity,
                height: 26,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${kind.toUpperCase()} · ${env.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Before an environment switch closes every tab: true when nothing would be lost, or when the
/// user agreed to discard the unsaved edits of the tabs that have some.
Future<bool> confirmLeavingTabs(BuildContext context, WidgetRef ref) async {
  final count = ref.read(workspaceProvider.notifier).dirtyCount;
  if (count == 0) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.l10n.unsavedChangesTitle),
      content: Text(c.l10n.envUnsavedBody(count)),
      actions: [
        TextButton(
          key: const ValueKey('env-unsaved-cancel'),
          onPressed: () => Navigator.pop(c, false),
          child: Text(c.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('env-unsaved-discard'),
          onPressed: () => Navigator.pop(c, true),
          child: Text(c.l10n.envDiscardAndSwitch),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Lists the environments to switch between, add or remove.
Future<void> showEnvironmentSwitcher(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SwitcherDialog());

/// Opens the dialog that adds an environment (the server tells its kind). True when one was added.
/// The dialog only collects and checks; it is closed before the environment is added, because
/// adding switches the session and the router then rebuilds the page stack.
Future<bool?> showAddEnvironmentDialog(BuildContext context) async {
  final request = await showDialog<_AddRequest>(
    context: context,
    builder: (_) => const _AddDialog(),
  );
  return request == null ? false : request.run();
}

/// Everything the add dialog decided, with the objects needed once the dialog is gone (the
/// dialog's own `ref` and `context` are dead by then).
class _AddRequest {
  const _AddRequest({
    required this.notifier,
    required this.messenger,
    required this.router,
    required this.notSavedText,
    required this.name,
    required this.url,
    required this.kind,
    required this.openWizard,
  });

  final EnvironmentsNotifier notifier;
  final ScaffoldMessengerState messenger;
  final GoRouter? router;
  final String notSavedText;
  final String name;
  final String url;
  final EnvironmentKind kind;
  final bool openWizard;

  /// Adds the environment (which switches to it) and then says where to go. True when added.
  Future<bool> run() async {
    final r = await notifier.add(name: name, serverUrl: url, kind: kind);
    if (r == EnvChange.rejected) return false;
    if (r == EnvChange.notSaved) {
      messenger.showSnackBar(SnackBar(content: Text(notSavedText)));
    }
    if (openWizard) router?.go('/setup?server=${Uri.encodeQueryComponent(url)}');
    return true;
  }
}

/// The dialog behind [showEnvironmentSwitcher]: one tile per environment plus "add".
class _SwitcherDialog extends ConsumerWidget {
  const _SwitcherDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(environmentsProvider);
    final notifier = ref.read(environmentsProvider.notifier);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.envSwitcherTitle),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in state.items)
              _EnvTile(
                env: e,
                active: e.id == state.activeId,
                onSwitch: () async {
                  if (!await confirmLeavingTabs(context, ref)) return;
                  if (!context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final note = l.envNotSaved;
                  Navigator.pop(context);
                  final r = await notifier.switchTo(e.id);
                  if (r == EnvChange.notSaved) {
                    messenger.showSnackBar(SnackBar(content: Text(note)));
                  }
                },
                onRemove: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(c.l10n.envRemoveTitle),
                      content: Text(c.l10n.envRemoveBody(e.name)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(c.l10n.cancel),
                        ),
                        FilledButton(
                          key: const ValueKey('env-remove-confirm'),
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(c.l10n.envRemove),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  final r = await notifier.remove(e.id);
                  if (r == EnvChange.notSaved && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(l.envNotSaved)));
                  }
                },
              ),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('env-add'),
                icon: const Icon(Icons.add),
                label: Text(l.envAdd),
                onPressed: () async {
                  final request = await showDialog<_AddRequest>(
                    context: context,
                    builder: (_) => const _AddDialog(),
                  );
                  if (request == null || !context.mounted) return;
                  // Close the switcher too before the environment changes the router state.
                  Navigator.pop(context);
                  await request.run();
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
      surfaceTintColor: theme.colorScheme.surfaceTint,
    );
  }
}

/// One environment in the switcher: kind, name, address, and switch or remove.
class _EnvTile extends StatelessWidget {
  const _EnvTile({
    required this.env,
    required this.active,
    required this.onSwitch,
    required this.onRemove,
  });

  final AppEnvironment env;
  final bool active;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = environmentColors(env.kind, Theme.of(context).brightness);
    final kind = environmentKindLabel(l, env.kind);
    return ListTile(
      key: ValueKey('env-tile-${env.id}'),
      selected: active,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          kind,
          style: TextStyle(
            color: colors.foreground,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(env.name),
      subtitle: Text(
        env.serverUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: active
          ? Chip(label: Text(l.envActive))
          : IconButton(
              key: ValueKey('env-remove-${env.id}'),
              tooltip: l.envRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
      onTap: active ? null : onSwitch,
    );
  }
}

/// Asks for an address, checks it with the server and adds the environment it reports.
class _AddDialog extends ConsumerStatefulWidget {
  const _AddDialog();

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

/// State of [_AddDialog]: the fields and the server's answer for the address that was checked.
class _AddDialogState extends ConsumerState<_AddDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  EnvironmentProbe? _probe;
  String? _checkedUrl;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final l = context.l10n;
    final url = normalizeServerUrl(_url.text);
    if (url == null) {
      setState(() {
        _probe = null;
        _error = l.envInvalidUrl;
      });
      return;
    }
    if (ref
        .read(environmentsProvider)
        .items
        .any((e) => sameServer(e.serverUrl, url))) {
      setState(() {
        _probe = null;
        _error = l.envAlreadyListed;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _probe = null;
    });
    try {
      final info = await ref.read(environmentProbeProvider)(url);
      // The address was edited while the server was answering: that answer is for another one.
      if (!mounted || normalizeServerUrl(_url.text) != url) return;
      setState(() {
        _probe = info;
        _checkedUrl = url;
        if (_name.text.trim().isEmpty) _name.text = info.name;
      });
    } catch (e) {
      if (mounted && normalizeServerUrl(_url.text) == url) {
        setState(() => _error = l.envUnreachable(errorMessage(e)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final probe = _probe;
    final url = _checkedUrl;
    if (probe == null || url == null) return;
    final name = _name.text.trim().isEmpty ? probe.name : _name.text.trim();
    // Adding switches at once, so it asks about unsaved tabs like a switch does.
    if (!await confirmLeavingTabs(context, ref)) return;
    if (!mounted) return;
    if (ref
        .read(environmentsProvider)
        .items
        .any((e) => sameServer(e.serverUrl, url))) {
      setState(() => _error = context.l10n.envAlreadyListed);
      return;
    }
    // A server without a company: offer the setup wizard (ADR 0047). Best effort.
    var needsSetup = false;
    try {
      needsSetup = (await ref.read(setupStatusProvider)(url)).needsSetup;
    } catch (_) {}
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    var openWizard = false;
    if (needsSetup && router != null) {
      openWizard =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(ctx.l10n.setupAddOfferTitle),
              content: Text(ctx.l10n.setupAddOfferBody),
              actions: [
                TextButton(
                  key: const ValueKey('setup-offer-later'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.l10n.setupLater),
                ),
                FilledButton(
                  key: const ValueKey('setup-offer-open'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.l10n.setupOffer),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted) return;
    }
    // Capture what is needed once the dialog is gone, then close it before anything changes
    // the router state. The kind is the server's word, never the user's.
    final request = _AddRequest(
      notifier: ref.read(environmentsProvider.notifier),
      messenger: ScaffoldMessenger.of(context),
      router: router,
      notSavedText: context.l10n.envNotSaved,
      name: name,
      url: url,
      kind: probe.kind,
      openWizard: openWizard,
    );
    Navigator.pop(context, request);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final probe = _probe;
    return AlertDialog(
      title: Text(l.envAdd),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('env-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l.envServerUrl),
              // Another address means the last check no longer applies.
              onChanged: (_) {
                if (_probe != null) setState(() => _probe = null);
              },
              onSubmitted: (_) => _check(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('env-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l.envName),
            ),
            const SizedBox(height: 12),
            if (probe != null)
              Row(
                children: [
                  Chip(
                    key: const ValueKey('env-detected-kind'),
                    backgroundColor: environmentColors(
                      probe.kind,
                      Theme.of(context).brightness,
                    ).background,
                    label: Text(
                      environmentKindLabel(l, probe.kind),
                      style: TextStyle(
                        color: environmentColors(
                          probe.kind,
                          Theme.of(context).brightness,
                        ).foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.envDetected(
                        environmentKindLabel(l, probe.kind),
                        probe.dbName,
                      ),
                    ),
                  ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        OutlinedButton(
          key: const ValueKey('env-check'),
          onPressed: _busy ? null : _check,
          child: Text(l.envCheck),
        ),
        FilledButton(
          key: const ValueKey('env-add-confirm'),
          onPressed: probe == null || _busy ? null : _add,
          child: Text(l.envAdd),
        ),
      ],
    );
  }
}
