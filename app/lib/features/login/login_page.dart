import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/brand.dart';
import '../../app/environment_ui.dart';
import '../../app/profile.dart';
import '../../app/session.dart';
import '../field/offline/kv_store.dart';
import '../setup/setup_api.dart';
import '../../l10n/l10n.dart';

/// Seeded demo users (SEED_DEV_DATA=true), one per role, for quick switching in dev mode.
const _demoUsers = [
  'admin',
  'sales',
  'manager',
  'support',
  'production',
  'viewer',
];

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final _server = TextEditingController(
    text: ref.read(sessionProvider).serverUrl,
  );
  final _user = TextEditingController(text: 'sales@example.com');
  final _token = TextEditingController();
  bool _useToken = false;
  bool _busy = false;
  String? _error;

  /// Whether the server in the address field has no company yet (offers the setup wizard).
  bool _needsSetup = false;

  /// The address [_needsSetup] was asked for, so a late answer for another address is ignored.
  String? _setupAskedFor;

  /// Pending timer of the debounced setup check.
  Timer? _setupDebounce;

  /// Counts address edits and setup checks; an answer counts only while its number is current,
  /// so a slow answer for an earlier address (even one typed again later) is dropped.
  int _setupGeneration = 0;

  /// The address was edited: the earlier answer no longer applies, so the offer goes away and the
  /// new address is asked after a short pause. A late answer for an older address is ignored.
  void _serverEdited(String _) {
    _setupDebounce?.cancel();
    _setupAskedFor = null;
    _setupGeneration++;
    if (_needsSetup) setState(() => _needsSetup = false);
    _setupDebounce = Timer(const Duration(milliseconds: 500), _checkSetup);
  }

  @override
  void dispose() {
    _setupDebounce?.cancel();
    super.dispose();
  }

  /// Asks the server in the address field whether it needs setting up. Failures (unreachable,
  /// not a TradoCraft server) just mean no offer.
  Future<void> _checkSetup() async {
    final url = _server.text.trim();
    _setupAskedFor = url;
    final generation = ++_setupGeneration;
    var needs = false;
    if (url.isNotEmpty) {
      try {
        needs = (await ref.read(setupStatusProvider)(url)).needsSetup;
      } catch (_) {}
    }
    if (mounted && generation == _setupGeneration && _setupAskedFor == url) {
      setState(() => _needsSetup = needs);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkSetup();
    // A named profile remembers who signed in last, so a window per role opens ready to go.
    if (ref.read(profileProvider) != null) {
      ref.read(kvStoreProvider).get(SessionStore.lastDevUserKey).then((u) {
        if (u != null && u.isNotEmpty && mounted && !_userEdited) {
          _user.text = u;
        }
      }, onError: (Object _) {});
    }
  }

  /// Set by typing in the field (not by assigning [_user]'s text), so a remembered user never
  /// overwrites what the person typed, even when they typed the default back.
  bool _userEdited = false;

  Future<void> _signIn() async {
    final session = Session(
      serverUrl: _server.text.trim(),
      devUser: _useToken ? null : _user.text.trim(),
      accessToken: _useToken ? _token.text.trim() : null,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Verify the credentials before storing them.
      final probe = ProviderContainer(
        overrides: [initialSessionProvider.overrideWithValue(session)],
      );
      try {
        await probe.read(apiProvider).core.me();
      } finally {
        probe.dispose();
      }
      await ref.read(sessionProvider.notifier).signIn(session);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Another environment chosen in the switcher: show its address.
    ref.listen(sessionProvider, (_, s) {
      _server.text = s.serverUrl;
      _checkSetup();
    });
    return Scaffold(
      body: Column(
        children: [
          const EnvironmentBanner(),
          Expanded(child: _form(context)),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    return Center(
      // Scrolls in short windows, so the sign-in button stays reachable.
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    brandName,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _server,
                    decoration: InputDecoration(labelText: context.l10n.server),
                    onChanged: _serverEdited,
                    onSubmitted: (_) => _checkSetup(),
                  ),
                  SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.l10n.developmentUser),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.l10n.accessToken),
                      ),
                    ],
                    selected: {_useToken},
                    onSelectionChanged: (s) =>
                        setState(() => _useToken = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (_useToken)
                    TextField(
                      controller: _token,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.oidcAccessToken,
                      ),
                    )
                  else
                    TextField(
                      controller: _user,
                      onChanged: (_) => _userEdited = true,
                      decoration: InputDecoration(
                        labelText: context.l10n.email,
                        helperText: context.l10n.devModeHelp,
                      ),
                      onSubmitted: (_) => _signIn(),
                    ),
                  if (!_useToken) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final u in _demoUsers)
                          ActionChip(
                            label: Text(u),
                            onPressed: _busy
                                ? null
                                : () {
                                    // Keeps a remembered user from replacing this choice.
                                    _userEdited = true;
                                    _user.text = '$u@example.com';
                                    _signIn();
                                  },
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: Text(context.l10n.signIn),
                  ),
                  if (_needsSetup) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.setupOfferHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('login-setup'),
                      icon: const Icon(Icons.add_business),
                      label: Text(context.l10n.setupOffer),
                      onPressed: _busy
                          ? null
                          : () => context.go(
                              '/setup?server=${Uri.encodeQueryComponent(_server.text.trim())}',
                            ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const ValueKey('login-environments'),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(context.l10n.envSwitcherTitle),
                    onPressed: _busy
                        ? null
                        : () => showEnvironmentSwitcher(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
