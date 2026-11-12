import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/attachments.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../customers/customer_form.dart';
import '../kb/kb_entry_screen.dart' show KbArticlePicker;
import '../kb/kb_suggestions.dart';
import '../repairs/repairs_page.dart' show showNewRepairDialog;
import 'call_dialogs.dart';
import 'ticket_collab.dart';
import 'ticket_extras.dart';
import 'ticket_split.dart';
import 'tickets_page.dart';
import '../../shared/app_icons.dart';
import '../tutorial/targets.dart';

final teamsProvider = FutureProvider.autoDispose<List<Team>>(
  (ref) => ref.watch(apiProvider).helpdesk.listTeams(),
);

final usersProvider = FutureProvider<List<CompanyUser>>(
  (ref) => ref.watch(apiProvider).core.listUsers(),
);

/// One ticket: the conversation, a composer for replies and internal notes (with prepared answers
/// in the ticket's language), the ticket's properties and links, and the actions on it.
class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({
    super.key,
    required this.id,
    this.pickFiles,
    this.presenceInterval = const Duration(seconds: 20),
  });
  final String id;

  /// How often "I am here" is sent while the screen is open.
  final Duration presenceInterval;
  final AttachmentPicker? pickFiles;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  TicketDetail? _d;
  String? _error;
  bool _busy = false;

  // Properties.
  final _subject = TextEditingController();
  final _contactName = TextEditingController();
  final _contactEmail = TextEditingController();
  String _status = 'open';
  String _priority = 'normal';
  String _category = 'question';
  String _language = 'nl';
  String? _ownerId;
  String? _teamId;
  String? _customerId;
  String? _contactId;
  String? _customerName;
  String? _quotationId;
  String? _opportunityId;
  List<QuotationSummary> _quotations = [];
  List<Opportunity> _opportunities = [];
  List<Contact> _contacts = [];
  List<Repair> _repairs = [];

  // Composer.
  /// The composer mode the user chose; replying also needs the helpdesk.reply permission.
  bool _replyChosen = true;
  bool get _reply =>
      _replyChosen &&
      (ref.read(meProvider).value?.permissions.contains('helpdesk.reply') ??
          false);
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _replySubject = TextEditingController();
  final _body = TextEditingController();
  String? _statusAfter;
  String? _answerInfo;
  List<FileInfo> _attached = [];

  /// How files are chosen; replaceable in tests.
  AttachmentPicker get _picker => widget.pickFiles ?? pickAttachmentFiles;

  TradocraftApi get _api => ref.read(apiProvider);

  // Presence: colleagues active on this ticket (advisory, polling).
  Timer? _beatTimer;
  List<PresenceEntry> _others = [];
  String _beatMode = 'viewing';
  bool _readMarked = false;

  @override
  void initState() {
    super.initState();
    _load();
    _body.addListener(_bodyChanged);
  }

  /// Whether the beat is running; null until the first [didChangeDependencies].
  bool? _beating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The presence beat tells colleagues that someone is looking at the ticket: it runs only
    // while this screen is visible, not in a background workspace tab.
    final visible = TabScope.activeOf(context);
    if (visible == _beating) return;
    _beating = visible;
    _beatTimer?.cancel();
    _beatTimer = null;
    if (visible) {
      _beat();
      _beatTimer = Timer.periodic(widget.presenceInterval, (_) => _beat());
    }
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _body.removeListener(_bodyChanged);
    super.dispose();
  }

  String get _presenceMode =>
      _replyChosen && _body.text.trim().isNotEmpty ? 'replying' : 'viewing';

  /// Typing in the reply box tells the others at once instead of at the next beat.
  void _bodyChanged() {
    if (_presenceMode != _beatMode) _beat();
  }

  Future<void> _beat() async {
    final mode = _presenceMode;
    _beatMode = mode;
    try {
      final others = await _api.helpdesk.presenceBeat(
        id: widget.id,
        body: PresenceInput(mode: mode),
      );
      if (mounted) setState(() => _others = others);
    } catch (_) {
      // Presence is only a hint; a failed beat is not worth an error message.
    }
  }

  Future<void> _load() async {
    try {
      final d = await _api.helpdesk.getTicket(id: widget.id);
      _apply(d);
      if (!_readMarked) {
        _readMarked = true;
        unawaited(
          _api.helpdesk.markRead(id: widget.id).then((_) {}, onError: (_) {}),
        );
      }
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  /// Shows a loaded ticket in the form; ignored once the screen is gone.
  void _apply(TicketDetail d) {
    if (!mounted) return;
    final t = d.ticket;
    TabScope.reportTitle(context, t.number);
    setState(() {
      _d = d;
      _error = null;
      _subject.text = t.subject;
      _contactName.text = t.contactName;
      _contactEmail.text = t.contactEmail;
      _status = t.status;
      _priority = t.priority;
      _category = t.category;
      _language = t.language;
      _ownerId = t.ownerUserId;
      _teamId = t.teamId;
      _customerId = t.customerId;
      _contactId = t.contactId;
      _customerName = t.customerName;
      _quotationId = t.quotationId;
      _opportunityId = t.opportunityId;
      if (_to.text.isEmpty) _to.text = t.contactEmail;
    });
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final c = _customerId;
    if (c == null) {
      setState(() {
        _quotations = [];
        _opportunities = [];
        _contacts = [];
        _repairs = [];
      });
      return;
    }
    final quotes = await _api.sales
        .listQuotations(customerId: c, limit: 100)
        .then((p) => p.items, onError: (Object _) => <QuotationSummary>[]);
    final opps = await _api.crm
        .listOpportunities(customerId: c, limit: 100)
        .then((p) => p.items, onError: (Object _) => <Opportunity>[]);
    final people = await _api.crm
        .listCustomerContacts(id: c)
        .then((p) => p, onError: (Object _) => <Contact>[]);
    final repairs = await _api.repairs
        .listTicketRepairs(id: widget.id)
        .then((p) => p, onError: (Object _) => <Repair>[]);
    if (mounted) {
      setState(() {
        _repairs = repairs;
        _quotations = quotes;
        _opportunities = opps;
        _contacts = people;
      });
    }
  }

  Future<void> _run(
    Future<TicketDetail> Function() action, {
    String? success,
  }) async {
    setState(() => _busy = true);
    TicketDetail? d;
    final ok = await runAction(
      context,
      () async => d = await action(),
      success: success,
    );
    if (mounted) setState(() => _busy = false);
    if (ok && d != null) _apply(d!);
  }

  Future<void> _saveProperties() => _run(
    () => _api.helpdesk.updateTicket(
      id: widget.id,
      body: TicketInput(
        subject: _subject.text.trim(),
        status: _status,
        priority: _priority,
        category: _category,
        language: _language,
        ownerUserId: _ownerId,
        customerId: _customerId,
        contactId: _contactId,
        contactName: _contactName.text.trim(),
        contactEmail: _contactEmail.text.trim(),
        quotationId: _quotationId,
        opportunityId: _opportunityId,
      ),
    ),
    success: context.l10n.saved,
  );

  Future<void> _send() async {
    final l = context.l10n;
    if (_body.text.trim().isEmpty) return;
    if (_reply) {
      // Nothing is locked, but sending over a colleague's answer needs a second thought.
      final now = await _api.helpdesk
          .presenceList(id: widget.id)
          .then((p) => p, onError: (Object _) => <PresenceEntry>[]);
      final replying = now.where((o) => o.mode == 'replying').toList();
      if (replying.isNotEmpty) {
        if (!mounted) return;
        if (!await confirmSendWhileOthersReply(context, replying)) return;
      }
    }
    if (!mounted) return;
    List<String> split(String s) =>
        s.split(RegExp(r'[,;\s]+')).where((e) => e.isNotEmpty).toList();
    await _run(
      () => _reply
          ? _api.helpdesk.reply(
              id: widget.id,
              body: ReplyInput(
                to: split(_to.text),
                cc: split(_cc.text),
                subject: _replySubject.text.trim().isEmpty
                    ? null
                    : _replySubject.text.trim(),
                body: _body.text,
                attachmentIds: [for (final f in _attached) f.id],
                status: _statusAfter,
              ),
            )
          : _api.helpdesk.addNote(
              id: widget.id,
              body: NoteInput(
                body: _body.text,
                attachmentIds: [for (final f in _attached) f.id],
                status: _statusAfter,
              ),
            ),
      success: _reply ? l.replyQueued : l.noteAdded,
    );
    if (_d != null) {
      setState(() {
        _body.clear();
        _replySubject.clear();
        _statusAfter = null;
        _answerInfo = null;
        _attached = [];
      });
    }
  }

  void _appendToReply(String text) => setState(() {
    _body.text = _body.text.trim().isEmpty
        ? text
        : '${_body.text.trimRight()}\n\n$text';
  });

  Future<void> _insertArticle() async {
    final picked = await showDialog<EntrySummary>(
      context: context,
      builder: (_) =>
          KbArticlePicker(publishedOnly: true, language: _d?.ticket.language),
    );
    if (picked == null || !mounted) return;
    try {
      final r = await _api.kb.renderKbEntry(id: widget.id, entryId: picked.id);
      _appendToReply(kbInsertionText(r));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _insertAnswer() async {
    final answer = await showDialog<PreparedAnswer>(
      context: context,
      builder: (_) => const _AnswerPicker(),
    );
    if (answer == null || !mounted) return;
    final l = context.l10n;
    try {
      final r = await _api.helpdesk.renderAnswer(
        id: widget.id,
        answerId: answer.id,
      );
      setState(() {
        if (r.subject.isNotEmpty) _replySubject.text = r.subject;
        _body.text = _body.text.trim().isEmpty
            ? r.body
            : '${_body.text.trimRight()}\n\n${r.body}';
        _answerInfo = r.fallback
            ? l.answerFallback(
                languageName(_language),
                languageName(r.language),
              )
            : null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  /// Moves the ticket to a team (and keeps or changes its owner).
  Future<void> _assign(String? teamId) => _run(
    () => _api.helpdesk.assign(
      id: widget.id,
      body: AssignmentInput(teamId: teamId, ownerUserId: _ownerId),
    ),
    success: context.l10n.saved,
  );

  Future<void> _escalate() async {
    final t = _d!.ticket;
    final r = await showEscalateDialog(context, ticketId: t.id);
    if (r == null || !mounted) return;
    _apply(r);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.collabEscalated)));
  }

  Future<void> _delegate() async {
    final t = _d!.ticket;
    final r = await showDelegateDialog(
      context,
      ticketId: t.id,
      currentOwnerId: t.ownerUserId,
    );
    if (r == null || !mounted) return;
    _apply(r);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.collabHandedOver)));
  }

  Future<void> _merge() async {
    final l = context.l10n;
    final target = await showMergeDialog(context, ticket: _d!.ticket);
    if (target == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.ticketMerged)));
    // The ticket is closed and its content now lives in the target.
    _apply(target);
    if (GoRouter.maybeOf(context) != null) {
      context.pushReplacement('/helpdesk/${target.ticket.id}');
    }
  }

  Future<void> _split() async {
    final l = context.l10n;
    final d = await showSplitDialog(
      context,
      ticket: _d!.ticket,
      articles: _d!.articles,
    );
    if (d == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.ticketSplit(d.ticket.number))));
    await _load();
    if (mounted && GoRouter.maybeOf(context) != null) {
      context.push('/helpdesk/${d.ticket.id}');
    }
  }

  Future<void> _createLead() async {
    final l = context.l10n;
    final value = await askText(
      context,
      title: l.createLead,
      label: l.expectedValueOptional,
    );
    if (value == null) return;
    await _run(
      () => _api.helpdesk.createLead(
        id: widget.id,
        body: LeadInput(expectedValue: parseDecimalInput(value)),
      ),
      success: l.leadCreated,
    );
  }

  Future<void> _convert() async {
    final l = context.l10n;
    final reference = await askText(
      context,
      title: l.convertToOrder,
      label: l.customerReference,
    );
    if (reference == null) return;
    await _run(
      () => _api.helpdesk.convert(
        id: widget.id,
        body: ConvertTicketInput(customerReference: reference),
      ),
      success: l.orderCreated,
    );
  }

  /// Links the ticket to a person of the customer: name, address and language follow.
  void _selectContact(Contact? c) {
    setState(() {
      _contactId = c?.id;
      if (c != null) {
        _contactName.text = c.fullName;
        _contactEmail.text = c.emails.isEmpty ? '' : c.emails.first.email;
        _language = c.effectiveLanguage;
      }
    });
  }

  Future<void> _logCall() async {
    final t = _d!.ticket;
    Contact? who;
    for (final c in _contacts) {
      if (c.id == _contactId) who = c;
    }
    final d = await showCallDialog(context, ticketId: t.id, contact: who);
    if (d != null && mounted) {
      _apply(d);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.callLogged)));
    }
  }

  Future<void> _newCustomer() async {
    final t = _d!.ticket;
    final c = await showNewCustomerForm(
      context,
      name: t.contactName,
      email: t.contactEmail,
      language: t.language,
    );
    if (c != null) {
      setState(() {
        _customerId = c.id;
        _customerName = c.name;
      });
      await _saveProperties();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = _d;
    if (d == null) {
      return Scaffold(
        body: Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final conversation = _conversation(context, d, perms);
    final panel = _panel(context, d, perms);
    return Scaffold(
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: conversation),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: panel,
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ExpansionTile(title: Text(l.ticketDetails), children: [panel]),
                SizedBox(height: 900, child: conversation),
              ],
            ),
    );
  }

  Widget _conversation(
    BuildContext context,
    TicketDetail d,
    List<String> perms,
  ) {
    final l = context.l10n;
    final t = d.ticket;
    final theme = Theme.of(context);
    final canReply = perms.contains('helpdesk.reply');
    final canWrite = perms.contains('helpdesk.write');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.canPop()
                    ? context.pop(true)
                    : context.go('/helpdesk'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Expanded(
                child: Text(
                  '${t.number}  ${t.subject}',
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canWrite && !t.internal)
                TextButton.icon(
                  onPressed: _logCall,
                  icon: const Icon(AppIcons.phoneInTalk),
                  label: Text(l.logCall),
                ),
              if (t.sla.state != 'none') ...[
                Flexible(child: SlaBadge(sla: t.sla)),
                const SizedBox(width: 8),
              ],
              if (t.escalatedAt != null) ...[
                Tooltip(
                  message: l.collabEscalatedBy(t.escalatedByName ?? ''),
                  child: Chip(
                    key: const ValueKey('escalated-badge'),
                    avatar: Icon(
                      AppIcons.trendingUp,
                      size: 16,
                      color: Colors.red.shade700,
                    ),
                    label: Text(l.collabEscalatedBadge),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Chip(label: Text(l.ticketStatus(t.status))),
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(AppIcons.translate, size: 16),
                label: Text(languageName(t.language)),
              ),
            ],
          ),
        ),
        if (t.internal || t.category == 'production_question')
          MaterialBanner(
            leading: const Icon(AppIcons.precisionManufacturing),
            content: Text(l.internalQuestionHelp(languageName(t.language))),
            actions: const [SizedBox.shrink()],
          ),
        if (t.mergedIntoId != null)
          MaterialBanner(
            leading: const Icon(AppIcons.mergeType),
            content: Text(l.mergedInto(t.mergedIntoNumber ?? '')),
            actions: [
              TextButton(
                onPressed: () =>
                    context.pushReplacement('/helpdesk/${t.mergedIntoId}'),
                child: Text(t.mergedIntoNumber ?? ''),
              ),
            ],
          ),
        PresenceBanner(others: _others),
        if (d.readers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SeenByLine(readers: d.readers),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final a in d.articles)
                _ArticleCard(
                  article: a,
                  dio: ref.read(dioProvider),
                  ticketId: t.id,
                ),
            ],
          ),
        ),
        if (canWrite) _composer(context, canReply),
      ],
    );
  }

  Widget _composer(BuildContext context, bool canReply) {
    final l = context.l10n;
    final canKb =
        ref.watch(meProvider).value?.permissions.contains('kb.read') ?? false;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      enabled: canReply,
                      icon: const Icon(AppIcons.mail),
                      label: Text(l.replyToCustomer),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(AppIcons.lock),
                      label: Text(l.internalNote),
                    ),
                  ],
                  selected: {_reply},
                  onSelectionChanged: (s) =>
                      setState(() => _replyChosen = s.first),
                ),
                if (_reply)
                  OutlinedButton.icon(
                    onPressed: _insertAnswer,
                    icon: const Icon(AppIcons.textSnippet),
                    label: Text(l.insertPreparedAnswer),
                  ),
                if (_reply && canKb)
                  OutlinedButton.icon(
                    key: const ValueKey('insert-article'),
                    onPressed: _insertArticle,
                    icon: const Icon(AppIcons.menuBook),
                    label: Text(l.kbInsertArticle),
                  ),
                if (_reply)
                  Text(
                    l.writeIn(languageName(_d!.ticket.language)),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (_reply && canKb)
              KbSuggestionsPanel(ticketId: widget.id, onInsert: _appendToReply),
            if (_answerInfo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _answerInfo!,
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
              ),
            const SizedBox(height: 8),
            if (_reply)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _to,
                      decoration: InputDecoration(labelText: l.to),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cc,
                      decoration: InputDecoration(labelText: l.cc),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _replySubject,
                      decoration: InputDecoration(
                        labelText: l.subject,
                        hintText: 'Re: ${_d!.ticket.subject}',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: _reply ? l.message : l.internalNote,
                filled: !_reply,
                fillColor: Colors.amber.shade50,
              ),
            ),
            const SizedBox(height: 8),
            AttachmentComposer(
              key: ValueKey('attachments-$_reply'),
              dio: ref.read(dioProvider),
              uploadPath: '/api/v1/tickets/${widget.id}/attachments',
              files: _attached,
              pick: _picker,
              onChanged: (f) => setState(() => _attached = f),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    key: ValueKey('after-$_reply-$_statusAfter'),
                    initialValue: _statusAfter,
                    decoration: InputDecoration(labelText: l.statusAfterwards),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          _reply
                              ? l.ticketStatus('pending_customer')
                              : l.unchanged,
                        ),
                      ),
                      for (final s in ticketStatuses)
                        DropdownMenuItem<String?>(
                          value: s,
                          child: Text(l.ticketStatus(s)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _statusAfter = v),
                  ),
                ),
                const Spacer(),
                TutorialTarget(id: 'ticket-send', child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: Icon(_reply ? AppIcons.send : AppIcons.noteAdd),
                  label: Text(_reply ? l.send : l.addNote),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, TicketDetail d, List<String> perms) {
    final l = context.l10n;
    final t = d.ticket;
    final theme = Theme.of(context);
    final canWrite = perms.contains('helpdesk.write');
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.ticketDetails, style: theme.textTheme.titleMedium),
        gap,
        TextField(
          controller: _subject,
          decoration: InputDecoration(labelText: l.subject),
        ),
        gap,
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _status,
                decoration: InputDecoration(labelText: l.status),
                items: [
                  for (final s in ticketStatuses)
                    DropdownMenuItem(value: s, child: Text(l.ticketStatus(s))),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _priority,
                decoration: InputDecoration(labelText: l.priority),
                items: [
                  for (final p in ticketPriorities)
                    DropdownMenuItem(
                      value: p,
                      child: Text(l.ticketPriority(p)),
                    ),
                ],
                onChanged: (v) => setState(() => _priority = v!),
              ),
            ),
          ],
        ),
        gap,
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _category,
          decoration: InputDecoration(
            labelText: l.category,
            helperText:
                t.suggestedCategory != null && t.suggestedCategory != _category
                ? l.suggested(l.ticketCategory(t.suggestedCategory!))
                : null,
          ),
          items: [
            for (final c in ticketCategories)
              DropdownMenuItem(value: c, child: Text(l.ticketCategory(c))),
          ],
          onChanged: (v) => setState(() => _category = v!),
        ),
        gap,
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _language,
                decoration: InputDecoration(labelText: l.customerLanguage),
                items: [
                  for (final c in languageCodes)
                    DropdownMenuItem(value: c, child: Text(languageName(c))),
                ],
                onChanged: (v) => setState(() => _language = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                key: ValueKey('owner-${users.length}-$_ownerId'),
                initialValue: users.any((u) => u.id == _ownerId)
                    ? _ownerId
                    : null,
                decoration: InputDecoration(labelText: l.owner),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l.unassigned),
                  ),
                  for (final u in users)
                    DropdownMenuItem<String?>(
                      value: u.id,
                      child: Text(u.displayName),
                    ),
                ],
                onChanged: (v) => setState(() => _ownerId = v),
              ),
            ),
          ],
        ),
        gap,
        DropdownButtonFormField<String?>(
          isExpanded: true,
          key: ValueKey('team-${teams.length}-$_teamId'),
          initialValue: teams.any((x) => x.id == _teamId) ? _teamId : null,
          decoration: InputDecoration(labelText: l.team),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l.noTeam)),
            for (final x in teams)
              DropdownMenuItem<String?>(value: x.id, child: Text(x.name)),
          ],
          onChanged: canWrite && !_busy ? _assign : null,
        ),
        const Divider(height: 32),
        WatchersSection(
          ticketId: t.id,
          watchers: d.watchers,
          canWrite: canWrite,
          onChanged: (w) => setState(
            () => _d = TicketDetail(
              ticket: d.ticket,
              articles: d.articles,
              watchers: w,
              readers: d.readers,
            ),
          ),
        ),
        const Divider(height: 32),
        if (t.sla.state != 'none') ...[
          SlaSection(sla: t.sla),
          const Divider(height: 32),
        ],
        TagsSection(
          ticketId: t.id,
          tags: t.tags,
          canWrite: canWrite,
          onChanged: _apply,
        ),
        const Divider(height: 32),
        TimeSection(ticketId: t.id, canWrite: canWrite),
        const Divider(height: 32),
        ActivitySection(
          ticketId: t.id,
          version: '${t.updatedAt}-${d.articles.length}-${d.watchers.length}',
        ),
        const Divider(height: 32),
        CsatSection(ticket: t),
        const Divider(height: 32),
        Text(l.customer, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SearchPicker<Customer>(
          key: ValueKey('cust-$_customerId'),
          label: l.customer,
          initial: null,
          display: (c) => '${c.code} · ${c.name}',
          search: (q) async =>
              (await _api.crm.listCustomers(q: q, limit: 20)).items,
          onSelected: (c) {
            setState(() {
              // The person belongs to the previous customer.
              if (c.id != _customerId) _contactId = null;
              _customerId = c.id;
              _customerName = c.name;
              _quotationId = null;
              _opportunityId = null;
            });
            _loadLinks();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _customerName ?? l.noCustomerLinked,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (_customerId == null && canWrite)
                TutorialTarget(id: 'ticket-new-customer', child: TextButton.icon(
                  onPressed: _newCustomer,
                  icon: const Icon(AppIcons.personAddAlt),
                  label: Text(l.newCustomer),
                )),
            ],
          ),
        ),
        if (_customerId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String?>(
              isExpanded: true,
              key: ValueKey('contact-${_contacts.length}-$_contactId'),
              initialValue: _contacts.any((c) => c.id == _contactId)
                  ? _contactId
                  : null,
              decoration: InputDecoration(labelText: l.contactPerson),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.noContactLinked),
                ),
                for (final c in _contacts)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(
                      [
                        c.fullName,
                        if (c.jobTitle.isNotEmpty) c.jobTitle,
                        languageName(c.effectiveLanguage),
                      ].join(' · '),
                    ),
                  ),
              ],
              onChanged: (id) => _selectContact(
                id == null ? null : _contacts.firstWhere((c) => c.id == id),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _contactName,
                decoration: InputDecoration(labelText: l.contactName),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _contactEmail,
                decoration: InputDecoration(labelText: l.email),
              ),
            ),
          ],
        ),
        gap,
        DropdownButtonFormField<String?>(
          isExpanded: true,
          key: ValueKey('q-${_quotations.length}-$_quotationId'),
          initialValue: _quotations.any((q) => q.id == _quotationId)
              ? _quotationId
              : null,
          decoration: InputDecoration(labelText: l.quotation),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l.none)),
            for (final q in _quotations)
              DropdownMenuItem<String?>(
                value: q.id,
                child: Text(
                  '${q.number} rev. ${q.revision} · ${l.quotationStatus(q.status.json ?? '')} · ${money(q.subtotal)}',
                ),
              ),
          ],
          onChanged: (v) => setState(() => _quotationId = v),
        ),
        gap,
        DropdownButtonFormField<String?>(
          isExpanded: true,
          key: ValueKey('o-${_opportunities.length}-$_opportunityId'),
          initialValue: _opportunities.any((o) => o.id == _opportunityId)
              ? _opportunityId
              : null,
          decoration: InputDecoration(labelText: l.opportunity),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l.none)),
            for (final o in _opportunities)
              DropdownMenuItem<String?>(
                value: o.id,
                child: Text(
                  '${o.number} · ${o.title} · ${l.opportunityStage(o.stage.json ?? '')}',
                ),
              ),
          ],
          onChanged: (v) => setState(() => _opportunityId = v),
        ),
        gap,
        if (canWrite)
          FilledButton.tonal(
            onPressed: _busy ? null : _saveProperties,
            child: Text(l.saveChanges),
          ),
        const Divider(height: 32),
        Text(l.actions, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // A customer who says a product is coming (or arrived) gets a repair, linked here.
            if (perms.contains('repairs.write') &&
                t.customerId != null &&
                !t.internal)
              OutlinedButton.icon(
                icon: const Icon(AppIcons.buildCircle),
                label: Text(l.createRepair),
                onPressed: _busy
                    ? null
                    : () async {
                        final d = await showNewRepairDialog(
                          context,
                          ticketId: t.id,
                          customer: Customer.fromJson({
                            'id': t.customerId,
                            'code': '',
                            'name': t.customerName ?? '',
                            'street': '',
                            'postal_code': '',
                            'city': '',
                            'country_code': 'BE',
                            'language': t.language,
                            'active': true,
                          }),
                          contactId: t.contactId,
                          fault: t.subject,
                        );
                        if (d != null && context.mounted) {
                          await _load();
                          if (context.mounted) {
                            context.push('/repairs/${d.repair.id}');
                          }
                        }
                      },
              ),
            if (canWrite && t.status != 'closed') ...[
              OutlinedButton.icon(
                key: const ValueKey('escalate-ticket'),
                icon: const Icon(AppIcons.trendingUp),
                label: Text(l.collabEscalate),
                onPressed: _busy ? null : _escalate,
              ),
              OutlinedButton.icon(
                key: const ValueKey('delegate-ticket'),
                icon: const Icon(AppIcons.swapHoriz),
                label: Text(l.collabDelegate),
                onPressed: _busy ? null : _delegate,
              ),
            ],
            if (canWrite &&
                t.customerId != null &&
                t.mergedIntoId == null &&
                t.status != 'closed')
              OutlinedButton.icon(
                key: const ValueKey('merge-ticket'),
                icon: const Icon(AppIcons.mergeType),
                label: Text(l.mergeTicket),
                onPressed: _busy ? null : _merge,
              ),
            if (canWrite && t.mergedIntoId == null && _d!.articles.length > 1)
              OutlinedButton.icon(
                key: const ValueKey('split-ticket'),
                icon: const Icon(AppIcons.callSplit),
                label: Text(l.splitTicket),
                onPressed: _busy ? null : _split,
              ),
            for (final r in _repairs)
              ActionChip(
                avatar: const Icon(AppIcons.buildCircle, size: 18),
                label: Text('${r.number} · ${l.repairStatus(r.status)}'),
                onPressed: () => context.push('/repairs/${r.id}'),
              ),
            if (t.opportunityId != null)
              OutlinedButton.icon(
                icon: const Icon(AppIcons.trendingUp),
                label: Text(t.opportunityNumber ?? l.opportunity),
                onPressed: () =>
                    context.push('/opportunities/${t.opportunityId}'),
              )
            else if (canWrite && perms.contains('opportunities.write'))
              OutlinedButton.icon(
                icon: const Icon(AppIcons.trendingUp),
                label: Text(l.createLead),
                onPressed: t.customerId == null ? null : _createLead,
              ),
            if (t.quotationId != null)
              OutlinedButton.icon(
                icon: const Icon(AppIcons.requestQuote),
                label: Text('${t.quotationNumber} rev. ${t.quotationRevision}'),
                onPressed: () async {
                  await context.push('/quotations/${t.quotationId}');
                  _load();
                },
              ),
            if (t.customerId != null && perms.contains('quotations.write'))
              TutorialTarget(id: 'ticket-new-quotation', child: OutlinedButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.newQuotation),
                onPressed: () async {
                  final opp = t.opportunityId == null
                      ? ''
                      : '&opportunity=${t.opportunityId}';
                  await context.push(
                    '/quotations/new?customer=${t.customerId}$opp',
                  );
                  _loadLinks();
                },
              )),
            if (t.orderId != null)
              OutlinedButton.icon(
                icon: const Icon(AppIcons.inventory),
                label: Text(t.orderNumber ?? l.order),
                onPressed: () => context.push('/orders/${t.orderId}'),
              )
            else if (t.quotationId != null && perms.contains('orders.write'))
              FilledButton.icon(
                icon: const Icon(AppIcons.checkCircle),
                label: Text(l.convertToOrder),
                onPressed: _busy ? null : _convert,
              ),
          ],
        ),
        if (t.quotationId != null && t.orderId == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.convertHelp, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.article,
    required this.dio,
    required this.ticketId,
  });
  final Article article;
  final Dio dio;
  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final a = article;
    final theme = Theme.of(context);
    final when = DateFormat('dd/MM/yyyy HH:mm').format(a.createdAt.toLocal());
    final (
      Color color,
      IconData icon,
      String label,
      Alignment align,
    ) = switch (a.kind) {
      'email_in' => (
        theme.colorScheme.surfaceContainerHighest,
        AppIcons.callReceived,
        a.fromName.isEmpty ? a.fromAddress : '${a.fromName} <${a.fromAddress}>',
        Alignment.centerLeft,
      ),
      'email_out' => (
        theme.colorScheme.primaryContainer,
        AppIcons.callMade,
        '${a.authorName ?? a.fromName} → ${a.toAddresses.join(', ')}',
        Alignment.centerRight,
      ),
      'call_in' || 'call_out' => (
        a.kind == 'call_in'
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        a.kind == 'call_in' ? AppIcons.phoneCallback : AppIcons.phoneForwarded,
        [
          a.kind == 'call_in' ? l.callIncoming : l.callOutgoing,
          if (a.contactName != null) a.contactName!,
          if (a.authorName != null) a.authorName!,
        ].join(' · '),
        a.kind == 'call_in' ? Alignment.centerLeft : Alignment.centerRight,
      ),
      'portal_in' => (
        theme.colorScheme.surfaceContainerHighest,
        AppIcons.language,
        '${a.contactName ?? a.fromName} · ${l.viaPortal}',
        Alignment.centerLeft,
      ),
      _ => (
        Colors.amber.shade100,
        AppIcons.lock,
        '${l.internalNote} · ${a.authorName ?? ''}',
        Alignment.center,
      ),
    };
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Card(
          color: color,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (a.delivery != null) ...[
                      Icon(
                        switch (a.delivery) {
                          'sent' => AppIcons.doneAll,
                          'failed' => AppIcons.error,
                          _ => AppIcons.schedule,
                        },
                        size: 16,
                        color: a.delivery == 'failed'
                            ? theme.colorScheme.error
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Text(switch (a.delivery) {
                        'sent' => l.deliverySent,
                        'failed' => l.deliveryFailed,
                        _ => l.deliveryQueued,
                      }, style: theme.textTheme.bodySmall),
                      const SizedBox(width: 8),
                    ],
                    Text(when, style: theme.textTheme.bodySmall),
                  ],
                ),
                if (a.subject.isNotEmpty && a.kind != 'note')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(a.subject, style: theme.textTheme.titleSmall),
                  ),
                if (a.phoneNumber != null || a.durationSeconds != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (a.phoneNumber != null) a.phoneNumber!,
                        if (a.durationSeconds != null)
                          l.minutesShort(
                            (a.durationSeconds! / 60).ceil().toString(),
                          ),
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 6),
                SelectableText(a.body),
                AttachmentChips(
                  files: a.attachments,
                  dio: dio,
                  pathFor: (id) => '/api/v1/tickets/$ticketId/attachments/$id',
                ),
                if (a.deliveryError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      a.deliveryError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable list of prepared answers; returns the chosen one.
class _AnswerPicker extends ConsumerStatefulWidget {
  const _AnswerPicker();

  @override
  ConsumerState<_AnswerPicker> createState() => _AnswerPickerState();
}

class _AnswerPickerState extends ConsumerState<_AnswerPicker> {
  String _q = '';
  late Future<List<PreparedAnswer>> _answers = ref
      .read(apiProvider)
      .helpdesk
      .listAnswers(active: true);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.preparedAnswers),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(AppIcons.search),
                hintText: l.search,
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<PreparedAnswer>>(
                future: _answers,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(
                          () => _answers = ref
                              .read(apiProvider)
                              .helpdesk
                              .listAnswers(active: true),
                        ),
                        child: Text(errorMessage(snap.error!)),
                      ),
                    );
                  }
                  final list = (snap.data ?? const <PreparedAnswer>[])
                      .where(
                        (a) =>
                            _q.isEmpty ||
                            '${a.code} ${a.name} ${a.category ?? ''}'
                                .toLowerCase()
                                .contains(_q),
                      )
                      .toList();
                  return ListView(
                    children: [
                      for (final a in list)
                        ListTile(
                          title: Text(a.name),
                          subtitle: Text(
                            [
                              a.code,
                              if (a.category != null) a.category!,
                            ].join(' · '),
                          ),
                          trailing: Text(
                            a.texts
                                .map((t) => t.language.toUpperCase())
                                .join(' '),
                          ),
                          onTap: () => Navigator.pop(context, a),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
