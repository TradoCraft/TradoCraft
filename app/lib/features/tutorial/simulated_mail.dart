import 'dart:convert';

import 'package:dio/dio.dart';

/// The simulated customer of the story (a made-up person at a fictitious company, on the reserved
/// domain `example.test`).
const tutorialCustomerMail = 'maya.okafor@example.test';

/// Name of the simulated sender.
const tutorialCustomerPerson = 'Maya Okafor';

/// The company name the simulated customer gives in its second e-mail.
const tutorialCustomerCompany = 'Brightwheel Logistics BV';

/// The address the simulated e-mails are sent to.
const tutorialMailbox = 'support@example.test';

bool _isAscii(String s) => s.codeUnits.every((c) => c < 128);

/// Header text as an ASCII-safe value: ASCII as is, anything else as RFC 2047 encoded words of at
/// most 36 bytes each (split on character boundaries).
String encodeHeaderText(String s) {
  if (_isAscii(s)) return s;
  final words = <String>[];
  var bytes = <int>[];
  void flush() {
    if (bytes.isEmpty) return;
    words.add('=?UTF-8?B?${base64.encode(bytes)}?=');
    bytes = [];
  }

  for (final r in s.runes) {
    final b = utf8.encode(String.fromCharCode(r));
    if (bytes.length + b.length > 36) flush();
    bytes.addAll(b);
  }
  flush();
  return words.join(' ');
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// An RFC 5322 date in UTC, e.g. `Thu, 12 Nov 2026 10:00:00 +0000`.
String rfc2822Date(DateTime d) {
  final u = d.toUtc();
  return '${_days[u.weekday - 1]}, ${u.day} ${_months[u.month - 1]} ${u.year} '
      '${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)} +0000';
}

/// A Message-ID that is unique per run: the moment in microseconds, the [kind] of mail and a
/// [salt] (a counter or random number).
String newMessageId(DateTime now, String kind, int salt) =>
    '<tut.${now.toUtc().microsecondsSinceEpoch}.$kind.$salt@example.test>';

/// An RFC 822 message with CRLF line endings. The subject and the sender's name are encoded
/// when they are not ASCII; a non-ASCII body is sent as base64 UTF-8, an ASCII one as 7bit.
String buildRfc822({
  required String messageId,
  required String fromName,
  required String fromAddress,
  required String toAddress,
  required String subject,
  required String body,
  required DateTime date,
  String? inReplyTo,
}) {
  final headers = <String>[
    'Message-ID: $messageId',
    if (inReplyTo != null) ...['In-Reply-To: $inReplyTo', 'References: $inReplyTo'],
    'Date: ${rfc2822Date(date)}',
    'From: ${encodeHeaderText(fromName)} <$fromAddress>',
    'To: $toAddress',
    'Subject: ${encodeHeaderText(subject)}',
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
  ];
  final text = body.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  final String encoded;
  if (_isAscii(body)) {
    headers.add('Content-Transfer-Encoding: 7bit');
    encoded = text.endsWith('\r\n') ? text : '$text\r\n';
  } else {
    headers.add('Content-Transfer-Encoding: base64');
    final b64 = base64.encode(utf8.encode(text));
    encoded = [
      for (var i = 0; i < b64.length; i += 76)
        b64.substring(i, i + 76 > b64.length ? b64.length : i + 76),
    ].join('\r\n');
  }
  return '${headers.join('\r\n')}\r\n\r\n$encoded\r\n';
}

/// The three canned e-mails of the story.
enum TutorialMailKind {
  /// The first request for a quotation.
  request,

  /// The answer with company details.
  details,

  /// The acceptance with a change.
  change,
}

/// The languages the canned e-mails exist in; anything else gets English.
const tutorialMailLanguages = ['en', 'nl', 'fr', 'de', 'es'];

/// Subject and body of a canned mail in [lang].
({String subject, String body}) tutorialMailText(
  TutorialMailKind kind,
  String lang,
) {
  final l = tutorialMailLanguages.contains(lang) ? lang : 'en';
  final t = _texts[kind]![l]!;
  return (subject: t.$1, body: t.$2);
}

const _sign = '\n\nMaya Okafor\nBrightwheel Logistics';

final _texts = <TutorialMailKind, Map<String, (String, String)>>{
  TutorialMailKind.request: {
    'en': ('Request for quotation: TUT-CART', 'Hello,\n\nWe are looking for 8 carts (your model TUT-CART) for our warehouse. Could you send us a quotation with a delivery time?\n\nKind regards$_sign'),
    'nl': ('Offerteaanvraag: TUT-CART', 'Goedendag,\n\nWij zoeken 8 karretjes (uw model TUT-CART) voor ons magazijn. Kunt u ons een offerte met leveringstermijn sturen?\n\nMet vriendelijke groet$_sign'),
    'fr': ('Demande de devis : TUT-CART', 'Bonjour,\n\nNous cherchons 8 chariots (votre modèle TUT-CART) pour notre entrepôt. Pouvez-vous nous envoyer un devis avec un délai de livraison ?\n\nCordialement$_sign'),
    'de': ('Angebotsanfrage: TUT-CART', 'Guten Tag,\n\nwir suchen 8 Karren (Ihr Modell TUT-CART) für unser Lager. Können Sie uns ein Angebot mit Lieferzeit schicken?\n\nMit freundlichen Grüßen$_sign'),
    'es': ('Solicitud de presupuesto: TUT-CART', 'Hola,\n\nBuscamos 8 carritos (su modelo TUT-CART) para nuestro almacén. ¿Pueden enviarnos un presupuesto con plazo de entrega?\n\nUn saludo$_sign'),
  },
  TutorialMailKind.details: {
    'en': ('Re: Request for quotation: TUT-CART', 'Hello,\n\nThank you. Our company details:\n\nBrightwheel Logistics BV\nVAT number: BE0123456749\nVoorbeeldlaan 12, 9000 Gent, Belgium\n\nKind regards$_sign'),
    'nl': ('Re: Offerteaanvraag: TUT-CART', 'Goedendag,\n\nBedankt. Onze bedrijfsgegevens:\n\nBrightwheel Logistics BV\nBTW-nummer: BE0123456749\nVoorbeeldlaan 12, 9000 Gent, België\n\nMet vriendelijke groet$_sign'),
    'fr': ('Re: Demande de devis : TUT-CART', 'Bonjour,\n\nMerci. Les coordonnées de notre société :\n\nBrightwheel Logistics BV\nNuméro de TVA : BE0123456749\nVoorbeeldlaan 12, 9000 Gand, Belgique\n\nCordialement$_sign'),
    'de': ('Re: Angebotsanfrage: TUT-CART', 'Guten Tag,\n\nvielen Dank. Unsere Firmendaten:\n\nBrightwheel Logistics BV\nUSt-IdNr.: BE0123456749\nVoorbeeldlaan 12, 9000 Gent, Belgien\n\nMit freundlichen Grüßen$_sign'),
    'es': ('Re: Solicitud de presupuesto: TUT-CART', 'Hola,\n\nGracias. Los datos de nuestra empresa:\n\nBrightwheel Logistics BV\nNIF-IVA: BE0123456749\nVoorbeeldlaan 12, 9000 Gante, Bélgica\n\nUn saludo$_sign'),
  },
  TutorialMailKind.change: {
    'en': ('Re: Quotation for 8 carts', 'Hello,\n\nWe accept your quotation, but we need 10 carts instead of 8. Could you send an updated quotation?\n\nKind regards$_sign'),
    'nl': ('Re: Offerte voor 8 karretjes', 'Goedendag,\n\nWij gaan akkoord met uw offerte, maar we hebben 10 karretjes nodig in plaats van 8. Kunt u een aangepaste offerte sturen?\n\nMet vriendelijke groet$_sign'),
    'fr': ('Re: Devis pour 8 chariots', 'Bonjour,\n\nNous acceptons votre devis, mais il nous faut 10 chariots au lieu de 8. Pouvez-vous envoyer un devis mis à jour ?\n\nCordialement$_sign'),
    'de': ('Re: Angebot für 8 Karren', 'Guten Tag,\n\nwir nehmen Ihr Angebot an, brauchen aber 10 Karren statt 8. Können Sie ein angepasstes Angebot schicken?\n\nMit freundlichen Grüßen$_sign'),
    'es': ('Re: Presupuesto para 8 carritos', 'Hola,\n\nAceptamos su presupuesto, pero necesitamos 10 carritos en lugar de 8. ¿Pueden enviar un presupuesto actualizado?\n\nUn saludo$_sign'),
  },
};

/// What a scripted "customer writes in" button needs.
class InboundMailResult {
  /// Creates a result.
  const InboundMailResult({
    required this.ticketId,
    required this.ticketNumber,
    required this.messageId,
    required this.newTicket,
  });

  /// The ticket the mail landed in.
  final String ticketId;

  /// Its number (also usable as `[Ticket#number]` in a subject).
  final String ticketNumber;

  /// The Message-ID that was sent.
  final String messageId;

  /// Whether a new ticket was opened (false: the mail joined an existing thread).
  final bool newTicket;
}

/// Builds the canned mail [kind] in [lang] and posts it to `POST /api/v1/helpdesk/inbound`.
/// [inReplyTo] is the Message-ID of the customer's previous mail; [ticketNumber] adds the
/// [messageId] fixes the Message-ID (a retry reuses it); the `[Ticket#...]` tag in the subject, which threads the mail when the reply headers are missing.
Future<InboundMailResult> sendTutorialMail(
  Dio dio, {
  required TutorialMailKind kind,
  required String lang,
  String? inReplyTo,
  String? ticketNumber,
  DateTime? now,
  int? salt,
  String? messageId,
}) async {
  final at = now ?? DateTime.now();
  final id = messageId ?? newMessageId(at, kind.name, salt ?? at.microsecond);
  final text = tutorialMailText(kind, lang);
  final tag = ticketNumber == null ? '' : ' [Ticket#$ticketNumber]';
  final raw = buildRfc822(
    messageId: id,
    inReplyTo: inReplyTo,
    fromName: tutorialCustomerPerson,
    fromAddress: tutorialCustomerMail,
    toAddress: tutorialMailbox,
    subject: '${text.subject}$tag',
    body: text.body,
    date: at,
  );
  final res = await dio.post<Object?>(
    '/api/v1/helpdesk/inbound',
    data: raw,
    options: Options(contentType: 'message/rfc822'),
  );
  final json = res.data;
  if (json is! Map) throw StateError('unexpected answer of the inbound endpoint');
  return InboundMailResult(
    ticketId: '${json['ticket_id']}',
    ticketNumber: '${json['ticket_number']}',
    messageId: id,
    newTicket: json['new_ticket'] == true,
  );
}
