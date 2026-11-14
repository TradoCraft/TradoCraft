import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../shared/app_icons.dart';
import 'api.dart';

/// How often an administrator's app asks whether the background worker runs (ADR 0052).
const workerPollInterval = Duration(minutes: 1);

final _since = DateFormat('dd/MM/yyyy HH:mm');

/// The worker's heartbeat for administrators (`users.admin`), asked again every
/// [workerPollInterval]. Null for everyone else, and when the server cannot answer: a failed
/// check is not a reason to claim the worker is down.
final workerStatusProvider = FutureProvider.autoDispose<WorkerStatus?>((
  ref,
) async {
  final perms = ref.watch(meProvider).value?.permissions;
  if (perms == null || !perms.contains('users.admin')) return null;
  final timer = Timer(workerPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(apiProvider).core.getWorker();
  } catch (_) {
    return null;
  }
});

/// An amber strip under the environment banner while no background worker runs: mail is then
/// neither sent nor fetched. Only administrators see it; nothing is shown otherwise.
class WorkerBanner extends ConsumerWidget {
  const WorkerBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(workerStatusProvider).value;
    final l = context.l10n;
    final String text;
    switch (status?.state) {
      case WorkerState.down:
        final last = status!.lastBeatAt;
        text = last == null
            ? l.workerNeverSeenBanner
            : l.workerDownBanner(_since.format(last.toLocal()));
      case WorkerState.neverSeen:
        text = l.workerNeverSeenBanner;
      default:
        return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      liveRegion: true,
      label: l.workerBannerSemantics,
      child: Material(
        key: const ValueKey('worker-banner'),
        color: dark ? const Color(0xFF8A5A00) : const Color(0xFFFFE0A3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                AppIcons.warningAmber,
                size: 18,
                color: dark ? Colors.white : Colors.black,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: dark ? Colors.white : Colors.black,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
