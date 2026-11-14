import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart' show errorMessage;
import '../../app/brand.dart';
import '../../app/environment_ui.dart';
import '../../app/session.dart';
import '../../l10n/l10n.dart';
import 'setup_api.dart';

/// The steps of the wizard; [token] is left out when the server does not ask for one.
enum _Step { company, region, admin, token, review }

/// Wizard that creates the first company of an empty server (ADR 0047): company, region,
/// administrator, the setup token when the server wants one, review and create. In development
/// mode it then signs in as the new administrator; with OIDC it explains how to sign in.
class SetupPage extends ConsumerStatefulWidget {
  /// Creates the wizard for [server], or for the session's server when null.
  const SetupPage({super.key, this.server});

  /// Address of the server to set up.
  final String? server;

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

/// State of [SetupPage]: the fields, the current step and the outcome.
class _SetupPageState extends ConsumerState<SetupPage> {
  final _name = TextEditingController();
  final _legal = TextEditingController();
  final _vat = TextEditingController();
  final _country = TextEditingController(text: 'BE');
  final _currency = TextEditingController(text: 'EUR');
  final _email = TextEditingController();
  final _adminName = TextEditingController();
  final _token = TextEditingController();
  String _language = 'en';

  late final String _server =
      widget.server ?? ref.read(sessionProvider).serverUrl;
  SetupStatusInfo? _status;
  String? _statusError;
  int _index = 0;
  bool _validated = false;
  bool _busy = false;
  String? _error;
  SetupResult? _result;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _legal,
      _vat,
      _country,
      _currency,
      _email,
      _adminName,
      _token,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await ref.read(setupStatusProvider)(_server);
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _statusError = errorMessage(e));
    }
  }

  List<_Step> get _steps => [
    _Step.company,
    _Step.region,
    _Step.admin,
    if (_status?.tokenRequired ?? false) _Step.token,
    _Step.review,
  ];

  _Step get _step => _steps[_index.clamp(0, _steps.length - 1)];

  /// The error text of each field of [step]; empty when the step is valid.
  Map<String, String> _problems(
    _Step step,
    AppLocalizations l,
  ) => switch (step) {
    _Step.company => {
      if (!SetupValidation.name(_name.text)) 'name': l.setupErrName,
      if (!SetupValidation.vat(_vat.text)) 'vat': l.setupErrVat,
    },
    _Step.region => {
      if (!SetupValidation.country(_country.text)) 'country': l.setupErrCountry,
      if (!SetupValidation.currency(_currency.text))
        'currency': l.setupErrCurrency,
    },
    _Step.admin => {
      if (!SetupValidation.email(_email.text)) 'email': l.setupErrEmail,
      if (_adminName.text.trim().isEmpty) 'adminName': l.setupErrAdminName,
    },
    _Step.token => {if (_token.text.trim().isEmpty) 'token': l.setupErrToken},
    _Step.review => {},
  };

  void _next() {
    if (_problems(_step, context.l10n).isNotEmpty) {
      setState(() => _validated = true);
      return;
    }
    setState(() {
      _index++;
      _validated = false;
      _error = null;
    });
  }

  void _back() => setState(() {
    _index--;
    _validated = false;
    _error = null;
  });

  String _failure(Object e) {
    final l = context.l10n;
    if (e is InsecureServerException) return l.setupErrInsecure;
    if (e is RedirectRefusedException) return l.setupErrRedirect;
    if (e is DioException) {
      switch (e.response?.statusCode) {
        case 403:
          return l.setupErr403;
        case 404:
          return l.setupErr404;
        case 409:
          return l.setupErr409;
      }
    }
    return errorMessage(e);
  }

  Future<void> _create() async {
    final req = SetupRequest(
      name: _name.text,
      legalName: _legal.text,
      vatNumber: _vat.text,
      countryCode: _country.text,
      currency: _currency.text,
      defaultLanguage: _language,
      adminEmail: _email.text,
      adminDisplayName: _adminName.text,
      token: (_status?.tokenRequired ?? false) ? _token.text : null,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(setupBootstrapProvider)(_server, req);
      if (!mounted) return;
      setState(() => _result = result);
      if (result.isDev) {
        // The admin e-mail is the dev user of this server: sign in as that user.
        await ref
            .read(sessionProvider.notifier)
            .signIn(Session(serverUrl: _server, devUser: result.adminEmail));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const EnvironmentBanner(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _content(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l = context.l10n;
    final header = <Widget>[
      Text(brandName, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(l.setupTitle, style: Theme.of(context).textTheme.titleMedium),
      Text(
        l.setupServer(_server),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
    ];
    final result = _result;
    if (result != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...header,
          Text(
            l.setupDone(result.companyName),
            key: const ValueKey('setup-done'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            result.isDev
                ? l.setupDoneDev(result.adminEmail)
                : l.setupDoneOidc(result.adminEmail),
            key: const ValueKey('setup-next'),
          ),
          if (!result.isDev) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('setup-to-login'),
              onPressed: () => context.go('/login'),
              child: Text(l.setupToLogin),
            ),
          ],
        ],
      );
    }
    if (_status == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          if (_statusError != null)
            Text(
              _statusError!,
              key: const ValueKey('setup-status-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(l.setupToLogin),
          ),
        ],
      );
    }
    if (!_status!.needsSetup) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Text(l.setupUnavailable, key: const ValueKey('setup-unavailable')),
          const SizedBox(height: 16),
          TextButton(
            key: const ValueKey('setup-unavailable-back'),
            onPressed: () => context.go('/login'),
            child: Text(l.setupToLogin),
          ),
        ],
      );
    }
    final problems = _validated ? _problems(_step, l) : <String, String>{};
    final last = _step == _Step.review;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        Text(
          l.setupStepOf(_index + 1, _steps.length),
          key: const ValueKey('setup-progress'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        ..._fields(context, problems),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('setup-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            if (_index > 0)
              TextButton(
                key: const ValueKey('setup-back'),
                onPressed: _busy ? null : _back,
                child: Text(l.setupBack),
              ),
            const Spacer(),
            if (last)
              FilledButton(
                key: const ValueKey('setup-create'),
                onPressed: _busy ? null : _create,
                child: Text(l.setupCreate),
              )
            else
              FilledButton(
                key: const ValueKey('setup-next-button'),
                onPressed: _next,
                child: Text(l.setupNext),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('setup-cancel'),
          onPressed: _busy ? null : () => context.go('/login'),
          child: Text(l.cancel),
        ),
      ],
    );
  }

  Widget _field(
    String key,
    TextEditingController c,
    String label,
    Map<String, String> problems, {
    String? helper,
    TextInputType? type,
    bool obscure = false,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey('setup-$key'),
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: problems[key],
        counterText: '',
      ),
      maxLength: maxLength,
    ),
  );

  List<Widget> _fields(BuildContext context, Map<String, String> p) {
    final l = context.l10n;
    switch (_step) {
      case _Step.company:
        return [
          Text(
            l.setupStepCompany,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _field('name', _name, l.setupCompanyName, p, maxLength: 200),
          _field('legal', _legal, l.setupLegalName, p, maxLength: 200),
          _field('vat', _vat, l.setupVatNumber, p),
        ];
      case _Step.region:
        return [
          Text(
            l.setupStepRegion,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _field(
            'country',
            _country,
            l.setupCountry,
            p,
            maxLength: 2,
            formatters: [UpperCaseFormatter()],
          ),
          _field(
            'currency',
            _currency,
            l.setupCurrency,
            p,
            maxLength: 3,
            formatters: [UpperCaseFormatter()],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: const ValueKey('setup-language'),
              initialValue: _language,
              decoration: InputDecoration(labelText: l.setupLanguage),
              items: const [
                DropdownMenuItem(value: 'nl', child: Text('Nederlands')),
                DropdownMenuItem(value: 'fr', child: Text('Français')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
              ],
              onChanged: (v) => setState(() => _language = v ?? _language),
            ),
          ),
        ];
      case _Step.admin:
        return [
          Text(l.setupStepAdmin, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _field(
            'email',
            _email,
            l.setupAdminEmail,
            p,
            type: TextInputType.emailAddress,
          ),
          _field('adminName', _adminName, l.setupAdminName, p, maxLength: 200),
        ];
      case _Step.token:
        return [
          Text(l.setupStepToken, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _field(
            'token',
            _token,
            l.setupToken,
            p,
            helper: l.setupTokenHelp,
            obscure: true,
          ),
        ];
      case _Step.review:
        final rows = [
          (l.setupCompanyName, _name.text.trim()),
          if (_legal.text.trim().isNotEmpty)
            (l.setupLegalName, _legal.text.trim()),
          if (_vat.text.trim().isNotEmpty) (l.setupVatNumber, _vat.text.trim()),
          (l.setupCountry, _country.text.trim().toUpperCase()),
          (l.setupCurrency, _currency.text.trim().toUpperCase()),
          (l.setupLanguage, _language),
          (l.setupAdminEmail, _email.text.trim()),
          (l.setupAdminName, _adminName.text.trim()),
        ];
        return [
          Text(
            l.setupStepReview,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(l.setupReviewHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(flex: 3, child: Text(value)),
                ],
              ),
            ),
        ];
    }
  }
}

/// Turns what is typed into upper case (country and currency codes).
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
