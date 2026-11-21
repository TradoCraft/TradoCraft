import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../app/session.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/attachments.dart';
import '../../shared/format.dart';
import '../../shared/live_record_watcher.dart';
import '../../shared/search_picker.dart';
import '../customers/customer_form.dart';
import '../kb/kb_entry_screen.dart' show KbArticlePicker;
import '../kb/kb_suggestions.dart';
import '../repairs/repairs_page.dart' show showNewRepairDialog;
import 'call_dialogs.dart';
import 'library_pdf_picker.dart';
import 'ticket_collab.dart';
import 'ticket_merge.dart';
import 'ticket_extras.dart';
import 'ticket_links.dart';
import 'ticket_split.dart';
import 'tickets_page.dart';
import '../../shared/app_icons.dart';
import '../../shared/load_failed.dart';
import '../todo/object_todos_button.dart';
import '../tutorial/api_events.dart';
import '../tutorial/controller.dart';
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
  bool _missing = false;
  bool _busy = false;

  int _checklistRefresh = 0;

  /// Raised on every live refresh, so the panels that load themselves (activity, time, checklist)
  /// load again when a colleague changed something they show.
  int _liveTick = 0;

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
  final _libraryPdfs = <LibraryPdfSelection>[];

  /// How files are chosen; replaceable in tests.
  AttachmentPicker get _picker => widget.pickFiles ?? pickAttachmentFiles;

  TradocraftApi get _api => ref.read(apiProvider);

  // Presence: colleagues active on this ticket (advisory, polling).
  Timer? _beatTimer;
  List<PresenceEntry> _others = [];
  String _beatMode = 'viewing';
  bool _readMarked = false;
  RecordLiveWatcher? _watcher;
  String? _conflictMessage;
  bool _isConflict = false;
  bool _conflictRetry = false;
  bool _retryingConflict = false;

  // Live changes by colleagues (A8). A refresh that is running swallows the events that arrive
  // meanwhile into one more refresh. [_pendingTheirs] is the server's ticket when it differs
  // from the user's unsaved edits in a way that needs a decision.
  Future<void>? _liveRefreshTask;
  bool _liveRefreshQueued = false;
  bool _liveRefreshNotifyFailure = false;
  String _queuedKind = 'updated';
  String _queuedWho = '';
  int _mutationGen = 0;
  int _linksSeq = 0;
  StreamSubscription<ApiEvent>? _tutorialMail;
  TicketDetail? _pendingTheirs;
  String _pendingActor = '';
  String _pendingKind = 'updated';

  @override
  void initState() {
    super.initState();
    _load();
    _body.addListener(_bodyChanged);
    ref.listenManual(tutorialAssistCompletedProvider, (_, completed) {
      if (completed?.missionId == 'customer' &&
          completed?.stepId == 'linked' &&
          ref.read(tutorialProvider).values['ticketId'] == widget.id) {
        unawaited(_refreshFromServer('updated', ''));
      }
    });
    // Tutorial mail is imported by this client. It does not arrive through the
    // external record watcher, so refresh the open ticket after the import.
    _tutorialMail = ref.read(apiEventBusProvider).stream.listen((event) {
      if (!mounted ||
          event.method != 'POST' ||
          event.path != '/helpdesk/inbound' ||
          event.status < 200 ||
          event.status >= 300 ||
          (event.scope != null &&
              event.scope != tutorialSessionId(ref.read(sessionProvider)))) {
        return;
      }
      final result = event.json;
      if (result is Map &&
          result['ticket_id'] == widget.id &&
          result['new_ticket'] == false &&
          result['duplicate'] != true) {
        unawaited(_refreshFromServer('note', _d?.ticket.contactName ?? ''));
      }
    });
    _watcher = watchRecordChanges(
      ref,
      entityType: 'ticket',
      recordId: widget.id,
      currentVersion: () => _d?.ticket.version,
      onExternalChange: (ev) {
        if (!mounted) return;
        if (ev.kind == 'presence') {
          unawaited(_loadPresence());
        } else {
          unawaited(_refreshFromServer(ev.kind, ev.changedByName));
        }
      },
    );
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
    unawaited(_tutorialMail?.cancel());
    _watcher?.dispose();
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

  /// A colleague arrived or started or stopped replying: show it now, not at the next beat.
  Future<void> _loadPresence() async {
    try {
      final others = await _api.helpdesk.presenceList(id: widget.id);
      if (mounted) setState(() => _others = others);
    } catch (_) {
      // Presence is only a hint.
    }
  }

  /// The editable properties as the form shows them now.
  TicketValues get _formValues => {
    TicketField.subject: _subject.text.trim(),
    TicketField.status: _status,
    TicketField.priority: _priority,
    TicketField.category: _category,
    TicketField.language: _language,
    TicketField.owner: _ownerId,
    TicketField.customer: _customerId,
    TicketField.contactId: _contactId,
    TicketField.contactName: _contactName.text.trim(),
    TicketField.contactEmail: _contactEmail.text.trim(),
    TicketField.quotation: _quotationId,
    TicketField.opportunity: _opportunityId,
  };

  void _setField(TicketField f, String? v) {
    switch (f) {
      case TicketField.subject:
        _subject.text = v ?? '';
      case TicketField.status:
        _status = v ?? _status;
      case TicketField.priority:
        _priority = v ?? _priority;
      case TicketField.category:
        _category = v ?? _category;
      case TicketField.language:
        _language = v ?? _language;
      case TicketField.owner:
        _ownerId = v;
      case TicketField.customer:
        _customerId = v;
      case TicketField.contactId:
        _contactId = v;
      case TicketField.contactName:
        _contactName.text = v ?? '';
      case TicketField.contactEmail:
        _contactEmail.text = v ?? '';
      case TicketField.quotation:
        _quotationId = v;
      case TicketField.opportunity:
        _opportunityId = v;
    }
  }

  /// Fetches the ticket as it is on the server and lays it over the open form: the conversation
  /// is always brought up to date; the properties are replaced when the user has not edited
  /// them, merged when the user and the colleague changed different fields, and put to the user
  /// (Compare) when both changed the same field. A save that was refused with a 409 comes here
  /// too. Background SSE failures are ignored (next event or Reload catches up); failures after
  /// a 409 show a retryable conflict notice while keeping unsaved edits.
  Future<void> _refreshFromServer(
    String kind,
    String who, {
    bool notifyOnFailure = false,
  }) async {
    if (notifyOnFailure) _liveRefreshNotifyFailure = true;
    if (_liveRefreshTask != null) {
      _liveRefreshQueued = true;
      _queuedKind = kind;
      _queuedWho = who;
      if (notifyOnFailure) await _liveRefreshTask;
      return;
    }
    Future<void> run() async {
      var curKind = kind;
      var curWho = who;
      var reportFailure = false;
      try {
        do {
          _liveRefreshQueued = false;
          reportFailure = reportFailure || _liveRefreshNotifyFailure;
          _liveRefreshNotifyFailure = false;
          final gen = _mutationGen;
          final fresh = await _api.helpdesk.getTicket(id: widget.id);
          if (!mounted) return;
          if (gen != _mutationGen && _d != null) {
            final freshV = fresh.ticket.version;
            final currentV = _d!.ticket.version;
            if (freshV == null || currentV == null || freshV <= currentV) {
              reportFailure = false;
              if (_liveRefreshQueued) {
                curKind = _queuedKind;
                curWho = _queuedWho;
              }
              continue;
            }
          }
          _absorb(fresh, curKind, curWho);
          reportFailure = false;
          if (_liveRefreshQueued) {
            curKind = _queuedKind;
            curWho = _queuedWho;
          }
        } while (_liveRefreshQueued && mounted);
      } catch (_) {
        if (mounted && (reportFailure || _liveRefreshNotifyFailure)) {
          _liveRefreshNotifyFailure = false;
          setState(() {
            _conflictRetry = true;
            _conflictMessage = context.l10n.recordConflictMessage;
            _isConflict = true;
          });
        }
      } finally {
        _liveRefreshNotifyFailure = false;
        _liveRefreshTask = null;
      }
    }

    _liveRefreshTask = run();
    await _liveRefreshTask;
  }

  Future<void> _retryConflict() async {
    if (_retryingConflict) return;
    setState(() => _retryingConflict = true);
    try {
      await _refreshFromServer('updated', '', notifyOnFailure: true);
    } finally {
      if (mounted) setState(() => _retryingConflict = false);
    }
  }

  void _absorb(TicketDetail fresh, String kind, String who) {
    final l = context.l10n;
    final shown = _d;
    if (shown != null) {
      final shownV = shown.ticket.version;
      final pendingV = _pendingTheirs?.ticket.version;
      final minVersion = shownV == null
          ? pendingV
          : (pendingV != null && pendingV > shownV ? pendingV : shownV);
      final freshV = fresh.ticket.version;
      if (freshV != null && minVersion != null && freshV < minVersion) return;
    }
    _liveTick++;
    final name = who.isEmpty ? l.ticketMergeSomeone : who;
    if (shown == null) {
      _apply(fresh);
      return;
    }
    final base = ticketValues(shown.ticket);
    final mine = _formValues;
    final merge = mergeTicketFields(
      base: base,
      mine: mine,
      theirs: ticketValues(fresh.ticket),
    );
    if (changedFields(base, mine).isEmpty) {
      _pendingTheirs = null;
      _apply(fresh);
      setState(() {
        _conflictMessage = l.ticketLiveChange(_liveKey(kind), name);
        _isConflict = false;
      });
    } else if (merge.conflicts.isEmpty) {
      _pendingTheirs = null;
      _applyMerged(fresh, merge.resolved);
      setState(() {
        _conflictMessage = merge.takenFromTheirs.isEmpty
            ? l.ticketLiveChange(_liveKey(kind), name)
            : l.ticketLiveMerged(name);
        _isConflict = false;
      });
    } else {
      // The conversation moves on, but the ticket itself stays at the version the form was
      // built from: saving still goes through the version check until the user has decided.
      setState(() {
        _d = TicketDetail(
          ticket: shown.ticket,
          articles: fresh.articles,
          watchers: fresh.watchers,
          readers: fresh.readers,
        );
        _pendingTheirs = fresh;
        _pendingActor = name;
        _pendingKind = kind;
        _conflictRetry = false;
        _conflictMessage = l.ticketLiveUnsaved(name);
        _isConflict = true;
      });
    }
  }

  /// Message selector for [AppLocalizations.ticketLiveChange]; `time` is a reserved ICU word.
  String _liveKey(String kind) => kind == 'time' ? 'timeEntry' : kind;

  String? _customerNameFor(
    String? id,
    List<Ticket?> candidates,
    String? prevId,
    String? prevName,
  ) {
    if (id == null) return null;
    if (id == prevId && prevName != null) return prevName;
    for (final t in candidates) {
      if (t != null && t.customerId == id && t.customerName != null) {
        return t.customerName;
      }
    }
    return _customerName;
  }

  /// Shows [fresh] in the form with [resolved] on top of it, so the user's edits that survive
  /// the merge stay unsaved edits, now on top of the current version.
  void _applyMerged(TicketDetail fresh, TicketValues resolved) {
    final myCustomerId = _customerId, myCustomerName = _customerName;
    _apply(fresh, loadLinks: false);
    setState(() {
      resolved.forEach(_setField);
      if (_customerId == myCustomerId) _customerName = myCustomerName;
    });
    _loadLinks();
  }

  /// Opens the side-by-side comparison for the fields both people changed.
  Future<void> _compare() async {
    final fresh = _pendingTheirs, shown = _d;
    if (fresh == null || shown == null) return;
    final mine = _formValues;
    final theirs = ticketValues(fresh.ticket);
    final merge = mergeTicketFields(
      base: ticketValues(shown.ticket),
      mine: mine,
      theirs: theirs,
    );
    TicketValues? choice;
    if (merge.conflicts.isNotEmpty) {
      choice = await showTicketMergeDialog(
        context,
        theirName: _pendingActor,
        merge: merge,
        mine: mine,
        theirs: theirs,
        valueLabel: _valueLabel,
      );
      if (choice == null || !mounted) return;
      merge.resolved.addAll(choice);
    }
    final current = _d;
    final latestPending = _pendingTheirs;
    final unchanged =
        identical(current, shown) &&
        identical(latestPending, fresh) &&
        changedFields(mine, _formValues).isEmpty;
    if (unchanged) {
      _pendingTheirs = null;
      _applyMerged(fresh, merge.resolved);
      return;
    }
    if (latestPending != null) {
      _reconcileDialogChoices(
        shown: shown,
        fresh: fresh,
        resolved: merge.resolved,
        choice: choice,
        latest: latestPending,
      );
      return;
    }
    if (choice != null &&
        current != null &&
        _conflictMessage != null &&
        changedFields(ticketValues(current.ticket), _formValues).isNotEmpty) {
      final prevCustomerId = _customerId;
      setState(() => choice!.forEach(_setField));
      if (_customerId != prevCustomerId) _loadLinks();
    }
  }

  void _reconcileDialogChoices({
    required TicketDetail shown,
    required TicketDetail fresh,
    required TicketValues resolved,
    required TicketValues? choice,
    required TicketDetail latest,
  }) {
    final current = _d;
    final currentV = current?.ticket.version;
    final freshV = fresh.ticket.version;
    final currentIsNewer =
        currentV != null && freshV != null && currentV > freshV;
    final baseTicket = currentIsNewer ? current!.ticket : fresh.ticket;
    final mine = currentIsNewer ? {..._formValues, ...?choice} : resolved;
    final reconciled = mergeTicketFields(
      base: ticketValues(baseTicket),
      mine: mine,
      theirs: ticketValues(latest.ticket),
    );
    final l = context.l10n;
    final actor = _pendingActor.isEmpty ? l.ticketMergeSomeone : _pendingActor;
    final kind = _pendingKind;
    final msg = _conflictMessage;
    final prevCustomerId = _customerId;
    final prevCustomerName = _customerName;
    final resolvedCustomerName = _customerNameFor(
      reconciled.resolved[TicketField.customer],
      [baseTicket, fresh.ticket, latest.ticket],
      prevCustomerId,
      prevCustomerName,
    );
    if (reconciled.conflicts.isEmpty) {
      _pendingTheirs = null;
      _applyMerged(latest, reconciled.resolved);
      setState(() {
        if (_customerId == reconciled.resolved[TicketField.customer]) {
          _customerName = resolvedCustomerName;
        }
        if (!identical(latest, fresh)) {
          _conflictMessage = reconciled.takenFromTheirs.isEmpty
              ? l.ticketLiveChange(_liveKey(kind), actor)
              : l.ticketLiveMerged(actor);
          _isConflict = false;
        }
      });
      return;
    }
    setState(() {
      _d = TicketDetail(
        ticket: baseTicket,
        articles: latest.articles,
        watchers: latest.watchers,
        readers: latest.readers,
      );
      reconciled.resolved.forEach(_setField);
      _customerName = resolvedCustomerName;
      _pendingTheirs = latest;
      _pendingActor = actor;
      _pendingKind = kind;
      _conflictRetry = false;
      _conflictMessage = msg ?? l.ticketLiveUnsaved(actor);
      _isConflict = true;
    });
    if (_customerId != prevCustomerId) _loadLinks();
  }

  /// A readable form of a field value for the comparison (ids become names).
  String _valueLabel(TicketField f, String? v) {
    if (v == null || v.isEmpty) return '';
    final l = context.l10n;
    String named(
      String? Function(Ticket t) id,
      String? Function(Ticket t) name,
    ) {
      for (final t in [_d?.ticket, _pendingTheirs?.ticket]) {
        if (t != null && id(t) == v && name(t) != null) return name(t)!;
      }
      return v;
    }

    return switch (f) {
      TicketField.status => l.ticketStatus(v),
      TicketField.priority => l.ticketPriority(v),
      TicketField.category => l.ticketCategory(v),
      TicketField.language => languageName(v),
      TicketField.owner =>
        ref
                .read(usersProvider)
                .value
                ?.where((u) => u.id == v)
                .map((u) => u.displayName)
                .firstOrNull ??
            named((t) => t.ownerUserId, (t) => t.ownerName),
      TicketField.customer => named((t) => t.customerId, (t) => t.customerName),
      TicketField.contactId =>
        _contacts
                .where((c) => c.id == v)
                .map((c) => c.fullName)
                .firstOrNull ??
            named(
              (t) => t.contactId,
              (t) => t.contactName.isEmpty ? null : t.contactName,
            ),
      TicketField.quotation =>
        _quotations.where((q) => q.id == v).map((q) => q.number).firstOrNull ??
            named((t) => t.quotationId, (t) => t.quotationNumber),
      TicketField.opportunity =>
        _opportunities
                .where((o) => o.id == v)
                .map((o) => o.number)
                .firstOrNull ??
            named((t) => t.opportunityId, (t) => t.opportunityNumber),
      _ => v,
    };
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
    if (_busy) return;
    setState(() => _busy = true);
    final loadGen = _mutationGen;
    try {
      final d = await _api.helpdesk.getTicket(id: widget.id);
      if (!mounted) return;
      final currentV = _d?.ticket.version;
      final loadedV = d.ticket.version;
      if (_d != null &&
          loadGen == _mutationGen &&
          loadedV != null &&
          currentV != null &&
          loadedV < currentV) {
        return;
      }
      _mutationGen++;
      _apply(d);
      if (!_readMarked) {
        _readMarked = true;
        unawaited(
          _api.helpdesk.markRead(id: widget.id).then((_) {}, onError: (_) {}),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _missing = errorStatus(e) == 404;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows a loaded ticket in the form; ignored once the screen is gone.
  void _apply(TicketDetail d, {bool loadLinks = true}) {
    if (!mounted) return;
    final t = d.ticket;
    TabScope.reportTitle(context, t.number);
    setState(() {
      _d = d;
      _error = null;
      _conflictMessage = null;
      _isConflict = false;
      _conflictRetry = false;
      _pendingTheirs = null;
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
    if (loadLinks) _loadLinks();
  }

  Future<void> _loadLinks() async {
    final c = _customerId;
    final seq = ++_linksSeq;
    if (c == null) {
      if (mounted) {
        setState(() {
          _quotations = [];
          _opportunities = [];
          _contacts = [];
          _repairs = [];
        });
      }
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
    if (!mounted || _customerId != c || seq != _linksSeq) return;
    setState(() {
      _repairs = repairs;
      _quotations = quotes;
      _opportunities = opps;
      _contacts = people;
    });
  }

  Future<bool> _run(
    Future<TicketDetail> Function() action, {
    String? success,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    TicketDetail? d;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    var ok = false;
    try {
      d = await action();
      ok = true;
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      final isChecklistBlocked =
          errorCode(e) == 'checklist_incomplete' ||
          (errorStatus(e) == 409 &&
              e is DioException &&
              e.response?.data is Map &&
              (e.response?.data as Map)['error'] == 'checklist_incomplete');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isChecklistBlocked
                ? l.ticketCloseBlockedChecklist
                : errorMessage(e),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _checklistRefresh++;
      });
    }
    if (ok && d != null) {
      _mutationGen++;
      _apply(d);
    }
    return ok;
  }

  Future<void> _saveProperties() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final d = await _api.helpdesk.updateTicket(
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
          expectedVersion: _d?.ticket.version,
        ),
      );
      if (!mounted) return;
      _mutationGen++;
      _apply(d);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.saved)));
    } catch (e) {
      if (!mounted) return;
      if (isRecordChangedError(e)) {
        // Someone saved first: bring in their version and merge it with this form.
        await _refreshFromServer('updated', '', notifyOnFailure: true);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    final sent = await _run(
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
                libraryPdfs: _libraryPdfs.isEmpty
                    ? null
                    : [for (final item in _libraryPdfs) item.variant],
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
    if (sent && mounted && _d != null) {
      setState(() {
        _body.clear();
        _replySubject.clear();
        _statusAfter = null;
        _answerInfo = null;
        _attached = [];
        _libraryPdfs.clear();
      });
    }
  }

  Future<void> _pickLibraryPdf() async {
    final selection = await showDialog<LibraryPdfSelection>(
      context: context,
      builder: (_) => LibraryPdfPicker(language: _language),
    );
    if (!mounted || selection == null) return;
    final duplicate = _libraryPdfs.any((item) =>
        item.documentId == selection.documentId &&
        item.pdf.revision == selection.pdf.revision &&
        item.pdf.language == selection.pdf.language);
    if (!duplicate) setState(() => _libraryPdfs.add(selection));
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
    final answer = await showDialog<SuggestedAnswer>(
      context: context,
      builder: (_) => _AnswerPicker(
        ticketId: widget.id,
        kind: _reply ? 'reply' : 'internal_note',
      ),
    );
    if (answer == null || !mounted) return;
    final l = context.l10n;
    setState(() {
      if (answer.subject.isNotEmpty) _replySubject.text = answer.subject;
      _body.text = _body.text.trim().isEmpty
          ? answer.body
          : '${_body.text.trimRight()}\n\n${answer.body}';
      _answerInfo = answer.fallback
          ? l.answerFallback(
              languageName(_language),
              languageName(answer.language),
            )
          : null;
    });
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final t = _d!.ticket;
      final r = await showEscalateDialog(context, ticketId: t.id);
      if (r == null || !mounted) return;
      _mutationGen++;
      _apply(r);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.collabEscalated)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delegate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final t = _d!.ticket;
      final r = await showDelegateDialog(
        context,
        ticketId: t.id,
        currentOwnerId: t.ownerUserId,
      );
      if (r == null || !mounted) return;
      _mutationGen++;
      _apply(r);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.collabHandedOver)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final l = context.l10n;
      final target = await showMergeDialog(context, ticket: _d!.ticket);
      if (target == null || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.ticketMerged)));
      // The ticket is closed and its content now lives in the target.
      _mutationGen++;
      _apply(target);
      if (GoRouter.maybeOf(context) != null) {
        context.pushReplacement('/helpdesk/${target.ticket.id}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final t = _d!.ticket;
      Contact? who;
      for (final c in _contacts) {
        if (c.id == _contactId) who = c;
      }
      final d = await showCallDialog(context, ticketId: t.id, contact: who);
      if (d != null && mounted) {
        _mutationGen++;
        _apply(d);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.callLogged)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (c == null || !mounted) return;
    await _liveRefreshTask;
    if (!mounted) return;
    setState(() {
      _customerId = c.id;
      _customerName = c.name;
    });
    await _saveProperties();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = _d;
    if (d == null) {
      return Scaffold(
        body: _error != null
            ? LoadFailedView(
                message: _error!,
                leaveTo: '/helpdesk',
                notFound: _missing,
                todoKind: TodoLinkKind.ticket,
                todoId: widget.id,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final conversation = _conversation(
      context,
      d,
      perms,
    ).lockRecordEditing(_busy);
    final panel = _panel(context, d, perms).lockRecordEditing(_busy);
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
        if (_conflictMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: RecordConflictBanner(
              message: _conflictMessage!,
              isConflict: _isConflict,
              onReload: _pendingTheirs != null
                  ? _compare
                  : _conflictRetry
                  ? (_retryingConflict ? null : _retryConflict)
                  : (_busy ? null : _load),
              actionLabel: _pendingTheirs != null
                  ? l.ticketMergeCompare
                  : _conflictRetry
                  ? l.retry
                  : null,
              actionIcon: _pendingTheirs != null ? AppIcons.mergeType : null,
              onDismiss: _pendingTheirs != null || _conflictRetry
                  ? null
                  : () => setState(() => _conflictMessage = null),
            ),
          ),
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
              ObjectTodosButton(
                kind: TodoLinkKind.ticket,
                id: t.id,
                label: t.number,
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
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.amber.withValues(alpha: 0.14)
                    : Colors.amber.shade50,
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
            if (_reply && canReply && canKb) ...[
              TextButton(
                onPressed: _busy ? null : _pickLibraryPdf,
                child: Text(l.attachFromDocuments),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in _libraryPdfs)
                    InputChip(
                      label: Text('${item.pdf.filename} · ${l.documentRevision(item.pdf.revision)}'),
                      onDeleted: _busy ? null : () => setState(() => _libraryPdfs.remove(item)),
                    ),
                ],
              ),
            ],
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
                TutorialTarget(
                  id: 'ticket-send',
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: Icon(_reply ? AppIcons.send : AppIcons.noteAdd),
                    label: Text(_reply ? l.send : l.addNote),
                  ),
                ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _language,
                    decoration: InputDecoration(labelText: l.customerLanguage),
                    items: [
                      for (final c in languageCodes)
                        DropdownMenuItem(
                          value: c,
                          child: Text(languageName(c)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _language = v!),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.ticketLanguageSource(t.languageSource),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
          onAction: (action) => _run(action),
        ),
        const Divider(height: 32),
        TimeSection(
          ticketId: t.id,
          canWrite: canWrite,
          refreshVersion: _liveTick,
        ),
        const Divider(height: 32),
        TicketLinksCard(
          ticketId: t.id,
          number: t.number,
          canWrite: canWrite,
          canReply: perms.contains('helpdesk.reply'),
          refreshVersion: _liveTick,
        ),
        const Divider(height: 32),
        TicketChecklistCard(
          ticketId: t.id,
          refreshVersion: _checklistRefresh + _liveTick,
          teamId: t.teamId,
          category: t.category,
          canWrite: canWrite,
        ),
        const Divider(height: 32),
        ActivitySection(
          ticketId: t.id,
          version:
              '${t.updatedAt}-${d.articles.length}-${d.watchers.length}-$_liveTick',
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
                TutorialTarget(
                  id: 'ticket-new-customer',
                  child: TextButton.icon(
                    onPressed: _newCustomer,
                    icon: const Icon(AppIcons.personAddAlt),
                    label: Text(l.newCustomer),
                  ),
                ),
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
          TutorialTarget(
            id: 'ticket-save-properties',
            child: FilledButton.tonal(
              onPressed: _busy ? null : _saveProperties,
              child: Text(l.saveChanges),
            ),
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
              TutorialTarget(
                id: 'ticket-new-quotation',
                child: OutlinedButton.icon(
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
                ),
              ),
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
        theme.brightness == Brightness.dark
            ? const Color(0xFF3E2F14)
            : Colors.amber.shade100,
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

/// Ranked prepared answers for this ticket; returns the chosen one. Typing `/code` or a word narrows it.
class _AnswerPicker extends ConsumerStatefulWidget {
  const _AnswerPicker({required this.ticketId, required this.kind});
  final String ticketId;
  final String kind;

  @override
  ConsumerState<_AnswerPicker> createState() => _AnswerPickerState();
}

class _AnswerPickerState extends ConsumerState<_AnswerPicker> {
  String _q = '';
  late Future<List<SuggestedAnswer>> _answers = _load();

  Future<List<SuggestedAnswer>> _load() => ref
      .read(apiProvider)
      .helpdesk
      .suggest(
        id: widget.ticketId,
        q: _q.startsWith('/') ? _q.substring(1) : _q,
        kind: widget.kind,
      );

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
                helperText: l.answerShortcutHint,
              ),
              onChanged: (v) => setState(() {
                _q = v.trim();
                _answers = _load();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<SuggestedAnswer>>(
                future: _answers,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _answers = _load()),
                        child: Text(errorMessage(snap.error!)),
                      ),
                    );
                  }
                  final list = snap.data ?? const <SuggestedAnswer>[];
                  return ListView(
                    children: [
                      for (final a in list)
                        ListTile(
                          key: ValueKey('suggest-${a.code}'),
                          title: Text(a.name),
                          subtitle: Text(a.code),
                          trailing: Text(a.language.toUpperCase()),
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

/// Sorts active checklist templates so templates matching [teamId] or [category] appear first.
List<ChecklistTemplate> sortChecklistTemplates(
  List<ChecklistTemplate> templates, {
  String? teamId,
  String? category,
}) {
  int score(ChecklistTemplate t) =>
      (teamId != null && t.teamId == teamId ? 1 : 0) +
      (category != null && t.category == category ? 1 : 0);

  final sorted = [...templates]
    ..sort((a, b) {
      final diff = score(b).compareTo(score(a));
      if (diff != 0) return diff;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return sorted;
}

/// Checklist section on a ticket: apply template, toggle/edit/reorder/delete items, and add items.
class TicketChecklistCard extends ConsumerStatefulWidget {
  const TicketChecklistCard({
    super.key,
    required this.ticketId,
    required this.category,
    this.teamId,
    this.canWrite = true,
    this.refreshVersion = 0,
  });

  final String ticketId;
  final String? teamId;
  final String category;
  final bool canWrite;
  final int refreshVersion;

  @override
  ConsumerState<TicketChecklistCard> createState() =>
      _TicketChecklistCardState();
}

class _TicketChecklistCardState extends ConsumerState<TicketChecklistCard> {
  final _addController = TextEditingController();
  List<ChecklistItem> _items = const [];
  List<ChecklistTemplate> _templates = const [];
  bool _loading = true;
  bool _busy = false;
  bool _refreshPending = false;
  Object? _loadError;
  int _generation = 0;

  bool _owns(int generation) => mounted && generation == _generation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TicketChecklistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) {
      _items = const [];
      _templates = const [];
      _addController.clear();
      _busy = false;
      _refreshPending = false;
      _load();
    } else if (oldWidget.refreshVersion != widget.refreshVersion) {
      if (_busy) {
        _refreshPending = true;
      } else {
        _load();
      }
    }
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final ticketId = widget.ticketId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = ref.read(apiProvider);
    try {
      final results = await Future.wait([
        api.helpdesk.listTicketChecklist(id: ticketId),
        api.helpdesk.listTemplates(active: true),
      ]);
      if (!_owns(generation)) return;
      setState(() {
        _items = [...results[0] as List<ChecklistItem>]
          ..sort((a, b) => a.position.compareTo(b.position));
        _templates = results[1] as List<ChecklistTemplate>;
        _loading = false;
      });
    } catch (e) {
      if (!_owns(generation)) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _mutate(Future<void> Function(String, int) action) async {
    if (_busy || _loading || _loadError != null || !widget.canWrite) return;
    final ticketId = widget.ticketId;
    final generation = _generation;
    setState(() => _busy = true);
    await runAction(context, () async {
      try {
        await action(ticketId, generation);
      } catch (_) {
        if (_owns(generation)) rethrow;
      }
    });
    if (!_owns(generation)) return;
    setState(() => _busy = false);
    if (_refreshPending) {
      _refreshPending = false;
      await _load();
    }
  }

  Future<void> _toggleDone(ChecklistItem item, bool done) =>
      _mutate((ticketId, generation) async {
        final updated = await ref
            .read(apiProvider)
            .helpdesk
            .updateTicketChecklistItem(
              id: ticketId,
              itemId: item.id,
              body: UpdateChecklistItemInput(done: done),
            );
        if (!_owns(generation)) return;
        setState(() {
          _items = [
            for (final existing in _items)
              existing.id == updated.id ? updated : existing,
          ];
        });
      });

  Future<void> _editItem(ChecklistItem item) async {
    final generation = _generation;
    final l = context.l10n;
    final controller = TextEditingController(text: item.description);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.edit),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l.checklistTitle),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null ||
        next.isEmpty ||
        next == item.description ||
        !_owns(generation)) {
      return;
    }
    await _mutate((ticketId, generation) async {
      final updated = await ref
          .read(apiProvider)
          .helpdesk
          .updateTicketChecklistItem(
            id: ticketId,
            itemId: item.id,
            body: UpdateChecklistItemInput(description: next),
          );
      if (!_owns(generation)) return;
      setState(() {
        _items = [
          for (final existing in _items)
            existing.id == updated.id ? updated : existing,
        ];
      });
    });
  }

  Future<void> _moveItem(int index, int delta) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _items.length) return;
    final item = _items[index];
    final targetPosition = _items[targetIndex].position;
    await _mutate((ticketId, generation) async {
      await ref
          .read(apiProvider)
          .helpdesk
          .updateTicketChecklistItem(
            id: ticketId,
            itemId: item.id,
            body: UpdateChecklistItemInput(position: targetPosition),
          );
      if (!_owns(generation)) return;
      final refreshed = await ref
          .read(apiProvider)
          .helpdesk
          .listTicketChecklist(id: ticketId);
      if (!_owns(generation)) return;
      setState(() {
        _items = [...refreshed]
          ..sort((a, b) => a.position.compareTo(b.position));
      });
    });
  }

  Future<void> _deleteItem(ChecklistItem item) =>
      _mutate((ticketId, generation) async {
        await ref
            .read(apiProvider)
            .helpdesk
            .deleteTicketChecklistItem(id: ticketId, itemId: item.id);
        if (!_owns(generation)) return;
        setState(() {
          _items = _items.where((e) => e.id != item.id).toList();
        });
      });

  Future<void> _addItem() async {
    if (_busy || _loading || _loadError != null) return;
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    await _mutate((ticketId, generation) async {
      final created = await ref
          .read(apiProvider)
          .helpdesk
          .addTicketChecklistItem(
            id: ticketId,
            body: AddChecklistItemInput(description: text),
          );
      if (!_owns(generation)) return;
      _addController.clear();
      setState(() {
        _items = [..._items, created]
          ..sort((a, b) => a.position.compareTo(b.position));
      });
    });
  }

  Future<void> _applyTemplate(String templateId) =>
      _mutate((ticketId, generation) async {
        final applied = await ref
            .read(apiProvider)
            .helpdesk
            .applyTemplate(
              id: ticketId,
              body: ApplyTemplateInput(templateId: templateId),
            );
        if (!_owns(generation)) return;
        setState(() {
          _items = [...applied]
            ..sort((a, b) => a.position.compareTo(b.position));
        });
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final total = _items.length;
    final done = _items.where((e) => e.done).length;
    final sortedTemplates = sortChecklistTemplates(
      _templates,
      teamId: widget.teamId,
      category: widget.category,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.checklist, size: 18),
                const SizedBox(width: 6),
                Text(l.checklistTitle, style: theme.textTheme.titleMedium),
                if (total > 0) ...[
                  const SizedBox(width: 8),
                  ChecklistProgressBadge(done: done, total: total),
                ],
              ],
            ),
            if (widget.canWrite)
              PopupMenuButton<String>(
                key: const ValueKey('checklist-apply-template'),
                tooltip: l.checklistApplyTemplate,
                enabled: !_busy && !_loading && _loadError == null,
                onSelected: _applyTemplate,
                itemBuilder: (_) {
                  if (sortedTemplates.isEmpty) {
                    return [
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(l.checklistNoTemplates),
                      ),
                    ];
                  }
                  return [
                    for (final tpl in sortedTemplates)
                      PopupMenuItem<String>(
                        value: tpl.id,
                        child: Text(tpl.name),
                      ),
                  ];
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.add, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        l.checklistApplyTemplate,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (_loadError != null)
          Row(
            children: [
              Expanded(child: Text(errorMessage(_loadError!))),
              TextButton(onPressed: _load, child: Text(l.retry)),
            ],
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.checklistEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          for (var i = 0; i < _items.length; i++)
            _buildItemRow(context, _items[i], i),
        if (widget.canWrite) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('checklist-add-input'),
                  controller: _addController,
                  enabled: !_busy && !_loading && _loadError == null,
                  decoration: InputDecoration(
                    hintText: l.checklistAddItem,
                    isDense: true,
                  ),
                  onSubmitted: _busy || _loading || _loadError != null
                      ? null
                      : (_) => _addItem(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('checklist-add-button'),
                icon: const Icon(AppIcons.add),
                tooltip: l.checklistAddItem,
                onPressed: _busy || _loading || _loadError != null
                    ? null
                    : _addItem,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildItemRow(BuildContext context, ChecklistItem item, int index) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final meta = [
      if (item.doneByName != null && item.doneByName!.isNotEmpty)
        item.doneByName!,
      if (item.doneAt != null) date(item.doneAt),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.done,
            visualDensity: VisualDensity.compact,
            onChanged: widget.canWrite && !_busy
                ? (v) => _toggleDone(item, v ?? false)
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    style: item.done
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.outline,
                          )
                        : null,
                  ),
                  if (item.done && meta.isNotEmpty)
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.canWrite) ...[
            IconButton(
              icon: const Icon(AppIcons.edit, size: 16),
              tooltip: l.edit,
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : () => _editItem(item),
            ),
            IconButton(
              icon: const Icon(AppIcons.arrowUpward, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: _busy || index == 0
                  ? null
                  : () => _moveItem(index, -1),
            ),
            IconButton(
              icon: const Icon(AppIcons.arrowDownward, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: _busy || index == _items.length - 1
                  ? null
                  : () => _moveItem(index, 1),
            ),
            IconButton(
              icon: const Icon(AppIcons.delete, size: 16),
              tooltip: l.delete,
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : () => _deleteItem(item),
            ),
          ],
        ],
      ),
    );
  }
}
