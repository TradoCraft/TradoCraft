import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';

/// What a detail screen shows when its record could not be loaded: a clear "not found" state when
/// the record is gone ([notFound], HTTP 404; a to-do link can outlive its record), otherwise the
/// error. Always with a way out: back to where the user came from, or [leaveTo] (the section
/// list) when nothing is left to go back to. Inside a workspace tab that closes the tab.
class LoadFailedView extends StatelessWidget {
  const LoadFailedView({
    super.key,
    required this.message,
    required this.leaveTo,
    this.notFound = false,
  });

  /// The error sentence (`errorMessage`).
  final String message;

  /// The section list to go to when there is no screen to go back to, e.g. `/orders`.
  final String leaveTo;

  /// The record does not exist (any more) or is not available to the user.
  final bool notFound;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: ValueKey(notFound ? 'record-not-found' : 'record-load-failed'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notFound)
              Icon(
                AppIcons.searchOff,
                size: 48,
                color: theme.colorScheme.outline,
              ),
            if (notFound)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.recordNotFound,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: notFound
                    ? theme.textTheme.bodySmall
                    : TextStyle(color: theme.colorScheme.error),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('record-back'),
              icon: const Icon(AppIcons.arrowBack),
              label: Text(MaterialLocalizations.of(context).backButtonTooltip),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(leaveTo),
            ),
          ],
        ),
      ),
    );
  }
}
