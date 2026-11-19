import 'model.dart';
import 'simulated_mail.dart';

/// Chapter 10: working the ticket of chapter 7 as a helpdesk agent (note, tag, time, escalation).

Map? _tutorialTicket(Object? json) {
  final items = json is Map ? json['items'] : json;
  if (items is! List) return null;
  for (final i in items) {
    if (i is Map && i['contact_email'] == tutorialCustomerMail) return i;
  }
  return null;
}

/// Chapter 10: the helpdesk agent's day on the ticket from chapter 7.
final helpdeskMission = Mission(
  id: 'helpdesk',
  steps: [
    MissionStep(
      id: 'needs',
      probe: Probe(
        '/api/v1/tickets',
        query: {'q': 'TUT-CART', 'limit': 50},
        done: (json, _) => _tutorialTicket(json) != null,
        capture: (json, _) {
          final t = _tutorialTicket(json);
          return t == null
              ? const {}
              : {'ticketId': '${t['id']}', 'ticketNumber': '${t['number']}'};
        },
      ),
    ),
    MissionStep(
      id: 'note',
      hasHint: true,
      route: '/helpdesk/{ticketId}',
      targets: const ['ticket-send'],
      completion: const OnApi('POST', '/tickets/{ticketId}/notes'),
    ),
    MissionStep(
      id: 'tag',
      route: '/helpdesk/{ticketId}',
      completion: const OnApi('POST', '/tickets/{ticketId}/tags'),
    ),
    MissionStep(
      id: 'time',
      route: '/helpdesk/{ticketId}',
      completion: const OnApi('POST', '/tickets/{ticketId}/time-entries'),
    ),
    MissionStep(
      id: 'escalate',
      hasHint: true,
      route: '/helpdesk/{ticketId}',
      completion: const OnApi('POST', '/tickets/{ticketId}/escalate'),
    ),
    const MissionStep(id: 'tour', route: '/helpdesk/answers'),
    const MissionStep(id: 'done'),
  ],
);
