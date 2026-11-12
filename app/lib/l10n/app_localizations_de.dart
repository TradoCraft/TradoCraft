// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get accepted => 'Angenommen';

  @override
  String get accessToken => 'Zugriffstoken';

  @override
  String get account => 'Konto';

  @override
  String get action => 'Aktion';

  @override
  String get actionAddTag => 'Tag hinzufügen';

  @override
  String get actionSetCategory => 'Kategorie setzen';

  @override
  String get actionSetInternal => 'Als intern markieren';

  @override
  String get actionSetOwner => 'Besitzer setzen';

  @override
  String get actionSetPriority => 'Priorität setzen';

  @override
  String get actionSetTeam => 'Team setzen';

  @override
  String get actions => 'Aktionen';

  @override
  String get activate => 'Aktivieren';

  @override
  String get active => 'Aktiv';

  @override
  String activeSince(String date) {
    return 'Aktiv seit $date. Änderungen erfolgen über eine neue Revision.';
  }

  @override
  String get add => 'Hinzufügen';

  @override
  String get addAction => 'Aktion hinzufügen';

  @override
  String get addClosure => 'Schließzeit hinzufügen';

  @override
  String get addComponent => 'Komponente hinzufügen';

  @override
  String get addComponentBySerial =>
      'Komponente per Seriennummer hinzufügen (auf Lager)';

  @override
  String get addEquipment => 'Anlage hinzufügen';

  @override
  String get addMember => 'Mitglied hinzufügen';

  @override
  String get addNote => 'Notiz hinzufügen';

  @override
  String get addNoteHint => 'Interne Notiz hinzufügen';

  @override
  String get addPart => 'Teil hinzufügen';

  @override
  String get addPhone => 'Nummer hinzufügen';

  @override
  String get addPhoto => 'Foto hinzufügen';

  @override
  String get addProduct => 'Produkt hinzufügen';

  @override
  String get addRebate => 'Rabatt hinzufügen';

  @override
  String get addTag => 'Tag hinzufügen';

  @override
  String get addTask => 'Aufgabe hinzufügen';

  @override
  String addedBy(String date, String name) {
    return 'hinzugefügt am $date von $name';
  }

  @override
  String get addressForm => 'Anredeform';

  @override
  String get addressFormal => 'Förmlich (Sie)';

  @override
  String get addressInformal => 'Informell (du)';

  @override
  String get addVisit => 'Besuch hinzufügen';

  @override
  String get agreed => 'Vereinbart';

  @override
  String get all => 'Alle';

  @override
  String get allCategories => 'Alle Kategorien';

  @override
  String get allOwners => 'Alle Besitzer';

  @override
  String get allProducts => 'Alle Produkte';

  @override
  String get allStatuses => 'Alle Status';

  @override
  String get allTags => 'Alle Tags';

  @override
  String get allTeams => 'Alle Teams';

  @override
  String get always => 'immer';

  @override
  String andMore(int count) {
    return '… und $count weitere';
  }

  @override
  String get announceRepair => 'Reparatur ankündigen';

  @override
  String get announcedNotReceived => 'Angekündigt, noch nicht eingegangen';

  @override
  String answerFallback(String ticketLanguage, String usedLanguage) {
    return 'Noch kein Text auf $ticketLanguage: der Text auf $usedLanguage wurde verwendet. Vor dem Senden übersetzen.';
  }

  @override
  String get anyValue => 'Alle';

  @override
  String get appLanguage => 'Sprache';

  @override
  String get appTitle => 'TradoCraft';

  @override
  String get apply => 'Anwenden';

  @override
  String get assignTo => 'Zuweisen an';

  @override
  String get attachFile => 'Datei anhängen';

  @override
  String get attachments => 'Anhänge';

  @override
  String get attachmentsHelp => 'Bilder (JPEG, PNG, WebP) und PDF, bis 12 MB';

  @override
  String get automatic => 'Automatisch';

  @override
  String get automationHelp =>
      'Regeln laufen in dieser Reihenfolge, wenn ein Ticket erstellt, geändert oder vom Kunden beantwortet wird. Eine Regel gilt, wenn alle Bedingungen zutreffen. Regeln ändern nur Tickets; sie senden keine E-Mails.';

  @override
  String get automationRules => 'Automatisierungsregeln';

  @override
  String get autoRenew => 'Automatisch verlängern';

  @override
  String get backIntoWork => 'Zurück in Arbeit';

  @override
  String get backToCurrentRevision => 'Zurück zur aktuellen Revision';

  @override
  String get backlogByOwner => 'Offene Tickets nach Besitzer';

  @override
  String get backlogByPriority => 'Offene Tickets nach Priorität';

  @override
  String get backlogByStatus => 'Offene Tickets nach Status';

  @override
  String get backlogByTeam => 'Offene Tickets nach Team';

  @override
  String get basisBusiness => 'Geschäftszeiten';

  @override
  String get basisElapsed => 'verstrichene Zeit';

  @override
  String get billOfMaterials => 'Stückliste';

  @override
  String get billable => 'Abrechenbar';

  @override
  String get bomActive => 'aktiv';

  @override
  String get bomObsolete => 'veraltet';

  @override
  String get bomRev => 'Stücklistenrev.';

  @override
  String get bomRevision => 'Stücklistenrevision';

  @override
  String get breached => 'Verletzt';

  @override
  String get breachesByTeam => 'SLA-Verletzungen nach Team';

  @override
  String get builtInto => 'Verbaut in';

  @override
  String get bulkKeepsQuotes =>
      'Angebote vor diesem Datum behalten die aktuellen Preise';

  @override
  String get bulkPriceChange => 'Preise gesammelt ändern';

  @override
  String get businessHours => 'Geschäftszeiten';

  @override
  String get businessHoursEnabled => 'Nur Geschäftszeiten zählen';

  @override
  String get businessHoursHelp =>
      'Servicezeiten zählen nur die Stunden unten, an Tagen ohne Feiertag. Ausgeschaltet laufen sie rund um die Uhr.';

  @override
  String get businessHoursInvalidTime => 'Zeiten als HH:MM eingeben.';

  @override
  String get businessHoursRecompute =>
      'Beim Speichern werden die Fristen aller offenen Tickets neu berechnet.';

  @override
  String get businessHoursSaved =>
      'Gespeichert. Offene Tickets wurden neu berechnet.';

  @override
  String get byStage => 'nach Phase';

  @override
  String get callIncoming => 'Eingehender Anruf';

  @override
  String get callLogged => 'Anruf erfasst';

  @override
  String get callMinutes => 'Dauer (Minuten)';

  @override
  String get callOutgoing => 'Ausgehender Anruf';

  @override
  String get callSummary => 'Gesprächsinhalt';

  @override
  String callWith(String name) {
    return 'Gespräch mit $name';
  }

  @override
  String get canStillKeep =>
      'Die vereinbarten Preise können beibehalten werden.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get cancelJob => 'Einsatz stornieren';

  @override
  String get cancelOrder => 'Auftrag stornieren';

  @override
  String get cancelReasonLabel => 'Stornierungsgrund';

  @override
  String get cancelRepair => 'Reparatur stornieren';

  @override
  String get cancelled => 'storniert';

  @override
  String cancelledReason(String reason) {
    return 'Storniert: $reason';
  }

  @override
  String get cannotConfirmNewer =>
      'Eine neuere Revision dieses Auftrags wird vorbereitet. Sie können sie bestätigen, sobald sie Ihnen zugesandt wurde.';

  @override
  String get cannotConfirmOther =>
      'Dieser Auftrag kann nicht bestätigt werden.';

  @override
  String get captureSignature => 'Unterschrift erfassen';

  @override
  String get category => 'Kategorie';

  @override
  String get categoryComplaint => 'Reklamation';

  @override
  String get categoryLead => 'Lead (neue Anfrage)';

  @override
  String get categoryOrderConfirmation => 'Auftragsbestätigung';

  @override
  String get categoryOther => 'sonstiges';

  @override
  String get categoryProductionQuestion => 'Rückfrage Produktion';

  @override
  String get categoryQuestion => 'Frage';

  @override
  String get categoryQuoteChange => 'Angebotsänderung';

  @override
  String get categoryService => 'Service / Reparatur';

  @override
  String get cc => 'Cc';

  @override
  String get change => 'Änderung';

  @override
  String get changePriority => 'Priorität ändern';

  @override
  String get channel => 'Kanal';

  @override
  String get channelEmail => 'E-Mail';

  @override
  String get channelInternal => 'Interne Frage';

  @override
  String get channelManual => 'Manuell erfasst';

  @override
  String get channelPhone => 'Telefon';

  @override
  String get channelPortal => 'Portal';

  @override
  String get checklistOnePerLine => 'Checkliste (eine Aufgabe pro Zeile)';

  @override
  String get chooseCustomerAndLine =>
      'Kunden wählen und mindestens eine gültige Position hinzufügen.';

  @override
  String get choosePhoto => 'Aus Galerie wählen';

  @override
  String get chooseRebateTarget =>
      'Produkt oder Familie wählen und Prozentsatz eingeben.';

  @override
  String get chooseZonePrice => 'Zone wählen und Preis eingeben.';

  @override
  String get city => 'Ort';

  @override
  String get clear => 'Löschen';

  @override
  String get close => 'Schließen';

  @override
  String get closedLabel => 'geschlossen';

  @override
  String get closes => 'Schließt';

  @override
  String get closureKindCollectiveLeave => 'Betriebsurlaub';

  @override
  String get closureKindHoliday => 'Feiertag';

  @override
  String get closureKindInventory => 'Inventur';

  @override
  String get closureKindLabel => 'Grund';

  @override
  String get closureKindOther => 'Sonstiges';

  @override
  String get closureKindWorks => 'Bauarbeiten';

  @override
  String get closurePolicyBlock => 'Nicht erlaubt';

  @override
  String get closurePolicyBlockHelp =>
      'Eine Lieferung kann nicht an einem Schließtag geplant werden; wählen Sie ein anderes Datum.';

  @override
  String get closurePolicyOverride =>
      'Braucht einen Grund und das Recht zum Übersteuern';

  @override
  String get closurePolicyOverrideHelp =>
      'Nur Benutzer mit dem Recht zum Übersteuern können an einem Schließtag planen, mit Begründung.';

  @override
  String get closurePolicyTitle =>
      'Wenn eine Lieferung an einem Schließtag des Kunden geplant wird';

  @override
  String get closurePolicyWarn => 'Nur warnen';

  @override
  String get closurePolicyWarnHelp =>
      'Das Datum wird gespeichert und die Schließzeit als Warnung angezeigt.';

  @override
  String get closures => 'Schließtage';

  @override
  String get closuresShowPast => 'Vergangene Schließzeiten anzeigen';

  @override
  String get code => 'Code';

  @override
  String get codeNameRequired => 'Code und Name sind erforderlich.';

  @override
  String get codeNameVatRequired =>
      'Code, Name und MwSt.-Satz sind Pflichtfelder.';

  @override
  String get completeJob => 'Einsatz abschließen';

  @override
  String get completionNotes => 'Was wurde getan (und was offen bleibt)';

  @override
  String get component => 'Komponente';

  @override
  String get componentHistory => 'Komponentenhistorie';

  @override
  String componentSince(String product, String date) {
    return '$product · seit $date';
  }

  @override
  String get componentsAsBuilt => 'Komponenten (wie gebaut)';

  @override
  String get confirm => 'bestätigen';

  @override
  String get confirmOnBehalf => 'Im Namen des Kunden bestätigen';

  @override
  String get confirmOnBehalfHelp =>
      'Halten Sie fest, dass der Kunde diese Revision bestätigt hat, zum Beispiel telefonisch oder per E-Mail.';

  @override
  String get confirmOrder => 'Auftrag bestätigen';

  @override
  String get confirmOrderHelp =>
      'Mit der Bestätigung akzeptieren Sie diesen Auftrag wie dargestellt.';

  @override
  String get confirmation => 'Bestätigung';

  @override
  String get confirmationDate => 'Bestätigt am';

  @override
  String get confirmed => 'bestätigt';

  @override
  String get confirmedRevision => 'Bestätigte Revision';

  @override
  String get confirmedVia => 'Bestätigt über';

  @override
  String get confirmedViaPortal => 'Kundenportal';

  @override
  String get confirmedViaStaff => 'Mitarbeiter, im Namen des Kunden';

  @override
  String conflictsOnDate(int count) {
    return '$count haben an diesem Datum bereits einen Preis';
  }

  @override
  String get contactName => 'Name des Ansprechpartners';

  @override
  String get contactPerson => 'Ansprechpartner';

  @override
  String get contacts => 'Kontakte';

  @override
  String get contractEnded => 'Beendet';

  @override
  String get contractJobs => 'Einsätze dieses Vertrags';

  @override
  String contractLabel(String number) {
    return 'Vertrag $number';
  }

  @override
  String contractOpenJobs(String count) {
    return '$count offene Einsätze';
  }

  @override
  String get contracts => 'Verträge';

  @override
  String get contractSuspended => 'Ausgesetzt';

  @override
  String get convertHelp =>
      'Wünscht der Kunde Änderungen? Erst eine neue Angebotsrevision erstellen, hier verknüpfen und dann umwandeln.';

  @override
  String get convertToOrder => 'In Auftrag umwandeln';

  @override
  String get countAddLine => 'Nicht aufgeführten Bestand hinzufügen';

  @override
  String get countCancel => 'Inventur abbrechen';

  @override
  String get countCounted => 'Gezählt';

  @override
  String get countDifference => 'Differenz';

  @override
  String get countExpected => 'Erwartet';

  @override
  String get countInvalidQuantity => 'Eine gezählte Menge ist keine Zahl.';

  @override
  String countMovedDuring(int count) {
    return 'Bei $count Zeile(n) gab es Bewegungen während des Zählens; die gezählte Menge hat sie ersetzt.';
  }

  @override
  String get countNew => 'Neue Inventur';

  @override
  String countOf(int count, int total) {
    return '$count von $total';
  }

  @override
  String get countOneProduct => 'Nur ein Artikel (optional)';

  @override
  String get countOverwriteWarning =>
      'Bewegungen während des Zählens werden überschrieben: beim Buchen der Inventur wird die gezählte Menge zum Bestand.';

  @override
  String get countPost => 'Inventur buchen';

  @override
  String get countPostConfirm =>
      'Die Differenzen werden als Bestandskorrekturen gebucht. Zeilen ohne gezählte Menge bleiben unverändert.';

  @override
  String get countProgress => 'Gezählt';

  @override
  String get countStart => 'Inventur starten';

  @override
  String get countStatusCounting => 'In Arbeit';

  @override
  String get countStatusPosted => 'Gebucht';

  @override
  String countStockAtPost(String quantity) {
    return 'Bestand beim Buchen: $quantity';
  }

  @override
  String get countWarehouseRequired => 'Wählen Sie ein Lager.';

  @override
  String get countWholeWarehouse => 'Gesamtes Lager';

  @override
  String get countedBy => 'Gestartet von';

  @override
  String get country => 'Land';

  @override
  String get create => 'Anlegen';

  @override
  String get createLead => 'Lead anlegen';

  @override
  String get createRepair => 'Reparatur anlegen';

  @override
  String get created => 'erstellt';

  @override
  String get csatAlready => 'Diese Umfrage wurde bereits beantwortet.';

  @override
  String get csatAverage => 'Kundenzufriedenheit';

  @override
  String get csatBad => 'Nicht zufrieden';

  @override
  String get csatComment => 'Kommentar (optional)';

  @override
  String get csatEnabled =>
      'Zufriedenheitsumfrage beim Schließen eines Tickets senden';

  @override
  String get csatExpired => 'Dieser Link ist abgelaufen.';

  @override
  String get csatGood => 'Zufrieden';

  @override
  String get csatNone => 'Noch keine Bewertung';

  @override
  String csatQuestion(String number) {
    return 'Wie zufrieden sind Sie mit der Bearbeitung von Ticket $number?';
  }

  @override
  String csatResponses(int count) {
    return '$count Antworten';
  }

  @override
  String get csatThanks => 'Vielen Dank für Ihr Feedback!';

  @override
  String get csatTitle => 'Kundenzufriedenheit';

  @override
  String get csvCopied => 'CSV in die Zwischenablage kopiert';

  @override
  String get current => 'Aktuell';

  @override
  String get customer => 'Kunde';

  @override
  String get customerDeclinedToSign =>
      'Der Kunde hat die Unterschrift verweigert';

  @override
  String get customerEquipment => 'Anlagen des Kunden';

  @override
  String get customerLanguage => 'Kundensprache';

  @override
  String customerMainNumber(String name) {
    return 'Hauptnummer von $name';
  }

  @override
  String customerNamed(String name) {
    return 'Kunde: $name';
  }

  @override
  String get customerOptional => 'Kunde (optional)';

  @override
  String get customerReference => 'Kundenreferenz';

  @override
  String get customers => 'Kunden';

  @override
  String get customerSignature => 'Unterschrift des Kunden';

  @override
  String get date => 'Datum';

  @override
  String declinedToSignWithReason(String reason) {
    return 'Unterschrift verweigert: $reason';
  }

  @override
  String get defaultTeam => 'Standardteam für neue Tickets';

  @override
  String get deleteRuleConfirm =>
      'Diese Regel löschen? Von ihr geänderte Tickets behalten ihre Änderungen.';

  @override
  String get deliveries => 'Lieferungen';

  @override
  String get deliveryBlocked =>
      'Lieferungen an einem Schließtag sind nicht erlaubt. Wählen Sie ein anderes Datum.';

  @override
  String get deliveryCancel => 'Lieferung stornieren';

  @override
  String get deliveryCancelReason => 'Grund der Stornierung';

  @override
  String get deliveryChooseSerial => 'Seriennummer wählen';

  @override
  String deliveryClosedWarning(String from, String to, String next) {
    return 'Der Kunde ist von $from bis $to geschlossen. Nächster offener Tag: $next.';
  }

  @override
  String get deliveryFailed => 'nicht gesendet';

  @override
  String get deliveryLocation => 'Lagerort';

  @override
  String get deliveryLot => 'Charge';

  @override
  String get deliveryNew => 'Neue Lieferung';

  @override
  String get deliveryNoDate => 'kein Datum';

  @override
  String get deliveryNoLines =>
      'Noch nichts zu liefern: reservieren Sie zuerst Bestand für den Auftrag.';

  @override
  String get deliveryOnClosure => 'an einem Schließtag';

  @override
  String get deliveryOverrideNeedsRight =>
      'Eine Lieferung an einem Schließtag braucht einen Grund und das Recht zum Übersteuern.';

  @override
  String get deliveryOverrideReason =>
      'Grund für die Lieferung an einem Schließtag';

  @override
  String get deliveryPicking => 'Kommissionierliste';

  @override
  String get deliveryPlannedDate => 'Geplantes Datum';

  @override
  String get deliveryQueued => 'wartet auf Versand';

  @override
  String get deliverySent => 'gesendet';

  @override
  String get deliverySerial => 'Seriennummer';

  @override
  String get deliverySettingsTitle => 'Lieferungseinstellungen';

  @override
  String get deliveryShip => 'Versenden';

  @override
  String get deliveryShipTo => 'Lieferadresse';

  @override
  String get deliveryShippedSnack => 'Lieferung versendet';

  @override
  String get deliveryStatusPlanned => 'geplant';

  @override
  String get deliveryStatusShipped => 'versendet';

  @override
  String deliveryUseDay(String date) {
    return '$date wählen';
  }

  @override
  String get department => 'Abteilung';

  @override
  String get departmentCode => 'Kürzel';

  @override
  String get departmentMembers => 'Kollegen dieser Abteilung';

  @override
  String get departments => 'Abteilungen';

  @override
  String get departmentsHelp =>
      'Reparaturen werden an diese Abteilungen weitergeleitet. Nur Kollegen einer Abteilung können deren Reparaturen bearbeiten.';

  @override
  String get description => 'Beschreibung';

  @override
  String get devModeHelp => 'Der Server muss mit AUTH_MODE=dev laufen';

  @override
  String get developmentUser => 'Entwicklungsbenutzer';

  @override
  String get deviceLanguage => 'Gerätesprache';

  @override
  String get difference => 'Differenz';

  @override
  String get dismiss => 'Ablehnen';

  @override
  String get dismissRequest => 'Anfrage ablehnen';

  @override
  String get draftSaved => 'Entwurf gespeichert';

  @override
  String get dryRun => 'An einem Ticket testen';

  @override
  String get dryRunHelp =>
      'Zeigt, welche Regeln für ein Ticket gelten würden und was sie ändern würden. Es wird nichts geändert.';

  @override
  String get dryRunRun => 'Test ausführen';

  @override
  String get drawSignatureFirst => 'Bitte zuerst unterschreiben';

  @override
  String dueOnDate(String date) {
    return 'Fällig am $date';
  }

  @override
  String get edit => 'Bearbeiten';

  @override
  String get editClosure => 'Schließzeit bearbeiten';

  @override
  String get editContact => 'Kontakt bearbeiten';

  @override
  String get editDepartment => 'Abteilung bearbeiten';

  @override
  String get editJob => 'Einsatz bearbeiten';

  @override
  String get email => 'E-Mail';

  @override
  String get emailAddresses =>
      'E-Mail-Adressen (die erste ist die Hauptadresse)';

  @override
  String get endContract => 'Vertrag beenden';

  @override
  String get endDate => 'Enddatum';

  @override
  String get enterChange => 'Änderung eingeben, z. B. 4,5 für +4,5 %.';

  @override
  String enterValidNumbersLine(int line) {
    return 'Position $line: gültige Zahlen eingeben.';
  }

  @override
  String get equipment => 'Anlage';

  @override
  String get estimatedMinutes => 'Geschätzte Minuten';

  @override
  String get expectedClose => 'Voraussichtlicher Abschluss';

  @override
  String expectedCloseDate(String date) {
    return 'Voraussichtlicher Abschluss $date';
  }

  @override
  String get expectedValue => 'Erwarteter Wert';

  @override
  String get expectedValueEur => 'Erwarteter Wert (€)';

  @override
  String get expectedValueOptional => 'Erwarteter Wert (optional)';

  @override
  String get explode => 'Auflösen';

  @override
  String get exportCsv => 'Als CSV kopieren';

  @override
  String get families => 'Familien';

  @override
  String get family => 'Familie';

  @override
  String familyNamed(String code) {
    return 'Familie $code';
  }

  @override
  String get faultDescription => 'Was ist defekt';

  @override
  String get firstDueDate => 'Erste Fälligkeit';

  @override
  String get firstName => 'Vorname';

  @override
  String get firstResponseMinutes => 'Erstreaktion (Min.)';

  @override
  String get firstResponseTime => 'Erstreaktion';

  @override
  String get from => 'Ab';

  @override
  String get fromYou => 'Sie';

  @override
  String generalRebateInfo(String percent) {
    return 'Allgemeiner Rabatt auf alle Produkte: $percent % (Nettopreisprodukte werden nie rabattiert).';
  }

  @override
  String get generalRebatePercent => 'Allgemeiner Rabatt %';

  @override
  String greetingPreview(String greeting) {
    return 'Anrede: $greeting';
  }

  @override
  String get helpdesk => 'Kundendienst';

  @override
  String get helpdeskReports => 'Berichte';

  @override
  String get helpdeskSettings => 'Helpdesk-Einstellungen';

  @override
  String get history => 'Verlauf';

  @override
  String get holidayDate => 'Datum';

  @override
  String get holidayInvalid => 'Datum (JJJJ-MM-TT) und Namen eingeben.';

  @override
  String get holidays => 'Feiertage';

  @override
  String get holidaysHelp => 'Tage, an denen der Helpdesk geschlossen ist.';

  @override
  String get calendarFor => 'Kalender für';

  @override
  String get calendarCompanyWide => 'Ganzes Unternehmen';

  @override
  String get calendarInherited =>
      'Dieses Team hat keinen eigenen Kalender und nutzt den des Unternehmens. Beim Speichern wird einer für das Team angelegt.';

  @override
  String get calendarHolidaysInherited =>
      'Die Feiertage des Unternehmens gelten auch für dieses Team. Hier hinzugefügte Feiertage gehören dem Team selbst.';

  @override
  String get calendarUseCompany => 'Unternehmenskalender verwenden';

  @override
  String get calendarRemoved =>
      'Das Team nutzt wieder den Unternehmenskalender.';

  @override
  String get basisMixed => 'Geschäftszeiten oder verstrichene Zeit, je Team';

  @override
  String get inactive => 'inaktiv';

  @override
  String get inactiveContact => 'Nicht mehr aktiv (ausgeschieden)';

  @override
  String indicativeLine(String description) {
    return '$description (unverbindlich, zu bestätigen)';
  }

  @override
  String indicativeToConfirm(int count) {
    return '$count unverbindliche(r) Preis(e) vor dem Versand zu bestätigen: den vereinbarten Preis im Feld Listenpreis eingeben.';
  }

  @override
  String get insertPreparedAnswer => 'Textbaustein einfügen';

  @override
  String get instructions => 'Anweisungen';

  @override
  String get internalNote => 'Interne Notiz';

  @override
  String internalQuestionHelp(String language) {
    return 'Interne Frage. Fragen Sie den Kunden per Antwort auf $language und geben Sie die Antwort danach als interne Notiz an Ihren Kollegen weiter.';
  }

  @override
  String get internalTicket => 'Internes Ticket';

  @override
  String get internalTicketHelp =>
      'Eine Frage unter Kollegen; nichts wird an den Kunden gesendet.';

  @override
  String get interval => 'Intervall';

  @override
  String get jobCancelled => 'Storniert';

  @override
  String get jobCompleted => 'Abgeschlossen';

  @override
  String jobCount(String count) {
    return '$count Einsätze';
  }

  @override
  String jobCreatedOnDate(String date) {
    return 'Einsatz wird am $date angelegt';
  }

  @override
  String get jobInProgress => 'In Arbeit';

  @override
  String get jobKindInspection => 'Inspektion';

  @override
  String get jobKindInstallation => 'Installation';

  @override
  String get jobKindMaintenance => 'Wartung';

  @override
  String get jobKindOther => 'Sonstiges';

  @override
  String get jobKindRepair => 'Reparatur';

  @override
  String get jobName => 'Titel';

  @override
  String get jobPlanned => 'Geplant';

  @override
  String get jobTitle => 'Funktion';

  @override
  String get jobs => 'Einsätze';

  @override
  String get keepAgreedPrices => 'Vereinbarte Preise beibehalten';

  @override
  String get language => 'Sprache';

  @override
  String languageSameAsCustomer(String language) {
    return 'Wie das Unternehmen ($language)';
  }

  @override
  String lastDays(int days) {
    return 'Letzte $days Tage';
  }

  @override
  String get lastName => 'Nachname';

  @override
  String get leadCreated => 'Lead angelegt';

  @override
  String get leadDays => 'Einsatz anlegen (Tage vorher)';

  @override
  String get lineDiscount => 'Zusatzrab. ±';

  @override
  String get listPrice => 'Listenpreis';

  @override
  String get loadMore => 'Mehr laden';

  @override
  String get logCall => 'Anruf erfassen';

  @override
  String get logTime => 'Zeit erfassen';

  @override
  String get logWork => 'Arbeit erfassen';

  @override
  String get loginLinkInvalid =>
      'Dieser Anmeldelink ist abgelaufen oder wurde bereits verwendet. Fordern Sie einen neuen an.';

  @override
  String get loginLinkSent =>
      'Wenn diese Adresse das Portal nutzen darf, ist ein Anmeldelink unterwegs. Prüfen Sie Ihren Posteingang.';

  @override
  String get lookUp => 'Suchen';

  @override
  String get lost => 'Verloren';

  @override
  String get lostReason => 'Verlustgrund';

  @override
  String get markAsLost => 'Als verloren markieren';

  @override
  String get markAsSent => 'Als versendet markieren';

  @override
  String get markCompleted => 'Als abgeschlossen markieren';

  @override
  String get markReceived => 'Als eingegangen markieren';

  @override
  String get markShipped => 'Als zurückgesendet markieren';

  @override
  String get markWaitingCustomer => 'Wartet auf Kunden';

  @override
  String get markWaitingParts => 'Wartet auf Teile';

  @override
  String get materialRequirements => 'Materialbedarf (aktive Revision)';

  @override
  String get mergeAction => 'Zusammenführen';

  @override
  String get mergeHelp =>
      'Alle Nachrichten, Dateien, Tags und Zeiteinträge wandern in das gewählte Ticket desselben Kunden. Dieses Ticket wird geschlossen. Das kann nicht rückgängig gemacht werden.';

  @override
  String get mergeNoCandidates => 'Kein anderes offenes Ticket dieses Kunden.';

  @override
  String get mergeTicket => 'In anderes Ticket zusammenführen…';

  @override
  String mergedInto(String number) {
    return 'Zusammengeführt mit $number';
  }

  @override
  String get message => 'Nachricht';

  @override
  String get messageSent => 'Nachricht gesendet';

  @override
  String get minutes => 'Minuten';

  @override
  String minutesShort(String minutes) {
    return '$minutes Min.';
  }

  @override
  String get moduleDelivery => 'Lieferung';

  @override
  String get moduleProduction => 'Produktion';

  @override
  String get moveDown => 'Nach unten';

  @override
  String get moveUp => 'Nach oben';

  @override
  String get months => 'Monate';

  @override
  String get myJobs => 'Meine Einsätze';

  @override
  String get myOrders => 'Meine Aufträge';

  @override
  String get myProfile => 'Meine Daten';

  @override
  String get myRepairs => 'Meine Reparaturen';

  @override
  String get myTickets => 'Meine Tickets';

  @override
  String get name => 'Name';

  @override
  String get navigate => 'Navigieren';

  @override
  String get netPrice => 'Nettopreis';

  @override
  String get newAnswer => 'Neuer Textbaustein';

  @override
  String get newContact => 'Neuer Kontakt';

  @override
  String get newContract => 'Neuer Vertrag';

  @override
  String get newCustomer => 'Neuer Kunde';

  @override
  String get newDepartment => 'Neue Abteilung';

  @override
  String get newFamily => 'Neue Familie';

  @override
  String get newItem => 'Neu';

  @override
  String get newJob => 'Neuer Einsatz';

  @override
  String get newLabel => 'Neu';

  @override
  String get newOpportunity => 'Neue Verkaufschance';

  @override
  String get newPrice => 'Neuer Preis';

  @override
  String newPricesValidFrom(String date) {
    return 'Neue Preise gültig ab $date';
  }

  @override
  String get newPriority => 'Neue Priorität';

  @override
  String get newProduct => 'Neues Produkt';

  @override
  String get newQuotation => 'Neues Angebot';

  @override
  String get newRepair => 'Neue Reparatur';

  @override
  String get newRevision => 'Neue Revision';

  @override
  String newRevisionOf(String number) {
    return 'Neue Revision von $number';
  }

  @override
  String get newRule => 'Neue Regel';

  @override
  String get newTeam => 'Neues Team';

  @override
  String get newTicket => 'Neues Ticket';

  @override
  String get no => 'Nein';

  @override
  String get noAccess =>
      'Ihr Konto hat noch keinen Zugriff auf einen Bereich. Fragen Sie einen Administrator.';

  @override
  String get noActiveBom => 'Keine aktive Stückliste.';

  @override
  String get noBom => 'Noch keine Stückliste.';

  @override
  String get noClosures => 'Keine Schließzeiten erfasst.';

  @override
  String get noContactLinked => 'Kein Ansprechpartner verknüpft';

  @override
  String get noContacts => 'Noch keine Kontakte.';

  @override
  String get noContracts => 'Keine Verträge';

  @override
  String get noCustomerEquipment =>
      'Dieser Kunde hat keine installierten Geräte';

  @override
  String get noCustomerLinked => 'Kein Kunde verknüpft';

  @override
  String get noEquipment => 'Keine Anlage verknüpft';

  @override
  String get noExpectedClose => 'Kein voraussichtliches Abschlussdatum';

  @override
  String get noJobsAssigned => 'Ihnen sind keine Einsätze zugewiesen.';

  @override
  String get noLines => 'Noch keine Positionen.';

  @override
  String get noOrdersYet => 'Sie haben noch keine Aufträge.';

  @override
  String get noParts => 'Keine Teile erfasst';

  @override
  String get noPermission =>
      'Sie haben keine Berechtigung, diese Einstellungen zu ändern.';

  @override
  String get noPhotos => 'Noch keine Fotos.';

  @override
  String get noPrices => 'Noch keine Preise.';

  @override
  String get noPriorityChanges => 'Noch keine Prioritätsänderungen.';

  @override
  String get noPriorityRequests => 'Keine Anfragen.';

  @override
  String get noQuotations => 'Noch keine Angebote.';

  @override
  String get noRebates => 'Keine Produkt- oder Familienrabatte.';

  @override
  String get noRepairs => 'Keine Reparaturen.';

  @override
  String get noRepairsYet => 'Sie haben noch keine Reparaturen.';

  @override
  String get noRules => 'Noch keine Regeln.';

  @override
  String get noSerialComponents => 'Keine Komponenten mit Seriennummer.';

  @override
  String get noSignature => 'Noch nicht unterschrieben';

  @override
  String get noTeam => 'Kein Team';

  @override
  String get noTechnicians => 'Niemand zugewiesen';

  @override
  String get noTicketsYet => 'Sie haben noch keine Tickets.';

  @override
  String get noTimeEntries => 'Noch keine Zeit erfasst.';

  @override
  String get nobodyFound => 'Niemand mit dieser Nummer gefunden.';

  @override
  String get nonBillable => 'Nicht abrechenbar';

  @override
  String get none => 'Keine';

  @override
  String get notClosed => 'Nicht geschlossen';

  @override
  String get notRouted => 'Noch nicht weitergeleitet';

  @override
  String get notScheduled => 'Nicht geplant';

  @override
  String get noteAdded => 'Notiz hinzugefügt';

  @override
  String get noteOptional => 'Bemerkung (optional)';

  @override
  String get notes => 'Bemerkungen';

  @override
  String get noUpcomingVisits => 'Keine Besuche fällig';

  @override
  String get number => 'Nummer';

  @override
  String get numberRequired => 'Zahl';

  @override
  String get obsoleteRevision => 'Veraltete Revision (nur Lesen).';

  @override
  String get oidcAccessToken => 'OIDC-Zugriffstoken';

  @override
  String get ok => 'OK';

  @override
  String get onSiteContact => 'Ansprechpartner vor Ort';

  @override
  String get openEnded => 'offen';

  @override
  String get openJobsOnly => 'Nur aktive';

  @override
  String get openOnly => 'Nur offene';

  @override
  String get openOpportunity => 'Verkaufschance öffnen';

  @override
  String openPriorityRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offene Prioritätsanfragen',
      one: '1 offene Prioritätsanfrage',
    );
    return '$_temp0';
  }

  @override
  String openRepairsCount(String count) {
    return '$count offen';
  }

  @override
  String get opens => 'Öffnet';

  @override
  String get opportunities => 'Verkaufschancen';

  @override
  String get opportunity => 'Verkaufschance';

  @override
  String get opportunityOptional => 'Verkaufschance (optional)';

  @override
  String get order => 'Auftrag';

  @override
  String orderAlreadyConfirmed(String date) {
    return 'Dieser Auftrag wurde am $date bestätigt.';
  }

  @override
  String get orderAwaitingConfirmation => 'wartet auf Ihre Bestätigung';

  @override
  String get orderConfirmationQueued =>
      'Die Auftragsbestätigung wurde zum Versand vorgemerkt.';

  @override
  String get orderConfirmedSnack => 'Auftrag bestätigt.';

  @override
  String get orderConfirmedThanks => 'Vielen Dank, Ihr Auftrag ist bestätigt.';

  @override
  String get orderCreated => 'Auftrag angelegt';

  @override
  String get orderSaved => 'Auftrag gespeichert.';

  @override
  String get orderStatusInPlanning => 'in Planung';

  @override
  String get orderStatusInProduction => 'in Produktion';

  @override
  String get orderStatusPartiallyShipped => 'teilweise versendet';

  @override
  String get orderStatusPlanned => 'geplant';

  @override
  String get orderStatusReadyForShipping => 'versandbereit';

  @override
  String get orderStatusShipped => 'versendet';

  @override
  String get orderStockRelease => 'Freigeben';

  @override
  String get orderStockReserve => 'Reservieren';

  @override
  String get orderStockReserveHint =>
      'Bestand kann reserviert werden, sobald der Kunde den Auftrag bestätigt hat.';

  @override
  String orderStockThisLine(String quantity) {
    return '$quantity für diese Zeile reserviert';
  }

  @override
  String get orderStockTitle => 'Lagerverfügbarkeit';

  @override
  String get orders => 'Aufträge';

  @override
  String get owner => 'Verantwortlich';

  @override
  String get ownerEmpty => 'Niemand';

  @override
  String get ownerSet => 'Jemand';

  @override
  String get p90 => '90 % innerhalb';

  @override
  String get partFreeTextHint => 'Produkt wählen oder Beschreibung eingeben';

  @override
  String get partsUsed => 'Verwendete Teile';

  @override
  String get paymentDays => 'Zahlungsziel (Tage)';

  @override
  String get pdf => 'PDF';

  @override
  String get perDay => 'Pro Tag';

  @override
  String get perWeek => 'Pro Woche';

  @override
  String get personTitle => 'Anrede';

  @override
  String get phone => 'Telefon';

  @override
  String get phoneCall => 'Telefonanruf';

  @override
  String get phoneDirect => 'Durchwahl';

  @override
  String get phoneHint => 'Mit Ländervorwahl, z. B. +32 475 12 34 56';

  @override
  String get phoneMobile => 'Mobil';

  @override
  String get phoneNumber => 'Telefonnummer';

  @override
  String get phoneNumbers => 'Telefonnummern';

  @override
  String get phoneOther => 'Sonstige';

  @override
  String get phoneWork => 'Büro';

  @override
  String photoBy(String name) {
    return 'von $name';
  }

  @override
  String get photos => 'Fotos';

  @override
  String get photosAdded => 'Fotos hinzugefügt';

  @override
  String get placeholdersHelp =>
      'Platzhalter (klicken zum Einfügen in der aktuellen Sprache):';

  @override
  String get portalAccess => 'Zugang zum Kundenportal';

  @override
  String get portalScope => 'Sieht im Portal';

  @override
  String get portalScopeCustomer => 'Alle Tickets des Unternehmens';

  @override
  String get portalScopeOwn => 'Nur eigene Tickets';

  @override
  String get portalSignInIntro =>
      'Geben Sie Ihre E-Mail-Adresse ein. Wir senden Ihnen einen Anmeldelink, ein Passwort ist nicht nötig.';

  @override
  String get portalTitle => 'Kundenportal';

  @override
  String get postalCode => 'PLZ';

  @override
  String get preparedAnswers => 'Textbausteine';

  @override
  String get preparedAnswersHelp =>
      'Wiederverwendbare Antworten auf wiederkehrende Fragen, ein Text pro Sprache. Platzhalter wie «quotation.number» werden für das Ticket ausgefüllt; der Text kann vor dem Senden noch bearbeitet werden.';

  @override
  String get preview => 'Vorschau';

  @override
  String priceListOf(String date) {
    return 'Preisliste vom $date';
  }

  @override
  String get priceListValidOn => 'Preisliste gültig am';

  @override
  String get priceZone => 'Preiszone';

  @override
  String pricedOnPriceListOf(String date) {
    return 'Kalkuliert nach der Preisliste vom $date';
  }

  @override
  String get prices => 'Preise';

  @override
  String pricesCreated(int count, String date) {
    return '$count Preise angelegt, gültig ab $date';
  }

  @override
  String pricesWillChange(int count) {
    return '$count Preise werden geändert';
  }

  @override
  String get pricing => 'Preisbildung';

  @override
  String get pricingIndicative => 'unverbindlich';

  @override
  String get pricingIndicativeHelp => 'Unverbindlich (je Angebot bestätigen)';

  @override
  String get pricingList => 'Listenpreis';

  @override
  String get pricingListHelp => 'Listenpreis (Rabatte gelten)';

  @override
  String get pricingNet => 'netto';

  @override
  String get pricingNetHelp => 'Nettopreis (nie rabattiert)';

  @override
  String get priority => 'Priorität';

  @override
  String priorityChangeLine(String date, String from, String to, String name) {
    return '$date: $from → $to von $name';
  }

  @override
  String get priorityChangedSnack => 'Priorität geändert.';

  @override
  String get priorityExpedite => 'dringend';

  @override
  String get priorityHigh => 'hoch';

  @override
  String get priorityHistory => 'Prioritätsverlauf';

  @override
  String get priorityLow => 'niedrig';

  @override
  String get priorityNormal => 'normal';

  @override
  String get priorityRequestHelp =>
      'Unser Team entscheidet, ob und wie die Priorität geändert wird.';

  @override
  String priorityRequestLine(String name, String priority) {
    return '$name wünscht Priorität: $priority';
  }

  @override
  String get priorityRequestSent => 'Ihre Anfrage wurde gesendet.';

  @override
  String get priorityRequests => 'Prioritätsanfragen des Kunden';

  @override
  String get priorityUrgent => 'dringend';

  @override
  String get probability => 'Wahrscheinlichkeit';

  @override
  String get probabilityPercent => 'Wahrscheinlichkeit %';

  @override
  String get probabilityShort => 'Wahrsch.';

  @override
  String get product => 'Produkt';

  @override
  String productCount(int count) {
    return '$count Produkte';
  }

  @override
  String get productDescription => 'Produkt';

  @override
  String get productFamilies => 'Produktfamilien';

  @override
  String get productFamily => 'Produktfamilie';

  @override
  String get productRebates => 'Produktrabatte';

  @override
  String get productTypeConfigurable => 'konfigurierbar';

  @override
  String get productTypeManufactured => 'eigengefertigt';

  @override
  String get productTypePurchased => 'zugekauft';

  @override
  String get productTypeService => 'Dienstleistung';

  @override
  String get production => 'Produktion';

  @override
  String productionBomRevision(String revision) {
    return 'Stücklistenrevision $revision';
  }

  @override
  String get productionBuildComponent => 'Fertigen';

  @override
  String get productionBuildForStock => 'Auf Lager fertigen';

  @override
  String get productionCancel => 'Fertigungsauftrag stornieren';

  @override
  String get productionCancelReason => 'Grund der Stornierung';

  @override
  String get productionChooseSerials => 'Seriennummern wählen';

  @override
  String get productionComplete => 'Abschließen';

  @override
  String get productionCompleted => 'Fertigungsauftrag abgeschlossen';

  @override
  String get productionComponents => 'Komponenten';

  @override
  String get productionConsumed => 'Verbraucht';

  @override
  String get productionDivision => 'Bereich';

  @override
  String get productionDivisionAdd => 'Bereich hinzufügen';

  @override
  String get productionDivisionEdit => 'Bereich bearbeiten';

  @override
  String get productionDivisions => 'Bereiche';

  @override
  String get productionExpiry => 'Verfallsdatum';

  @override
  String get productionExtraFrom => 'Zusätzlicher Bestand aus';

  @override
  String get productionLocation => 'Einlagern in';

  @override
  String get productionLot => 'Chargennummer';

  @override
  String get productionNoDivision => 'kein Bereich';

  @override
  String get productionNothingToRelease =>
      'Nichts freizugeben: jede zu fertigende Position ist durch Fertigungsaufträge gedeckt.';

  @override
  String get productionOrderCancelled =>
      'Der Kundenauftrag wurde storniert. Stornieren Sie diesen Fertigungsauftrag, um die Komponenten freizugeben.';

  @override
  String get productionOrdersOfOrder => 'Fertigungsaufträge';

  @override
  String get productionOutput => 'Ergebnis';

  @override
  String get productionPlannedReady => 'Geplant fertig';

  @override
  String get productionPromised => 'Zugesagt';

  @override
  String get productionQuantityBuilt => 'Gefertigte Menge';

  @override
  String get productionRelease => 'Für die Produktion freigeben';

  @override
  String get productionReleased => 'Für die Produktion freigegeben';

  @override
  String get productionRequired => 'Benötigt';

  @override
  String get productionReserveAgain => 'Erneut reservieren';

  @override
  String get productionReserved => 'Reserviert';

  @override
  String get productionScrap => 'Ausschuss';

  @override
  String get productionSerials => 'Seriennummern, eine pro Zeile';

  @override
  String productionSerialsNeeded(String count) {
    return 'Wählen Sie $count Seriennummern';
  }

  @override
  String get productionShort => 'Bestand reicht nicht';

  @override
  String get productionStart => 'Starten';

  @override
  String get productionStatusCompleted => 'abgeschlossen';

  @override
  String get productionStatusInProgress => 'in Arbeit';

  @override
  String get productionStatusReleased => 'freigegeben';

  @override
  String get productionToRelease => 'Freizugeben';

  @override
  String get products => 'Produkte';

  @override
  String get profileHelp =>
      'Wählen Sie die Sprache und die Anrede in unseren E-Mails und in diesem Portal.';

  @override
  String get quantity => 'Menge';

  @override
  String get question => 'Frage';

  @override
  String get questionToSales => 'Frage an den Vertrieb';

  @override
  String questionToSalesHelp(String salesperson) {
    return '$salesperson erhält diese Frage und stellt sie dem Kunden in seiner Sprache.';
  }

  @override
  String get quotation => 'Angebot';

  @override
  String get quotations => 'Angebote';

  @override
  String raisedBy(String name) {
    return 'Erstellt von $name';
  }

  @override
  String get reason => 'Grund';

  @override
  String get reasonRequired => 'Ein Grund ist erforderlich.';

  @override
  String get rebate => 'Std.-Rabatt';

  @override
  String rebateFor(String target, String percent) {
    return '$target: $percent %';
  }

  @override
  String get rebatePercent => 'Rabatt %';

  @override
  String get rebateSourceFamily => 'Familie';

  @override
  String get rebateSourceGeneral => 'allgemein';

  @override
  String get rebateSourceProduct => 'Produkt';

  @override
  String rebatesOf(String customer) {
    return 'Rabatte · $customer';
  }

  @override
  String get recurrenceMonthList => 'In gewählten Monaten';

  @override
  String get recurrenceMonths => 'Alle N Monate';

  @override
  String get recurrenceWeeks => 'Alle N Wochen';

  @override
  String registerProduct(String product) {
    return '$product erfassen';
  }

  @override
  String get registerUnit => 'Einheit erfassen';

  @override
  String get registered => 'Erfasst';

  @override
  String get rejected => 'Abgelehnt';

  @override
  String get remove => 'Entfernen';

  @override
  String get removeAndScrap => 'Entfernen und verschrotten';

  @override
  String get removeBackToStock => 'Entfernen, zurück ins Lager';

  @override
  String get removeLine => 'Zeile entfernen';

  @override
  String removedBy(String date, String name) {
    return 'entfernt am $date von $name';
  }

  @override
  String get reopenJob => 'Einsatz wieder öffnen';

  @override
  String get repairAnnouncedByTicket =>
      'Der Kunde hat sie angekündigt (das Produkt ist noch nicht eingetroffen)';

  @override
  String get repairAnnouncedOk =>
      'Reparatur angekündigt. Schreiben Sie die Nummer auf das Paket und senden Sie uns das Produkt.';

  @override
  String get repairPhotosHelp =>
      'Fotos vom Produkt und vom Defekt helfen uns sehr.';

  @override
  String get repairPortalAnnounced => 'Angekündigt, noch nicht eingegangen';

  @override
  String get repairPortalInRepair => 'In Reparatur';

  @override
  String get repairPortalReady => 'Repariert, versandbereit';

  @override
  String get repairPortalWaitingCustomer => 'Wartet auf Ihre Antwort';

  @override
  String get repairStatusAnnounced => 'Angekündigt';

  @override
  String get repairStatusCancelled => 'Storniert';

  @override
  String get repairStatusCompleted => 'Abgeschlossen';

  @override
  String get repairStatusInProgress => 'In Arbeit';

  @override
  String get repairStatusReceived => 'Eingegangen';

  @override
  String get repairStatusRouted => 'In der Abteilungswarteschlange';

  @override
  String get repairStatusShipped => 'Zurückgesendet';

  @override
  String get repairStatusWaitingCustomer => 'Wartet auf Kunden';

  @override
  String get repairStatusWaitingParts => 'Wartet auf Teile';

  @override
  String get repairs => 'Reparaturen';

  @override
  String get replaceSignature => 'Unterschrift ersetzen';

  @override
  String get replyQueued => 'Antwort zum Versand bereit';

  @override
  String get replyToCustomer => 'Antwort an Kunden';

  @override
  String get reportQueued => 'Der Bericht wird gesendet';

  @override
  String get reportSend => 'Bericht per E-Mail senden';

  @override
  String reportSentTo(String to, String date) {
    return 'Gesendet an $to am $date';
  }

  @override
  String get reportView => 'Bericht ansehen (PDF)';

  @override
  String repricingFailed(String error) {
    return 'Die heutigen Preise konnten nicht berechnet werden: $error';
  }

  @override
  String get requestDismissedSnack => 'Anfrage abgelehnt.';

  @override
  String get requestLessUrgent => 'Weniger dringend';

  @override
  String get requestMoreUrgent => 'Dringender (eilig)';

  @override
  String get requestPriorityChange => 'Prioritätsänderung anfragen';

  @override
  String get requestStatusApplied => 'angewendet';

  @override
  String get requestStatusDismissed => 'abgelehnt';

  @override
  String get requestStatusOpen => 'offen';

  @override
  String get required => 'Pflichtfeld';

  @override
  String get resolutionHours => 'Lösung innerhalb (Stunden)';

  @override
  String get resolutionMinutes => 'Lösung (Min.)';

  @override
  String get resolutionTime => 'Lösung';

  @override
  String get responseTimes => 'Reaktions- und Lösungszeiten';

  @override
  String get responseHours => 'Reaktion innerhalb (Stunden)';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get revisionActivated => 'Revision aktiviert';

  @override
  String revisionItem(int revision, String status, int lines) {
    return 'Revision $revision · $status · $lines Positionen';
  }

  @override
  String get revisionNotes => 'Revisionsnotizen';

  @override
  String revisionNumber(int revision) {
    return 'Revision $revision';
  }

  @override
  String revisionPriceLists(String agreed, String current) {
    return 'Vereinbarte Preise: Preisliste vom $agreed. Aktuelle Preise: Preisliste vom $current.';
  }

  @override
  String revisionViewNotice(int revision, int current) {
    return 'Sie sehen Revision $revision (schreibgeschützt). Die aktuelle Revision ist $current.';
  }

  @override
  String get revisions => 'Revisionen';

  @override
  String get roleInvoicing => 'Buchhaltung';

  @override
  String get roleManagement => 'Geschäftsleitung';

  @override
  String get roleOther => 'Sonstige';

  @override
  String get rolePurchasing => 'Einkauf';

  @override
  String get roleQuality => 'Qualität';

  @override
  String get roleSalesContact => 'Vertriebskontakt';

  @override
  String get roleTechnical => 'Techniker';

  @override
  String get roles => 'Rollen';

  @override
  String get roundTo => 'Runden auf';

  @override
  String get routeNote => 'Hinweis für die Abteilung';

  @override
  String get routeRepair => 'An Abteilung weiterleiten';

  @override
  String get ruleActions => 'Aktionen';

  @override
  String get ruleConditions => 'Bedingungen (alle müssen zutreffen)';

  @override
  String get ruleConditionsHelp =>
      'Pro Zeile beliebig viele Werte wählen; ein Ticket braucht einen davon. Leere Zeilen werden ignoriert.';

  @override
  String get ruleNameRequired => 'Eine Regel braucht einen Namen.';

  @override
  String get ruleResultAfterStop => 'übersprungen (gestoppt)';

  @override
  String get ruleResultInactive => 'aus';

  @override
  String get ruleResultMatched => 'gilt';

  @override
  String get ruleResultNoMatch => 'trifft nicht zu';

  @override
  String get ruleResultOtherTrigger => 'anderes Ereignis';

  @override
  String get ruleTrigger => 'Wann';

  @override
  String get ruleTriggerCreated => 'Ein Ticket wird erstellt';

  @override
  String get ruleTriggerCustomerReplied => 'Der Kunde antwortet';

  @override
  String get ruleTriggerUpdated => 'Ein Ticket wird von Mitarbeitern geändert';

  @override
  String get salesperson => 'Verkäufer';

  @override
  String get save => 'Speichern';

  @override
  String get saveChanges => 'Änderungen speichern';

  @override
  String get saveDraft => 'Entwurf speichern';

  @override
  String get saved => 'Gespeichert';

  @override
  String savedNumber(String number) {
    return '$number gespeichert';
  }

  @override
  String get scheduledEnd => 'Ende';

  @override
  String get scheduledStart => 'Beginn';

  @override
  String get scrapPercent => 'Ausschuss %';

  @override
  String get search => 'Suchen';

  @override
  String get send => 'Senden';

  @override
  String get sendBackToTriage => 'Zurück zur Triage';

  @override
  String get sendLoginLink => 'Anmeldelink senden';

  @override
  String get sendOrderConfirmation => 'Auftragsbestätigung senden';

  @override
  String get sendOrderConfirmationHelp =>
      'Die Auftragsbestätigung wird dem Kunden als PDF per E-Mail geschickt. Die Revision kann danach nicht mehr bearbeitet werden.';

  @override
  String get senderDomain => 'Absender-Domain';

  @override
  String get serial => 'Seriennr.';

  @override
  String get serialBuiltIn => 'verbaut';

  @override
  String get serialDelivered => 'geliefert';

  @override
  String get serialInStock => 'auf Lager';

  @override
  String get serialInstalled => 'installiert';

  @override
  String get serialNumber => 'Seriennummer';

  @override
  String get serialNumbers => 'Seriennummern';

  @override
  String get serialNumbersHelp =>
      'Jede Einheit erhält eine eigene Seriennummer und Historie';

  @override
  String get serialScrapped => 'verschrottet';

  @override
  String get server => 'Server';

  @override
  String get serviceReport => 'Servicebericht';

  @override
  String get setWarranty => 'Garantie festlegen';

  @override
  String get showInactive => 'Inaktive anzeigen';

  @override
  String signedByOn(String name, String date) {
    return 'Unterschrieben von $name am $date';
  }

  @override
  String get signerName => 'Name des Unterzeichners';

  @override
  String get signHere => 'Hier unterschreiben';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signOut => 'Abmelden';

  @override
  String signedInAs(String name) {
    return 'Angemeldet als $name';
  }

  @override
  String get signingIn => 'Anmeldung…';

  @override
  String get singleProduct => 'Einzelnes Produkt';

  @override
  String get siteAddress => 'Einsatzort';

  @override
  String get siteName => 'Name des Standorts';

  @override
  String skippedWithoutPrice(int count) {
    return '$count Produkt/Zonen-Kombinationen haben keinen Preis und werden übersprungen';
  }

  @override
  String get sla => 'SLA';

  @override
  String get slaAndSatisfaction => 'SLA und Zufriedenheit';

  @override
  String get slaAtRisk => 'Gefährdet';

  @override
  String get slaBreached => 'Überschritten';

  @override
  String get slaCompliance => 'SLA-Einhaltung';

  @override
  String slaComplianceDetail(int breached, int total) {
    return '$breached von $total verletzt';
  }

  @override
  String slaDue(String date) {
    return 'Fällig $date';
  }

  @override
  String get slaFilterAny => 'Jeder SLA-Status';

  @override
  String get slaFirstResponse => 'Erstreaktion';

  @override
  String slaLeft(String time) {
    return 'noch $time';
  }

  @override
  String get slaMet => 'Eingehalten';

  @override
  String get slaNone => 'Kein SLA';

  @override
  String get slaOnTime => 'Im Plan';

  @override
  String slaOverdue(String time) {
    return '$time überfällig';
  }

  @override
  String get slaPaused => 'Uhr angehalten: wartet auf den Kunden';

  @override
  String get slaPolicies => 'Service-Level (SLA)';

  @override
  String get slaPoliciesHelp =>
      'Reine verstrichene Zeit, Geschäftszeiten werden nicht berücksichtigt. Die Uhr steht, solange ein Ticket auf den Kunden wartet.';

  @override
  String get slaResolution => 'Lösung';

  @override
  String get splitAction => 'Teilen';

  @override
  String splitFiles(int count) {
    return '$count Datei(en)';
  }

  @override
  String get splitHelp =>
      'Wählen Sie die Nachrichten, die in ein neues Ticket desselben Kunden wandern. Ihre Dateien wandern mit. Nicht rückgängig zu machen (Tickets lassen sich wieder zusammenführen).';

  @override
  String get splitKeepOne =>
      'Mindestens eine Nachricht muss in diesem Ticket bleiben.';

  @override
  String get splitSubjectOptional => 'Betreff des neuen Tickets (optional)';

  @override
  String get splitTicket => 'Ticket teilen…';

  @override
  String get stage => 'Phase';

  @override
  String get stageLead => 'Lead';

  @override
  String get stageLost => 'verloren';

  @override
  String get stageNegotiation => 'Verhandlung';

  @override
  String get stageProposal => 'Angebot';

  @override
  String get stageQualified => 'qualifiziert';

  @override
  String get stageWon => 'gewonnen';

  @override
  String get startDate => 'Startdatum';

  @override
  String get startJob => 'Einsatz starten';

  @override
  String get startWork => 'Arbeit beginnen';

  @override
  String get status => 'Status';

  @override
  String get statusAccepted => 'angenommen';

  @override
  String get statusAfterwards => 'Status danach';

  @override
  String get statusDraft => 'Entwurf';

  @override
  String get statusRejected => 'abgelehnt';

  @override
  String get statusSent => 'versendet';

  @override
  String get statusSuperseded => 'ersetzt';

  @override
  String get stopOnMatch => 'Nach dieser Regel stoppen';

  @override
  String get stopOnMatchHelp =>
      'Wenn sie zutrifft, werden die folgenden Regeln übersprungen.';

  @override
  String get stockAdjust => 'Korrigieren';

  @override
  String get stockAdjustReason => 'Warum wird der Bestand korrigiert?';

  @override
  String get stockAdjustRequired =>
      'Wählen Sie einen Lagerplatz, geben Sie eine Menge und einen Grund an.';

  @override
  String get stockAllWarehouses => 'Alle Lager';

  @override
  String get stockAssignedTo => 'Zugeordnet an';

  @override
  String get stockAvailable => 'Verfügbar';

  @override
  String get stockBarcode => 'Barcode';

  @override
  String get stockBelowReorder => 'Unter Meldebestand';

  @override
  String get stockChangeBy => 'Ändern um (+/−)';

  @override
  String get stockCounts => 'Inventuren';

  @override
  String stockExpiredQty(String quantity) {
    return '$quantity abgelaufen';
  }

  @override
  String get stockExpiry => 'Verfallsdatum';

  @override
  String get stockFrom => 'Von';

  @override
  String get stockInVans => 'In Fahrzeugen';

  @override
  String get stockInvalidNumbers =>
      'Kosten, Bestandsgrenzen und Lieferzeit müssen Zahlen sein.';

  @override
  String get stockIssue => 'Warenausgang';

  @override
  String get stockKindVan => 'Servicefahrzeug';

  @override
  String get stockKindWarehouse => 'Lager';

  @override
  String get stockLeadTime => 'Lieferzeit (Tage)';

  @override
  String get stockLocation => 'Lagerplatz';

  @override
  String get stockLocations => 'Bestand je Lagerplatz';

  @override
  String get stockLot => 'Charge';

  @override
  String get stockLotNumber => 'Chargennummer';

  @override
  String get stockLotTrackingHelp => 'Chargen';

  @override
  String get stockMoves => 'Bewegungen';

  @override
  String get stockNewLocation => 'Neuer Lagerplatz';

  @override
  String get stockNewLot => 'Neue Charge';

  @override
  String get stockNewQuantity => 'Neue Menge';

  @override
  String get stockNewVan => 'Neues Servicefahrzeug';

  @override
  String get stockNewWarehouse => 'Neues Lager';

  @override
  String get stockNoMoves => 'Noch keine Bewegungen';

  @override
  String get stockNoWarehouses =>
      'Noch keine Lager. Ein Administrator legt sie hier an.';

  @override
  String get stockNote => 'Bemerkung';

  @override
  String get stockNothingInStock => 'Kein Bestand';

  @override
  String get stockOnHand => 'Bestand';

  @override
  String get stockOnlyInStock => 'Nur auf Lager';

  @override
  String get stockProductQuantityRequired =>
      'Wählen Sie einen Artikel und geben Sie eine Menge ein.';

  @override
  String get stockReasonConsumption => 'Verbrauch';

  @override
  String get stockReasonCorrection => 'Korrektur';

  @override
  String get stockReasonCount => 'Inventur';

  @override
  String get stockReasonManualReceipt => 'Manueller Wareneingang';

  @override
  String get stockReasonProductionOutput => 'Produktionsausgang';

  @override
  String get stockReasonPurchaseReceipt => 'Wareneingang Bestellung';

  @override
  String get stockReasonRepairUse => 'Bei Reparatur verbraucht';

  @override
  String get stockReasonReturn => 'Kundenretoure';

  @override
  String get stockReasonReversal => 'Stornierung';

  @override
  String get stockReasonScrap => 'Ausschuss';

  @override
  String get stockReasonShipment => 'Lieferung';

  @override
  String get stockReasonVanReplenishment => 'Fahrzeug auffüllen';

  @override
  String get stockReceive => 'Wareneingang';

  @override
  String get stockReorderMax => 'Höchstbestand';

  @override
  String get stockReorderMin => 'Mindestbestand';

  @override
  String get stockReservations => 'Für Aufträge reserviert';

  @override
  String get stockReserved => 'Reserviert';

  @override
  String get stockReverse => 'Stornieren';

  @override
  String get stockReverseAnyway => 'Trotzdem stornieren';

  @override
  String get stockReverseTitle => 'Diese Bewegung stornieren';

  @override
  String get stockReversed => 'storniert';

  @override
  String stockShortBy(String quantity) {
    return 'Es fehlen $quantity';
  }

  @override
  String get stockStandardCost => 'Standardkosten';

  @override
  String get stockStateAvailable => 'Auf Lager';

  @override
  String get stockStateNotStocked => 'Kein Lagerartikel';

  @override
  String get stockStatePartial => 'Teilweise auf Lager';

  @override
  String get stockStateReserved => 'Reserviert';

  @override
  String get stockStateShort => 'Nicht auf Lager';

  @override
  String get stockTitle => 'Lager';

  @override
  String get stockTo => 'Nach';

  @override
  String get stockTrackingLot => 'Charge';

  @override
  String get stockTransfer => 'Umlagern';

  @override
  String get stockWarehouse => 'Lager';

  @override
  String get stockWarehouses => 'Lager und Fahrzeuge';

  @override
  String get street => 'Straße';

  @override
  String get streetAddress => 'Straße und Nr.';

  @override
  String structureRevision(int revision) {
    return 'Struktur (Revision $revision)';
  }

  @override
  String get subassembly => 'Baugruppe';

  @override
  String get subject => 'Betreff';

  @override
  String get subjectContains => 'Betreff enthält';

  @override
  String get subjectOptional => 'Betreff (optional)';

  @override
  String suggested(String value) {
    return 'Vorschlag: $value';
  }

  @override
  String get tag => 'Tag';

  @override
  String get suspendContract => 'Aussetzen';

  @override
  String get tags => 'Tags';

  @override
  String get takePhoto => 'Foto aufnehmen';

  @override
  String get tasks => 'Aufgaben';

  @override
  String tasksProgress(String done, String total) {
    return '$done von $total erledigt';
  }

  @override
  String get team => 'Team';

  @override
  String get teamLead => 'Teamleiter';

  @override
  String get teamMembers => 'Mitglieder';

  @override
  String get teamName => 'Teamname';

  @override
  String get teams => 'Teams';

  @override
  String get technicians => 'Techniker';

  @override
  String get text => 'Text';

  @override
  String get ticket => 'Ticket';

  @override
  String get ticketClosed => 'Geschlossen';

  @override
  String get ticketDetails => 'Ticketdetails';

  @override
  String get ticketInProgress => 'In Bearbeitung';

  @override
  String get ticketMerged => 'Tickets zusammengeführt';

  @override
  String get ticketOpened => 'Ticket erstellt';

  @override
  String ticketSplit(String number) {
    return 'Ticket $number erstellt';
  }

  @override
  String get ticketStatusClosed => 'geschlossen';

  @override
  String get ticketStatusNew => 'neu';

  @override
  String get ticketStatusOpen => 'offen';

  @override
  String get ticketStatusPendingCustomer => 'wartet auf Kunden';

  @override
  String get ticketStatusPendingInternal => 'wartet auf Kollegen';

  @override
  String get ticketVolume => 'Erstellte und geschlossene Tickets';

  @override
  String get ticketWaitingForYou => 'Wartet auf Ihre Antwort';

  @override
  String get tickets => 'Tickets';

  @override
  String get timeLogged => 'Erfasste Zeit';

  @override
  String get timeNote => 'Notiz';

  @override
  String timeTotal(String total, String billable) {
    return 'Gesamt $total, abrechenbar $billable';
  }

  @override
  String timeTotals(String work, String travel) {
    return 'Arbeit $work · Fahrt $travel';
  }

  @override
  String get timeTracking => 'Zeiterfassung';

  @override
  String get timeZone => 'Zeitzone';

  @override
  String get title => 'Titel';

  @override
  String get titleCustomerValueRequired =>
      'Titel, Kunde und ein gültiger Wert sind erforderlich.';

  @override
  String get titleMr => 'Herr';

  @override
  String get titleMs => 'Frau';

  @override
  String get titleNone => 'Nicht angegeben';

  @override
  String get to => 'An';

  @override
  String get topCategories => 'Häufigste Kategorien';

  @override
  String get topTags => 'Häufigste Tags';

  @override
  String get total => 'Gesamt';

  @override
  String productsTotalChange(String from, String to, String difference) {
    return 'Produkte ohne Versand und MwSt.: $from → $to ($difference)';
  }

  @override
  String get totalExclVat => 'Summe netto';

  @override
  String get totalInclVat => 'Gesamtbetrag brutto';

  @override
  String get totalsToBuyOrMake => 'Summen zu kaufen oder zu fertigen';

  @override
  String get tracking => 'Rückverfolgung';

  @override
  String get twoLetters => '2 Buchstaben';

  @override
  String get type => 'Typ';

  @override
  String get unassigned => 'Nicht zugewiesen';

  @override
  String get unchanged => 'Unverändert';

  @override
  String get unit => 'Einheit';

  @override
  String get unitPrice => 'Einzelpreis';

  @override
  String get unitPriceExclVat => 'Einzelpreis (netto)';

  @override
  String get unknownCaller => 'Unbekannter Anrufer';

  @override
  String get until => 'Bis';

  @override
  String get upcomingVisits => 'Anstehende Besuche';

  @override
  String get updateToCurrentPrices => 'Auf aktuelle Preise aktualisieren';

  @override
  String get updated => 'Aktualisiert';

  @override
  String get uploadingFile => 'Wird hochgeladen…';

  @override
  String get uploadingPhotos => 'Hochladen…';

  @override
  String get useAnotherPriceListDate => 'Anderes Preislistendatum verwenden';

  @override
  String get validFrom => 'Gültig ab';

  @override
  String validFromDate(String date) {
    return 'Gültig ab $date';
  }

  @override
  String validUntil(String date) {
    return 'gültig bis $date';
  }

  @override
  String get value => 'Wert';

  @override
  String get vat => 'MwSt.';

  @override
  String get vatNumber => 'USt-IdNr.';

  @override
  String vatOn(String rate, String base) {
    return 'MwSt. $rate % auf $base';
  }

  @override
  String get vatPercent => 'MwSt. %';

  @override
  String get viaPortal => 'Über das Kundenportal';

  @override
  String get visitTemplates => 'Besuche';

  @override
  String get visitTitleRequired => 'Jeder Besuch braucht einen Titel';

  @override
  String get warranty => 'Garantie';

  @override
  String get warrantyExpired => 'Garantie abgelaufen';

  @override
  String get warrantyIn => 'In Garantie';

  @override
  String get warrantyOut => 'Außerhalb der Garantie';

  @override
  String get warrantyUnknown => 'Unbekannt';

  @override
  String get weekdayFriday => 'Freitag';

  @override
  String get weekdayMonday => 'Montag';

  @override
  String get weekdaySaturday => 'Samstag';

  @override
  String get weekdaySunday => 'Sonntag';

  @override
  String get weekdayThursday => 'Donnerstag';

  @override
  String get weekdayTuesday => 'Dienstag';

  @override
  String get weekdayWednesday => 'Mittwoch';

  @override
  String warrantyUntilDate(String date) {
    return 'bis $date';
  }

  @override
  String get warrantyUntilLabel => 'Garantie bis';

  @override
  String weighted(String amount) {
    return 'gewichtet $amount';
  }

  @override
  String get whatWasAsked => 'Was wurde gefragt?';

  @override
  String get whoIsCalling => 'Wer ruft an?';

  @override
  String get won => 'Gewonnen';

  @override
  String get workFrom => 'Von';

  @override
  String get workKindTravel => 'Fahrt';

  @override
  String get workKindWork => 'Arbeit';

  @override
  String get workLogs => 'Erfasste Zeit';

  @override
  String get workUntil => 'Bis';

  @override
  String writeIn(String language) {
    return 'Auf $language schreiben';
  }

  @override
  String get yes => 'Ja';

  @override
  String get yourMessage => 'Ihre Nachricht';

  @override
  String get yourReference => 'Ihre Referenz (RMA oder Bestellung)';

  @override
  String get zone => 'Zone';

  @override
  String zoneAndRebate(String zone, String percent) {
    return 'Zone $zone · allgemeiner Rabatt $percent %';
  }

  @override
  String get zonesNoneAll => 'Zonen (keine Auswahl = alle)';

  @override
  String get kbTitle => 'Wissensdatenbank';

  @override
  String get kbNewArticle => 'Neuer Artikel';

  @override
  String get kbSearchHint => 'Artikel suchen';

  @override
  String get kbAllCategories => 'Alle Kategorien';

  @override
  String get kbAllStatuses => 'Alle Status';

  @override
  String get kbAllAudiences => 'Alle Zielgruppen';

  @override
  String get kbManageCategories => 'Kategorien';

  @override
  String get kbStatusPublished => 'Veröffentlicht';

  @override
  String get kbStatusArchived => 'Archiviert';

  @override
  String get kbAudience => 'Zielgruppe';

  @override
  String get kbAudienceInternal => 'Intern (nur Mitarbeiter)';

  @override
  String get kbAudiencePortal => 'Kundenportal';

  @override
  String get kbAudiencePublic => 'Öffentlich';

  @override
  String get kbArticleTitle => 'Titel';

  @override
  String get kbSummary => 'Zusammenfassung';

  @override
  String get kbBody => 'Text (Markdown)';

  @override
  String get kbPreview => 'Vorschau';

  @override
  String get kbWriteTab => 'Schreiben';

  @override
  String get kbMarkdownHelp =>
      'Verwenden Sie # für Überschriften, **fett**, *kursiv*, - für Listen, [Text](https://…) für Links und ![Beschreibung](image:ID) für Bilder.';

  @override
  String get kbTagsLabel => 'Tags (durch Komma getrennt)';

  @override
  String get kbRelated => 'Verwandte Artikel';

  @override
  String get kbAddRelated => 'Verwandten Artikel hinzufügen';

  @override
  String get kbImages => 'Bilder';

  @override
  String get kbUploadImage => 'Bild hochladen';

  @override
  String get kbInsertImage => 'In Text einfügen';

  @override
  String get kbPublish => 'Veröffentlichen';

  @override
  String get kbUnpublish => 'Zurückziehen';

  @override
  String get kbArchive => 'Archivieren';

  @override
  String get kbHistory => 'Versionsverlauf';

  @override
  String kbVersionLine(int version, String name, String date) {
    return 'Version $version · $name · $date';
  }

  @override
  String get kbRestore => 'Diese Version wiederherstellen';

  @override
  String kbRestoredFrom(int version) {
    return 'wiederhergestellt aus Version $version';
  }

  @override
  String kbFeedback(int yes, int no) {
    return '$yes fanden dies hilfreich, $no nicht';
  }

  @override
  String kbViews(int count) {
    return '$count Aufrufe';
  }

  @override
  String get kbNoArticles => 'Keine Artikel gefunden.';

  @override
  String get kbNoCategory => 'Keine Kategorie';

  @override
  String get kbMainCategory => 'Hauptkategorie';

  @override
  String get kbSortOrder => 'Reihenfolge';

  @override
  String get kbNewCategory => 'Neue Kategorie';

  @override
  String get kbCategoryNames => 'Name je Sprache';

  @override
  String get kbDelete => 'Löschen';

  @override
  String get kbSuggestedArticles => 'Vorgeschlagene Artikel';

  @override
  String get kbNoSuggestions => 'Keine passenden Artikel.';

  @override
  String get kbInsertText => 'Text einfügen';

  @override
  String get kbInsertLink => 'Link einfügen';

  @override
  String get kbInsertArticle => 'Artikel einfügen';

  @override
  String get kbNoPortalLink =>
      'Dieser Artikel ist intern: nur der Text kann eingefügt werden.';

  @override
  String get kbHelp => 'Hilfe';

  @override
  String get kbHelpHeading => 'Wie können wir helfen?';

  @override
  String get kbHelpSearch => 'Hilfeartikel durchsuchen';

  @override
  String get kbHelpEmpty =>
      'Keine Artikel gefunden. Sie können stattdessen ein Ticket eröffnen.';

  @override
  String get kbWasHelpful => 'War dieser Artikel hilfreich?';

  @override
  String get kbYes => 'Ja';

  @override
  String get kbNo => 'Nein';

  @override
  String get kbThanks => 'Vielen Dank für Ihr Feedback.';

  @override
  String get kbStillNeedHelp =>
      'Brauchen Sie noch Hilfe? Eröffnen Sie ein Ticket.';

  @override
  String get kbRelatedReading => 'Verwandte Artikel';

  @override
  String get kbDeflectionTitle =>
      'Diese Artikel beantworten Ihre Frage vielleicht schon';

  @override
  String kbShownIn(String language) {
    return 'In Ihrer Sprache nicht verfügbar; angezeigt auf $language.';
  }

  @override
  String kbUpdatedOn(String date) {
    return 'Aktualisiert am $date';
  }

  @override
  String offlineWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen warten auf die Synchronisierung',
      one: '1 Änderung wartet auf die Synchronisierung',
    );
    return '$_temp0';
  }

  @override
  String offlineFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count brauchen Ihre Aufmerksamkeit',
      one: '1 braucht Ihre Aufmerksamkeit',
    );
    return '$_temp0';
  }

  @override
  String get offlineQueueTitle =>
      'Änderungen, die auf die Synchronisierung warten';

  @override
  String get offlineSyncNow => 'Jetzt synchronisieren';

  @override
  String get offlineRetry => 'Erneut versuchen';

  @override
  String get offlineDiscard => 'Verwerfen';

  @override
  String get offlineDiscardQuestion =>
      'Diese Änderung verwerfen? Sie wird nicht an den Server gesendet.';

  @override
  String get offlineAllSynced => 'Alles ist synchronisiert.';

  @override
  String offlineAttempts(int count) {
    return 'Versuche: $count';
  }

  @override
  String offlineLastError(String message) {
    return 'Letzter Fehler: $message';
  }

  @override
  String get offlineRejected =>
      'Der Server hat diese Änderung abgelehnt. Der Auftrag wurde möglicherweise inzwischen neu zugewiesen, storniert oder geändert.';

  @override
  String offlineDataFrom(String time) {
    return 'Offline: Daten von $time';
  }

  @override
  String get offlinePendingSync => 'Wartet auf Synchronisierung';

  @override
  String get offlineQueuedMessage =>
      'Keine Verbindung: auf diesem Gerät gespeichert, wird gesendet, sobald Sie wieder online sind.';

  @override
  String offlinePhotosWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos warten auf das Hochladen',
      one: '1 Foto wartet auf das Hochladen',
    );
    return '$_temp0';
  }

  @override
  String get offlineTooLarge =>
      'Zu groß, um offline gespeichert zu werden. Bitte verbinden Sie sich, um es zu senden.';

  @override
  String get offlineReload => 'Neu laden';

  @override
  String get offlineOpStart => 'Auftrag starten';

  @override
  String get offlineOpTaskDone => 'Aufgabe abgehakt';

  @override
  String get offlineOpTaskUndone => 'Aufgabe abgewählt';

  @override
  String get offlineOpTaskAdd => 'Neue Aufgabe';

  @override
  String get offlineOpWorkLog => 'Zeiteintrag';

  @override
  String get offlineOpPart => 'Verwendetes Teil';

  @override
  String get offlineOpComplete => 'Auftrag abschließen';

  @override
  String get offlineOpDecline => 'Kunde verweigert die Unterschrift';

  @override
  String get offlineOpSignature => 'Unterschrift des Kunden';

  @override
  String get offlineOpPhoto => 'Foto';

  @override
  String get collabEscalate => 'Eskalieren';

  @override
  String get collabEscalateTitle => 'Ticket eskalieren';

  @override
  String get collabDelegate => 'Übergeben';

  @override
  String get collabDelegateTitle => 'Ticket übergeben';

  @override
  String get collabEscalateTo => 'Eskalieren an';

  @override
  String get collabNoTarget => 'Teamleiter des Ticket-Teams';

  @override
  String get collabPerson => 'Kollege';

  @override
  String get collabTeam => 'Team';

  @override
  String get collabHandOverTo => 'Neuer Verantwortlicher';

  @override
  String get collabReasonRequired => 'Grund (erforderlich)';

  @override
  String get collabRaisePriority => 'Priorität um eine Stufe erhöhen';

  @override
  String get collabCommentOptional =>
      'Kommentar für den neuen Verantwortlichen (optional)';

  @override
  String get collabInternalHint => 'Intern: wird nie an den Kunden gesendet.';

  @override
  String get collabEscalated => 'Ticket eskaliert';

  @override
  String get collabHandedOver => 'Ticket übergeben';

  @override
  String get collabEscalatedBadge => 'Eskaliert';

  @override
  String collabEscalatedBy(String name) {
    return 'Eskaliert von $name';
  }

  @override
  String get collabWatch => 'Beobachten';

  @override
  String get collabUnwatch => 'Nicht mehr beobachten';

  @override
  String get collabWatchers => 'Beobachter';

  @override
  String get collabNoWatchers => 'Niemand beobachtet dieses Ticket';

  @override
  String get collabAddWatcher => 'Beobachter hinzufügen';

  @override
  String get collabActivity => 'Aktivität';

  @override
  String get collabNoActivity => 'Noch keine Aktivität';

  @override
  String collabSeenBy(String readers) {
    return 'Gesehen von $readers';
  }

  @override
  String get collabFilterUnread => 'Ungelesen';

  @override
  String get collabFilterWatching => 'Beobachtet';

  @override
  String get collabFilterEscalated => 'Eskaliert';

  @override
  String get collabUnreadTooltip => 'Ungelesen';

  @override
  String collabReplying(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names antworten gerade',
      one: '$names antwortet gerade',
    );
    return '$_temp0 — vor dem Senden abstimmen';
  }

  @override
  String collabViewing(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names sehen sich dieses Ticket an',
      one: '$names sieht sich dieses Ticket an',
    );
    return '$_temp0';
  }

  @override
  String collabConfirmSend(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names antworten gerade auf dieses Ticket.',
      one: '$names antwortet gerade auf dieses Ticket.',
    );
    return '$_temp0 Trotzdem senden?';
  }

  @override
  String get collabSendAnyway => 'Trotzdem senden';

  @override
  String get collabSystem => 'System';

  @override
  String collabEventCreated(String actor) {
    return '$actor hat das Ticket angelegt';
  }

  @override
  String collabEventAssignedOwner(String actor, String owner) {
    return '$actor hat das Ticket $owner zugewiesen';
  }

  @override
  String collabEventOwnerCleared(String actor) {
    return '$actor hat den Verantwortlichen entfernt';
  }

  @override
  String collabEventTeam(String actor, String team) {
    return '$actor hat das Ticket in das Team $team verschoben';
  }

  @override
  String collabEventTeamCleared(String actor) {
    return '$actor hat das Team entfernt';
  }

  @override
  String collabEventDelegated(String actor, String owner) {
    return '$actor hat das Ticket an $owner übergeben';
  }

  @override
  String collabEventEscalated(String actor) {
    return '$actor hat das Ticket eskaliert';
  }

  @override
  String collabEventStatus(String actor, String before, String after) {
    return '$actor hat den Status von $before auf $after geändert';
  }

  @override
  String collabEventPriority(String actor, String before, String after) {
    return '$actor hat die Priorität von $before auf $after geändert';
  }

  @override
  String collabEventMergedInto(String actor, String number) {
    return '$actor hat dieses Ticket mit $number zusammengeführt';
  }

  @override
  String collabEventMergedFrom(String actor, String number) {
    return '$actor hat $number in dieses Ticket zusammengeführt';
  }

  @override
  String collabEventTagAdded(String actor, String tag) {
    return '$actor hat das Tag $tag hinzugefügt';
  }

  @override
  String collabEventTagRemoved(String actor, String tag) {
    return '$actor hat das Tag $tag entfernt';
  }

  @override
  String collabMsgCustomer(String actor) {
    return '$actor (Kunde) schrieb';
  }

  @override
  String collabMsgReply(String actor) {
    return '$actor hat dem Kunden geantwortet';
  }

  @override
  String collabMsgNote(String actor) {
    return '$actor hat eine interne Notiz hinzugefügt';
  }

  @override
  String collabMsgCall(String actor) {
    return '$actor hat ein Telefonat erfasst';
  }

  @override
  String get planningTitle => 'Planung';

  @override
  String get planningDay => 'Tag';

  @override
  String get planningWeek => 'Woche';

  @override
  String get planningToday => 'Heute';

  @override
  String get planningPrevious => 'Zurück';

  @override
  String get planningNext => 'Weiter';

  @override
  String get planningBacklog => 'Zu planen';

  @override
  String get planningBacklogEmpty => 'Nichts mehr zu planen.';

  @override
  String get planningSkillFilter => 'Fähigkeit';

  @override
  String get planningAllSkills => 'Alle Fähigkeiten';

  @override
  String get planningNoTechnicians =>
      'Keine Techniker vorhanden. Weisen Sie Benutzern die Rolle Techniker zu.';

  @override
  String get planningPlan => 'Planen';

  @override
  String planningScheduleJob(String number) {
    return '$number planen';
  }

  @override
  String get planningSuggestions => 'Vorschläge';

  @override
  String get planningShowSuggestions => 'Vorschläge anzeigen';

  @override
  String get planningNoSuggestions =>
      'Kein freier Termin in den nächsten zwei Wochen gefunden.';

  @override
  String planningMissingSkills(int count) {
    return '$count Fähigkeit(en) fehlen';
  }

  @override
  String get planningRequiredSkills => 'Erforderliche Fähigkeiten';

  @override
  String get planningChecking => 'Prüfen…';

  @override
  String get planningNoConflicts => 'Keine Konflikte.';

  @override
  String get planningConfirmTitle => 'Trotz Konflikten planen?';

  @override
  String get planningConfirmBody => 'Diese Planung enthält Fehler:';

  @override
  String get planningScheduleAnyway => 'Trotzdem planen';

  @override
  String get planningScheduled => 'Auftrag geplant.';

  @override
  String planningConflictDoubleBooked(String name) {
    return '$name hat zu dieser Zeit einen anderen Auftrag (inklusive Fahrzeit).';
  }

  @override
  String planningConflictOutsideHours(String name) {
    return '$name liegt außerhalb der Arbeitszeit.';
  }

  @override
  String planningConflictOnAbsence(String name) {
    return '$name ist abwesend.';
  }

  @override
  String planningConflictMissingSkill(String name, String skill) {
    return '$name fehlt die Fähigkeit $skill.';
  }

  @override
  String get planningConflictCrossesDays =>
      'Der Auftrag geht über Mitternacht hinaus.';

  @override
  String get planningAbsenceVacation => 'Urlaub';

  @override
  String get planningAbsenceSick => 'Krank';

  @override
  String get planningAbsenceTraining => 'Schulung';

  @override
  String get planningAbsenceOther => 'Andere Abwesenheit';

  @override
  String get planningAgendaEmpty => 'Nichts geplant.';

  @override
  String get planningSettingsTitle => 'Planungseinstellungen';

  @override
  String get planningAbsences => 'Abwesenheiten';

  @override
  String get planningHours => 'Arbeitszeiten';

  @override
  String get planningSkills => 'Fähigkeiten';

  @override
  String get planningGeneral => 'Allgemein';

  @override
  String get planningAddAbsence => 'Abwesenheit hinzufügen';

  @override
  String get planningNoAbsences => 'Keine Abwesenheiten erfasst.';

  @override
  String get planningTechnician => 'Techniker';

  @override
  String get planningKind => 'Art';

  @override
  String get planningDefaultHours => 'Standard des Unternehmens';

  @override
  String get planningUsesDefault =>
      'Keine eigenen Zeiten: Es gilt der Standard des Unternehmens.';

  @override
  String get planningAddBlock => 'Zeitblock hinzufügen';

  @override
  String get planningAddSkill => 'Fähigkeit hinzufügen';

  @override
  String get planningTechnicianSkills => 'Fähigkeiten je Techniker';

  @override
  String planningSkillLevel(int n) {
    return 'Stufe $n';
  }

  @override
  String get planningTravelBuffer => 'Fahrzeit zwischen Aufträgen (Minuten)';

  @override
  String get planningTravelBufferHelp =>
      'Wird zwischen zwei Aufträgen eines Technikers am selben Tag freigehalten.';

  @override
  String get planningDefaultJobMinutes =>
      'Standarddauer eines Auftrags (Minuten)';

  @override
  String get planningTimezone => 'Zeitzone';

  @override
  String get adminTitle => 'Verwaltung';

  @override
  String get adminUsers => 'Benutzer';

  @override
  String get adminModules => 'Module';

  @override
  String get newUser => 'Neuer Benutzer';

  @override
  String get editUser => 'Benutzer bearbeiten';

  @override
  String get userDisabledModules => 'Deaktivierte Module';

  @override
  String get userNotSignedIn => 'Noch nicht angemeldet';

  @override
  String get userResendInvitation => 'Einladung erneut senden';

  @override
  String get userInvitationSent => 'Einladung gesendet';

  @override
  String get userCreated => 'Benutzer hinzugefügt';

  @override
  String get userFilterAll => 'Alle Mitglieder';

  @override
  String get userFilterActive => 'Aktive Mitglieder';

  @override
  String get userFilterInactive => 'Deaktivierte Mitglieder';

  @override
  String get userActiveHelp =>
      'Ein deaktiviertes Mitglied kann sich nicht mehr bei dieser Firma anmelden.';

  @override
  String get userCannotDeactivateSelf =>
      'Sie können sich nicht selbst deaktivieren.';

  @override
  String get userCannotDropOwnAdmin =>
      'Sie können Ihre eigene Administratorrolle nicht entfernen.';

  @override
  String userRolePermissions(int count) {
    return '$count Berechtigungen';
  }

  @override
  String get userModulesHelp =>
      'Schalten Sie Module für diese Person aus. Von der Firma deaktivierte Module können hier nicht wieder eingeschaltet werden.';

  @override
  String get userModuleCompanyOff => 'Für die ganze Firma ausgeschaltet';

  @override
  String moduleRequires(String modules) {
    return 'Benötigt $modules';
  }

  @override
  String get modulesIntro =>
      'Schalten Sie die Module aus, die diese Firma nicht nutzt. Sie verschwinden für die Benutzer und der Server lehnt ihre Anfragen ab.';

  @override
  String get modulesSaved => 'Module gespeichert';

  @override
  String moduleAlsoRequires(String modules) {
    return 'Benötigt auch $modules';
  }

  @override
  String moduleAlsoSwitchedOff(String modules) {
    return 'Schaltet auch aus: $modules';
  }

  @override
  String moduleAlsoSwitchedOn(String modules) {
    return 'Schaltet auch ein: $modules';
  }

  @override
  String moduleExpand(String module) {
    return '$module aufklappen';
  }

  @override
  String moduleCollapse(String module) {
    return '$module zuklappen';
  }

  @override
  String get moduleOn => 'An';

  @override
  String get moduleOff => 'Aus';

  @override
  String moduleLevel(int level) {
    return 'Ebene $level';
  }

  @override
  String get userRoleAdmin => 'Administrator';

  @override
  String get userRoleSalesManager => 'Vertriebsleiter';

  @override
  String get userRoleSales => 'Vertrieb';

  @override
  String get userRoleSupport => 'Support';

  @override
  String get userRoleProduction => 'Produktion';

  @override
  String get userRoleWarehouse => 'Lager';

  @override
  String get userRoleProductManager => 'Produktmanager';

  @override
  String get userRoleWorkshop => 'Werkstatt';

  @override
  String get userRoleTechnician => 'Techniker';

  @override
  String get userRoleDispatcher => 'Disponent';

  @override
  String get userRoleLogistics => 'Logistik';

  @override
  String get userRoleViewer => 'Leser';

  @override
  String get moduleCustomers => 'Kunden';

  @override
  String get moduleProducts => 'Produkte';

  @override
  String get moduleSales => 'Vertrieb';

  @override
  String get moduleEngineering => 'Engineering';

  @override
  String get moduleInventory => 'Lagerbestand';

  @override
  String get moduleHelpdesk => 'Helpdesk';

  @override
  String get moduleKb => 'Wissensdatenbank';

  @override
  String get moduleRepairs => 'Reparaturen';

  @override
  String get moduleField => 'Außendienst';

  @override
  String get purpose => 'Verwendungszweck';

  @override
  String get purposeInstallation => 'Installation';

  @override
  String get purposeStock => 'Lager';

  @override
  String get deliveryCountry => 'Lieferland';

  @override
  String deliveryCountryDefault(String country) {
    return 'Standard: $country';
  }

  @override
  String get deliveryCountryInvalid =>
      'Geben Sie einen zweistelligen Ländercode ein, zum Beispiel BE.';

  @override
  String get shippingNotRequired => 'nicht erforderlich';

  @override
  String get shippingPending => 'ausstehend';

  @override
  String get shippingQuoted => 'angeboten';

  @override
  String get shippingRequested => 'angefragt';

  @override
  String get shippingPendingBanner =>
      'Warten auf ein Versandangebot der Logistik. Das Angebot kann erst versendet werden, wenn die Kosten erfasst sind.';

  @override
  String get shippingQuotedBanner =>
      'Die Versandkosten wurden angeboten und stehen als Versandposition im Angebot.';

  @override
  String get shippingLineNote => 'Von der Logistik hinzugefügt';

  @override
  String get sendAnyway => 'Trotzdem senden';

  @override
  String sendAnywayHelp(String message) {
    return '$message\n\nAls Logistik dürfen Sie das Angebot ohne Versandkosten senden. Trotzdem senden?';
  }

  @override
  String get shippingRequests => 'Versandanfragen';

  @override
  String get shippingQueue => 'Offen und angefragt';

  @override
  String get markAsRequested => 'Als angefragt markieren';

  @override
  String get enterQuote => 'Angebot erfassen';

  @override
  String get carrier => 'Spediteur';

  @override
  String get amount => 'Betrag';

  @override
  String get currency => 'Währung';

  @override
  String get quotedAmount => 'Angebotener Betrag';

  @override
  String get requestedAt => 'Angefragt am';

  @override
  String get amountRequired => 'Geben Sie einen gültigen Betrag ein.';

  @override
  String get carrierRequired => 'Geben Sie den Spediteur an.';

  @override
  String get packagingCategory => 'Verpackungskategorie';

  @override
  String get packagingCategories => 'Verpackungskategorien';

  @override
  String get newPackagingCategory => 'Neue Verpackungskategorie';

  @override
  String get requiresShippingQuote => 'Erfordert ein Versandangebot';

  @override
  String get lengthMm => 'Länge (mm)';

  @override
  String get widthMm => 'Breite (mm)';

  @override
  String get heightMm => 'Höhe (mm)';

  @override
  String get weightG => 'Gewicht (g)';

  @override
  String get dimensions => 'Abmessungen';

  @override
  String dimensionsValue(int length, int width, int height) {
    return '$length x $width x $height mm';
  }

  @override
  String get weight => 'Gewicht';

  @override
  String weightValue(int grams) {
    return '$grams g';
  }

  @override
  String get positiveWholeNumbers =>
      'Abmessungen und Gewicht müssen positive ganze Zahlen sein oder leer.';

  @override
  String get powerTab => 'Stromversorgung';

  @override
  String get powerNotElectrical =>
      'Es sind keine Versorgungen angegeben: Das ist kein elektrisches Produkt und wird nie mit einem Stromnetz abgeglichen.';

  @override
  String get powerAddSupply => 'Versorgung hinzufügen';

  @override
  String get currentType => 'Stromart';

  @override
  String get currentAc => 'AC';

  @override
  String get currentDc => 'DC';

  @override
  String get voltageV => 'Spannung (V)';

  @override
  String get phases => 'Phasen';

  @override
  String get frequencyHz => 'Frequenz (Hz)';

  @override
  String get frequencyBoth => '50 und 60 Hz';

  @override
  String get tolerancePct => 'Toleranz (%)';

  @override
  String get powerVoltageInvalid =>
      'Geben Sie die Spannung als positive ganze Zahl ein.';

  @override
  String get powerToleranceInvalid =>
      'Die Toleranz muss eine ganze Zahl von 0 bis 50 sein.';

  @override
  String get powerSupplyDuplicate =>
      'Dieselbe Versorgung ist doppelt aufgeführt.';

  @override
  String get powerCheckTitle => 'Netzverträglichkeit prüfen';

  @override
  String get powerCheckHelp =>
      'Gleicht die gespeicherten Versorgungen mit den Stromnetzen eines Landes ab.';

  @override
  String get powerGrid => 'Stromnetz';

  @override
  String get powerAnyGrid => 'Jedes Netz in diesem Land';

  @override
  String get powerCheck => 'Prüfen';

  @override
  String powerResultCompatible(String country) {
    return 'Verträglich mit dem Stromnetz von $country.';
  }

  @override
  String powerResultIncompatible(
    String country,
    String supported,
    String available,
  ) {
    return 'Passt nicht zum Netz von $country. Unterstützt: $supported. Dort verfügbar: $available.';
  }

  @override
  String get powerResultExternal =>
      'Läuft nur mit Gleichstrom und braucht ein externes Netzteil; es wird nicht gegen das Netz geprüft.';

  @override
  String get powerResultNotApplicable =>
      'Kein elektrisches Produkt; es gibt nichts zu prüfen.';

  @override
  String powerResultUnknown(String country) {
    return 'Für $country liegen keine Netzdaten vor; die Verträglichkeit kann nicht geprüft werden.';
  }

  @override
  String get powerStatusCompatible => 'Verträglich';

  @override
  String get powerStatusIncompatible => 'Nicht verträglich';

  @override
  String get powerStatusExternal => 'Externes Netzteil nötig';

  @override
  String get powerStatusNotApplicable => 'Nicht zutreffend';

  @override
  String get powerStatusUnknown => 'Netz unbekannt';

  @override
  String get relatedTab => 'Verwandt';

  @override
  String get relationRules => 'Regeln';

  @override
  String get relationSuggestions => 'Vorschläge';

  @override
  String get relationNoRules => 'Für dieses Produkt gelten keine Regeln.';

  @override
  String get relationNoSuggestions => 'Noch keine Vorschläge.';

  @override
  String get relationKindCompatible => 'Kompatibel';

  @override
  String get relationKindIncompatible => 'Inkompatibel';

  @override
  String get relationKindSuggested => 'Empfohlen';

  @override
  String get relationAddRule => 'Regel hinzufügen';

  @override
  String get relationEdit => 'Beziehung bearbeiten';

  @override
  String get relationsTitle => 'Produktbeziehungen';

  @override
  String get newRelation => 'Neue Beziehung';

  @override
  String get relationKindLabel => 'Art';

  @override
  String get relationSideA => 'Erste Seite';

  @override
  String get relationSideB => 'Zweite Seite';

  @override
  String get relationBidirectional => 'Gilt in beide Richtungen';

  @override
  String get relationStrength => 'Stärke (1-100)';

  @override
  String get relationStrengthHelp =>
      'Wird nur von Empfehlungsregeln verwendet.';

  @override
  String get relationNeedSides =>
      'Wählen Sie auf beiden Seiten ein Produkt oder eine Familie.';

  @override
  String get relationStrengthInvalid =>
      'Die Stärke muss eine ganze Zahl von 1 bis 100 sein.';

  @override
  String get relationsEmpty => 'Keine Beziehungen.';

  @override
  String relationFamilyValue(String code) {
    return 'Familie $code';
  }

  @override
  String get suggestionReasonRule => 'Regel';

  @override
  String get suggestionReasonOften => 'Oft zusammen gekauft';

  @override
  String suggestionStrength(int n) {
    return 'Stärke $n';
  }

  @override
  String suggestionConfidence(int pct) {
    return 'Konfidenz $pct %';
  }

  @override
  String suggestionBecause(String code) {
    return 'Wegen $code';
  }

  @override
  String get powerGridsTitle => 'Stromnetze';

  @override
  String get newPowerGrid => 'Neues Stromnetz';

  @override
  String get powerGridInvalid =>
      'Geben Sie einen zweistelligen Ländercode, eine Spannung, 1 oder 3 Phasen und 50 oder 60 Hz an.';

  @override
  String get warningKindPowerGrid => 'Stromnetz';

  @override
  String get warningKindIncompatible => 'Inkompatible Produkte';

  @override
  String hintsPowerIncompatible(String code) {
    return '$code passt nicht zum Stromnetz am Lieferort.';
  }

  @override
  String hintsSupported(String value) {
    return 'Unterstützt: $value';
  }

  @override
  String hintsAvailable(String value) {
    return 'Verfügbar: $value';
  }

  @override
  String hintsPowerExternal(String code) {
    return '$code läuft mit Gleichstrom und braucht ein externes Netzteil.';
  }

  @override
  String hintsPowerUnknown(String country, String code) {
    return 'Keine Netzdaten für $country, daher konnte $code nicht geprüft werden. Ergänzen Sie das Netz des Landes unter Stromnetze auf der Produktseite.';
  }

  @override
  String hintsIncompatibleProducts(String a, String b) {
    return '$a und $b sind nicht kompatibel.';
  }

  @override
  String get suggestionsTitle => 'Vorgeschlagene Ergänzungen';

  @override
  String get hintsTitle => 'Warnungen und Vorschläge';

  @override
  String revisionShippingExisting(String amount) {
    return 'Bestehende Versandkosten: $amount';
  }

  @override
  String get revisionShippingReset =>
      'Mit aktuellen Preisen werden diese Versandkosten zurückgesetzt. Vor dem Versand des überarbeiteten Angebots ist ein neues Versandangebot der Logistik erforderlich.';

  @override
  String revisionShippingKept(String amount) {
    return 'Mit vereinbarten Preisen wird der angebotene Versand in das überarbeitete Angebot übernommen (aktuelle Kosten: $amount).';
  }

  @override
  String get packagesReceiving => 'Wareneingang';

  @override
  String get packagesIntake => 'Reparaturannahme';

  @override
  String get registerParcel => 'Paket erfassen';

  @override
  String get registeredParcels => 'Erfasste Pakete';

  @override
  String get noParcels => 'Keine Pakete.';

  @override
  String get sender => 'Absender';

  @override
  String get trackingNumber => 'Sendungsnummer';

  @override
  String get parcelCount => 'Anzahl Pakete';

  @override
  String get packageCondition => 'Zustand des Kartons';

  @override
  String get conditionIntact => 'Unbeschädigt';

  @override
  String get conditionDamaged => 'Beschädigt';

  @override
  String get conditionOpened => 'Geöffnet';

  @override
  String get conditionWet => 'Nass';

  @override
  String get conditionNote => 'Bemerkung zum Zustand';

  @override
  String get removePhoto => 'Foto entfernen';

  @override
  String parcelRegistered(String number) {
    return 'Paket $number erfasst';
  }

  @override
  String get pkgStatusRegistered => 'Erfasst';

  @override
  String get pkgStatusOpened => 'Geöffnet';

  @override
  String get pkgStatusLinked => 'Reparatur zugeordnet';

  @override
  String get pkgStatusClosed => 'Abgeschlossen';

  @override
  String get packageKindRepair => 'Reparatur';

  @override
  String get packageKindOther => 'Sonstiges (keine Reparatur)';

  @override
  String get packageKindReturn => 'Zurück an den Absender';

  @override
  String get toOpen => 'Zu öffnen';

  @override
  String get toProcess => 'Zu bearbeiten';

  @override
  String get toRoute => 'Weiterzuleiten';

  @override
  String get nothingHere => 'Hier ist nichts zu tun.';

  @override
  String get openParcel => 'Paket öffnen';

  @override
  String get parcelContents => 'Was ist im Paket?';

  @override
  String get closeParcel => 'Paket abschließen';

  @override
  String get noteRequired => 'Eine Bemerkung ist erforderlich.';

  @override
  String get linkToRepair => 'Reparatur zuordnen';

  @override
  String get repairSuggestions => 'Vorgeschlagene Reparaturen';

  @override
  String get noSuggestions => 'Keine angekündigte Reparatur passt.';

  @override
  String suggestedCustomer(String name) {
    return 'Vorgeschlagener Kunde: $name';
  }

  @override
  String suggestionScore(String score) {
    return 'Punktzahl $score';
  }

  @override
  String get reasonSerial => 'Gleiche Seriennummer';

  @override
  String get reasonCustomer => 'Gleicher Kunde';

  @override
  String get reasonReference => 'Gleiche Referenz';

  @override
  String get reasonTicket => 'Gleiches Ticket';

  @override
  String get reasonProduct => 'Ähnliches Produkt';

  @override
  String get reasonRecent => 'Kürzlich angekündigt';

  @override
  String get confirmLinkTitle => 'Zuordnung bestätigen';

  @override
  String confirmLinkBody(String parcel, String repair) {
    return 'Paket $parcel enthält Reparatur $repair. Eine angekündigte Reparatur wird als eingegangen markiert.';
  }

  @override
  String get customerMismatchWarning =>
      'Der Kunde des Pakets ist nicht der Kunde der Reparatur.';

  @override
  String get confirmCustomerMismatch =>
      'Ja, es wurde von jemand anderem geschickt (z. B. einem Kollegen)';

  @override
  String get confirmLink => 'Bestätigen und zuordnen';

  @override
  String get linkConflict =>
      'Die Reparatur wurde inzwischen geändert. Die Liste wurde aktualisiert; bitte prüfen und erneut versuchen.';

  @override
  String get createNewRepair => 'Neue Reparatur anlegen';

  @override
  String get parcelsSection => 'Pakete';

  @override
  String get noParcelsLinked => 'Kein Paket zugeordnet.';

  @override
  String get unlinkParcel => 'Paket lösen';

  @override
  String get parcelsToLink => 'Pakete, die auf diese Reparatur warten';

  @override
  String get linkParcel => 'Paket zuordnen';

  @override
  String get parcelLinked => 'Paket zugeordnet';

  @override
  String get parcelUnlinked => 'Paket gelöst';

  @override
  String get customerUnknown => 'Kunde unbekannt';

  @override
  String get findingsSection => 'Befunde';

  @override
  String get findingsLabel => 'Was festgestellt wurde';

  @override
  String get diagnosisLabel => 'Diagnose';

  @override
  String get saveFindings => 'Befunde speichern';

  @override
  String get warrantySection => 'Garantie';

  @override
  String get warrantyVoid => 'Erloschen (Missbrauch)';

  @override
  String get warrantyAutomatic => 'Automatisches Ergebnis';

  @override
  String warrantyComparedWith(String date) {
    return 'Verglichen mit dem Eingangsdatum $date';
  }

  @override
  String get warrantyProvisional =>
      'Noch nicht eingegangen: mit heute verglichen, daher vorläufig.';

  @override
  String serialUnitLabel(String unit) {
    return 'Seriennummern-Einheit: $unit';
  }

  @override
  String get noSerialUnit => 'Keine Seriennummern-Einheit verknüpft';

  @override
  String get linkSerialUnit => 'Seriennummern-Einheit verknüpfen';

  @override
  String get unlinkSerialUnit => 'Seriennummern-Einheit lösen';

  @override
  String get serialUnitSeveral =>
      'Mehrere Einheiten passen. Wählen Sie die richtige.';

  @override
  String get serialUnitNoResults => 'Keine Einheiten gefunden';

  @override
  String get recheckWarranty => 'Garantie erneut prüfen';

  @override
  String get markWarrantyVoid => 'Garantie erlöschen lassen (Missbrauch)';

  @override
  String get removeWarrantyOverride => 'Überschreibung entfernen';

  @override
  String get warrantyVoidTitle => 'Garantie erlöschen lassen';

  @override
  String get warrantyRemoveTitle => 'Überschreibung „erloschen“ entfernen';

  @override
  String get warrantyReasonLabel => 'Grund (erforderlich)';

  @override
  String warrantyOverriddenBy(String name, String date, String reason) {
    return 'Von $name am $date auf erloschen gesetzt: $reason';
  }

  @override
  String get eventFindings => 'Befunde aktualisiert';

  @override
  String get eventSerialUnit => 'Seriennummern-Einheit';

  @override
  String get eventWarrantyAuto => 'Automatische Garantie';

  @override
  String get eventWarrantyManual => 'Garantie manuell gesetzt';

  @override
  String get eventWarrantyVoid => 'Garantie erloschen';

  @override
  String get eventWarrantyVoidRemoved => 'Garantie-Überschreibung entfernt';

  @override
  String get csvMenu => 'CSV-Export und -Import';

  @override
  String get csvExport => 'CSV exportieren';

  @override
  String get csvImport => 'CSV importieren';

  @override
  String csvExported(String name) {
    return '$name gespeichert';
  }

  @override
  String csvExportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String csvImportTitle(String entity) {
    return 'CSV-Import: $entity';
  }

  @override
  String get csvImportHelp =>
      'Zeilen werden über den Code zugeordnet: ein vorhandener Code wird aktualisiert, ein neuer Code wird angelegt. Spalten, die in der Datei fehlen, bleiben unverändert, und es wird nie etwas gelöscht. Alles oder nichts: Bei einem Fehler in einer Zeile wird nichts importiert. Getrennt durch Semikolon oder Komma, UTF-8.';

  @override
  String get csvChooseFile => 'CSV-Datei auswählen';

  @override
  String get csvChooseOther => 'Andere Datei auswählen';

  @override
  String get csvChecking => 'Datei wird geprüft...';

  @override
  String get csvImporting => 'Import läuft...';

  @override
  String get csvPreview => 'Vorschau: Es wurde noch nichts importiert';

  @override
  String get csvDone => 'Import abgeschlossen';

  @override
  String get csvToCreate => 'Neu anzulegen';

  @override
  String get csvToUpdate => 'Zu aktualisieren';

  @override
  String get csvUnchanged => 'Unverändert';

  @override
  String get csvCreated => 'Angelegt';

  @override
  String get csvUpdated => 'Aktualisiert';

  @override
  String get csvImportAction => 'Importieren';

  @override
  String get csvEmptyFile => 'Die Datei ist leer.';

  @override
  String get csvNotUtf8 =>
      'Die Datei ist kein UTF-8-Text. Speichern Sie sie als CSV (UTF-8) und versuchen Sie es erneut.';

  @override
  String get csvReadFailed => 'Die Datei konnte nicht gelesen werden.';

  @override
  String csvErrorsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Probleme gefunden',
      one: '1 Problem gefunden',
    );
    return '$_temp0. Es wurde nichts importiert.';
  }

  @override
  String csvErrorRow(int row) {
    return 'Zeile $row';
  }

  @override
  String csvErrorRowColumn(int row, String column) {
    return 'Zeile $row, Spalte $column';
  }

  @override
  String csvAndMore(int count) {
    return 'und $count weitere';
  }

  @override
  String profileTooltip(String name) {
    return 'Profil: $name';
  }

  @override
  String get tabTicket => 'Ticket';

  @override
  String get tabQuotation => 'Angebot';

  @override
  String get tabNewQuotation => 'Neues Angebot';

  @override
  String get tabOrder => 'Auftrag';

  @override
  String get tabRepair => 'Reparatur';

  @override
  String get tabJob => 'Einsatz';

  @override
  String get tabProduct => 'Produkt';

  @override
  String get tabOpportunity => 'Chance';

  @override
  String get tabStock => 'Bestand';

  @override
  String get tabArticle => 'Artikel';

  @override
  String get tabContract => 'Vertrag';

  @override
  String get tabCount => 'Inventur';

  @override
  String get workspaceOverview => 'Übersicht';

  @override
  String get openTabs => 'Offene Tabs';

  @override
  String get closeTab => 'Tab schließen';

  @override
  String get openInNewTab => 'In neuem Tab öffnen';

  @override
  String get unsavedChangesTitle => 'Ungespeicherte Änderungen';

  @override
  String get unsavedChangesBody =>
      'Dieser Tab hat ungespeicherte Änderungen. Schließen und verwerfen?';

  @override
  String get discardChanges => 'Änderungen verwerfen';

  @override
  String get remarkProduction => 'Produktionshinweis';

  @override
  String get remarkProductionHelp => 'Intern, wird dem Kunden nie angezeigt';

  @override
  String get remarkCustomer => 'Kundenhinweis';

  @override
  String get remarkCustomerHelp =>
      'Wird auf Angebot und Auftragsbestätigung gedruckt';

  @override
  String get remarkHistory => 'Frühere Hinweise';

  @override
  String get remarkHistoryThisCustomer => 'Dieser Kunde';

  @override
  String get remarkHistoryThisLanguage => 'Diese Sprache';

  @override
  String get remarkHistoryAll => 'Alle';

  @override
  String get remarkHistoryEmpty => 'Keine früheren Hinweise zu diesem Produkt.';

  @override
  String remarkHistoryUsed(int count, String quotation) {
    return '$count-mal verwendet, zuletzt auf $quotation';
  }

  @override
  String get defaultProductionRemark => 'Standard-Produktionshinweis';

  @override
  String get optionsTab => 'Optionen';

  @override
  String get optionsIntro =>
      'Produkte, die zusammen mit diesem im Angebot angeboten werden. Eine erforderliche Option wird automatisch hinzugefügt.';

  @override
  String get optionsNone => 'Dieses Produkt hat keine Optionen.';

  @override
  String get optionAdd => 'Option hinzufügen';

  @override
  String get optionRequired => 'Erforderlich';

  @override
  String get optionQuantity => 'Menge pro Einheit';

  @override
  String get optionRemove => 'Option entfernen';

  @override
  String get optionsSaved => 'Optionen gespeichert.';

  @override
  String get optionsInvalidQuantity =>
      'Geben Sie für jede Option eine Menge größer als 0 ein.';

  @override
  String optionsChooseTitle(String product) {
    return 'Optionen für $product';
  }

  @override
  String get optionsChooseHelp =>
      'Erforderliche Optionen werden automatisch hinzugefügt. Haken Sie optionale Optionen zum Hinzufügen an.';

  @override
  String get optionsAddSelected => 'Hinzufügen';

  @override
  String get optionsSkip => 'Ohne optionale Optionen';

  @override
  String get optionLine => 'Option der Zeile darüber';

  @override
  String get configurator => 'Konfigurator';

  @override
  String get configurators => 'Konfiguratoren';

  @override
  String get configure => 'Konfigurieren';

  @override
  String get newConfiguration => 'Neue Konfiguration';

  @override
  String get savedConfigurations => 'Gespeicherte Konfigurationen';

  @override
  String cfgAddRow(String item) {
    return '$item hinzufügen';
  }

  @override
  String cfgAddRowToGroup(String group) {
    return 'Zeile zu $group hinzufügen';
  }

  @override
  String get cfgCalculated => 'Berechnet';

  @override
  String get cfgChangeCustomer => 'Anderer Kunde';

  @override
  String get cfgCreateQuotation => 'Angebot erstellen';

  @override
  String get cfgUpdateQuotation => 'Angebot aktualisieren';

  @override
  String get cfgDeleteConfirm =>
      'Diese Konfiguration löschen? Daraus erstellte Angebote bleiben erhalten.';

  @override
  String get cfgDeleteRow => 'Zeile löschen';

  @override
  String get cfgDuplicateRow => 'Zeile duplizieren';

  @override
  String get cfgDiscard => 'Verwerfen';

  @override
  String get cfgDiscardChanges => 'Nicht gespeicherte Änderungen verwerfen?';

  @override
  String cfgEach(String value) {
    return 'Je Element: $value';
  }

  @override
  String get cfgErrors => 'Fehler';

  @override
  String get cfgWarnings => 'Warnungen';

  @override
  String get cfgInfo => 'Information';

  @override
  String cfgEvalFailed(String message) {
    return 'Neuberechnung fehlgeschlagen: $message';
  }

  @override
  String get cfgInput => 'Eingabe';

  @override
  String get cfgIssues => 'Hinweise';

  @override
  String get cfgLines => 'Positionen';

  @override
  String get cfgWhy => 'Warum?';

  @override
  String get cfgInvalidNumber => 'Keine gültige Zahl';

  @override
  String get cfgNewerRevision =>
      'Eine neuere Revision dieses Konfigurators ist verfügbar.';

  @override
  String get cfgUpgrade => 'Aktualisieren';

  @override
  String get cfgNoConfigurations => 'Noch keine gespeicherten Konfigurationen.';

  @override
  String get cfgNoModels => 'Noch kein Konfigurator ist aktiv.';

  @override
  String get cfgNoCustomer => 'Kein Kunde';

  @override
  String get cfgNoIssues => 'Keine Hinweise.';

  @override
  String get cfgNoLines => 'Die Konfiguration ergibt noch keine Positionen.';

  @override
  String get cfgNotInCatalogue => 'Nicht im Produktkatalog';

  @override
  String get cfgPinned => 'Eigener Wert (fixiert)';

  @override
  String get cfgPricesNeedCustomer =>
      'Wählen Sie einen Kunden, um Preise zu sehen.';

  @override
  String get cfgQuoteBlocked =>
      'Beheben Sie die Fehler, bevor Sie ein Angebot erstellen.';

  @override
  String get cfgQuoteNeedsCustomer =>
      'Wählen Sie einen Kunden, bevor Sie ein Angebot erstellen.';

  @override
  String cfgQuoteCreated(String number) {
    return 'Angebot $number erstellt.';
  }

  @override
  String cfgQuoteUpdated(String number) {
    return 'Angebot $number aktualisiert.';
  }

  @override
  String cfgQuoteRevised(String number) {
    return 'Angebot $number: eine neue Revision wurde erstellt.';
  }

  @override
  String cfgResetToCalculated(String value) {
    return 'Auf berechneten Wert zurücksetzen ($value)';
  }

  @override
  String cfgStale(String value) {
    return 'Die Berechnung ergibt jetzt $value';
  }

  @override
  String cfgRevision(int revision) {
    return 'Revision $revision';
  }

  @override
  String cfgRule(String rule) {
    return 'Regel: $rule';
  }

  @override
  String get cfgSaved => 'Gespeichert.';

  @override
  String get cfgSelectLine =>
      'Wählen Sie eine Position, um ihre Herkunft zu sehen.';

  @override
  String get cfgSetForAll => 'Für alle Zeilen setzen…';

  @override
  String cfgSetForAllTitle(String column) {
    return '$column für alle Zeilen';
  }

  @override
  String get cfgStart => 'Starten';

  @override
  String get cfgUnsaved => 'Nicht gespeichert';

  @override
  String cfgNewerRevisionAvailable(int revision) {
    return 'Revision $revision verfügbar';
  }

  @override
  String get cfgbActivate => 'Aktivieren';

  @override
  String get cfgbActivateConfirm =>
      'Diesen Entwurf aktivieren? Der Vertrieb nutzt ihn für neue Konfigurationen; die aktive Revision wird veraltet.';

  @override
  String get cfgbActivated => 'Aktiviert.';

  @override
  String cfgbActivatedOn(String date) {
    return 'aktiviert am $date';
  }

  @override
  String get cfgbActivateModel => 'Verfügbar machen';

  @override
  String cfgbActivateRefused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Probleme',
      one: '1 Problem',
    );
    return 'Nicht aktiviert: $_temp0 zu lösen.';
  }

  @override
  String cfgbActiveRevision(int revision) {
    return 'aktiv: Revision $revision';
  }

  @override
  String get cfgbAddChild => 'Optionszeile hinzufügen';

  @override
  String get cfgbAddColumn => 'Spalte hinzufügen';

  @override
  String get cfgbAddComputed => 'Berechneten Wert hinzufügen';

  @override
  String get cfgbAddField => 'Feld hinzufügen';

  @override
  String get cfgbAddItemTable => 'Positionstabelle hinzufügen';

  @override
  String get cfgbAddOption => 'Option hinzufügen';

  @override
  String get cfgbAddRow => 'Zeile hinzufügen';

  @override
  String get cfgbAddRule => 'Ausgaberegel hinzufügen';

  @override
  String get cfgbAddSection => 'Abschnitt hinzufügen';

  @override
  String get cfgbAddTable => 'Tabelle hinzufügen';

  @override
  String get cfgbAddValidation => 'Prüfung hinzufügen';

  @override
  String get cfgbApply => 'Übernehmen';

  @override
  String cfgbChildRuleTitle(String id) {
    return 'Optionszeile $id';
  }

  @override
  String get cfgbCode => 'Produktcode (Formel)';

  @override
  String get cfgbCodeExpr => 'Formel';

  @override
  String get cfgbCodeHelp => 'z. B. \'BELT-M\' oder motor_code';

  @override
  String get cfgbCodeTemplate => 'Produktcode (Vorlage)';

  @override
  String get cfgbCodeTemplateHelp =>
      'Text mit Formeln in geschweiften Klammern, z. B. DRV- und dann motor_size in Klammern';

  @override
  String get cfgbColumn => 'Spalte';

  @override
  String get cfgbColumnName => 'Spalte';

  @override
  String get cfgbCommentTemplate => 'Kommentar (Vorlage)';

  @override
  String cfgbComputedOf(String scope) {
    return 'Berechnete Werte: $scope';
  }

  @override
  String cfgbComputedTitle(String name) {
    return 'Berechneter Wert $name';
  }

  @override
  String get cfgbConditions => 'Bedingungen';

  @override
  String get cfgbCreate => 'Anlegen';

  @override
  String get cfgbCsvExport => 'CSV exportieren';

  @override
  String get cfgbCsvImport => 'CSV importieren';

  @override
  String cfgbCsvImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen importiert.',
      one: '1 Zeile importiert.',
    );
    return '$_temp0';
  }

  @override
  String get cfgbCsvProblems => 'Die CSV-Datei wurde nicht importiert';

  @override
  String get cfgbDeactivateModel => 'Zurückziehen';

  @override
  String get cfgbDefault => 'Standardwert';

  @override
  String get cfgbDefaultExpr => 'Standardwert (Formel)';

  @override
  String get cfgbDefaultExprHelp => 'Statt eines festen Standardwerts';

  @override
  String get cfgbDescriptionTemplate => 'Beschreibung (Vorlage)';

  @override
  String get cfgbDesignTitle => 'Konfiguratoren gestalten';

  @override
  String get cfgbDimCurrent => 'Strom';

  @override
  String get cfgbDimension => 'Größe';

  @override
  String get cfgbDimLength => 'Länge';

  @override
  String get cfgbDimMass => 'Masse';

  @override
  String get cfgbDimPower => 'Leistung';

  @override
  String get cfgbDimSpeed => 'Geschwindigkeit';

  @override
  String get cfgbDimVoltage => 'Spannung';

  @override
  String get cfgbDiscard => 'Verwerfen';

  @override
  String get cfgbDisplayUnits => 'Anzeigeeinheiten:';

  @override
  String cfgbDraftRevision(int revision) {
    return 'Entwurf: Revision $revision';
  }

  @override
  String get cfgbEditDraft => 'Entwurf bearbeiten';

  @override
  String get cfgbEnabledIf => 'Aktiv wenn';

  @override
  String cfgbExported(String name) {
    return '$name gespeichert.';
  }

  @override
  String get cfgbExportJson => 'JSON exportieren';

  @override
  String get cfgbExpr => 'Formel';

  @override
  String get cfgbFamily => 'Produktfamilie (Code)';

  @override
  String cfgbFieldsOf(String scope) {
    return 'Felder: $scope';
  }

  @override
  String cfgbFieldTitle(String name) {
    return 'Feld $name';
  }

  @override
  String get cfgbForEach => 'Für jedes';

  @override
  String get cfgbForEachHelp =>
      'Eine Liste: eine Zeile pro Element, mit each und each_index';

  @override
  String cfgbFormulaType(String type) {
    return 'Ergebnis: $type';
  }

  @override
  String get cfgbGroupField => 'Gruppieren nach Feld';

  @override
  String get cfgbGroupHelp =>
      'Eine Gruppe ist ein Abschnitt von Zeilen (z. B. eine Halle): eine pro Wert des Gruppierungsfelds einer Positionstabelle. Gruppenfelder mit dem Namen eines Projektfelds überschreiben dieses in der Gruppe.';

  @override
  String get cfgbGroupLabel => 'Name einer Gruppe';

  @override
  String get cfgbHelp => 'Hilfetext';

  @override
  String get cfgbId => 'Id';

  @override
  String get cfgbImported =>
      'In den Editor importiert; speichern, um es zu behalten.';

  @override
  String cfgbImportFailed(String message) {
    return 'Nicht importiert: $message';
  }

  @override
  String get cfgbImportJson => 'JSON importieren';

  @override
  String get cfgbImportNotExport => 'Diese Datei ist kein Konfigurator-Export.';

  @override
  String cfgbImportReplace(String name) {
    return 'Die gesamte Definition dieses Entwurfs durch $name ersetzen?';
  }

  @override
  String get cfgbInactive => 'für den Vertrieb nicht verfügbar';

  @override
  String get cfgbItemLabel => 'Positionsbezeichnung (Vorlage)';

  @override
  String get cfgbItemLabelHelp =>
      'Benennt eine Zeile in Kommentaren und Meldungen; Formeln in geschweiften Klammern, z. B. group_name und index';

  @override
  String get cfgbItemTable => 'Positionstabelle';

  @override
  String get cfgbKeys => 'Schlüsselspalten:';

  @override
  String get cfgbKindExact => 'Exakt';

  @override
  String get cfgbKindRange => 'Bereich';

  @override
  String get cfgbLabel => 'Bezeichnung';

  @override
  String get cfgbLayout => 'Layout';

  @override
  String get cfgbLayoutSections => 'Formularabschnitte';

  @override
  String get cfgbLayoutSectionsHelp =>
      'Felder nennen in ihrem Layout einen Abschnitt; das Formular zeigt sie unter dessen Überschrift.';

  @override
  String get cfgbMax => 'Maximum';

  @override
  String get cfgbMaxLength => 'Maximale Länge';

  @override
  String get cfgbMaxRows => 'Maximale Zeilen';

  @override
  String get cfgbMergeIdentical => 'Gleiche Zeilen zusammenfassen';

  @override
  String get cfgbMergeIdenticalHelp =>
      'Zeilen mit gleichem Code werden eine; der Kommentar nennt die Positionen';

  @override
  String get cfgbMessage => 'Meldung (Vorlage)';

  @override
  String get cfgbMin => 'Minimum';

  @override
  String get cfgbMinRows => 'Minimale Zeilen';

  @override
  String get cfgbMoveDown => 'Nach unten';

  @override
  String get cfgbMoveUp => 'Nach oben';

  @override
  String get cfgbNewDraft => 'Neuer Entwurf aus der aktiven Revision';

  @override
  String get cfgbNewDraftFromThis => 'Neuer Entwurf aus dieser Revision';

  @override
  String get cfgbNewModel => 'Neuer Konfigurator';

  @override
  String get cfgbNoProblems => 'Keine Probleme';

  @override
  String get cfgbOnMissing => 'Wenn keine Zeile passt';

  @override
  String get cfgbOnMissingClamp => 'Nächsthöhere Zeile';

  @override
  String get cfgbOnMissingHelp =>
      'Nächsthöhere Zeile: Ein Wert unter oder zwischen den Bereichen nimmt die Zeile mit dem nächsthöheren Bereich, ein Wert über allen Bereichen die letzte Zeile; ein Versatz über ein Ende hinaus stoppt bei der ersten oder letzten Zeile.';

  @override
  String get cfgbOnMissingError => 'Fehler';

  @override
  String get cfgbOnMissingNull => 'Kein Wert';

  @override
  String get cfgbOptionsFamily => 'Produktfamilie';

  @override
  String get cfgbOptionsFrom => 'Erlaubte Alternativen (Formel)';

  @override
  String get cfgbOptionsFromHelp =>
      'Eine Liste, aus der der Benutzer statt des berechneten Werts wählen kann';

  @override
  String get cfgbOptionsStatic => 'Feste Liste';

  @override
  String get cfgbOptionsTable => 'Tabellenspalte';

  @override
  String get cfgbOrder => 'Reihenfolge';

  @override
  String get cfgbOutputRules => 'Ausgaberegeln';

  @override
  String get cfgbOverridable => 'Der Benutzer darf ihn überschreiben';

  @override
  String get cfgbOverridableHelp =>
      'Angezeigt als berechnet, fixiert oder fixiert aber veraltet';

  @override
  String get cfgbPattern => 'Muster (regulärer Ausdruck)';

  @override
  String get cfgbPercentBase => 'Prozentsatz von';

  @override
  String get cfgbPercentBaseList => 'dem Listenpreis der Hauptzeile';

  @override
  String get cfgbPercentBaseNet => 'dem Nettopreis der Hauptzeile';

  @override
  String get cfgbPercentOfParent => 'Prozent der Hauptzeile (Formel)';

  @override
  String get cfgbPercentOfParentHelp =>
      'Bepreist die Zeile mit diesem Prozentsatz der Hauptzeile, z. B. 20';

  @override
  String cfgbProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Probleme',
      one: '1 Problem',
    );
    return '$_temp0';
  }

  @override
  String get cfgbProductFilter => 'Produktfilter (Formel auf p)';

  @override
  String get cfgbProductFilterHelp => 'z. B. p.attr(\'kw\') >= 1';

  @override
  String get cfgbQuantity => 'Menge (Formel)';

  @override
  String get cfgbQuantityHelp =>
      'Standard 1; null oder weniger lässt die Zeile weg';

  @override
  String get cfgbRangeKey => 'Bereichsschlüssel';

  @override
  String get cfgbRangeKeyHelp => 'Der Suchschlüssel mit dem Wert';

  @override
  String get cfgbRangeMax => 'Maximumspalte';

  @override
  String get cfgbRangeMin => 'Minimumspalte';

  @override
  String get cfgbRawJson => 'Definition als JSON';

  @override
  String get cfgbRemoveColumn => 'Spalte entfernen';

  @override
  String get cfgbRemoveItemTable => 'Positionstabelle entfernen';

  @override
  String get cfgbRemoveRow => 'Zeile entfernen';

  @override
  String get cfgbReplace => 'Ersetzen';

  @override
  String get cfgbRequired => 'Pflichtfeld';

  @override
  String get cfgbRevisions => 'Revisionen';

  @override
  String cfgbRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen',
      one: '1 Zeile',
    );
    return '$_temp0';
  }

  @override
  String cfgbRuleTitle(String id) {
    return 'Ausgaberegel $id';
  }

  @override
  String get cfgbSavedValid =>
      'Gespeichert. Der Entwurf kann aktiviert werden.';

  @override
  String cfgbSavedWithProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Problemen',
      one: '1 Problem',
    );
    return 'Gespeichert mit $_temp0.';
  }

  @override
  String get cfgbScope => 'Ebene';

  @override
  String get cfgbScopeGroup => 'Gruppe';

  @override
  String get cfgbScopeItem => 'Position (Zeile)';

  @override
  String cfgbScopeItems(String table) {
    return 'Positionen: $table';
  }

  @override
  String get cfgbScopeProject => 'Projekt';

  @override
  String get cfgbScopes => 'Ebenen';

  @override
  String get cfgbSection => 'Abschnitt';

  @override
  String get cfgbSectionTemplate => 'Abschnitt (Vorlage)';

  @override
  String get cfgbSectionTemplateHelp =>
      'Standard: der Gruppenname bei Gruppen- und Positionsregeln';

  @override
  String get cfgbSelectComputed =>
      'Wählen Sie einen berechneten Wert oder fügen Sie einen hinzu.';

  @override
  String get cfgbSelectField =>
      'Wählen Sie ein Feld oder fügen Sie eines hinzu.';

  @override
  String get cfgbSelectRule =>
      'Wählen Sie eine Ausgaberegel oder fügen Sie eine hinzu.';

  @override
  String get cfgbSelectTable =>
      'Wählen Sie eine Tabelle oder fügen Sie eine hinzu.';

  @override
  String get cfgbSelectValidation =>
      'Wählen Sie eine Prüfung oder fügen Sie eine hinzu.';

  @override
  String get cfgbSeverity => 'Schweregrad';

  @override
  String get cfgbSeverityError => 'Fehler';

  @override
  String get cfgbSeverityInfo => 'Information';

  @override
  String get cfgbSeverityWarning => 'Warnung';

  @override
  String get cfgbShow => 'Für den Benutzer sichtbar';

  @override
  String get cfgbShownAt => 'Angezeigt bei Feld';

  @override
  String get cfgbStatusActive => 'aktiv';

  @override
  String get cfgbStatusDraft => 'Entwurf';

  @override
  String get cfgbStatusObsolete => 'veraltet';

  @override
  String get cfgbStep => 'Schritt';

  @override
  String get cfgbTabComputed => 'Berechnete Werte';

  @override
  String get cfgbTabFields => 'Felder & Layout';

  @override
  String get cfgbTabGeneral => 'Allgemein';

  @override
  String get cfgbTable => 'Tabelle';

  @override
  String get cfgbTableKind => 'Art';

  @override
  String get cfgbTables => 'Nachschlagetabellen';

  @override
  String cfgbTableTitle(String name) {
    return 'Tabelle $name';
  }

  @override
  String get cfgbTabOutputs => 'Ausgaberegeln';

  @override
  String get cfgbTabTables => 'Tabellen';

  @override
  String get cfgbTabTest => 'Testen';

  @override
  String get cfgbTabTransfer => 'Import/Export';

  @override
  String get cfgbTabValidations => 'Prüfungen';

  @override
  String get cfgbTestHelp =>
      'Testen Sie den gespeicherten Entwurf, wie der Vertrieb ihn sieht. Nichts wird gespeichert; wählen Sie eine Zeile, um zu sehen, warum sie da ist.';

  @override
  String get cfgbTestNeedsValid =>
      'Der gespeicherte Entwurf hat Probleme; der Test kann fehlschlagen, bis sie gelöst sind.';

  @override
  String get cfgbTestReset => 'Neu beginnen';

  @override
  String get cfgbTestUnsaved =>
      'Der Test verwendet den gespeicherten Entwurf; speichern Sie, um Ihre letzten Änderungen einzubeziehen.';

  @override
  String get cfgbTranslations => 'Übersetzungen';

  @override
  String get cfgbTypeBoolean => 'Ja/Nein';

  @override
  String get cfgbTypeChoice => 'Auswahl';

  @override
  String get cfgbTypeInteger => 'Ganzzahl';

  @override
  String get cfgbTypeNumber => 'Zahl';

  @override
  String get cfgbTypeProduct => 'Produkt';

  @override
  String get cfgbTypeText => 'Text';

  @override
  String get cfgbUnsavedText => 'Der Entwurf hat ungespeicherte Änderungen.';

  @override
  String get cfgbUnsavedTitle => 'Ungespeicherte Änderungen';

  @override
  String get cfgbValidations => 'Prüfungen';

  @override
  String cfgbValidationTitle(String id) {
    return 'Prüfung $id';
  }

  @override
  String get cfgbValidationWhenHelp => 'Wenn wahr, wird die Meldung angezeigt';

  @override
  String get cfgbValue => 'Wert';

  @override
  String get cfgbVisibleIf => 'Sichtbar wenn';

  @override
  String get cfgbWhen => 'Wenn';

  @override
  String get cfgbWhenHelp => 'Zeilen entstehen nur, wenn dies wahr ist';

  @override
  String get cfgbWidth => 'Breite';

  @override
  String get tabProductionOrder => 'Fertigungsauftrag';

  @override
  String get tabDeliveryNote => 'Lieferschein';

  @override
  String get vatRegime => 'MwSt.-Regime';

  @override
  String get vatRegimeDomestic => 'EU-Kunde, MwSt. berechnet';

  @override
  String get vatRegimeIntraEu => 'EU-Unternehmen, Reverse Charge';

  @override
  String get vatRegimeOutsideEu => 'Außerhalb der EU, keine MwSt.';

  @override
  String get addSubItem => 'Unterposition hinzufügen';

  @override
  String subItemsOptions(String product) {
    return 'Optionen von $product';
  }

  @override
  String get subItemsNoOptions => 'Dieses Produkt hat keine Optionen.';

  @override
  String get subItemsOtherProducts => 'Andere Produkte';

  @override
  String get crTitle => 'Berichte';

  @override
  String get crNew => 'Neuer Bericht';

  @override
  String get crEmpty =>
      'Noch keine Berichte. Erstellen Sie einen, um Ihre Daten zu gruppieren und zu summieren.';

  @override
  String get crShared => 'Geteilt';

  @override
  String get crPrivate => 'Privat';

  @override
  String get crShare => 'Mit allen im Unternehmen teilen';

  @override
  String crOwnedBy(String name) {
    return 'Von $name';
  }

  @override
  String get crObject => 'Bericht über';

  @override
  String get crJoin => 'Verknüpfte Daten hinzufügen';

  @override
  String get crGroupBy => 'Gruppieren nach';

  @override
  String get crAddGrouping => 'Gruppierung hinzufügen';

  @override
  String get crColumns => 'Spalten';

  @override
  String get crAddColumn => 'Spalte hinzufügen';

  @override
  String get crField => 'Feld';

  @override
  String get crSummary => 'Zusammenfassung';

  @override
  String get crSummaryNone => 'Wert anzeigen';

  @override
  String get crSumCount => 'Anzahl';

  @override
  String get crSumSum => 'Summe';

  @override
  String get crSumAvg => 'Durchschnitt';

  @override
  String get crSumMin => 'Minimum';

  @override
  String get crSumMax => 'Maximum';

  @override
  String get crFilters => 'Filter';

  @override
  String get crAddFilter => 'Filter hinzufügen';

  @override
  String get crMatchAll => 'Alle Filter müssen zutreffen';

  @override
  String get crMatchAny => 'Mindestens ein Filter muss zutreffen';

  @override
  String get crOpEq => 'ist gleich';

  @override
  String get crOpNe => 'ist ungleich';

  @override
  String get crOpGt => 'größer als';

  @override
  String get crOpGte => 'mindestens';

  @override
  String get crOpLt => 'kleiner als';

  @override
  String get crOpLte => 'höchstens';

  @override
  String get crOpContains => 'enthält';

  @override
  String get crOpStartsWith => 'beginnt mit';

  @override
  String get crOpIn => 'ist eines von';

  @override
  String get crOpIsNull => 'ist leer';

  @override
  String get crOpNotNull => 'ist nicht leer';

  @override
  String get crValue => 'Wert';

  @override
  String get crValueListHint => 'Werte durch Kommas trennen';

  @override
  String get crBucketNone => 'Genauer Wert';

  @override
  String get crBucketDay => 'Pro Tag';

  @override
  String get crBucketMonth => 'Pro Monat';

  @override
  String get crBucketYear => 'Pro Jahr';

  @override
  String get crSort => 'Sortieren';

  @override
  String get crAddSort => 'Sortierung hinzufügen';

  @override
  String get crDescending => 'Absteigend';

  @override
  String get crChart => 'Diagramm';

  @override
  String get crChartNone => 'Kein Diagramm';

  @override
  String get crChartBar => 'Balken';

  @override
  String get crChartLine => 'Linie';

  @override
  String get crChartPie => 'Kreis';

  @override
  String get crChartX => 'Kategorien';

  @override
  String get crChartY => 'Werte';

  @override
  String crRows(int count) {
    return '$count Zeilen';
  }

  @override
  String crRowsShown(int shown, int total) {
    return '$shown von $total Zeilen angezeigt';
  }

  @override
  String crChartShareShown(int count) {
    return 'Die Anteile beziehen sich auf die $count angezeigten Gruppen.';
  }

  @override
  String get crSaved => 'Bericht gespeichert';

  @override
  String get crDeleted => 'Bericht gelöscht';

  @override
  String get crDelete => 'Löschen';

  @override
  String get crDeleteConfirm => 'Diesen Bericht löschen?';

  @override
  String get crExportCsv => 'CSV exportieren';

  @override
  String get crExportPdf => 'PDF exportieren';

  @override
  String get crNeedName => 'Geben Sie dem Bericht einen Namen.';

  @override
  String get crNeedColumn => 'Fügen Sie mindestens eine Spalte hinzu.';

  @override
  String get crLoadMore => 'Weitere Zeilen anzeigen';

  @override
  String get crNoRows => 'Keine Zeilen für diesen Bericht.';

  @override
  String get crRun => 'Ausführen';

  @override
  String get crDateMode => 'Datum';

  @override
  String get crDateFixed => 'Festes Datum';

  @override
  String get crDateRelative => 'Relativ zu heute';

  @override
  String get crRelativePeriod => 'Zeitraum';

  @override
  String get crRelativeDays => 'Anzahl Tage';

  @override
  String get crRelativeDaysInvalid =>
      'Geben Sie eine ganze Zahl von Tagen zwischen 1 und 3660 ein.';

  @override
  String get crRelToday => 'Heute';

  @override
  String get crRelYesterday => 'Gestern';

  @override
  String get crRelThisWeek => 'Diese Woche';

  @override
  String get crRelLastWeek => 'Letzte Woche';

  @override
  String get crRelThisMonth => 'Dieser Monat';

  @override
  String get crRelLastMonth => 'Letzter Monat';

  @override
  String get crRelThisQuarter => 'Dieses Quartal';

  @override
  String get crRelLastQuarter => 'Letztes Quartal';

  @override
  String get crRelThisYear => 'Dieses Jahr';

  @override
  String get crRelLastYear => 'Letztes Jahr';

  @override
  String get crRelLastNDays => 'Letzte N Tage';

  @override
  String get crRelNextNDays => 'Nächste N Tage';

  @override
  String get envLive => 'Live';

  @override
  String get envTest => 'Test';

  @override
  String get envTutorial => 'Tutorial';

  @override
  String envBannerSemantics(String name, String kind) {
    return 'Umgebung $name, $kind';
  }

  @override
  String get envSwitcherTitle => 'Umgebungen';

  @override
  String envSwitchMenu(String name) {
    return 'Umgebung: $name';
  }

  @override
  String get envSwitchTooltip => 'Umgebung wechseln';

  @override
  String get envActive => 'Aktiv';

  @override
  String get envAdd => 'Umgebung hinzufügen';

  @override
  String get envName => 'Name';

  @override
  String get envServerUrl => 'Serveradresse';

  @override
  String get envCheck => 'Server prüfen';

  @override
  String envDetected(String kind, String db) {
    return 'Der Server meldet: $kind-Umgebung, Datenbank $db';
  }

  @override
  String get envInvalidUrl =>
      'Geben Sie eine vollständige Adresse ein, z. B. https://erp.example.com';

  @override
  String get envAlreadyListed => 'Dieser Server ist bereits in der Liste.';

  @override
  String envUnreachable(String error) {
    return 'Die Umgebung dieses Servers konnte nicht gelesen werden: $error';
  }

  @override
  String get envRemove => 'Entfernen';

  @override
  String get envRemoveTitle => 'Umgebung entfernen?';

  @override
  String envRemoveBody(String name) {
    return '$name wird von diesem Gerät entfernt, samt gespeicherter Anmeldung. Auf dem Server ändert sich nichts.';
  }

  @override
  String get envCannotRemoveActive =>
      'Wechseln Sie zuerst zu einer anderen Umgebung';

  @override
  String envUnsavedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offene Tabs haben nicht gespeicherte Änderungen',
      one: '1 offener Tab hat nicht gespeicherte Änderungen',
    );
    return '$_temp0. Beim Wechsel der Umgebung werden alle Tabs geschlossen und diese Änderungen verworfen.';
  }

  @override
  String get envDiscardAndSwitch => 'Verwerfen und wechseln';

  @override
  String get adminPriceZones => 'Preiszonen';

  @override
  String get newPriceZone => 'Neue Preiszone';

  @override
  String get editPriceZone => 'Preiszone bearbeiten';

  @override
  String get sortOrder => 'Sortierreihenfolge';

  @override
  String get noPriceZones => 'Noch keine Preiszonen.';

  @override
  String get priceZoneDeleted => 'Preiszone gelöscht';

  @override
  String get delete => 'Löschen';

  @override
  String deletePriceZoneConfirm(String code) {
    return 'Preiszone $code löschen? Abgelehnt, wenn Preise oder Kunden sie verwenden.';
  }

  @override
  String get sortOrderInvalid =>
      'Die Sortierreihenfolge muss eine ganze Zahl sein.';

  @override
  String get envNotSaved =>
      'Erledigt, aber die Liste der Umgebungen konnte auf diesem Gerät nicht gespeichert werden.';

  @override
  String get tutTitle => 'Tutorial';

  @override
  String get tutBack => 'Zurück';

  @override
  String get tutNext => 'Weiter';

  @override
  String get tutSkipStep => 'Schritt überspringen';

  @override
  String get tutPause => 'Pausieren';

  @override
  String get tutResume => 'Fortsetzen';

  @override
  String get tutPaused => 'Tutorial pausiert';

  @override
  String get tutTakeMe => 'Dorthin gehen';

  @override
  String tutStepOf(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String get tutOfferTitle => 'Willkommen bei TradoCraft';

  @override
  String get tutOfferBody =>
      'Dies ist eine Tutorial-Umgebung. Möchten Sie eine geführte Tour, die Ihnen die App Schritt für Schritt mit Übungsdaten zeigt?';

  @override
  String get tutOfferStart => 'Tutorial starten';

  @override
  String get tutOfferLater => 'Nicht jetzt';

  @override
  String get tutLiveTitle => 'Das Tutorial läuft nicht mit Live-Daten';

  @override
  String get tutLiveBody =>
      'Das Tutorial legt Datensätze an und läuft daher nur in einer Test- oder Tutorial-Umgebung. Wechseln Sie in eine solche oder fügen Sie eine hinzu.';

  @override
  String get tutSwitchEnv => 'Umgebung wechseln';

  @override
  String get tutAddEnv => 'Umgebung hinzufügen';

  @override
  String get tutMapIntro =>
      'Arbeiten Sie die Kapitel der Reihe nach durch. Sie können ein Kapitel jederzeit pausieren, wiederholen oder überspringen.';

  @override
  String get tutStatusDone => 'Erledigt';

  @override
  String get tutStatusCurrent => 'Als Nächstes';

  @override
  String get tutStatusLocked => 'Gesperrt';

  @override
  String get tutStatusSkipped => 'Übersprungen';

  @override
  String get tutStatusPaused => 'In Arbeit';

  @override
  String get tutStart => 'Starten';

  @override
  String get tutReplay => 'Wiederholen';

  @override
  String get tutSkipChapter => 'Kapitel überspringen';

  @override
  String get tutWelcomeTitle => 'Willkommen';

  @override
  String get tutWelcomeSummary =>
      'Orientierung: das Umgebungsband, die Tabs und die Tutorial-Steuerung.';

  @override
  String get tutProductTitle => 'Ihr erstes Produkt';

  @override
  String get tutProductSummary =>
      'Rolle: Produktmanager. Legen Sie drei Komponenten, ein Fertigprodukt und seine Stückliste an.';

  @override
  String get tutWelcomeBannerTitle => 'Das Band oben';

  @override
  String get tutWelcomeBannerBody =>
      'Dieses Band zeigt immer, in welcher Umgebung Sie sind: Name und Art. Gelb steht für Test, Blau für Tutorial und Rot für Live-Daten. Das Tutorial läuft nur in Test- und Tutorial-Umgebungen, nichts davon berührt echte Daten.';

  @override
  String get tutWelcomeTabsTitle => 'Tabs und Bereiche';

  @override
  String get tutWelcomeTabsBody =>
      'Die Bereiche stehen links (auf dem Telefon in der unteren Leiste). Wenn Sie einen Datensatz öffnen, etwa ein Produkt oder ein Angebot, kommt ein Tab im Arbeitsbereich hinzu, so können Sie mehrere Datensätze offen halten.';

  @override
  String get tutWelcomeControlsTitle => 'Diese Karte';

  @override
  String get tutWelcomeControlsBody =>
      'Ich bin Ihr Erzähler. „Weiter“ geht weiter, wenn ein Schritt nur eine Erklärung ist. Schritte, in denen Sie etwas tun sollen, sind von selbst erledigt, sobald Sie es getan haben. Mit „Zurück“ und „Schritt überspringen“ bewegen Sie sich frei, „Pausieren“ blendet mich bis „Fortsetzen“ aus.';

  @override
  String get tutWelcomeMenuTitle => 'Wo Sie mich finden';

  @override
  String get tutWelcomeMenuBody =>
      'Öffnen Sie das Kontomenü, dort finden Sie den Eintrag Tutorial. Er öffnet die Kapitelübersicht, in der Sie ein Kapitel jederzeit fortsetzen, wiederholen oder überspringen können.';

  @override
  String get tutWelcomeProductsTitle => 'Fangen wir an';

  @override
  String get tutWelcomeProductsBody =>
      'Öffnen Sie den Bereich Produkte. Das nächste Kapitel beginnt dort.';

  @override
  String get tutProductOpenTitle => 'Produkte';

  @override
  String get tutProductOpenBody =>
      'Heute sind Sie der Produktmanager. Alles, was die Firma verkauft oder baut, ist ein Produkt. Öffnen Sie den Bereich Produkte.';

  @override
  String get tutProductMotorTitle => 'Komponente: Motor';

  @override
  String get tutProductMotorBody =>
      'Legen Sie die erste Komponente an. Wählen Sie Neues Produkt, geben Sie Code TUT-MOTOR und Name Motor ein, lassen Sie den Typ auf Gekauft und speichern Sie.';

  @override
  String get tutProductMotorHint =>
      'Das Präfix TUT- kennzeichnet Tutorial-Daten, damit Sie sie später erkennen.';

  @override
  String get tutProductFrameTitle => 'Komponente: Frame';

  @override
  String get tutProductFrameBody =>
      'Legen Sie auf die gleiche Weise eine zweite Komponente an: Code TUT-FRAME, Name Frame, Typ Gekauft.';

  @override
  String get tutProductControllerTitle => 'Komponente: Controller';

  @override
  String get tutProductControllerBody =>
      'Und eine dritte: Code TUT-CTRL, Name Controller, Typ Gekauft.';

  @override
  String get tutProductCartTitle => 'Das Fertigprodukt';

  @override
  String get tutProductCartBody =>
      'Nun das Produkt, das Sie aus diesen Teilen bauen. Legen Sie Code TUT-CART, Name Cart an und wählen Sie den Typ Eigenfertigung: nur selbst gefertigte Produkte haben eine Stückliste.';

  @override
  String get tutProductOpenCartTitle => 'Cart öffnen';

  @override
  String get tutProductOpenCartBody =>
      'Öffnen Sie das neue Produkt Cart aus der Liste, um seine Tabs zu sehen.';

  @override
  String get tutProductBomTabTitle => 'Stückliste';

  @override
  String get tutProductBomTabBody =>
      'Wählen Sie den Tab Stückliste. Er listet die Komponenten, die für eine Einheit nötig sind. Eine Revision ist ein Entwurf, den Sie bearbeiten, oder die aktive, die die Fertigung verwendet. Drücken Sie Weiter, wenn Sie dort sind.';

  @override
  String get tutProductRevisionTitle => 'Eine erste Revision';

  @override
  String get tutProductRevisionBody =>
      'Wählen Sie Neue Revision, um einen Entwurf zu beginnen.';

  @override
  String get tutProductLinesTitle => 'Komponenten hinzufügen';

  @override
  String get tutProductLinesBody =>
      'Suchen Sie jede Komponente und fügen Sie sie hinzu: Motor, Frame und Controller. Drücken Sie dann Entwurf speichern.';

  @override
  String get tutProductLinesHint =>
      'Geben Sie TUT ins Suchfeld ein, um die drei Komponenten zu finden.';

  @override
  String get tutProductActivateTitle => 'Aktivieren';

  @override
  String get tutProductActivateBody =>
      'Drücken Sie Aktivieren. Ab jetzt verwenden Fertigung und Angebote diese Revision; spätere Änderungen laufen über eine neue Revision.';

  @override
  String get tutProductDoneTitle => 'Gut gemacht';

  @override
  String get tutProductDoneBody =>
      'Sie haben ein Fertigprodukt mit einer Stückliste aus drei Komponenten. Spätere Kapitel bauen darauf auf.';

  @override
  String get purchasing => 'Einkauf';

  @override
  String get tabSupplier => 'Lieferant';

  @override
  String get purchSuppliers => 'Lieferanten';

  @override
  String get purchNewSupplier => 'Neuer Lieferant';

  @override
  String get purchPaymentTerms => 'Zahlungsziel';

  @override
  String purchDays(int count) {
    return '$count Tage';
  }

  @override
  String get purchActiveOnly => 'Nur aktive';

  @override
  String get purchNameRequired => 'Der Name ist erforderlich.';

  @override
  String get purchCountryInvalid => 'Das Land muss ein 2-Buchstaben-Code sein.';

  @override
  String get purchCurrencyInvalid =>
      'Die Währung muss ein 3-Buchstaben-Code sein.';

  @override
  String get purchTermsInvalid =>
      'Das Zahlungsziel muss eine ganze Zahl von Tagen sein.';

  @override
  String get purchInactive => 'Inaktiv';

  @override
  String get purchPriceList => 'Preisliste';

  @override
  String get purchAddProduct => 'Produkt hinzufügen';

  @override
  String get purchEditPrice => 'Preis ändern';

  @override
  String get purchNoPrices => 'Noch keine Produkte in dieser Preisliste.';

  @override
  String get purchPickProduct => 'Wählen Sie ein Produkt.';

  @override
  String get purchPriceInvalid => 'Geben Sie einen gültigen Stückpreis ein.';

  @override
  String get purchMoqInvalid =>
      'Geben Sie eine gültige Mindestbestellmenge ein.';

  @override
  String get purchLeadInvalid =>
      'Die Lieferzeit muss eine ganze Zahl von Tagen sein.';

  @override
  String get purchSupplierArticleCode => 'Artikelnummer des Lieferanten';

  @override
  String get purchSupplierArticleName => 'Artikelbezeichnung des Lieferanten';

  @override
  String get purchMoq => 'Mindestbestellmenge';

  @override
  String get purchLeadTimeDays => 'Lieferzeit (Tage)';

  @override
  String get purchPreferred => 'Bevorzugter Lieferant';

  @override
  String purchRemoveProductConfirm(String code) {
    return '$code aus dieser Preisliste entfernen?';
  }

  @override
  String purchMoqValue(String qty) {
    return 'MBM $qty';
  }

  @override
  String purchLeadValue(int days) {
    return 'Lieferzeit $days T';
  }

  @override
  String get purchNoSuppliers => 'Keine Lieferanten gefunden.';

  @override
  String get purchOrders => 'Bestellungen';

  @override
  String get purchNewOrder => 'Neue Bestellung';

  @override
  String get purchNoOrders => 'Keine Bestellungen gefunden.';

  @override
  String get purchOrderNumber => 'Nummer';

  @override
  String get purchSupplier => 'Lieferant';

  @override
  String get purchAllSuppliers => 'Alle Lieferanten';

  @override
  String get purchOrderDate => 'Bestelldatum';

  @override
  String get purchExpectedDate => 'Gewünschter Liefertermin';

  @override
  String get purchStatusDraft => 'Entwurf';

  @override
  String get purchStatusApproved => 'genehmigt';

  @override
  String get purchStatusSent => 'gesendet';

  @override
  String get purchStatusPartial => 'teilweise erhalten';

  @override
  String get purchStatusReceived => 'erhalten';

  @override
  String get purchStatusCancelled => 'storniert';

  @override
  String get purchLines => 'Positionen';

  @override
  String get purchAddLine => 'Position hinzufügen';

  @override
  String get purchPickSupplier => 'Wählen Sie einen Lieferanten.';

  @override
  String get purchLineQtyInvalid =>
      'Die Menge muss größer als null sein, mit höchstens 4 Dezimalstellen.';

  @override
  String get purchLinePriceInvalid =>
      'Der Stückpreis muss null oder größer sein, mit höchstens 4 Dezimalstellen.';

  @override
  String get purchNeedLine => 'Fügen Sie mindestens eine Position hinzu.';

  @override
  String get purchApprove => 'Genehmigen';

  @override
  String get purchCancelOrder => 'Bestellung stornieren';

  @override
  String purchCancelOrderConfirm(String number) {
    return 'Bestellung $number stornieren? Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get purchKeepOrder => 'Bestellung behalten';

  @override
  String get purchQtyReceived => 'Erhalten';

  @override
  String get purchLineTotal => 'Positionssumme';

  @override
  String get purchSubtotal => 'Zwischensumme';

  @override
  String get purchTax => 'MwSt.';

  @override
  String get tabPurchaseOrder => 'Bestellung';

  @override
  String get purchReceiveGoods => 'Ware annehmen';

  @override
  String purchReceiveTitle(String number) {
    return 'Ware für $number annehmen';
  }

  @override
  String get purchReceiveDestination => 'Ziellagerplatz';

  @override
  String get purchReceiveQty => 'Anzunehmende Menge';

  @override
  String purchReceiveRemaining(String qty) {
    return 'Offen: $qty';
  }

  @override
  String get purchReceiveSerialsHelp => 'Eine Seriennummer pro Zeile';

  @override
  String get purchDeliveryNote => 'Lieferschein des Lieferanten';

  @override
  String purchReceiveQtyInvalid(String product, String max) {
    return '$product: Menge zwischen 0 und $max eingeben.';
  }

  @override
  String purchReceiveLotNeeded(String product) {
    return '$product: Chargennummer eingeben.';
  }

  @override
  String purchReceiveSerialWhole(String product) {
    return '$product: Die Menge muss eine ganze Zahl sein.';
  }

  @override
  String purchReceiveSerialCount(String product, int count) {
    return '$product: genau $count verschiedene Seriennummern eingeben.';
  }

  @override
  String get purchReceiveNothing =>
      'Für mindestens eine Position eine Menge eingeben.';

  @override
  String get purchReceiveLocationNeeded => 'Ziellagerplatz wählen.';

  @override
  String purchReceiptBooked(String number) {
    return 'Wareneingang $number gebucht.';
  }

  @override
  String get purchOpenReceipt => 'Wareneingang öffnen';

  @override
  String get purchReceipts => 'Wareneingänge';

  @override
  String get purchReceivedDate => 'Erhalten';

  @override
  String get purchOpenOrder => 'Bestellung';

  @override
  String get tabGoodsReceipt => 'Wareneingang';

  @override
  String get setupTitle => 'Neues Unternehmen einrichten';

  @override
  String get setupOffer => 'Neues Unternehmen einrichten';

  @override
  String get setupOfferHint => 'Dieser Server hat noch kein Unternehmen.';

  @override
  String setupServer(String url) {
    return 'Server: $url';
  }

  @override
  String setupStepOf(int n, int total) {
    return 'Schritt $n von $total';
  }

  @override
  String get setupStepCompany => 'Unternehmen';

  @override
  String get setupStepRegion => 'Land, Währung und Sprache';

  @override
  String get setupStepAdmin => 'Administrator';

  @override
  String get setupStepToken => 'Einrichtungstoken';

  @override
  String get setupStepReview => 'Überprüfung';

  @override
  String get setupCompanyName => 'Name des Unternehmens';

  @override
  String get setupLegalName => 'Rechtlicher Name (optional)';

  @override
  String get setupVatNumber => 'USt-IdNr. (optional)';

  @override
  String get setupCountry => 'Ländercode (2 Buchstaben, z. B. BE)';

  @override
  String get setupCurrency => 'Währung (3 Buchstaben, z. B. EUR)';

  @override
  String get setupLanguage => 'Standardsprache';

  @override
  String get setupAdminEmail => 'E-Mail des Administrators';

  @override
  String get setupAdminName => 'Name des Administrators';

  @override
  String get setupToken => 'Einrichtungstoken';

  @override
  String get setupTokenHelp => 'Der Wert von BOOTSTRAP_TOKEN auf dem Server.';

  @override
  String get setupErrName => 'Geben Sie den Namen des Unternehmens ein.';

  @override
  String get setupErrVat =>
      'Eine USt-IdNr. hat 4 bis 20 Buchstaben und Ziffern.';

  @override
  String get setupErrCountry => 'Geben Sie einen zweistelligen Ländercode ein.';

  @override
  String get setupErrCurrency =>
      'Geben Sie einen dreistelligen Währungscode ein.';

  @override
  String get setupErrEmail => 'Geben Sie eine gültige E-Mail-Adresse ein.';

  @override
  String get setupErrAdminName => 'Geben Sie den Namen des Administrators ein.';

  @override
  String get setupErrToken => 'Geben Sie das Einrichtungstoken ein.';

  @override
  String get setupNext => 'Weiter';

  @override
  String get setupBack => 'Zurück';

  @override
  String get setupCreate => 'Unternehmen anlegen';

  @override
  String get setupReviewHint =>
      'Prüfen Sie die Angaben. Auf diesem Server kann nur einmal ein Unternehmen angelegt werden.';

  @override
  String get setupErr403 => 'Das Einrichtungstoken fehlt oder ist falsch.';

  @override
  String get setupErr404 =>
      'Die Einrichtung ist auf diesem Server deaktiviert. Setzen Sie BOOTSTRAP_TOKEN auf dem Server und starten Sie ihn neu.';

  @override
  String get setupErr409 => 'Dieser Server hat bereits ein Unternehmen.';

  @override
  String setupDone(String name) {
    return 'Unternehmen $name angelegt.';
  }

  @override
  String setupDoneDev(String email) {
    return 'Anmeldung als $email.';
  }

  @override
  String setupDoneOidc(String email) {
    return 'Melden Sie sich über Ihren Identitätsanbieter mit $email an: Dieses Konto ist der Administrator.';
  }

  @override
  String get setupToLogin => 'Zur Anmeldung';

  @override
  String get setupAddOfferTitle => 'Diesen Server einrichten?';

  @override
  String get setupAddOfferBody =>
      'Dieser Server hat noch kein Unternehmen. Jetzt eines einrichten?';

  @override
  String get setupLater => 'Später';

  @override
  String get finMatchColumn => 'Abgleich';

  @override
  String get finance => 'Finanzen';

  @override
  String get finSupplierInvoices => 'Eingangsrechnungen';

  @override
  String get finSettings => 'Einstellungen';

  @override
  String get tabSupplierInvoice => 'Eingangsrechnung';

  @override
  String get finNewInvoice => 'Neue Eingangsrechnung';

  @override
  String get finNoInvoices => 'Keine Eingangsrechnungen gefunden.';

  @override
  String get finInvoiceNumber => 'Rechnungsnummer';

  @override
  String get finInternalNumber => 'Interne Nummer';

  @override
  String get finInvoiceDate => 'Rechnungsdatum';

  @override
  String get finDueDate => 'Fälligkeitsdatum';

  @override
  String get finStatusDraft => 'Entwurf';

  @override
  String get finStatusMatched => 'abgeglichen';

  @override
  String get finStatusDisputed => 'beanstandet';

  @override
  String get finStatusApproved => 'freigegeben';

  @override
  String get finStatusPaid => 'bezahlt';

  @override
  String get finMatchOk => 'in Ordnung';

  @override
  String get finMatchNotReceived => 'nicht erhalten';

  @override
  String get finMatchOverInvoiced => 'überfakturiert';

  @override
  String get finMatchPriceVariance => 'Preisabweichung';

  @override
  String get finMatchNoPoLine => 'keine Bestellposition';

  @override
  String get finOrderOptional => 'Bestellung (optional)';

  @override
  String get finNoOrder => 'Keine Bestellung';

  @override
  String get finOrderPrefillHint =>
      'Die Positionen werden aus dem erhaltenen, noch nicht berechneten Wareneingang übernommen.';

  @override
  String get finNumberRequired =>
      'Die Rechnungsnummer ist erforderlich (höchstens 64 Zeichen).';

  @override
  String get finLineDescriptionRequired =>
      'Eine Freitextposition braucht eine Beschreibung.';

  @override
  String get finVatInvalid =>
      'Der MwSt-Satz muss zwischen 0 und 100 liegen, mit höchstens 2 Dezimalstellen.';

  @override
  String get finOrdered => 'Bestellt';

  @override
  String get finInvoiced => 'Berechnet';

  @override
  String get finOrderPrice => 'Bestellpreis';

  @override
  String get finInvoicePrice => 'Rechnungspreis';

  @override
  String get finVariance => 'Abweichung';

  @override
  String get finMatches =>
      'Die Rechnung stimmt mit Bestellung und Wareneingängen überein.';

  @override
  String get finNotMatches =>
      'Die Rechnung stimmt nicht mit Bestellung und Wareneingängen überein.';

  @override
  String finTolerances(String qty, String price) {
    return 'Toleranzen: Menge $qty %, Preis $price %';
  }

  @override
  String get finSubmitMatch => 'Abgleich prüfen';

  @override
  String get finApprove => 'Freigeben';

  @override
  String get finOverrideTitle => 'Trotz Abweichung freigeben';

  @override
  String get finOverrideHelp =>
      'Die Rechnung stimmt nicht überein. Geben Sie den Grund für die Freigabe an; er wird mit der Freigabe gespeichert.';

  @override
  String get finOverrideReason => 'Grund der Ausnahme';

  @override
  String get finReasonRequired => 'Ein Grund ist erforderlich.';

  @override
  String get finDispute => 'Beanstanden';

  @override
  String get finDisputeReason => 'Grund der Beanstandung';

  @override
  String get finReopen => 'Wieder öffnen';

  @override
  String get finMarkPaid => 'Als bezahlt markieren';

  @override
  String get finPaymentDate => 'Zahlungsdatum';

  @override
  String get finPaymentReference => 'Zahlungsreferenz';

  @override
  String get finDeleteDraft => 'Entwurf löschen';

  @override
  String finDeleteConfirm(String number) {
    return 'Rechnung $number löschen? Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get finNetTotal => 'Netto';

  @override
  String get finGrossTotal => 'Gesamt inkl. MwSt';

  @override
  String get finDisputeReasonShown => 'Grund der Beanstandung';

  @override
  String get finOverrideShown => 'Grund der Ausnahme';

  @override
  String get finPaidOn => 'Bezahlt am';

  @override
  String get finPurchaseOrder => 'Bestellung';

  @override
  String get finQuantityTolerance => 'Mengentoleranz (%)';

  @override
  String get finPriceTolerance => 'Preistoleranz (%)';

  @override
  String get finToleranceInvalid =>
      'Geben Sie einen Prozentsatz zwischen 0 und 100 ein.';

  @override
  String get finSettingsSaved => 'Einstellungen gespeichert.';

  @override
  String get finSettingsHelp =>
      'Größte akzeptierte Abweichung zwischen Bestellung und Rechnung, bevor eine Position als Abweichung gilt.';

  @override
  String get finCreateInvoice => 'Eingangsrechnung anlegen';

  @override
  String get userRoleFinance => 'Finanzen';

  @override
  String get moduleFinance => 'Finanzen';

  @override
  String get productionDivisionMembers => 'Mitglieder';

  @override
  String get productionDivisionNoMembers => 'Keine Mitglieder';

  @override
  String get productionScopeMine => 'Meine Bereiche';

  @override
  String get productionScopeAll => 'Alle Bereiche';

  @override
  String get productionScopeEmpty =>
      'Keine Aufträge in Ihren Bereichen. Aufträge ohne Bereich sind eingeschlossen.';

  @override
  String get productionShowAllDivisions => 'Alle Bereiche anzeigen';

  @override
  String get productionYourDivisions => 'Ihre Bereiche';

  @override
  String get setupErrInsecure =>
      'Das Einrichtungstoken wird nicht über eine unverschlüsselte Verbindung an einen anderen Rechner gesendet. Verwenden Sie eine https://-Adresse (reines http ist nur für localhost erlaubt).';

  @override
  String get setupUnavailable =>
      'Die Einrichtung ist auf diesem Server nicht verfügbar: Er hat bereits ein Unternehmen, oder die Einrichtung ist deaktiviert.';

  @override
  String get setupErrRedirect =>
      'Der Server hat die Anfrage umgeleitet, daher wurde das Einrichtungstoken nicht weitergesendet. Prüfen Sie die Serveradresse (verwenden Sie die endgültige https://-Adresse).';

  @override
  String get tutSuppliersTitle => 'Lieferanten';

  @override
  String get tutSuppliersSummary =>
      'Hut: Einkäufer. Legen Sie zwei Lieferanten an und geben Sie ihnen eine Preisliste für Ihre Komponenten.';

  @override
  String get tutSuppliersNeedsTitle => 'Zuerst Kapitel 1';

  @override
  String get tutSuppliersNeedsBody =>
      'Dieses Kapitel braucht die vier Produkte aus Kapitel 1 (TUT-MOTOR, TUT-FRAME, TUT-CTRL und TUT-CART) und hat sie nicht gefunden. Gehen Sie zurück zur Kapitelübersicht und schließen Sie zuerst Kapitel 1 ab.';

  @override
  String get tutSuppliersOpenTitle => 'Setzen Sie den Einkäufer-Hut auf';

  @override
  String get tutSuppliersOpenBody =>
      'Ihre Komponenten müssen von irgendwoher kommen. Öffnen Sie Einkauf im Menü: Die Lieferantenliste ist das erste Segment.';

  @override
  String get tutSuppliersSupplierATitle => 'Der erste Lieferant';

  @override
  String get tutSuppliersSupplierABody =>
      'Legen Sie einen Lieferanten mit Code TUT-SUP-A und Name Voltaic Drives Ltd an. Code und Name sind die einzigen Pflichtfelder; Zahlungsbedingungen, USt-IdNr. und Kontaktdaten können später folgen.';

  @override
  String get tutSuppliersSupplierBTitle => 'Ein zweiter Lieferant';

  @override
  String get tutSuppliersSupplierBBody =>
      'Ein Einkäufer vergleicht gern. Legen Sie einen zweiten Lieferanten mit Code TUT-SUP-B und Name Ironbridge Frames an.';

  @override
  String get tutSuppliersOpenATitle => 'Öffnen Sie den ersten Lieferanten';

  @override
  String get tutSuppliersOpenABody =>
      'Öffnen Sie Voltaic Drives Ltd in der Liste. Die Preisliste steht unten auf dem Lieferantenbildschirm.';

  @override
  String get tutSuppliersPriceMotorTitle => 'Ein Preis für den Motor';

  @override
  String get tutSuppliersPriceMotorBody =>
      'Fügen Sie TUT-MOTOR der Preisliste hinzu: Stückpreis 120, Lieferzeit 14 Tage, Mindestbestellmenge 5. Bestellungen füllen ihre Positionen damit vor.';

  @override
  String get tutSuppliersPriceMotorHint =>
      'Wählen Sie das Produkt über das Suchfeld im Dialog; tippen Sie TUT-MOTOR.';

  @override
  String get tutSuppliersPriceFrameTitle => 'Ein Preis für den Rahmen';

  @override
  String get tutSuppliersPriceFrameBody =>
      'Dasselbe für TUT-FRAME: Stückpreis 45, Lieferzeit 10 Tage, Mindestbestellmenge 5.';

  @override
  String get tutSuppliersPriceControllerTitle => 'Ein Preis für die Steuerung';

  @override
  String get tutSuppliersPriceControllerBody =>
      'Und TUT-CTRL: Stückpreis 30, Lieferzeit 7 Tage, Mindestbestellmenge 5. Dieser Lieferant deckt nun alle drei Komponenten ab.';

  @override
  String get tutSuppliersOpenBTitle => 'Öffnen Sie den zweiten Lieferanten';

  @override
  String get tutSuppliersOpenBBody =>
      'Gehen Sie zurück zur Liste und öffnen Sie Ironbridge Frames.';

  @override
  String get tutSuppliersPriceMotorBTitle => 'Ein Konkurrenzpreis';

  @override
  String get tutSuppliersPriceMotorBBody =>
      'Geben Sie auch diesem Lieferanten einen Preis für TUT-MOTOR: Stückpreis 135, Lieferzeit 5 Tage, Mindestbestellmenge 1. Teurer, aber schneller; bei solchen Entscheidungen hilft eine Preisliste.';

  @override
  String get tutSuppliersDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutSuppliersDoneBody =>
      'Ein Lieferant ist ein Datensatz mit Zahlungsbedingungen und Kontakten; seine Preisliste verknüpft ihn mit Produkten samt Preis, Lieferzeit und Mindestbestellmenge. Als Nächstes: die Ware bestellen.';

  @override
  String get tutBuyingTitle => 'Einkaufen und Wareneingang';

  @override
  String get tutBuyingSummary =>
      'Hüte: Einkäufer und Wareneingang. Bestellen Sie die Komponenten, senden Sie die Bestellung und nehmen Sie die Ware in zwei Lieferungen an.';

  @override
  String get tutBuyingNeedsTitle => 'Zuerst Kapitel 1 und 2';

  @override
  String get tutBuyingNeedsBody =>
      'Dieses Kapitel braucht die Produkte aus Kapitel 1 und den Lieferanten Voltaic Drives Ltd mit Preisliste aus Kapitel 2 und hat die Produkte nicht gefunden. Schließen Sie diese Kapitel zuerst ab.';

  @override
  String get tutBuyingOpenTitle => 'Die Bestellliste';

  @override
  String get tutBuyingOpenBody =>
      'Öffnen Sie Einkauf. Neben Lieferanten gibt es ein Segment für Bestellungen; öffnen Sie es.';

  @override
  String get tutBuyingOrderTitle => 'Bestellen Sie die Komponenten';

  @override
  String get tutBuyingOrderBody =>
      'Legen Sie eine Bestellung an Voltaic Drives Ltd mit drei Positionen an: TUT-MOTOR, TUT-FRAME und TUT-CTRL, je 30 Stück. Die Preise kommen aus der Preisliste.';

  @override
  String get tutBuyingOrderHint =>
      'Wählen Sie zuerst den Lieferanten: Die Positionspreise werden ausgefüllt, sobald seine Preisliste geladen ist. Mit Position hinzufügen kommen die zweite und dritte Komponente dazu.';

  @override
  String get tutBuyingOpenOrderTitle => 'Der Bestellbildschirm';

  @override
  String get tutBuyingOpenOrderBody =>
      'Öffnen Sie die gerade angelegte Bestellung. Eine Bestellung ist zuerst ein Entwurf; die Schaltflächen oben folgen ihrem Verlauf: genehmigen, senden, empfangen.';

  @override
  String get tutBuyingApproveTitle => 'Genehmigen Sie die Bestellung';

  @override
  String get tutBuyingApproveBody =>
      'Genehmigen ist ein eigenes Recht, so kann ein Einkäufer Bestellungen vorbereiten, die ein Manager freigibt. Als Admin tragen Sie beide Hüte: Drücken Sie Genehmigen.';

  @override
  String get tutBuyingSendTitle => 'An den Lieferanten senden';

  @override
  String get tutBuyingSendBody =>
      'Drücken Sie Senden. Die Bestellung wird als gesendet markiert und der Lieferant erhält sie. In Test- und Tutorial-Umgebungen wird ausgehende E-Mail nur in Dateien auf dem Server geschrieben, nichts verlässt das Haus.';

  @override
  String get tutBuyingReceivePartTitle => 'Die erste Lieferung kommt an';

  @override
  String get tutBuyingReceivePartBody =>
      'Setzen Sie den Wareneingangs-Hut auf. Drücken Sie Ware annehmen, wählen Sie den Lagerplatz MAIN und buchen Sie je 10 Stück jeder Komponente, weniger als bestellt. Die Bestellung ist dann teilweise empfangen.';

  @override
  String get tutBuyingReceivePartHint =>
      'Ändern Sie im Dialog die Menge jeder Position; die Restmenge steht daneben. Eine Lieferscheinnummer ist optional.';

  @override
  String get tutBuyingReceiveRestTitle => 'Der Rest kommt an';

  @override
  String get tutBuyingReceiveRestBody =>
      'Nehmen Sie die restlichen 20 Stück jeder Komponente genauso an. Ist alles da, ist die Bestellung vollständig empfangen; jede Lieferung behält ihren eigenen Wareneingangsbeleg.';

  @override
  String get tutBuyingStockTitle => 'Sehen Sie sich den Bestand an';

  @override
  String get tutBuyingStockBody =>
      'Öffnen Sie Bestand. Die 30 Motoren, Rahmen und Steuerungen liegen im Lager MAIN. Jeder Wareneingang hat eine Lagerbewegung erzeugt, die Menge ist also immer nachvollziehbar.';

  @override
  String get tutBuyingDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutBuyingDoneBody =>
      'Eine Bestellung geht von Entwurf über genehmigt und gesendet zu empfangen. Ware darf in mehreren Lieferungen kommen, jede erhöht den Bestand. Die Lieferantenrechnung folgt.';

  @override
  String get tutInvoicesTitle => 'Rechnungen prüfen';

  @override
  String get tutInvoicesSummary =>
      'Hut: Buchhalter. Erfassen Sie Lieferantenrechnungen, lesen Sie den Drei-Wege-Abgleich, genehmigen, beanstanden und bezahlen Sie.';

  @override
  String get tutInvoicesNeedsTitle => 'Zuerst Kapitel 3';

  @override
  String get tutInvoicesNeedsBody =>
      'Dieses Kapitel braucht die vollständig empfangene Bestellung aus Kapitel 3, und die gibt es (noch) nicht. Schließen Sie zuerst Kapitel 3 ab.';

  @override
  String get tutInvoicesOpenOrderTitle => 'Zurück zur Bestellung';

  @override
  String get tutInvoicesOpenOrderBody =>
      'Die Rechnung des Lieferanten trifft ein. Öffnen Sie die Bestellung aus Kapitel 3 erneut: Sobald Ware empfangen ist, bietet sie eine Abkürzung zum Erfassen der Rechnung.';

  @override
  String get tutInvoicesCreateTitle => 'Erfassen Sie die Rechnung';

  @override
  String get tutInvoicesCreateBody =>
      'Drücken Sie Eingangsrechnung anlegen. Tippen Sie die Rechnungsnummer des Lieferanten, zum Beispiel TUT-INV-001, und speichern Sie. Die Positionen werden aus Bestellung und Wareneingang vorausgefüllt.';

  @override
  String get tutInvoicesCreateHint =>
      'Rechnungsdatum und Fälligkeit stehen standardmäßig auf heute und die Zahlungsbedingungen des Lieferanten.';

  @override
  String get tutInvoicesMatchTitle => 'Der Drei-Wege-Abgleich';

  @override
  String get tutInvoicesMatchBody =>
      'Das Banner vergleicht drei Belege: was bestellt, was empfangen und was berechnet wurde, Position für Position. Grün heißt, sie stimmen innerhalb der Toleranzen überein, die im Banner stehen. Drücken Sie Weiter, wenn Sie hingesehen haben.';

  @override
  String get tutInvoicesApproveTitle => 'Genehmigen Sie die Rechnung';

  @override
  String get tutInvoicesApproveBody =>
      'Der Abgleich ist grün, also drücken Sie Freigeben. Eine genehmigte Rechnung ist zahlungsbereit.';

  @override
  String get tutInvoicesSecondTitle => 'Eine verdächtige Rechnung';

  @override
  String get tutInvoicesSecondBody =>
      'Jetzt kommt eine zweite Rechnung von Voltaic Drives Ltd, diesmal ohne Bestellung: Legen Sie in Finanzen eine Lieferantenrechnung für diesen Lieferanten an, Nummer TUT-INV-002, lassen Sie die Bestellung leer und fügen Sie eine Position mit Beschreibung Motoren, Menge 10, Stückpreis 150 hinzu.';

  @override
  String get tutInvoicesSecondHint =>
      'Der echte Motorpreis ist 120 und diese Position hat keine Bestellposition zum Vergleich. Die App kann Preise einer bestellbezogenen Rechnung nicht ändern, daher zeigt hier eine Freitext-Rechnung eine Abweichung.';

  @override
  String get tutInvoicesMismatchTitle => 'Der Abgleich schlägt fehl';

  @override
  String get tutInvoicesMismatchBody =>
      'Das Banner ist orange: Eine Freitext-Position hat nichts zum Abgleichen und kann daher weder mit einer Bestellung noch mit einem Wareneingang geprüft werden. Die Position zeigt den Grund. Drücken Sie Weiter, wenn Sie hingesehen haben.';

  @override
  String get tutInvoicesDisputeTitle => 'Beanstanden Sie die Rechnung';

  @override
  String get tutInvoicesDisputeBody =>
      'Drücken Sie Beanstanden und nennen Sie einen Grund, zum Beispiel Preis entspricht nicht der Vereinbarung. Eine beanstandete Rechnung kann erst nach dem Wiedereröffnen bezahlt werden. (Ein Genehmiger kann einen fehlgeschlagenen Abgleich auch mit einem Abweichungsgrund genehmigen, der an der Rechnung bleibt.)';

  @override
  String get tutInvoicesTolerancesTitle => 'Die Toleranzen';

  @override
  String get tutInvoicesTolerancesBody =>
      'Wie weit eine Rechnung abweichen darf, ist eine Einstellung: Öffnen Sie das Segment Einstellungen in Finanzen, um die Mengen- und Preistoleranz in Prozent zu sehen. Sehen Sie nach und drücken Sie Weiter; Änderungen liegen bei Ihnen.';

  @override
  String get tutInvoicesPayTitle => 'Bezahlen Sie die richtige Rechnung';

  @override
  String get tutInvoicesPayBody =>
      'Öffnen Sie die erste Eingangsrechnung, die Sie erfasst haben (die, die gepasst hat und freigegeben wurde), und drücken Sie Als bezahlt markieren. Geben Sie eine Zahlungsreferenz wie TUT-PAY-001 ein. Die App erfasst die Zahlung; die Überweisung selbst geschieht anderswo.';

  @override
  String get tutInvoicesDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutInvoicesDoneBody =>
      'Der Drei-Wege-Abgleich vergleicht Bestellung, Wareneingang und Rechnung, bevor Geld fließt. Stimmige Rechnungen werden genehmigt und bezahlt, zweifelhafte beanstandet. Als Nächstes: die Karren selbst bauen.';

  @override
  String get tutManufacturingTitle => 'Fertigung';

  @override
  String get tutManufacturingSummary =>
      'Hüte: Fertigungsleiter und Werker. Richten Sie eine Abteilung ein und bauen Sie fünf Karren aus den Komponenten.';

  @override
  String get tutManufacturingNeedsTitle => 'Zuerst Kapitel 1 bis 3';

  @override
  String get tutManufacturingNeedsBody =>
      'Dieses Kapitel braucht den Karren mit Stückliste (Kapitel 1) und Komponenten auf Lager (Kapitel 3) und hat die Produkte nicht gefunden. Schließen Sie diese Kapitel zuerst ab.';

  @override
  String get tutManufacturingOpenDivisionsTitle => 'Abteilungen';

  @override
  String get tutManufacturingOpenDivisionsBody =>
      'Fertigungsarbeit ist in Abteilungen organisiert, zum Beispiel eine Montagelinie. Nur ein Administrator legt sie fest. Öffnen Sie Fertigung und erreichen Sie die Abteilungen über das Zahnrad oben rechts.';

  @override
  String get tutManufacturingDivisionTitle => 'Legen Sie eine Abteilung an';

  @override
  String get tutManufacturingDivisionBody =>
      'Fügen Sie eine Abteilung mit Code TUT-ASM und Name Tutorial assembly hinzu und haken Sie sich in der Mitgliederliste an: Mitglieder sind die Werker der Abteilung.';

  @override
  String get tutManufacturingDivisionHint =>
      'Der Dialog listet die Benutzer der Firma; haken Sie den Chip mit Ihrem Namen an.';

  @override
  String get tutManufacturingQueueTitle => 'Die Fertigungswarteschlange';

  @override
  String get tutManufacturingQueueBody =>
      'Gehen Sie zurück zu Fertigung. Wählen Sie oben in der Warteschlange Meine Bereiche: Das zeigt die Aufträge Ihrer Abteilungen plus Aufträge ohne Abteilung, nichts Unzugewiesenes bleibt verborgen. Sie sind Mitglied einer Abteilung, daher ist das für Sie die Voreinstellung; wählen Sie Alle Bereiche, um alles zu sehen.';

  @override
  String get tutManufacturingReleaseTitle =>
      'Geben Sie einen Fertigungsauftrag frei';

  @override
  String get tutManufacturingReleaseBody =>
      'Drücken Sie Auf Lager fertigen, wählen Sie TUT-CART mit Menge 5 und geben Sie frei. Die Stückliste wird eingefroren und die Komponenten werden reserviert. Normalerweise startet die Fertigung aus einer Auftragsposition; das sehen Sie in Kapitel 9.';

  @override
  String get tutManufacturingReleaseHint =>
      'Nur gefertigte Produkte mit aktiver Stückliste können freigegeben werden.';

  @override
  String get tutManufacturingAssignTitle => 'Weisen Sie es der Abteilung zu';

  @override
  String get tutManufacturingAssignBody =>
      'Der neue Auftrag ist offen. Wählen Sie im Feld Bereich die Abteilung Tutorial assembly und drücken Sie Speichern, damit er in der Warteschlange dieser Abteilung erscheint.';

  @override
  String get tutManufacturingStartTitle => 'Starten Sie die Arbeit';

  @override
  String get tutManufacturingStartBody =>
      'Setzen Sie den Werker-Hut auf und drücken Sie Starten. Der Auftrag geht von freigegeben auf in Arbeit.';

  @override
  String get tutManufacturingCompleteTitle => 'Schließen Sie den Auftrag ab';

  @override
  String get tutManufacturingCompleteBody =>
      'Drücken Sie Abschließen. Der Dialog zeigt die Ausbringungsmenge (5) und die verbrauchten Komponenten. Bestätigen Sie: Die Komponenten verlassen den Bestand und fünf fertige Karren kommen hinein.';

  @override
  String get tutManufacturingCompleteHint =>
      'Lassen Sie die Planwerte stehen; der Dialog erlaubt, Ausschuss oder Mehrverbrauch zu erfassen, wenn die Wirklichkeit abweicht.';

  @override
  String get tutManufacturingStockTitle => 'Prüfen Sie den Bestand';

  @override
  String get tutManufacturingStockBody =>
      'Öffnen Sie Bestand: TUT-CART hat jetzt 5 auf Lager und jede Komponente ist um 5 gesunken (je 25 übrig). Die Fertigung verbindet Einkauf und Verkauf.';

  @override
  String get tutManufacturingDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutManufacturingDoneBody =>
      'Abteilungen gruppieren Werker; ein Fertigungsauftrag friert die Stückliste ein, reserviert Komponenten, wird gestartet und abgeschlossen und macht aus Komponenten Fertigware. Als Nächstes: Preise.';

  @override
  String get tutPricesTitle => 'Preise und Zonen';

  @override
  String get tutPricesSummary =>
      'Hut: Vertriebsleiter. Legen Sie eine Preiszone an und geben Sie dem Karren einen Preis in zwei Zonen.';

  @override
  String get tutPricesNeedsTitle => 'Zuerst Kapitel 1';

  @override
  String get tutPricesNeedsBody =>
      'Dieses Kapitel braucht den Karren aus Kapitel 1 und hat ihn nicht gefunden. Schließen Sie zuerst Kapitel 1 ab.';

  @override
  String get tutPricesOpenAdminTitle => 'Öffnen Sie die Verwaltung';

  @override
  String get tutPricesOpenAdminBody =>
      'Ein Preis hängt von der Zone des Kunden ab: ein Land oder Markt mit eigener Preisliste. Zonen verwalten Sie unter Verwaltung. Öffnen Sie Verwaltung und wählen Sie das Segment Preiszonen; die Firma hat schon die Zonen Z1 bis Z5.';

  @override
  String get tutPricesZoneTitle => 'Legen Sie eine Zone an';

  @override
  String get tutPricesZoneBody =>
      'Fügen Sie eine Preiszone mit Code TUT-EXPORT und Name Exportzone hinzu. Kunden erhalten später eine Zone, wenn Sie einen anlegen.';

  @override
  String get tutPricesZoneHint =>
      'Wählen Sie zuerst oben auf der Verwaltungsseite das Segment Preiszonen.';

  @override
  String get tutPricesOpenCartTitle => 'Öffnen Sie den Karren';

  @override
  String get tutPricesOpenCartBody =>
      'Öffnen Sie das Produkt TUT-CART aus der Produktliste. Der erste Reiter, Preise, enthält die Preise je Zone.';

  @override
  String get tutPricesPriceExportTitle => 'Ein Preis in der neuen Zone';

  @override
  String get tutPricesPriceExportBody =>
      'Drücken Sie Neuer Preis, wählen Sie die Zone TUT-EXPORT, geben Sie den Stückpreis 1450 (ohne USt.) ein und speichern Sie.';

  @override
  String get tutPricesPriceExportHint =>
      'Das Gültig-ab-Datum steht standardmäßig auf heute; ein späteres Datum plant eine Preisänderung.';

  @override
  String get tutPricesPriceHomeTitle => 'Ein Preis in einer anderen Zone';

  @override
  String get tutPricesPriceHomeBody =>
      'Fügen Sie einen zweiten Preis für den Karren in einer bestehenden Zone hinzu, zum Beispiel Z1 mit 1200. Dasselbe Produkt kann nun je nach Zone des Kunden unterschiedlich kosten.';

  @override
  String get tutPricesDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutPricesDoneBody =>
      'Eine Preiszone gruppiert Kunden mit derselben Preisliste, und ein Produkt hat einen Preis je Zone und Datum. Angebote übernehmen den Preis der Kundenzone. Als Nächstes: Ein neuer Kunde schreibt.';

  @override
  String get tutCustomerTitle => 'Ein neuer Kunde schreibt';

  @override
  String get tutCustomerSummary =>
      'Hüte: Vertrieb und Helpdesk. Eine Kunden-E-Mail wird zum Ticket; der Absender ist neu, also fragen Sie Firmendaten ab und legen den Kunden an.';

  @override
  String get tutCustomerNeedsTitle => 'Zuerst Kapitel 6';

  @override
  String get tutCustomerNeedsBody =>
      'Dieses Kapitel braucht die Preiszone TUT-EXPORT aus Kapitel 6 (der neue Kunde bekommt sie) und hat sie nicht gefunden. Schließen Sie zuerst die früheren Kapitel ab.';

  @override
  String get tutCustomerMail1Title => 'Eine E-Mail kommt an';

  @override
  String get tutCustomerMail1Body =>
      'Jemand Unbekanntes bittet um ein Angebot für Ihren Karren. Ein echtes Postfach würde die Nachricht selbst liefern; hier spielt die Schaltfläche unten den Kunden und übergibt eine fertige E-Mail (von Maya Okafor, example.test) an das Helpdesk, genau wie der Mail-Import.';

  @override
  String get tutCustomerMail1Action => 'Kunden-E-Mail simulieren';

  @override
  String get tutCustomerOpenHelpdeskTitle => 'Das Ticket';

  @override
  String get tutCustomerOpenHelpdeskBody =>
      'Jede eingehende Nachricht wird ein Ticket. Öffnen Sie Helpdesk: Das Ticket von Maya Okafor steht in der Liste.';

  @override
  String get tutCustomerOpenTicketTitle => 'Öffnen Sie das Ticket';

  @override
  String get tutCustomerOpenTicketBody =>
      'Öffnen Sie das Ticket. Links steht die Konversation, rechts die Eigenschaften. Noch ist kein Kunde verknüpft, weil niemand mit dieser Adresse im System existiert.';

  @override
  String get tutCustomerReplyTitle => 'Fragen Sie Firmendaten ab';

  @override
  String get tutCustomerReplyBody =>
      'Antworten Sie Maya: Bedanken Sie sich und fragen Sie nach Firmenname, USt-IdNr. und Adresse, dann drücken Sie Senden. Die Antwort kommt in die Warteschlange des Mail-Workers. In Test- und Tutorial-Umgebungen wird ausgehende Post nur in Dateien auf dem Server geschrieben, Maya erhält also nichts.';

  @override
  String get tutCustomerReplyHint =>
      'Achten Sie darauf, dass über dem Nachrichtenfeld der Reiter Antwort (nicht Interne Notiz) gewählt ist.';

  @override
  String get tutCustomerMail2Title => 'Der Kunde antwortet';

  @override
  String get tutCustomerMail2Body =>
      'Spielen Sie mit der Schaltfläche Mayas Antwort ab. Sie ist die Antwort auf ihre erste Nachricht und landet als neue Nachricht im selben Ticket, mit Firmenname, USt-IdNr. und Adresse.';

  @override
  String get tutCustomerMail2Action => 'Kunden-E-Mail simulieren';

  @override
  String get tutCustomerReadDetailsTitle => 'Lesen Sie die Angaben';

  @override
  String get tutCustomerReadDetailsBody =>
      'Gehen Sie zurück zum Ticket (öffnen Sie es neu, falls die neue Nachricht noch fehlt) und lesen Sie Mayas Antwort: Firma Brightwheel Logistics BV, USt-IdNr. BE0123456749, Voorbeeldlaan 12, 9000 Gent, Belgien. Drücken Sie Weiter, wenn Sie die Angaben haben.';

  @override
  String get tutCustomerCreateCustomerTitle => 'Legen Sie den Kunden an';

  @override
  String get tutCustomerCreateCustomerBody =>
      'Drücken Sie in den Ticket-Eigenschaften auf Neuer Kunde. Tragen Sie Name Brightwheel Logistics BV, einen Code wie TUT-CUST, USt-IdNr. und Adresse ein und wählen Sie die Preiszone TUT-EXPORT. Beim Speichern wird das Ticket mit dem neuen Kunden verknüpft.';

  @override
  String get tutCustomerCreateCustomerHint =>
      'Straße Voorbeeldlaan 12, PLZ 9000, Ort Gent, Land BE. Sprache und Zahlungsbedingungen können bleiben, wie sie sind.';

  @override
  String get tutCustomerLinkedTitle => 'Das Ticket kennt seinen Kunden';

  @override
  String get tutCustomerLinkedBody =>
      'Das Ticket zeigt nun den Kunden, und neue Schaltflächen erscheinen: einen Lead anlegen oder direkt aus dem Ticket ein Angebot beginnen. Das nächste Kapitel erstellt das Angebot. Drücken Sie Weiter.';

  @override
  String get tutCustomerDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutCustomerDoneBody =>
      'Eingehende Post wird zu Tickets, eine Antwort fragt beim Kunden nach dem Fehlenden, und aus dem Ticket lässt sich ein Kunde anlegen, damit alles verknüpft bleibt. Als Nächstes: das Angebot.';

  @override
  String get tutQuotationTitle => 'Das Angebot';

  @override
  String get tutQuotationSummary =>
      'Hut: Vertriebsmitarbeiter. Bieten Sie dem neuen Kunden 8 Karren an, holen Sie die Zeitangabe der Fertigung ein und senden Sie das Angebot.';

  @override
  String get tutQuotationNeedsTitle => 'Zuerst Kapitel 7';

  @override
  String get tutQuotationNeedsBody =>
      'Dieses Kapitel braucht den Kunden Brightwheel Logistics BV aus Kapitel 7 und hat ihn nicht gefunden. Schließen Sie zuerst Kapitel 7 ab.';

  @override
  String get tutQuotationOpenQuotationsTitle => 'Angebote';

  @override
  String get tutQuotationOpenQuotationsBody =>
      'Öffnen Sie Angebote im Menü. Diese Liste enthält jedes Angebot mit Nummer, Kunde und Status.';

  @override
  String get tutQuotationCreateTitle => 'Erstellen Sie das Angebot';

  @override
  String get tutQuotationCreateBody =>
      'Drücken Sie Neues Angebot, wählen Sie Brightwheel Logistics BV, fügen Sie TUT-CART mit Menge 8 hinzu und speichern Sie den Entwurf. Der Stückpreis stammt aus der Preiszone des Kunden, TUT-EXPORT, also die 1450 aus Kapitel 6.';

  @override
  String get tutQuotationCreateHint =>
      'Nutzen Sie die Produktsuche bei den Positionen; tippen Sie TUT-CART. Ist der Kunde nicht vorausgewählt, suchen Sie nach Brightwheel.';

  @override
  String get tutQuotationLeadTitle => 'Wie lange dauert es?';

  @override
  String get tutQuotationLeadBody =>
      'Der Kunde wollte eine Lieferzeit. Ehrlich gesagt: Die App berechnet Lieferzeiten noch nicht automatisch, und ein Angebot hat kein Lieferdatumsfeld. Fragen Sie also die Fertigung (Hut wechseln, Fertigungswarteschlange und Komponentenbestand ansehen) und schreiben Sie die Antwort in die Notizen des Angebots, zum Beispiel: Lieferung etwa 3 Wochen nach Bestellung. Speichern Sie den Entwurf.';

  @override
  String get tutQuotationLeadHint =>
      'Bei einem Auftrag können Sie der Fertigung eine Frage als Ticket schicken (siehe Kapitel 9); Angebote haben diese Schaltfläche noch nicht.';

  @override
  String get tutQuotationSendTitle => 'Senden Sie das Angebot';

  @override
  String get tutQuotationSendBody =>
      'Drücken Sie Als versendet markieren. Ab jetzt ist das Angebot eingefroren: Es kann nur noch angenommen, abgelehnt oder überarbeitet werden. (Diese Schaltfläche versendet keine Mail; Sie schicken das PDF selbst oder antworten im Ticket.)';

  @override
  String get tutQuotationPdfTitle => 'Das PDF';

  @override
  String get tutQuotationPdfBody =>
      'Die PDF-Schaltfläche zeigt das Angebot, wie der Kunde es sähe. Es wird auf dem Server mit einem Satzprogramm erzeugt; ohne dieses gibt es eine Fehlermeldung, die sonst nichts beeinflusst. Sehen Sie gern hinein und drücken Sie dann Weiter.';

  @override
  String get tutQuotationPdfHint =>
      'Es geht nichts kaputt, wenn das PDF fehlschlägt: Das Angebot ist bereits gesendet.';

  @override
  String get tutQuotationDoneTitle => 'Was Sie gelernt haben';

  @override
  String get tutQuotationDoneBody =>
      'Ein Angebot übernimmt den Preis der Kundenzone, trägt Notizen und friert beim Senden ein. Lieferzeiten bleiben Ihre Einschätzung, gemeinsam mit der Fertigung. Als Nächstes: Der Kunde wünscht eine Änderung.';

  @override
  String get tutChangeTitle => 'Änderung, Auftrag, Fertigung';

  @override
  String get tutChangeSummary =>
      'Hüte: Vertrieb und Fertigung. Überarbeiten Sie das Angebot, machen Sie einen Auftrag daraus, bauen Sie die Karren und ein paar zusätzliche für den Bestand.';

  @override
  String get tutChangeNeedsTitle => 'Zuerst Kapitel 8';

  @override
  String get tutChangeNeedsBody =>
      'Dieses Kapitel braucht das gesendete Angebot aus Kapitel 8 und hat es nicht gefunden. Schließen Sie zuerst Kapitel 8 ab.';

  @override
  String get tutChangeMail3Title => 'Der Kunde antwortet wieder';

  @override
  String get tutChangeMail3Body =>
      'Maya ist mit dem Angebot zufrieden, will aber 10 Karren statt 8. Spielen Sie ihre E-Mail mit der Schaltfläche ab; sie landet im selben Ticket.';

  @override
  String get tutChangeMail3Action => 'Kunden-E-Mail simulieren';

  @override
  String get tutChangeOpenQuoteTitle => 'Öffnen Sie das gesendete Angebot';

  @override
  String get tutChangeOpenQuoteBody =>
      'Ein gesendetes Angebot ist eingefroren, eine Änderung bedeutet also eine neue Revision. Öffnen Sie das Angebot aus Kapitel 8.';

  @override
  String get tutChangeReviseTitle => 'Erstellen Sie eine Revision';

  @override
  String get tutChangeReviseBody =>
      'Drücken Sie Neue Revision und wählen Sie Vereinbarte Preise beibehalten. Die alte Revision gilt als ersetzt und ein neuer Entwurf mit derselben Nummer öffnet sich.';

  @override
  String get tutChangeReviseHint =>
      'Auf aktuelle Preise aktualisieren würde mit der heutigen Preisliste neu bewerten; hier behält der Kunde den vereinbarten Preis.';

  @override
  String get tutChangeEditTitle => 'Ändern Sie die Menge';

  @override
  String get tutChangeEditBody =>
      'Setzen Sie die Menge von TUT-CART auf 10 und speichern Sie den Entwurf.';

  @override
  String get tutChangeEditHint =>
      'Die Notizen der ersten Revision wurden kopiert; passen Sie sie an, wenn sich die Lieferzeit ändert.';

  @override
  String get tutChangeSendTitle => 'Senden Sie die Revision';

  @override
  String get tutChangeSendBody =>
      'Markieren Sie die neue Revision als gesendet, wie zuvor.';

  @override
  String get tutChangeAcceptTitle => 'Der Kunde nimmt an';

  @override
  String get tutChangeAcceptBody =>
      'Maya stimmt der neuen Revision zu: Drücken Sie Angenommen, um das festzuhalten.';

  @override
  String get tutChangeConvertTitle => 'Machen Sie einen Verkaufsauftrag daraus';

  @override
  String get tutChangeConvertBody =>
      'Drücken Sie In Auftrag umwandeln. Aus der angenommenen Revision entsteht ein Verkaufsauftrag im Entwurf, der sich öffnet.';

  @override
  String get tutChangeConvertHint =>
      'Der Dialog fragt nach der Referenz des Kunden; tippen Sie zum Beispiel TUT-PO-1 oder lassen Sie es leer.';

  @override
  String get tutChangeOpenOrderTitle => 'Der Verkaufsauftrag';

  @override
  String get tutChangeOpenOrderBody =>
      'Hat sich der Auftrag nicht von selbst geöffnet, öffnen Sie ihn unter Aufträge. Er enthält die 10 Karren, den Preis und die Kundenreferenz. Aufträge gehen von Entwurf über gesendet zu bestätigt.';

  @override
  String get tutChangeSendOrderTitle => 'Senden Sie die Auftragsbestätigung';

  @override
  String get tutChangeSendOrderBody =>
      'Drücken Sie Auftragsbestätigung senden. Der Auftrag wird gesendet: Der Kunde kann ihn nun bestätigen.';

  @override
  String get tutChangeSendOrderHint =>
      'Das Bestätigungsdokument braucht das Satzprogramm des Servers; fehlt es, verweigert der Server diesen Schritt und zum Weitermachen wird ein Server mit dem Programm gebraucht.';

  @override
  String get tutChangeConfirmTitle => 'Bestätigen Sie im Namen des Kunden';

  @override
  String get tutChangeConfirmBody =>
      'Maya hat per E-Mail schon zugesagt, also drücken Sie Im Namen des Kunden bestätigen und notieren etwa per E-Mail bestätigt. Der Auftrag ist nun bestätigt und kann in die Fertigung.';

  @override
  String get tutChangeReleaseTitle => 'Freizugeben';

  @override
  String get tutChangeReleaseBody =>
      'Setzen Sie den Fertigungs-Hut auf. Öffnen Sie Fertigung > Freizugeben: Die bestätigte Auftragsposition mit 10 Karren wartet. Drücken Sie Für die Produktion freigeben, um den Fertigungsauftrag genau für diese Position zu erzeugen.';

  @override
  String get tutChangeStartTitle => 'Starten Sie die Fertigung';

  @override
  String get tutChangeStartBody =>
      'Drücken Sie Starten beim neuen Fertigungsauftrag.';

  @override
  String get tutChangeCompleteTitle => 'Schließen Sie die Fertigung ab';

  @override
  String get tutChangeCompleteBody =>
      'Drücken Sie Abschließen und bestätigen Sie die 10 Karren. Die Komponenten werden verbraucht und die Karren gehen an den Auftrag.';

  @override
  String get tutChangeReadyTitle => 'Versandbereit';

  @override
  String get tutChangeReadyBody =>
      'Öffnen Sie den Auftrag erneut: Mit allen produzierten Positionen ist er versandbereit. Lieferung (Kommissionieren, Versand, Kunden fakturieren) liegt außerhalb dieses Tutorials. Drücken Sie Weiter.';

  @override
  String get tutChangeStockTitle => 'Ein paar extra für den Bestand';

  @override
  String get tutChangeStockBody =>
      'Die Fertigung läuft oft den Aufträgen voraus. Öffnen Sie Fertigung, drücken Sie Auf Lager fertigen und geben Sie 4 weitere Karren TUT-CART frei. Ohne Auftrag landen sie nach Abschluss einfach im Bestand.';

  @override
  String get tutChangeStockHint =>
      'Sie können diesen Auftrag wie in Kapitel 5 starten und abschließen oder ihn freigegeben lassen.';

  @override
  String get tutChangeDoneTitle => 'Gut gemacht: die ganze Geschichte';

  @override
  String get tutChangeDoneBody =>
      'Sie sind von Lieferanten über Einkauf, Rechnungen, Fertigung und Preise zu einem Ticket, einem neuen Kunden, einem überarbeiteten Angebot, einem Auftrag und der Fertigung für Auftrag und Bestand gekommen. Wie weiter: Lieferungen und Versand, Reparaturen, Außendienst und Berichte haben je einen eigenen Menüpunkt. Jedes Kapitel lässt sich aus der Kapitelübersicht wiederholen; bereits erledigte Schritte werden übersprungen.';

  @override
  String get tutInvoicesOpenSecondTitle =>
      'Öffnen Sie die verdächtige Rechnung';

  @override
  String get tutInvoicesOpenSecondBody =>
      'Öffnen Sie die Rechnung TUT-INV-002, die Sie gerade erfasst haben, aus der Liste in Finanzen.';

  @override
  String tutActionFailed(String reason) {
    return 'Die simulierte E-Mail konnte nicht gesendet werden: $reason. Versuchen Sie es erneut.';
  }

  @override
  String get tutActionForbidden =>
      'Sie dürfen keine E-Mail in das Helpdesk importieren (dafür ist das Schreibrecht für das Helpdesk nötig). Fragen Sie einen Administrator oder melden Sie sich als solcher an und versuchen Sie es erneut.';

  @override
  String workerDownBanner(String since) {
    return 'Die Hintergrundverarbeitung läuft seit $since nicht mehr: E-Mails werden weder gesendet noch abgerufen und SLA-Verletzungen werden nicht eskaliert.';
  }

  @override
  String get workerNeverSeenBanner =>
      'Die Hintergrundverarbeitung ist noch nie gelaufen: E-Mails werden weder gesendet noch abgerufen und SLA-Verletzungen werden nicht eskaliert.';

  @override
  String get workerBannerSemantics => 'Hintergrundverarbeitung';
}
