import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'identity_providers_page.dart';

/// The ready-made starting points of the form; the server only stores plain settings.
enum IdpPreset { entra, google, generic }

/// Signature algorithms the server accepts (never HS*, EdDSA or none).
const idpAlgorithms = [
  'RS256',
  'RS384',
  'RS512',
  'ES256',
  'ES384',
  'PS256',
  'PS384',
  'PS512',
];

/// The issuer of a Microsoft Entra ID tenant.
String entraIssuer(String tenant) =>
    'https://login.microsoftonline.com/${tenant.trim()}/v2.0';

final _domainPattern = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

/// Whether [d] (lower case, no `@`) looks like a domain name such as `example.com`.
bool looksLikeDomain(String d) => _domainPattern.hasMatch(d);

/// Whether [s] is an `https://` URL with a host.
bool isHttpsUrl(String s) {
  final u = Uri.tryParse(s.trim());
  return u != null && u.scheme == 'https' && u.host.isNotEmpty;
}

/// Add ([provider] null) or edit dialog of a saved identity provider; pops true when saved.
class IdentityProviderDialog extends ConsumerStatefulWidget {
  const IdentityProviderDialog({super.key, this.provider});

  /// The provider to edit; null to add one.
  final IdentityProviderInfo? provider;

  @override
  ConsumerState<IdentityProviderDialog> createState() =>
      _IdentityProviderDialogState();
}

class _IdentityProviderDialogState
    extends ConsumerState<IdentityProviderDialog> {
  IdentityProviderInfo? get _p => widget.provider;

  late final _name = TextEditingController(text: _p?.name);
  late final _tenant = TextEditingController();
  late final _issuer = TextEditingController(text: _p?.issuer);
  late final _audience = TextEditingController(text: _p?.audience);
  late final _clientId = TextEditingController(text: _p?.clientId);
  late final _scopes = TextEditingController(
    text: _p?.scopes ?? 'openid profile email',
  );
  late final _emailClaim = TextEditingController(
    text: _p?.emailClaim ?? 'email',
  );
  late final _verifiedClaim = TextEditingController(
    text: _p?.verifiedClaim ?? 'email_verified',
  );
  final _domainInput = TextEditingController();
  final _sample = TextEditingController();

  late String _policy = _p?.emailPolicy ?? 'require_verified_claim';
  late String _tokenUse = _p?.tokenUse ?? 'id_token';
  late final List<String> _domains = [...?_p?.allowedEmailDomains];
  late final Set<String> _algs = {...?_p?.algorithms};
  late bool _enabled = _p?.enabled ?? true;
  IdpPreset? _preset;
  final _errors = <String, String>{};
  String? _saveError;
  bool _busy = false;
  bool _testing = false;
  IdentityProviderTestResult? _report;
  String? _testError;

  @override
  void initState() {
    super.initState();
    if (_algs.isEmpty) _algs.addAll(idpAlgorithms);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _tenant,
      _issuer,
      _audience,
      _clientId,
      _scopes,
      _emailClaim,
      _verifiedClaim,
      _domainInput,
      _sample,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form from a preset.
  void _applyPreset(IdpPreset p) {
    setState(() {
      _preset = p;
      switch (p) {
        case IdpPreset.entra:
          _name.text = 'Microsoft Entra ID';
          _issuer.text = entraIssuer(_tenant.text);
          _policy = 'trust_provider_email';
          _verifiedClaim.text = 'xms_edov';
          _tokenUse = 'access_token';
        case IdpPreset.google:
          _name.text = 'Google';
          _issuer.text = 'https://accounts.google.com';
          _tokenUse = 'id_token';
          _policy = 'require_verified_claim';
          _verifiedClaim.text = 'email_verified';
        case IdpPreset.generic:
          _tokenUse = 'id_token';
          _policy = 'require_verified_claim';
          _verifiedClaim.text = 'email_verified';
      }
    });
  }

  /// Adds the typed domain as a chip (lower case, without a leading `@`).
  void _addDomain() {
    final l = context.l10n;
    final d = _domainInput.text.trim().toLowerCase().replaceFirst('@', '');
    if (d.isEmpty) return;
    setState(() {
      if (!looksLikeDomain(d)) {
        _errors['domains'] = l.idpErrDomain(d);
        return;
      }
      _errors.remove('domains');
      if (!_domains.contains(d)) _domains.add(d);
      _domainInput.clear();
    });
  }

  /// Checks the form on the client; true when it can be sent.
  bool _validate() {
    final l = context.l10n;
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = l.idpErrName;
    if (!isHttpsUrl(_issuer.text)) e['issuer'] = l.idpErrIssuer;
    if (_audience.text.trim().isEmpty) e['audience'] = l.idpErrAudience;
    final pending = _domainInput.text.trim().toLowerCase().replaceFirst('@', '');
    if (pending.isNotEmpty && !looksLikeDomain(pending)) {
      e['domains'] = l.idpErrDomain(pending);
    }
    if (_algs.isEmpty) e['algs'] = l.idpErrAlgorithms;
    setState(() {
      _errors
        ..clear()
        ..addAll(e);
    });
    return e.isEmpty;
  }

  /// The domains, including a typed one that was not confirmed with Enter yet.
  List<String> get _allDomains {
    final pending = _domainInput.text.trim().toLowerCase().replaceFirst('@', '');
    return [
      ..._domains,
      if (pending.isNotEmpty && !_domains.contains(pending)) pending,
    ];
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  IdentityProviderInput _input({bool? confirm}) => IdentityProviderInput(
    name: _name.text.trim(),
    issuer: _issuer.text.trim(),
    audience: _audience.text.trim(),
    clientId: _nullIfEmpty(_clientId.text),
    scopes: _nullIfEmpty(_scopes.text),
    tokenUse: _tokenUse,
    emailClaim: _nullIfEmpty(_emailClaim.text),
    emailPolicy: _policy,
    verifiedClaim: _nullIfEmpty(_verifiedClaim.text),
    allowedEmailDomains: _allDomains,
    algorithms: [
      for (final a in idpAlgorithms)
        if (_algs.contains(a)) a,
    ],
    enabled: _enabled,
    confirmLockout: confirm,
  );

  Future<void> _save() async {
    final l = context.l10n;
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final admin = ref.read(apiProvider).admin;
    final p = _p;
    final ok = await runWithLockoutGuard(
      context,
      (confirm) async {
        final body = _input(confirm: confirm ? true : null);
        if (p == null) {
          await admin.createProvider(body: body);
        } else {
          await admin.updateProvider(id: p.id!, body: body);
        }
      },
      success: l.idpSaved,
      onError: (e) => setState(
        () => _saveError = isForbidden(e)
            ? l.idpReadOnlyNotice
            : l.idpSaveRefused(errorMessage(e)),
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() {
      _testing = true;
      _report = null;
      _testError = null;
    });
    try {
      final token = _sample.text.trim();
      final r = await ref
          .read(apiProvider)
          .admin
          .testProvider(
            body: IdentityProviderTest(
              config: _input(),
              sampleToken: token.isEmpty ? null : token,
            ),
          );
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _testError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _line(bool? ok, String text, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok == null
              ? Icons.info_outline
              : ok
              ? Icons.check_circle_outline
              : Icons.cancel_outlined,
          size: 18,
          color: ok == false ? Theme.of(context).colorScheme.error : null,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );

  String _okText(AppLocalizations l, String label, bool? ok) =>
      '$label: ${ok == true ? l.idpTestOk : l.idpTestNotOk}';

  /// The readable report of a test: nothing here has been bound or stored.
  Widget _reportView(AppLocalizations l, IdentityProviderTestResult r) {
    final t = r.token;
    final b = t?.binding;
    return Card(
      key: const ValueKey('idp-report'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(r.discoveryReachable, l.idpTestDiscovery),
            if (r.discoveryReachable) _line(r.issuerMatch, l.idpTestIssuerMatch),
            if (r.error != null) _line(false, l.idpTestFailed(r.error!)),
            if (r.keyCount > 0)
              _line(
                true,
                l.idpTestKeys(r.keyCount, r.keyAlgorithms.join(', ')),
              ),
            if (r.claimsSupported != null)
              _line(null, l.idpTestClaims(r.claimsSupported!.join(', '))),
            if (t != null) ...[
              const Divider(),
              Text(
                l.idpTestToken,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _line(t.signatureOk, _okText(l, l.idpTestSignature, t.signatureOk)),
              if (t.audienceOk != null)
                _line(t.audienceOk, _okText(l, l.idpTestAudience, t.audienceOk)),
              if (t.expiryOk != null)
                _line(t.expiryOk, _okText(l, l.idpTestExpiry, t.expiryOk)),
              if (t.reason != null && !t.valid) _line(false, t.reason!),
              if (t.email != null)
                _line(null, l.idpTestEmail(t.email!))
              else if (t.valid)
                _line(false, l.idpTestNoEmail),
              if (t.emailVerified != null)
                _line(
                  t.emailVerified,
                  t.emailVerified! ? l.idpTestVerified : l.idpTestNotVerified,
                ),
              if (b != null)
                _line(
                  b.outcome != 'refused',
                  switch (b.outcome) {
                    'would_bind' => l.idpBindWould(b.userEmail ?? ''),
                    'existing_subject' => l.idpBindExisting(b.userEmail ?? ''),
                    _ => l.idpBindRefused(b.reason ?? ''),
                  },
                  key: const ValueKey('idp-binding'),
                ),
            ],
            const SizedBox(height: 6),
            Text(
              l.idpTestNothing,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rule(String value, String title, String body) => RadioListTile<String>(
    key: ValueKey('idp-rule-$value'),
    value: value,
    title: Text(title),
    subtitle: Text(body),
    isThreeLine: true,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final entra = _preset == IdpPreset.entra;
    return AlertDialog(
      title: Text(_p == null ? l.idpAddTitle : l.idpEditTitle),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_p == null) ...[
                Text(l.idpPreset, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (p, label) in [
                      (IdpPreset.entra, l.idpPresetEntra),
                      (IdpPreset.google, l.idpPresetGoogle),
                      (IdpPreset.generic, l.idpPresetGeneric),
                    ])
                      ChoiceChip(
                        key: ValueKey('idp-preset-${p.name}'),
                        label: Text(label),
                        selected: _preset == p,
                        onSelected: (_) => _applyPreset(p),
                      ),
                  ],
                ),
              ],
              TextField(
                key: const ValueKey('idp-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l.idpFieldName,
                  errorText: _errors['name'],
                ),
              ),
              if (entra)
                TextField(
                  key: const ValueKey('idp-tenant'),
                  controller: _tenant,
                  decoration: InputDecoration(labelText: l.idpTenantId),
                  onChanged: (v) =>
                      setState(() => _issuer.text = entraIssuer(v)),
                ),
              TextField(
                key: const ValueKey('idp-issuer'),
                controller: _issuer,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l.idpFieldIssuer,
                  errorText: _errors['issuer'],
                ),
              ),
              TextField(
                key: const ValueKey('idp-audience'),
                controller: _audience,
                decoration: InputDecoration(
                  labelText: l.idpFieldAudience,
                  helperText: entra ? l.idpAudienceEntraHint : null,
                  helperMaxLines: 2,
                  errorText: _errors['audience'],
                ),
              ),
              TextField(
                key: const ValueKey('idp-client-id'),
                controller: _clientId,
                decoration: InputDecoration(labelText: l.idpFieldClientId),
              ),
              TextField(
                key: const ValueKey('idp-scopes'),
                controller: _scopes,
                decoration: InputDecoration(labelText: l.idpFieldScopes),
              ),
              const SizedBox(height: 12),
              Text(l.idpFieldTokenUse, style: theme.textTheme.titleSmall),
              RadioGroup<String>(
                groupValue: _tokenUse,
                onChanged: (v) => setState(() => _tokenUse = v ?? _tokenUse),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      key: const ValueKey('idp-token-use-id_token'),
                      value: 'id_token',
                      title: Text(l.idpTokenUseIdTitle),
                      subtitle: Text(l.idpTokenUseIdBody),
                      isThreeLine: true,
                    ),
                    RadioListTile<String>(
                      key: const ValueKey('idp-token-use-access_token'),
                      value: 'access_token',
                      title: Text(l.idpTokenUseAccessTitle),
                      subtitle: Text(l.idpTokenUseAccessBody),
                      isThreeLine: true,
                    ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey('idp-email-claim'),
                controller: _emailClaim,
                decoration: InputDecoration(labelText: l.idpFieldEmailClaim),
              ),
              const SizedBox(height: 12),
              Text(l.idpEmailRuleTitle, style: theme.textTheme.titleSmall),
              if (entra) Text(l.idpEntraAdvice, style: theme.textTheme.bodySmall),
              RadioGroup<String>(
                groupValue: _policy,
                onChanged: (v) => setState(() => _policy = v ?? _policy),
                child: Column(
                  children: [
                    _rule(
                      'require_verified_claim',
                      l.idpRuleVerifiedTitle,
                      l.idpRuleVerifiedBody,
                    ),
                    _rule(
                      'trust_provider_email',
                      l.idpRuleTrustTitle,
                      l.idpRuleTrustBody,
                    ),
                    _rule(
                      'subject_only',
                      l.idpRuleSubjectTitle,
                      l.idpRuleSubjectBody,
                    ),
                  ],
                ),
              ),
              if (_policy == 'require_verified_claim')
                TextField(
                  key: const ValueKey('idp-verified-claim'),
                  controller: _verifiedClaim,
                  decoration: InputDecoration(
                    labelText: l.idpFieldVerifiedClaim,
                  ),
                ),
              if (_policy != 'subject_only') ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final d in _domains)
                      InputChip(
                        key: ValueKey('idp-domain-$d'),
                        label: Text(d),
                        onDeleted: () => setState(() => _domains.remove(d)),
                      ),
                  ],
                ),
                TextField(
                  key: const ValueKey('idp-domain-input'),
                  controller: _domainInput,
                  onSubmitted: (_) => _addDomain(),
                  decoration: InputDecoration(
                    labelText: l.idpFieldDomains,
                    helperText: l.idpDomainsHint,
                    helperMaxLines: 2,
                    errorText: _errors['domains'],
                  ),
                ),
              ],
              SwitchListTile(
                key: const ValueKey('idp-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.idpEnabled),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              ExpansionTile(
                key: const ValueKey('idp-advanced'),
                tilePadding: EdgeInsets.zero,
                title: Text(l.idpAdvanced),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.idpAlgorithms,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final a in idpAlgorithms)
                        FilterChip(
                          key: ValueKey('idp-alg-$a'),
                          label: Text(a),
                          selected: _algs.contains(a),
                          onSelected: (on) => setState(
                            () => on ? _algs.add(a) : _algs.remove(a),
                          ),
                        ),
                    ],
                  ),
                  if (_errors['algs'] != null)
                    Text(
                      _errors['algs']!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('idp-sample-token'),
                controller: _sample,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l.idpTestSampleToken,
                  helperText: l.idpTestSampleHint,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              if (_testing) const LinearProgressIndicator(),
              if (_testError != null)
                Text(
                  _testError!,
                  key: const ValueKey('idp-test-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (_report != null) _reportView(l, _report!),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _saveError!,
                    key: const ValueKey('idp-save-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        OutlinedButton(
          key: const ValueKey('idp-test'),
          onPressed: _busy || _testing ? null : _test,
          child: Text(l.idpTest),
        ),
        FilledButton(
          key: const ValueKey('idp-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
