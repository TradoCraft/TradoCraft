/// The generic record form (ADR 0085): a header with the title, an action bar with the status
/// bar, the concurrent-edit banner (ADR 0073), and a sheet holding smart buttons, the main
/// fields and optional tabs.
library;

import 'package:material_ui/material_ui.dart';

import '../../app/workspace.dart' show TabScope;
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/live_record_watcher.dart';
import 'record_form_controller.dart';

/// One tab of the sheet. Tabs keep their state while hidden.
class FormSheetTab {
  const FormSheetTab({required this.label, required this.child, this.icon});

  final String label;
  final IconData? icon;
  final Widget child;
}

class RecordFormView<T extends Object> extends StatefulWidget {
  const RecordFormView({
    super.key,
    required this.controller,
    required this.title,
    required this.body,
    this.onBack,
    this.titleExtras = const [],
    this.actions = const [],
    this.statusBar,
    this.smartButtons = const [],
    this.tabs = const [],
    this.onReload,
    this.reportDirty = true,
    this.maxSheetWidth,
    this.scrollController,
    this.beforeSheet = const [],
    this.chatter,
    this.chatterBeside = true,
  });

  final RecordFormController<T> controller;
  final String title;

  /// The main fields. Wrapped in the controller's `Form` and locked while a save runs.
  final Widget body;

  /// Back button; none when null.
  final VoidCallback? onBack;

  /// Next to the title (a to-do button).
  final List<Widget> titleExtras;

  /// The record's buttons (save, send, PDF), left of the status bar.
  final List<Widget> actions;
  final Widget? statusBar;

  /// Shortcuts to related records, at the top right of the sheet.
  final List<Widget> smartButtons;
  final List<FormSheetTab> tabs;

  /// The banner's reload; without it the banner has no button.
  final VoidCallback? onReload;

  /// Reports unsaved edits to the enclosing workspace tab (ADR 0041).
  final bool reportDirty;

  /// Caps the sheet width (a short form); null fills the page.
  final double? maxSheetWidth;
  final ScrollController? scrollController;

  /// Shown between the banner and the sheet (a shipping notice).
  final List<Widget> beforeSheet;

  /// The record's chatter (ADR 0086): beside the sheet on wide pages, below it on narrow ones.
  final Widget? chatter;

  /// Whether a wide page puts the chatter beside the sheet; a sheet that needs its full width
  /// (a line editor) keeps it below.
  final bool chatterBeside;

  @override
  State<RecordFormView<T>> createState() => _RecordFormViewState<T>();
}

class _RecordFormViewState<T extends Object> extends State<RecordFormView<T>>
    with TickerProviderStateMixin {
  TabController? _tabs;
  bool? _reportedDirty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _syncTabs();
  }

  @override
  void didUpdateWidget(RecordFormView<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    _syncTabs();
  }

  void _syncTabs() {
    final n = widget.tabs.length;
    if (n == 0) {
      _tabs?.dispose();
      _tabs = null;
    } else if (_tabs?.length != n) {
      final keep = (_tabs?.index ?? 0).clamp(0, n - 1);
      _tabs?.dispose();
      _tabs = TabController(length: n, vsync: this, initialIndex: keep)
        ..addListener(() => setState(() {}));
    }
  }

  void _onController() {
    if (!mounted) return;
    final dirty = widget.controller.dirty;
    if (widget.reportDirty && _reportedDirty != dirty) {
      _reportedDirty = dirty;
      TabScope.reportDirty(context, dirty);
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _tabs?.dispose();
    super.dispose();
  }

  Widget _header(ThemeData theme) {
    final c = widget.controller;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.md,
      runSpacing: Space.sm,
      children: [
        if (widget.onBack != null)
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: widget.onBack,
            icon: const Icon(AppIcons.arrowBack),
          ),
        Text(widget.title, style: theme.textTheme.headlineSmall),
        ...widget.titleExtras,
        if (c.dirty)
          Tooltip(
            message: context.l10n.formUnsavedChanges,
            child: Semantics(
              label: context.l10n.formUnsavedChanges,
              child: Icon(
                AppIcons.circle,
                size: 10,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (c.busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  /// Actions on the left, the status bar on the right; stacked when narrow.
  Widget _controlBar() {
    final actions = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widget.actions,
    );
    final status = widget.statusBar;
    if (status == null) return actions;
    if (widget.actions.isEmpty) {
      return Align(alignment: Alignment.centerRight, child: status);
    }
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              actions,
              const SizedBox(height: Space.sm),
              status,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: actions),
            const SizedBox(width: Space.lg),
            status,
          ],
        );
      },
    );
  }

  Widget _sheet(ThemeData theme) {
    final c = widget.controller;
    final tabs = _tabs;
    final sheet = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: Radii.large,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.smartButtons.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: widget.smartButtons,
            ),
            const SizedBox(height: Space.lg),
          ],
          widget.body,
          if (tabs != null) ...[
            const SizedBox(height: Space.xl),
            TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final t in widget.tabs)
                  Tab(
                    text: t.label,
                    icon: t.icon == null ? null : Icon(t.icon, size: 18),
                    iconMargin: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: Space.lg),
            // Hidden tabs stay built so their fields keep what was typed.
            for (final (i, t) in widget.tabs.indexed)
              Offstage(
                offstage: i != tabs.index,
                child: TickerMode(enabled: i == tabs.index, child: t.child),
              ),
          ],
        ],
      ),
    );
    return Form(key: c.formKey, child: sheet.lockRecordEditing(c.busy));
  }

  /// The sheet, with the chatter beside it when there is room (the sheet keeps the width it
  /// needs for its fields) and below it otherwise.
  Widget _sheetWithChatter(ThemeData theme) {
    final chatter = widget.chatter;
    if (chatter == null) return _sheet(theme);
    return LayoutBuilder(
      builder: (context, box) {
        if (!widget.chatterBeside || box.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheet(theme),
              const SizedBox(height: Space.lg),
              chatter,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _sheet(theme)),
            const SizedBox(width: Space.lg),
            SizedBox(width: 380, child: chatter),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    final notice = c.notice;
    final error = c.error;
    final children = <Widget>[
      _header(theme),
      if (widget.actions.isNotEmpty || widget.statusBar != null) ...[
        const SizedBox(height: Space.md),
        _controlBar(),
      ],
      if (notice != null) ...[
        const SizedBox(height: Space.md),
        RecordConflictNotice(
          notice: notice,
          onReload: widget.onReload == null || c.busy ? null : widget.onReload,
          onDismiss: c.dismissNotice,
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: Space.md),
        Text(error, style: TextStyle(color: theme.colorScheme.error)),
      ],
      ...widget.beforeSheet,
      const SizedBox(height: Space.lg),
      _sheetWithChatter(theme),
    ];
    // With the chatter beside it, the cap covers the sheet and the panel.
    final max = widget.maxSheetWidth == null
        ? null
        : widget.maxSheetWidth! +
              (widget.chatter == null || !widget.chatterBeside
                  ? 0
                  : 380 + Space.lg);
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (max != null) {
      content = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: content,
        ),
      );
    }
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(Space.lg),
      child: content,
    );
  }
}

/// The ADR 0073 banner for a controller's [RecordNotice]; for forms that are not a
/// [RecordFormView] (a dialog).
class RecordConflictNotice extends StatelessWidget {
  const RecordConflictNotice({
    super.key,
    required this.notice,
    required this.onReload,
    required this.onDismiss,
  });

  final RecordNotice notice;
  final VoidCallback? onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RecordConflictBanner(
      message: switch (notice.kind) {
        RecordNoticeKind.updatedBy => l.recordUpdatedBy(
          notice.changedByName ?? '',
        ),
        RecordNoticeKind.changed ||
        RecordNoticeKind.saveRefused => l.recordConflictMessage,
      },
      isConflict: notice.isConflict,
      onReload: onReload,
      onDismiss: onDismiss,
    );
  }
}

/// One step of a [FormStatusBar].
class FormStatusStep {
  const FormStatusStep(this.value, this.label);
  final String value;
  final String label;
}

/// The record's lifecycle as a row of steps with the current one highlighted. A [current] value
/// that is not among [steps] (a side exit such as "rejected") is shown after them. Steps before
/// the current one count as passed.
class FormStatusBar extends StatelessWidget {
  const FormStatusBar({
    super.key,
    required this.steps,
    required this.current,
    this.offPathLabel,
  });

  final List<FormStatusStep> steps;
  final String current;

  /// Label of [current] when it is not among [steps].
  final String? offPathLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final index = steps.indexWhere((s) => s.value == current);
    final shown = [
      ...steps,
      if (index < 0) FormStatusStep(current, offPathLabel ?? current),
    ];
    final at = index < 0 ? shown.length - 1 : index;
    final currentLabel = shown[at].label;
    return Semantics(
      container: true,
      label: context.l10n.formStatusCurrent(currentLabel),
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: Space.xs,
          children: [
            for (final (i, s) in shown.indexed) ...[
              if (i > 0)
                Icon(AppIcons.chevronRight, size: 16, color: cs.outline),
              Container(
                key: ValueKey('status-${s.value}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: i == at ? cs.primaryContainer : null,
                  borderRadius: Radii.small,
                ),
                child: Text(
                  s.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: i == at
                        ? cs.onPrimaryContainer
                        : i < at
                        ? cs.onSurfaceVariant
                        : cs.outline,
                    fontWeight: i == at ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shortcut from the record to related records, with an optional count ("3 Contacts").
class SmartButton extends StatelessWidget {
  const SmartButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.count,
  });

  final IconData icon;
  final String label;
  final String? count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: Space.sm),
          if (count == null)
            Text(label)
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}
