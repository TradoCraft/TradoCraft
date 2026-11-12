// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get accepted => 'Aanvaard';

  @override
  String get accessToken => 'Toegangstoken';

  @override
  String get account => 'Account';

  @override
  String get action => 'Actie';

  @override
  String get actionAddTag => 'Tag toevoegen';

  @override
  String get actionSetCategory => 'Categorie instellen';

  @override
  String get actionSetInternal => 'Als intern markeren';

  @override
  String get actionSetOwner => 'Eigenaar instellen';

  @override
  String get actionSetPriority => 'Prioriteit instellen';

  @override
  String get actionSetTeam => 'Team instellen';

  @override
  String get actions => 'Acties';

  @override
  String get activate => 'Activeren';

  @override
  String get active => 'Actief';

  @override
  String activeSince(String date) {
    return 'Actief sinds $date. Wijzigingen gebeuren via een nieuwe revisie.';
  }

  @override
  String get add => 'Toevoegen';

  @override
  String get addAction => 'Actie toevoegen';

  @override
  String get addClosure => 'Sluiting toevoegen';

  @override
  String get addComponent => 'Component toevoegen';

  @override
  String get addComponentBySerial =>
      'Component toevoegen op serienummer (in stock)';

  @override
  String get addEquipment => 'Installatie toevoegen';

  @override
  String get addMember => 'Lid toevoegen';

  @override
  String get addNote => 'Notitie toevoegen';

  @override
  String get addNoteHint => 'Interne opmerking toevoegen';

  @override
  String get addPart => 'Onderdeel toevoegen';

  @override
  String get addPhone => 'Telefoonnummer toevoegen';

  @override
  String get addPhoto => 'Foto toevoegen';

  @override
  String get addProduct => 'Product toevoegen';

  @override
  String get addRebate => 'Korting toevoegen';

  @override
  String get addTag => 'Label toevoegen';

  @override
  String get addTask => 'Taak toevoegen';

  @override
  String addedBy(String date, String name) {
    return 'toegevoegd $date door $name';
  }

  @override
  String get addressForm => 'Aanspreekvorm';

  @override
  String get addressFormal => 'Formeel (u)';

  @override
  String get addressInformal => 'Informeel (je)';

  @override
  String get addVisit => 'Bezoek toevoegen';

  @override
  String get agreed => 'Afgesproken';

  @override
  String get all => 'Alle';

  @override
  String get allCategories => 'Alle categorieën';

  @override
  String get allOwners => 'Alle eigenaars';

  @override
  String get allProducts => 'Alle producten';

  @override
  String get allStatuses => 'Alle statussen';

  @override
  String get allTags => 'Alle labels';

  @override
  String get allTeams => 'Alle teams';

  @override
  String get always => 'altijd';

  @override
  String andMore(int count) {
    return '… en nog $count';
  }

  @override
  String get announceRepair => 'Herstelling aankondigen';

  @override
  String get announcedNotReceived => 'Aangekondigd, nog niet ontvangen';

  @override
  String answerFallback(String ticketLanguage, String usedLanguage) {
    return 'Nog geen tekst in het $ticketLanguage: de tekst in het $usedLanguage werd gebruikt. Vertaal voor verzending.';
  }

  @override
  String get anyValue => 'Alle';

  @override
  String get appLanguage => 'Taal';

  @override
  String get appTitle => 'TradoCraft';

  @override
  String get apply => 'Toepassen';

  @override
  String get assignTo => 'Toewijzen aan';

  @override
  String get attachFile => 'Bestand bijvoegen';

  @override
  String get attachments => 'Bijlagen';

  @override
  String get attachmentsHelp =>
      'Afbeeldingen (JPEG, PNG, WebP) en PDF, tot 12 MB';

  @override
  String get automatic => 'Automatisch';

  @override
  String get automationHelp =>
      'Regels worden in deze volgorde uitgevoerd wanneer een ticket wordt aangemaakt, gewijzigd of door de klant beantwoord. Een regel geldt als al zijn voorwaarden kloppen. Regels wijzigen alleen tickets; ze versturen geen e-mail.';

  @override
  String get automationRules => 'Automatiseringsregels';

  @override
  String get autoRenew => 'Automatisch verlengen';

  @override
  String get backIntoWork => 'Terug in behandeling';

  @override
  String get backToCurrentRevision => 'Terug naar de huidige revisie';

  @override
  String get backlogByOwner => 'Open tickets per eigenaar';

  @override
  String get backlogByPriority => 'Open tickets per prioriteit';

  @override
  String get backlogByStatus => 'Open tickets per status';

  @override
  String get backlogByTeam => 'Open tickets per team';

  @override
  String get basisBusiness => 'openingsuren';

  @override
  String get basisElapsed => 'verstreken tijd';

  @override
  String get billOfMaterials => 'Stuklijst';

  @override
  String get billable => 'Factureerbaar';

  @override
  String get bomActive => 'actief';

  @override
  String get bomObsolete => 'vervallen';

  @override
  String get bomRev => 'Stuklijstrev.';

  @override
  String get bomRevision => 'Stuklijstrevisie';

  @override
  String get breached => 'Overschreden';

  @override
  String get breachesByTeam => 'SLA-overschrijdingen per team';

  @override
  String get builtInto => 'Ingebouwd in';

  @override
  String get bulkKeepsQuotes =>
      'Offertes vóór deze datum blijven de huidige prijzen gebruiken';

  @override
  String get bulkPriceChange => 'Prijzen in bulk wijzigen';

  @override
  String get businessHours => 'Openingsuren';

  @override
  String get businessHoursEnabled => 'Alleen openingsuren tellen';

  @override
  String get businessHoursHelp =>
      'Servicetermijnen tellen alleen de uren hieronder, op dagen die geen feestdag zijn. Uitgeschakeld lopen ze de klok rond.';

  @override
  String get businessHoursInvalidTime => 'Geef uren in als UU:MM.';

  @override
  String get businessHoursRecompute =>
      'Opslaan berekent de vervaltijden van alle open tickets opnieuw.';

  @override
  String get businessHoursSaved => 'Opgeslagen. Open tickets zijn herberekend.';

  @override
  String get byStage => 'volgens fase';

  @override
  String get callIncoming => 'Inkomend gesprek';

  @override
  String get callLogged => 'Gesprek geregistreerd';

  @override
  String get callMinutes => 'Duur (minuten)';

  @override
  String get callOutgoing => 'Uitgaand gesprek';

  @override
  String get callSummary => 'Wat werd er besproken';

  @override
  String callWith(String name) {
    return 'Gesprek met $name';
  }

  @override
  String get canStillKeep => 'Je kunt de afgesproken prijzen nog behouden.';

  @override
  String get cancel => 'Annuleren';

  @override
  String get cancelJob => 'Opdracht annuleren';

  @override
  String get cancelOrder => 'Order annuleren';

  @override
  String get cancelReasonLabel => 'Reden van annulering';

  @override
  String get cancelRepair => 'Herstelling annuleren';

  @override
  String get cancelled => 'geannuleerd';

  @override
  String cancelledReason(String reason) {
    return 'Geannuleerd: $reason';
  }

  @override
  String get cannotConfirmNewer =>
      'Er wordt een nieuwere revisie van deze order voorbereid. U kunt ze bevestigen zodra ze naar u is verstuurd.';

  @override
  String get cannotConfirmOther => 'Deze order kan niet worden bevestigd.';

  @override
  String get captureSignature => 'Handtekening vastleggen';

  @override
  String get category => 'Categorie';

  @override
  String get categoryComplaint => 'klacht';

  @override
  String get categoryLead => 'lead (nieuwe vraag)';

  @override
  String get categoryOrderConfirmation => 'orderbevestiging';

  @override
  String get categoryOther => 'andere';

  @override
  String get categoryProductionQuestion => 'vraag van productie';

  @override
  String get categoryQuestion => 'vraag';

  @override
  String get categoryQuoteChange => 'offerte aanpassen';

  @override
  String get categoryService => 'service / herstelling';

  @override
  String get cc => 'Cc';

  @override
  String get change => 'Wijziging';

  @override
  String get changePriority => 'Prioriteit wijzigen';

  @override
  String get channel => 'Kanaal';

  @override
  String get channelEmail => 'E-mail';

  @override
  String get channelInternal => 'Interne vraag';

  @override
  String get channelManual => 'Manueel ingevoerd';

  @override
  String get channelPhone => 'Telefoon';

  @override
  String get channelPortal => 'Portaal';

  @override
  String get checklistOnePerLine => 'Checklist (één taak per regel)';

  @override
  String get chooseCustomerAndLine =>
      'Kies een klant en voeg minstens één geldige lijn toe.';

  @override
  String get choosePhoto => 'Kies uit galerij';

  @override
  String get chooseRebateTarget =>
      'Kies een product of familie en geef een percentage in.';

  @override
  String get chooseZonePrice => 'Kies een zone en geef een prijs in.';

  @override
  String get city => 'Gemeente';

  @override
  String get clear => 'Wissen';

  @override
  String get close => 'Sluiten';

  @override
  String get closedLabel => 'gesloten';

  @override
  String get closes => 'Sluit';

  @override
  String get closureKindCollectiveLeave => 'Collectief verlof';

  @override
  String get closureKindHoliday => 'Feestdag';

  @override
  String get closureKindInventory => 'Inventaris';

  @override
  String get closureKindLabel => 'Reden';

  @override
  String get closureKindOther => 'Andere';

  @override
  String get closureKindWorks => 'Werken';

  @override
  String get closurePolicyBlock => 'Niet toegestaan';

  @override
  String get closurePolicyBlockHelp =>
      'Een levering kan niet op een gesloten dag gepland worden; kies een andere datum.';

  @override
  String get closurePolicyOverride =>
      'Vraagt een reden en het recht om te overrulen';

  @override
  String get closurePolicyOverrideHelp =>
      'Alleen gebruikers die mogen overrulen kunnen op een gesloten dag plannen, met een reden.';

  @override
  String get closurePolicyTitle =>
      'Wanneer een levering gepland wordt op een dag dat de klant gesloten is';

  @override
  String get closurePolicyWarn => 'Alleen waarschuwen';

  @override
  String get closurePolicyWarnHelp =>
      'De datum wordt bewaard en de sluiting wordt als waarschuwing getoond.';

  @override
  String get closures => 'Sluitingsdagen';

  @override
  String get closuresShowPast => 'Verleden sluitingen tonen';

  @override
  String get code => 'Code';

  @override
  String get codeNameRequired => 'Code en naam zijn verplicht.';

  @override
  String get codeNameVatRequired => 'Code, naam en btw-tarief zijn verplicht.';

  @override
  String get completeJob => 'Opdracht afronden';

  @override
  String get completionNotes => 'Wat werd gedaan (en wat nog openstaat)';

  @override
  String get component => 'Component';

  @override
  String get componentHistory => 'Historiek componenten';

  @override
  String componentSince(String product, String date) {
    return '$product · sinds $date';
  }

  @override
  String get componentsAsBuilt => 'Componenten (zoals gebouwd)';

  @override
  String get confirm => 'bevestigen';

  @override
  String get confirmOnBehalf => 'Bevestigen namens de klant';

  @override
  String get confirmOnBehalfHelp =>
      'Leg vast dat de klant deze revisie heeft bevestigd, bijvoorbeeld telefonisch of per e-mail.';

  @override
  String get confirmOrder => 'Order bevestigen';

  @override
  String get confirmOrderHelp =>
      'Door te bevestigen gaat u akkoord met deze order zoals weergegeven.';

  @override
  String get confirmation => 'Bevestiging';

  @override
  String get confirmationDate => 'Bevestigd op';

  @override
  String get confirmed => 'bevestigd';

  @override
  String get confirmedRevision => 'Bevestigde revisie';

  @override
  String get confirmedVia => 'Bevestigd via';

  @override
  String get confirmedViaPortal => 'klantenportaal';

  @override
  String get confirmedViaStaff => 'medewerker, namens de klant';

  @override
  String conflictsOnDate(int count) {
    return '$count hebben al een prijs op deze datum';
  }

  @override
  String get contactName => 'Naam contactpersoon';

  @override
  String get contactPerson => 'Contactpersoon';

  @override
  String get contacts => 'Contactpersonen';

  @override
  String get contractEnded => 'Beëindigd';

  @override
  String get contractJobs => 'Opdrachten van dit contract';

  @override
  String contractLabel(String number) {
    return 'Contract $number';
  }

  @override
  String contractOpenJobs(String count) {
    return '$count open opdrachten';
  }

  @override
  String get contracts => 'Contracten';

  @override
  String get contractSuspended => 'Opgeschort';

  @override
  String get convertHelp =>
      'Wil de klant nog iets wijzigen? Maak eerst een nieuwe revisie van de offerte, koppel die hier en zet ze dan om.';

  @override
  String get convertToOrder => 'Omzetten naar order';

  @override
  String get countAddLine => 'Voorraad toevoegen die niet in de lijst staat';

  @override
  String get countCancel => 'Inventarisatie annuleren';

  @override
  String get countCounted => 'Geteld';

  @override
  String get countDifference => 'Verschil';

  @override
  String get countExpected => 'Verwacht';

  @override
  String get countInvalidQuantity => 'Een getelde hoeveelheid is geen getal.';

  @override
  String countMovedDuring(int count) {
    return 'Bij $count lijn(en) waren er bewegingen tijdens het tellen; de getelde hoeveelheid heeft ze vervangen.';
  }

  @override
  String get countNew => 'Nieuwe inventarisatie';

  @override
  String countOf(int count, int total) {
    return '$count van $total';
  }

  @override
  String get countOneProduct => 'Slechts één product (optioneel)';

  @override
  String get countOverwriteWarning =>
      'Bewegingen tijdens het tellen worden overschreven: bij het boeken van de inventarisatie wordt de getelde hoeveelheid de voorraad.';

  @override
  String get countPost => 'Inventarisatie boeken';

  @override
  String get countPostConfirm =>
      'De verschillen worden als voorraadcorrecties geboekt. Lijnen zonder getelde hoeveelheid blijven ongewijzigd.';

  @override
  String get countProgress => 'Geteld';

  @override
  String get countStart => 'Inventarisatie starten';

  @override
  String get countStatusCounting => 'Bezig';

  @override
  String get countStatusPosted => 'Geboekt';

  @override
  String countStockAtPost(String quantity) {
    return 'Voorraad bij het boeken: $quantity';
  }

  @override
  String get countWarehouseRequired => 'Kies een magazijn.';

  @override
  String get countWholeWarehouse => 'Heel het magazijn';

  @override
  String get countedBy => 'Gestart door';

  @override
  String get country => 'Land';

  @override
  String get create => 'Aanmaken';

  @override
  String get createLead => 'Lead aanmaken';

  @override
  String get createRepair => 'Herstelling aanmaken';

  @override
  String get created => 'aangemaakt';

  @override
  String get csatAlready => 'Deze enquête werd al beantwoord.';

  @override
  String get csatAverage => 'Klanttevredenheid';

  @override
  String get csatBad => 'Niet tevreden';

  @override
  String get csatComment => 'Opmerking (optioneel)';

  @override
  String get csatEnabled =>
      'Tevredenheidsenquête sturen bij het sluiten van een ticket';

  @override
  String get csatExpired => 'Deze link is verlopen.';

  @override
  String get csatGood => 'Tevreden';

  @override
  String get csatNone => 'Nog geen beoordeling';

  @override
  String csatQuestion(String number) {
    return 'Hoe tevreden bent u over de afhandeling van ticket $number?';
  }

  @override
  String csatResponses(int count) {
    return '$count antwoorden';
  }

  @override
  String get csatThanks => 'Bedankt voor uw feedback!';

  @override
  String get csatTitle => 'Klanttevredenheid';

  @override
  String get csvCopied => 'CSV gekopieerd naar het klembord';

  @override
  String get current => 'Huidig';

  @override
  String get customer => 'Klant';

  @override
  String get customerDeclinedToSign => 'De klant weigerde te tekenen';

  @override
  String get customerEquipment => 'Installaties van de klant';

  @override
  String get customerLanguage => 'Taal klant';

  @override
  String customerMainNumber(String name) {
    return 'Hoofdnummer van $name';
  }

  @override
  String customerNamed(String name) {
    return 'Klant: $name';
  }

  @override
  String get customerOptional => 'Klant (optioneel)';

  @override
  String get customerReference => 'Referentie klant';

  @override
  String get customers => 'Klanten';

  @override
  String get customerSignature => 'Handtekening klant';

  @override
  String get date => 'Datum';

  @override
  String declinedToSignWithReason(String reason) {
    return 'Weigerde te tekenen: $reason';
  }

  @override
  String get defaultTeam => 'Standaardteam voor nieuwe tickets';

  @override
  String get deleteRuleConfirm =>
      'Deze regel verwijderen? Tickets die ze wijzigde, behouden hun wijzigingen.';

  @override
  String get deliveries => 'Leveringen';

  @override
  String get deliveryBlocked =>
      'Leveren op een gesloten dag is niet toegestaan. Kies een andere datum.';

  @override
  String get deliveryCancel => 'Levering annuleren';

  @override
  String get deliveryCancelReason => 'Reden van annulering';

  @override
  String get deliveryChooseSerial => 'Kies serienummer';

  @override
  String deliveryClosedWarning(String from, String to, String next) {
    return 'De klant is gesloten van $from tot $to. Eerstvolgende open dag: $next.';
  }

  @override
  String get deliveryFailed => 'niet verzonden';

  @override
  String get deliveryLocation => 'Locatie';

  @override
  String get deliveryLot => 'Lot';

  @override
  String get deliveryNew => 'Nieuwe levering';

  @override
  String get deliveryNoDate => 'geen datum';

  @override
  String get deliveryNoLines =>
      'Nog niets te leveren: reserveer eerst voorraad voor de order.';

  @override
  String get deliveryOnClosure => 'tijdens een sluiting';

  @override
  String get deliveryOverrideNeedsRight =>
      'Leveren op een gesloten dag vraagt een reden en het recht om te overrulen.';

  @override
  String get deliveryOverrideReason =>
      'Reden om op een gesloten dag te leveren';

  @override
  String get deliveryPicking => 'Pickinglijst';

  @override
  String get deliveryPlannedDate => 'Geplande datum';

  @override
  String get deliveryQueued => 'wacht op verzending';

  @override
  String get deliverySent => 'verzonden';

  @override
  String get deliverySerial => 'Serienummer';

  @override
  String get deliverySettingsTitle => 'Leverinstellingen';

  @override
  String get deliveryShip => 'Verzenden';

  @override
  String get deliveryShipTo => 'Leveradres';

  @override
  String get deliveryShippedSnack => 'Levering verzonden';

  @override
  String get deliveryStatusPlanned => 'gepland';

  @override
  String get deliveryStatusShipped => 'verzonden';

  @override
  String deliveryUseDay(String date) {
    return 'Kies $date';
  }

  @override
  String get department => 'Afdeling';

  @override
  String get departmentCode => 'Code';

  @override
  String get departmentMembers => 'Collega\'s in deze afdeling';

  @override
  String get departments => 'Afdelingen';

  @override
  String get departmentsHelp =>
      'Herstellingen worden naar deze afdelingen doorgestuurd. Enkel collega\'s van een afdeling kunnen haar herstellingen behandelen.';

  @override
  String get description => 'Omschrijving';

  @override
  String get devModeHelp => 'De server moet draaien met AUTH_MODE=dev';

  @override
  String get developmentUser => 'Ontwikkelgebruiker';

  @override
  String get deviceLanguage => 'Taal van het toestel';

  @override
  String get difference => 'Verschil';

  @override
  String get dismiss => 'Afwijzen';

  @override
  String get dismissRequest => 'Aanvraag afwijzen';

  @override
  String get draftSaved => 'Concept opgeslagen';

  @override
  String get dryRun => 'Testen op een ticket';

  @override
  String get dryRunHelp =>
      'Toont welke regels op een ticket van toepassing zouden zijn en wat ze zouden wijzigen. Er wordt niets gewijzigd.';

  @override
  String get dryRunRun => 'Test uitvoeren';

  @override
  String get drawSignatureFirst => 'Teken eerst een handtekening';

  @override
  String dueOnDate(String date) {
    return 'Uit te voeren op $date';
  }

  @override
  String get edit => 'Bewerken';

  @override
  String get editClosure => 'Sluiting wijzigen';

  @override
  String get editContact => 'Contactpersoon bewerken';

  @override
  String get editDepartment => 'Afdeling bewerken';

  @override
  String get editJob => 'Opdracht bewerken';

  @override
  String get email => 'E-mail';

  @override
  String get emailAddresses => 'E-mailadressen (het eerste is het hoofdadres)';

  @override
  String get endContract => 'Contract beëindigen';

  @override
  String get endDate => 'Einddatum';

  @override
  String get enterChange => 'Geef de wijziging in, bv. 4,5 voor +4,5 %.';

  @override
  String enterValidNumbersLine(int line) {
    return 'Lijn $line: geef geldige getallen in.';
  }

  @override
  String get equipment => 'Installatie';

  @override
  String get estimatedMinutes => 'Geschatte minuten';

  @override
  String get expectedClose => 'Verwachte afsluiting';

  @override
  String expectedCloseDate(String date) {
    return 'Verwachte afsluiting $date';
  }

  @override
  String get expectedValue => 'Verwachte waarde';

  @override
  String get expectedValueEur => 'Verwachte waarde (€)';

  @override
  String get expectedValueOptional => 'Verwachte waarde (optioneel)';

  @override
  String get explode => 'Uitsplitsen';

  @override
  String get exportCsv => 'Kopiëren als CSV';

  @override
  String get families => 'Families';

  @override
  String get family => 'Familie';

  @override
  String familyNamed(String code) {
    return 'Familie $code';
  }

  @override
  String get faultDescription => 'Wat is er mis';

  @override
  String get firstDueDate => 'Eerste uitvoerdatum';

  @override
  String get firstName => 'Voornaam';

  @override
  String get firstResponseMinutes => 'Eerste reactie (min)';

  @override
  String get firstResponseTime => 'Eerste reactie';

  @override
  String get from => 'Vanaf';

  @override
  String get fromYou => 'U';

  @override
  String generalRebateInfo(String percent) {
    return 'Algemene korting op alle producten: $percent % (nettoproducten krijgen nooit korting).';
  }

  @override
  String get generalRebatePercent => 'Algemene korting %';

  @override
  String greetingPreview(String greeting) {
    return 'Aanspreking: $greeting';
  }

  @override
  String get helpdesk => 'Helpdesk';

  @override
  String get helpdeskReports => 'Rapporten';

  @override
  String get helpdeskSettings => 'Helpdesk-instellingen';

  @override
  String get history => 'Geschiedenis';

  @override
  String get holidayDate => 'Datum';

  @override
  String get holidayInvalid => 'Geef een datum (JJJJ-MM-DD) en een naam in.';

  @override
  String get holidays => 'Feestdagen';

  @override
  String get holidaysHelp => 'Dagen waarop de helpdesk gesloten is.';

  @override
  String get calendarFor => 'Kalender voor';

  @override
  String get calendarCompanyWide => 'Hele bedrijf';

  @override
  String get calendarInherited =>
      'Dit team heeft geen eigen kalender en gebruikt die van het bedrijf. Opslaan maakt er een voor het team.';

  @override
  String get calendarHolidaysInherited =>
      'De feestdagen van het bedrijf gelden ook voor dit team. Feestdagen die je hier toevoegt, zijn van het team zelf.';

  @override
  String get calendarUseCompany => 'Bedrijfskalender gebruiken';

  @override
  String get calendarRemoved => 'Het team gebruikt weer de bedrijfskalender.';

  @override
  String get basisMixed => 'openingsuren of verstreken tijd, per team';

  @override
  String get inactive => 'inactief';

  @override
  String get inactiveContact => 'Niet meer actief (vertrokken)';

  @override
  String indicativeLine(String description) {
    return '$description (indicatief, te bevestigen)';
  }

  @override
  String indicativeToConfirm(int count) {
    return '$count indicatieve prijs/prijzen te bevestigen voor de offerte verzonden kan worden: geef de afgesproken prijs in het veld lijstprijs in.';
  }

  @override
  String get insertPreparedAnswer => 'Standaardantwoord invoegen';

  @override
  String get instructions => 'Instructies';

  @override
  String get internalNote => 'Interne notitie';

  @override
  String internalQuestionHelp(String language) {
    return 'Interne vraag. Stel de vraag aan de klant in het $language via een antwoord, en zet het antwoord daarna als interne notitie voor je collega.';
  }

  @override
  String get internalTicket => 'Intern ticket';

  @override
  String get internalTicketHelp =>
      'Een vraag tussen collega\'s; er wordt niets naar de klant gestuurd.';

  @override
  String get interval => 'Interval';

  @override
  String get jobCancelled => 'Geannuleerd';

  @override
  String get jobCompleted => 'Afgewerkt';

  @override
  String jobCount(String count) {
    return '$count opdrachten';
  }

  @override
  String jobCreatedOnDate(String date) {
    return 'opdracht wordt aangemaakt op $date';
  }

  @override
  String get jobInProgress => 'Bezig';

  @override
  String get jobKindInspection => 'Inspectie';

  @override
  String get jobKindInstallation => 'Installatie';

  @override
  String get jobKindMaintenance => 'Onderhoud';

  @override
  String get jobKindOther => 'Andere';

  @override
  String get jobKindRepair => 'Herstelling';

  @override
  String get jobName => 'Titel';

  @override
  String get jobPlanned => 'Gepland';

  @override
  String get jobTitle => 'Functie';

  @override
  String get jobs => 'Opdrachten';

  @override
  String get keepAgreedPrices => 'Afgesproken prijzen behouden';

  @override
  String get language => 'Taal';

  @override
  String languageSameAsCustomer(String language) {
    return 'Zelfde als het bedrijf ($language)';
  }

  @override
  String lastDays(int days) {
    return 'Laatste $days dagen';
  }

  @override
  String get lastName => 'Achternaam';

  @override
  String get leadCreated => 'Lead aangemaakt';

  @override
  String get leadDays => 'Opdracht aanmaken (dagen vooraf)';

  @override
  String get lineDiscount => 'Extra kort. ±';

  @override
  String get listPrice => 'Lijstprijs';

  @override
  String get loadMore => 'Meer laden';

  @override
  String get logCall => 'Gesprek registreren';

  @override
  String get logTime => 'Tijd registreren';

  @override
  String get logWork => 'Werk registreren';

  @override
  String get loginLinkInvalid =>
      'Deze aanmeldlink is verlopen of al gebruikt. Vraag een nieuwe aan.';

  @override
  String get loginLinkSent =>
      'Als dit adres het portaal mag gebruiken, is er een aanmeldlink onderweg. Controleer uw inbox.';

  @override
  String get lookUp => 'Opzoeken';

  @override
  String get lost => 'Verloren';

  @override
  String get lostReason => 'Reden verlies';

  @override
  String get markAsLost => 'Markeren als verloren';

  @override
  String get markAsSent => 'Markeren als verzonden';

  @override
  String get markCompleted => 'Markeer als afgewerkt';

  @override
  String get markReceived => 'Markeer als ontvangen';

  @override
  String get markShipped => 'Markeer als teruggestuurd';

  @override
  String get markWaitingCustomer => 'Wacht op klant';

  @override
  String get markWaitingParts => 'Wacht op onderdelen';

  @override
  String get materialRequirements => 'Materiaalbehoefte (actieve revisie)';

  @override
  String get mergeAction => 'Samenvoegen';

  @override
  String get mergeHelp =>
      'Alle berichten, bestanden, labels en tijdsregistraties gaan naar het gekozen ticket van dezelfde klant. Dit ticket wordt gesloten. Dit kan niet ongedaan gemaakt worden.';

  @override
  String get mergeNoCandidates => 'Geen ander open ticket van deze klant.';

  @override
  String get mergeTicket => 'Samenvoegen met ander ticket…';

  @override
  String mergedInto(String number) {
    return 'Samengevoegd met $number';
  }

  @override
  String get message => 'Bericht';

  @override
  String get messageSent => 'Bericht verzonden';

  @override
  String get minutes => 'Minuten';

  @override
  String minutesShort(String minutes) {
    return '$minutes min';
  }

  @override
  String get moduleDelivery => 'Levering';

  @override
  String get moduleProduction => 'Productie';

  @override
  String get moveDown => 'Naar beneden';

  @override
  String get moveUp => 'Naar boven';

  @override
  String get months => 'Maanden';

  @override
  String get myJobs => 'Mijn opdrachten';

  @override
  String get myOrders => 'Mijn orders';

  @override
  String get myProfile => 'Mijn gegevens';

  @override
  String get myRepairs => 'Mijn herstellingen';

  @override
  String get myTickets => 'Mijn tickets';

  @override
  String get name => 'Naam';

  @override
  String get navigate => 'Navigeer';

  @override
  String get netPrice => 'Nettoprijs';

  @override
  String get newAnswer => 'Nieuw antwoord';

  @override
  String get newContact => 'Nieuwe contactpersoon';

  @override
  String get newContract => 'Nieuw contract';

  @override
  String get newCustomer => 'Nieuwe klant';

  @override
  String get newDepartment => 'Nieuwe afdeling';

  @override
  String get newFamily => 'Nieuwe familie';

  @override
  String get newItem => 'Nieuw';

  @override
  String get newJob => 'Nieuwe opdracht';

  @override
  String get newLabel => 'Nieuw';

  @override
  String get newOpportunity => 'Nieuwe opportuniteit';

  @override
  String get newPrice => 'Nieuwe prijs';

  @override
  String newPricesValidFrom(String date) {
    return 'Nieuwe prijzen geldig vanaf $date';
  }

  @override
  String get newPriority => 'Nieuwe prioriteit';

  @override
  String get newProduct => 'Nieuw product';

  @override
  String get newQuotation => 'Nieuwe offerte';

  @override
  String get newRepair => 'Nieuwe herstelling';

  @override
  String get newRevision => 'Nieuwe revisie';

  @override
  String newRevisionOf(String number) {
    return 'Nieuwe revisie van $number';
  }

  @override
  String get newRule => 'Nieuwe regel';

  @override
  String get newTeam => 'Nieuw team';

  @override
  String get newTicket => 'Nieuw ticket';

  @override
  String get no => 'Nee';

  @override
  String get noAccess =>
      'Uw account heeft nog geen toegang tot een onderdeel. Vraag het aan een beheerder.';

  @override
  String get noActiveBom => 'Geen actieve stuklijst.';

  @override
  String get noBom => 'Nog geen stuklijst.';

  @override
  String get noClosures => 'Geen sluitingen geregistreerd.';

  @override
  String get noContactLinked => 'Geen contactpersoon gekoppeld';

  @override
  String get noContacts => 'Nog geen contactpersonen.';

  @override
  String get noContracts => 'Geen contracten';

  @override
  String get noCustomerEquipment =>
      'Deze klant heeft geen geïnstalleerde toestellen';

  @override
  String get noCustomerLinked => 'Geen klant gekoppeld';

  @override
  String get noEquipment => 'Geen installatie gekoppeld';

  @override
  String get noExpectedClose => 'Geen verwachte afsluitdatum';

  @override
  String get noJobsAssigned => 'Geen opdrachten aan u toegewezen.';

  @override
  String get noLines => 'Nog geen lijnen.';

  @override
  String get noOrdersYet => 'U hebt nog geen orders.';

  @override
  String get noParts => 'Geen onderdelen geregistreerd';

  @override
  String get noPermission =>
      'U hebt geen toelating om deze instellingen te wijzigen.';

  @override
  String get noPhotos => 'Nog geen foto\'s.';

  @override
  String get noPrices => 'Nog geen prijzen.';

  @override
  String get noPriorityChanges => 'Nog geen prioriteitswijzigingen.';

  @override
  String get noPriorityRequests => 'Geen aanvragen.';

  @override
  String get noQuotations => 'Nog geen offertes.';

  @override
  String get noRebates => 'Geen product- of familiekortingen.';

  @override
  String get noRepairs => 'Geen herstellingen.';

  @override
  String get noRepairsYet => 'U hebt nog geen herstellingen.';

  @override
  String get noRules => 'Nog geen regels.';

  @override
  String get noSerialComponents => 'Geen componenten met serienummer.';

  @override
  String get noSignature => 'Nog niet getekend';

  @override
  String get noTeam => 'Geen team';

  @override
  String get noTechnicians => 'Niemand toegewezen';

  @override
  String get noTicketsYet => 'U hebt nog geen tickets.';

  @override
  String get noTimeEntries => 'Nog geen tijd geregistreerd.';

  @override
  String get nobodyFound => 'Niemand gevonden met dit nummer.';

  @override
  String get nonBillable => 'Niet factureerbaar';

  @override
  String get none => 'Geen';

  @override
  String get notClosed => 'Niet afgesloten';

  @override
  String get notRouted => 'Nog niet doorgestuurd';

  @override
  String get notScheduled => 'Niet gepland';

  @override
  String get noteAdded => 'Notitie toegevoegd';

  @override
  String get noteOptional => 'Opmerking (optioneel)';

  @override
  String get notes => 'Opmerkingen';

  @override
  String get noUpcomingVisits => 'Geen bezoeken gepland';

  @override
  String get number => 'Nummer';

  @override
  String get numberRequired => 'Getal';

  @override
  String get obsoleteRevision => 'Vervallen revisie (alleen lezen).';

  @override
  String get oidcAccessToken => 'OIDC-toegangstoken';

  @override
  String get ok => 'OK';

  @override
  String get onSiteContact => 'Contactpersoon ter plaatse';

  @override
  String get openEnded => 'open';

  @override
  String get openJobsOnly => 'Enkel actieve';

  @override
  String get openOnly => 'Enkel open';

  @override
  String get openOpportunity => 'Opportuniteit openen';

  @override
  String openPriorityRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count openstaande prioriteitsaanvragen',
      one: '1 openstaande prioriteitsaanvraag',
    );
    return '$_temp0';
  }

  @override
  String openRepairsCount(String count) {
    return '$count open';
  }

  @override
  String get opens => 'Opent';

  @override
  String get opportunities => 'Opportuniteiten';

  @override
  String get opportunity => 'Opportuniteit';

  @override
  String get opportunityOptional => 'Opportuniteit (optioneel)';

  @override
  String get order => 'Order';

  @override
  String orderAlreadyConfirmed(String date) {
    return 'Deze order is bevestigd op $date.';
  }

  @override
  String get orderAwaitingConfirmation => 'wacht op uw bevestiging';

  @override
  String get orderConfirmationQueued =>
      'Orderbevestiging staat klaar om te worden verzonden.';

  @override
  String get orderConfirmedSnack => 'Order bevestigd.';

  @override
  String get orderConfirmedThanks => 'Bedankt, uw order is bevestigd.';

  @override
  String get orderCreated => 'Order aangemaakt';

  @override
  String get orderSaved => 'Order opgeslagen.';

  @override
  String get orderStatusInPlanning => 'in planning';

  @override
  String get orderStatusInProduction => 'in productie';

  @override
  String get orderStatusPartiallyShipped => 'gedeeltelijk verzonden';

  @override
  String get orderStatusPlanned => 'ingepland';

  @override
  String get orderStatusReadyForShipping => 'klaar voor verzending';

  @override
  String get orderStatusShipped => 'verzonden';

  @override
  String get orderStockRelease => 'Vrijgeven';

  @override
  String get orderStockReserve => 'Reserveren';

  @override
  String get orderStockReserveHint =>
      'Voorraad kan gereserveerd worden zodra de klant de order bevestigd heeft.';

  @override
  String orderStockThisLine(String quantity) {
    return '$quantity gereserveerd voor deze lijn';
  }

  @override
  String get orderStockTitle => 'Voorraadbeschikbaarheid';

  @override
  String get orders => 'Orders';

  @override
  String get owner => 'Verantwoordelijke';

  @override
  String get ownerEmpty => 'Niemand';

  @override
  String get ownerSet => 'Iemand';

  @override
  String get p90 => '90% binnen';

  @override
  String get partFreeTextHint => 'Kies een product of typ een omschrijving';

  @override
  String get partsUsed => 'Gebruikte onderdelen';

  @override
  String get paymentDays => 'Betalingstermijn (dagen)';

  @override
  String get pdf => 'PDF';

  @override
  String get perDay => 'Per dag';

  @override
  String get perWeek => 'Per week';

  @override
  String get personTitle => 'Aanspreektitel';

  @override
  String get phone => 'Telefoon';

  @override
  String get phoneCall => 'Telefoongesprek';

  @override
  String get phoneDirect => 'Rechtstreeks';

  @override
  String get phoneHint => 'Met landcode, bv. +32 475 12 34 56';

  @override
  String get phoneMobile => 'Gsm';

  @override
  String get phoneNumber => 'Telefoonnummer';

  @override
  String get phoneNumbers => 'Telefoonnummers';

  @override
  String get phoneOther => 'Andere';

  @override
  String get phoneWork => 'Werk';

  @override
  String photoBy(String name) {
    return 'door $name';
  }

  @override
  String get photos => 'Foto\'s';

  @override
  String get photosAdded => 'Foto\'s toegevoegd';

  @override
  String get placeholdersHelp =>
      'Plaatshouders (klik om in te voegen in de huidige taal):';

  @override
  String get portalAccess => 'Toegang tot het klantenportaal';

  @override
  String get portalScope => 'Ziet in het portaal';

  @override
  String get portalScopeCustomer => 'Alle tickets van het bedrijf';

  @override
  String get portalScopeOwn => 'Enkel eigen tickets';

  @override
  String get portalSignInIntro =>
      'Geef uw e-mailadres op. U ontvangt een link om aan te melden, een wachtwoord is niet nodig.';

  @override
  String get portalTitle => 'Klantenportaal';

  @override
  String get postalCode => 'Postcode';

  @override
  String get preparedAnswers => 'Standaardantwoorden';

  @override
  String get preparedAnswersHelp =>
      'Herbruikbare antwoorden op terugkerende vragen, één tekst per taal. Plaatshouders zoals «quotation.number» worden ingevuld voor het ticket; de tekst kan nog aangepast worden voor verzending.';

  @override
  String get preview => 'Voorbeeld';

  @override
  String priceListOf(String date) {
    return 'Prijslijst van $date';
  }

  @override
  String get priceListValidOn => 'Prijslijst geldig op';

  @override
  String get priceZone => 'Prijszone';

  @override
  String pricedOnPriceListOf(String date) {
    return 'Geprijsd volgens de prijslijst van $date';
  }

  @override
  String get prices => 'Prijzen';

  @override
  String pricesCreated(int count, String date) {
    return '$count prijzen aangemaakt, geldig vanaf $date';
  }

  @override
  String pricesWillChange(int count) {
    return '$count prijzen wijzigen';
  }

  @override
  String get pricing => 'Prijszetting';

  @override
  String get pricingIndicative => 'indicatief';

  @override
  String get pricingIndicativeHelp => 'Indicatief (per offerte bevestigen)';

  @override
  String get pricingList => 'lijstprijs';

  @override
  String get pricingListHelp => 'Lijstprijs (kortingen van toepassing)';

  @override
  String get pricingNet => 'netto';

  @override
  String get pricingNetHelp => 'Nettoprijs (nooit korting)';

  @override
  String get priority => 'Prioriteit';

  @override
  String priorityChangeLine(String date, String from, String to, String name) {
    return '$date: $from → $to door $name';
  }

  @override
  String get priorityChangedSnack => 'Prioriteit gewijzigd.';

  @override
  String get priorityExpedite => 'spoed';

  @override
  String get priorityHigh => 'hoog';

  @override
  String get priorityHistory => 'Historiek van de prioriteit';

  @override
  String get priorityLow => 'laag';

  @override
  String get priorityNormal => 'normaal';

  @override
  String get priorityRequestHelp =>
      'Ons team beslist of en hoe de prioriteit wordt aangepast.';

  @override
  String priorityRequestLine(String name, String priority) {
    return '$name vraagt prioriteit: $priority';
  }

  @override
  String get priorityRequestSent => 'Uw aanvraag is verzonden.';

  @override
  String get priorityRequests => 'Prioriteitsaanvragen van de klant';

  @override
  String get priorityUrgent => 'dringend';

  @override
  String get probability => 'Kans';

  @override
  String get probabilityPercent => 'Kans %';

  @override
  String get probabilityShort => 'Kans';

  @override
  String get product => 'Product';

  @override
  String productCount(int count) {
    return '$count producten';
  }

  @override
  String get productDescription => 'Product';

  @override
  String get productFamilies => 'Productfamilies';

  @override
  String get productFamily => 'Productfamilie';

  @override
  String get productRebates => 'Productkortingen';

  @override
  String get productTypeConfigurable => 'configureerbaar';

  @override
  String get productTypeManufactured => 'eigen productie';

  @override
  String get productTypePurchased => 'aangekocht';

  @override
  String get productTypeService => 'dienst';

  @override
  String get production => 'Productie';

  @override
  String productionBomRevision(String revision) {
    return 'Stuklijstrevisie $revision';
  }

  @override
  String get productionBuildComponent => 'Maken';

  @override
  String get productionBuildForStock => 'Voor voorraad maken';

  @override
  String get productionCancel => 'Productieorder annuleren';

  @override
  String get productionCancelReason => 'Reden van annulering';

  @override
  String get productionChooseSerials => 'Kies serienummers';

  @override
  String get productionComplete => 'Afronden';

  @override
  String get productionCompleted => 'Productieorder afgerond';

  @override
  String get productionComponents => 'Componenten';

  @override
  String get productionConsumed => 'Verbruikt';

  @override
  String get productionDivision => 'Afdeling';

  @override
  String get productionDivisionAdd => 'Afdeling toevoegen';

  @override
  String get productionDivisionEdit => 'Afdeling wijzigen';

  @override
  String get productionDivisions => 'Afdelingen';

  @override
  String get productionExpiry => 'Vervaldatum';

  @override
  String get productionExtraFrom => 'Extra voorraad genomen uit';

  @override
  String get productionLocation => 'Opslaan in';

  @override
  String get productionLot => 'Lotnummer';

  @override
  String get productionNoDivision => 'geen afdeling';

  @override
  String get productionNothingToRelease =>
      'Niets vrij te geven: elke te maken orderregel is gedekt door productieorders.';

  @override
  String get productionOrderCancelled =>
      'De verkooporder is geannuleerd. Annuleer deze productieorder om de componenten vrij te geven.';

  @override
  String get productionOrdersOfOrder => 'Productieorders';

  @override
  String get productionOutput => 'Resultaat';

  @override
  String get productionPlannedReady => 'Gepland klaar';

  @override
  String get productionPromised => 'Beloofd';

  @override
  String get productionQuantityBuilt => 'Gemaakte hoeveelheid';

  @override
  String get productionRelease => 'Vrijgeven aan productie';

  @override
  String get productionReleased => 'Vrijgegeven aan productie';

  @override
  String get productionRequired => 'Nodig';

  @override
  String get productionReserveAgain => 'Opnieuw reserveren';

  @override
  String get productionReserved => 'Gereserveerd';

  @override
  String get productionScrap => 'Afval';

  @override
  String get productionSerials => 'Serienummers, één per regel';

  @override
  String productionSerialsNeeded(String count) {
    return 'Kies $count serienummers';
  }

  @override
  String get productionShort => 'tekort aan voorraad';

  @override
  String get productionStart => 'Starten';

  @override
  String get productionStatusCompleted => 'afgerond';

  @override
  String get productionStatusInProgress => 'in uitvoering';

  @override
  String get productionStatusReleased => 'vrijgegeven';

  @override
  String get productionToRelease => 'Vrij te geven';

  @override
  String get products => 'Producten';

  @override
  String get profileHelp =>
      'Kies de taal en hoe wij u aanspreken in onze e-mails en in dit portaal.';

  @override
  String get quantity => 'Aantal';

  @override
  String get question => 'Vraag';

  @override
  String get questionToSales => 'Vraag aan verkoop';

  @override
  String questionToSalesHelp(String salesperson) {
    return '$salesperson krijgt deze vraag en stelt ze aan de klant in diens taal.';
  }

  @override
  String get quotation => 'Offerte';

  @override
  String get quotations => 'Offertes';

  @override
  String raisedBy(String name) {
    return 'Aangemaakt door $name';
  }

  @override
  String get reason => 'Reden';

  @override
  String get reasonRequired => 'Een reden is verplicht.';

  @override
  String get rebate => 'Std. korting';

  @override
  String rebateFor(String target, String percent) {
    return '$target: $percent %';
  }

  @override
  String get rebatePercent => 'Korting %';

  @override
  String get rebateSourceFamily => 'familie';

  @override
  String get rebateSourceGeneral => 'algemeen';

  @override
  String get rebateSourceProduct => 'product';

  @override
  String rebatesOf(String customer) {
    return 'Kortingen · $customer';
  }

  @override
  String get recurrenceMonthList => 'In gekozen maanden';

  @override
  String get recurrenceMonths => 'Om de N maanden';

  @override
  String get recurrenceWeeks => 'Om de N weken';

  @override
  String registerProduct(String product) {
    return '$product registreren';
  }

  @override
  String get registerUnit => 'Exemplaar registreren';

  @override
  String get registered => 'Geregistreerd';

  @override
  String get rejected => 'Geweigerd';

  @override
  String get remove => 'Verwijderen';

  @override
  String get removeAndScrap => 'Verwijderen en afdanken';

  @override
  String get removeBackToStock => 'Verwijderen, terug naar stock';

  @override
  String get removeLine => 'Regel verwijderen';

  @override
  String removedBy(String date, String name) {
    return 'verwijderd $date door $name';
  }

  @override
  String get reopenJob => 'Opdracht heropenen';

  @override
  String get repairAnnouncedByTicket =>
      'De klant kondigde het aan (het product is nog niet toegekomen)';

  @override
  String get repairAnnouncedOk =>
      'Herstelling aangekondigd. Schrijf het nummer op het pakket en stuur het product naar ons op.';

  @override
  String get repairPhotosHelp =>
      'Foto\'s van het product en het defect helpen ons enorm.';

  @override
  String get repairPortalAnnounced => 'Aangekondigd, nog niet ontvangen';

  @override
  String get repairPortalInRepair => 'In herstelling';

  @override
  String get repairPortalReady => 'Hersteld, klaar voor verzending';

  @override
  String get repairPortalWaitingCustomer => 'Wacht op uw antwoord';

  @override
  String get repairStatusAnnounced => 'Aangekondigd';

  @override
  String get repairStatusCancelled => 'Geannuleerd';

  @override
  String get repairStatusCompleted => 'Afgewerkt';

  @override
  String get repairStatusInProgress => 'In behandeling';

  @override
  String get repairStatusReceived => 'Ontvangen';

  @override
  String get repairStatusRouted => 'In wachtrij van afdeling';

  @override
  String get repairStatusShipped => 'Teruggestuurd';

  @override
  String get repairStatusWaitingCustomer => 'Wacht op klant';

  @override
  String get repairStatusWaitingParts => 'Wacht op onderdelen';

  @override
  String get repairs => 'Herstellingen';

  @override
  String get replaceSignature => 'Handtekening vervangen';

  @override
  String get replyQueued => 'Antwoord klaar voor verzending';

  @override
  String get replyToCustomer => 'Antwoord aan klant';

  @override
  String get reportQueued => 'De werkbon wordt verstuurd';

  @override
  String get reportSend => 'Werkbon per e-mail versturen';

  @override
  String reportSentTo(String to, String date) {
    return 'Verstuurd naar $to op $date';
  }

  @override
  String get reportView => 'Werkbon bekijken (PDF)';

  @override
  String repricingFailed(String error) {
    return 'De prijzen van vandaag konden niet berekend worden: $error';
  }

  @override
  String get requestDismissedSnack => 'Aanvraag afgewezen.';

  @override
  String get requestLessUrgent => 'Minder dringend';

  @override
  String get requestMoreUrgent => 'Dringender (spoed)';

  @override
  String get requestPriorityChange => 'Wijziging van prioriteit aanvragen';

  @override
  String get requestStatusApplied => 'toegepast';

  @override
  String get requestStatusDismissed => 'afgewezen';

  @override
  String get requestStatusOpen => 'open';

  @override
  String get required => 'Verplicht';

  @override
  String get resolutionHours => 'Oplossing binnen (uren)';

  @override
  String get resolutionMinutes => 'Oplossing (min)';

  @override
  String get resolutionTime => 'Oplossing';

  @override
  String get responseTimes => 'Reactie- en oplossingstijden';

  @override
  String get responseHours => 'Reactie binnen (uren)';

  @override
  String get retry => 'Opnieuw';

  @override
  String get revisionActivated => 'Revisie geactiveerd';

  @override
  String revisionItem(int revision, String status, int lines) {
    return 'Revisie $revision · $status · $lines lijnen';
  }

  @override
  String get revisionNotes => 'Revisienotities';

  @override
  String revisionNumber(int revision) {
    return 'Revisie $revision';
  }

  @override
  String revisionPriceLists(String agreed, String current) {
    return 'Afgesproken prijzen: prijslijst van $agreed. Huidige prijzen: prijslijst van $current.';
  }

  @override
  String revisionViewNotice(int revision, int current) {
    return 'U bekijkt revisie $revision (alleen lezen). De huidige revisie is $current.';
  }

  @override
  String get revisions => 'Revisies';

  @override
  String get roleInvoicing => 'Facturatie';

  @override
  String get roleManagement => 'Directie';

  @override
  String get roleOther => 'Andere';

  @override
  String get rolePurchasing => 'Aankoop';

  @override
  String get roleQuality => 'Kwaliteit';

  @override
  String get roleSalesContact => 'Commercieel contact';

  @override
  String get roleTechnical => 'Technicus';

  @override
  String get roles => 'Rollen';

  @override
  String get roundTo => 'Afronden op';

  @override
  String get routeNote => 'Opmerking voor de afdeling';

  @override
  String get routeRepair => 'Doorsturen naar afdeling';

  @override
  String get ruleActions => 'Acties';

  @override
  String get ruleConditions => 'Voorwaarden (alle moeten kloppen)';

  @override
  String get ruleConditionsHelp =>
      'Kies per lijn evenveel waarden als je wilt; een ticket heeft er één van nodig. Lege lijnen tellen niet mee.';

  @override
  String get ruleNameRequired => 'Een regel heeft een naam nodig.';

  @override
  String get ruleResultAfterStop => 'overgeslagen (gestopt)';

  @override
  String get ruleResultInactive => 'uit';

  @override
  String get ruleResultMatched => 'geldt';

  @override
  String get ruleResultNoMatch => 'past niet';

  @override
  String get ruleResultOtherTrigger => 'andere gebeurtenis';

  @override
  String get ruleTrigger => 'Wanneer';

  @override
  String get ruleTriggerCreated => 'Een ticket wordt aangemaakt';

  @override
  String get ruleTriggerCustomerReplied => 'De klant antwoordt';

  @override
  String get ruleTriggerUpdated =>
      'Een ticket wordt door een medewerker gewijzigd';

  @override
  String get salesperson => 'Verkoper';

  @override
  String get save => 'Opslaan';

  @override
  String get saveChanges => 'Wijzigingen opslaan';

  @override
  String get saveDraft => 'Concept opslaan';

  @override
  String get saved => 'Opgeslagen';

  @override
  String savedNumber(String number) {
    return '$number opgeslagen';
  }

  @override
  String get scheduledEnd => 'Einde';

  @override
  String get scheduledStart => 'Start';

  @override
  String get scrapPercent => 'Uitval %';

  @override
  String get search => 'Zoeken';

  @override
  String get send => 'Verzenden';

  @override
  String get sendBackToTriage => 'Terug naar triage';

  @override
  String get sendLoginLink => 'Verstuur aanmeldlink';

  @override
  String get sendOrderConfirmation => 'Orderbevestiging verzenden';

  @override
  String get sendOrderConfirmationHelp =>
      'De orderbevestiging wordt als pdf naar de klant gemaild. Daarna kan de revisie niet meer worden bewerkt.';

  @override
  String get senderDomain => 'Domein van de afzender';

  @override
  String get serial => 'serienummer';

  @override
  String get serialBuiltIn => 'ingebouwd';

  @override
  String get serialDelivered => 'geleverd';

  @override
  String get serialInStock => 'in stock';

  @override
  String get serialInstalled => 'geïnstalleerd';

  @override
  String get serialNumber => 'Serienummer';

  @override
  String get serialNumbers => 'Serienummers';

  @override
  String get serialNumbersHelp =>
      'Elk exemplaar krijgt een eigen serienummer en historiek';

  @override
  String get serialScrapped => 'afgedankt';

  @override
  String get server => 'Server';

  @override
  String get serviceReport => 'Werkbon';

  @override
  String get setWarranty => 'Garantie instellen';

  @override
  String get showInactive => 'Toon inactieve';

  @override
  String signedByOn(String name, String date) {
    return 'Getekend door $name op $date';
  }

  @override
  String get signerName => 'Naam van de ondertekenaar';

  @override
  String get signHere => 'Teken hier';

  @override
  String get signIn => 'Aanmelden';

  @override
  String get signOut => 'Afmelden';

  @override
  String signedInAs(String name) {
    return 'Aangemeld als $name';
  }

  @override
  String get signingIn => 'Aanmelden…';

  @override
  String get singleProduct => 'Eén product';

  @override
  String get siteAddress => 'Waar naartoe';

  @override
  String get siteName => 'Naam van de locatie';

  @override
  String skippedWithoutPrice(int count) {
    return '$count product/zone-combinaties hebben geen prijs en worden overgeslagen';
  }

  @override
  String get sla => 'SLA';

  @override
  String get slaAndSatisfaction => 'SLA en tevredenheid';

  @override
  String get slaAtRisk => 'Dreigt te laat';

  @override
  String get slaBreached => 'Overschreden';

  @override
  String get slaCompliance => 'SLA-naleving';

  @override
  String slaComplianceDetail(int breached, int total) {
    return '$breached van $total overschreden';
  }

  @override
  String slaDue(String date) {
    return 'Uiterlijk $date';
  }

  @override
  String get slaFilterAny => 'Elke SLA-status';

  @override
  String get slaFirstResponse => 'Eerste reactie';

  @override
  String slaLeft(String time) {
    return 'nog $time';
  }

  @override
  String get slaMet => 'Gehaald';

  @override
  String get slaNone => 'Geen SLA';

  @override
  String get slaOnTime => 'Op schema';

  @override
  String slaOverdue(String time) {
    return '$time te laat';
  }

  @override
  String get slaPaused => 'Klok gestopt: wacht op de klant';

  @override
  String get slaPolicies => 'Servicelevels (SLA)';

  @override
  String get slaPoliciesHelp =>
      'Gewone verstreken tijd, werkuren tellen niet mee. De klok stopt zolang een ticket op de klant wacht.';

  @override
  String get slaResolution => 'Oplossing';

  @override
  String get splitAction => 'Splitsen';

  @override
  String splitFiles(int count) {
    return '$count bestand(en)';
  }

  @override
  String get splitHelp =>
      'Kies de berichten die naar een nieuw ticket voor dezelfde klant gaan. Hun bestanden gaan mee. Dit kan niet ongedaan gemaakt worden (tickets kunnen wel opnieuw samengevoegd worden).';

  @override
  String get splitKeepOne => 'Minstens één bericht moet in dit ticket blijven.';

  @override
  String get splitSubjectOptional =>
      'Onderwerp van het nieuwe ticket (optioneel)';

  @override
  String get splitTicket => 'Ticket splitsen…';

  @override
  String get stage => 'Fase';

  @override
  String get stageLead => 'lead';

  @override
  String get stageLost => 'verloren';

  @override
  String get stageNegotiation => 'onderhandeling';

  @override
  String get stageProposal => 'voorstel';

  @override
  String get stageQualified => 'gekwalificeerd';

  @override
  String get stageWon => 'gewonnen';

  @override
  String get startDate => 'Startdatum';

  @override
  String get startJob => 'Start opdracht';

  @override
  String get startWork => 'Start werk';

  @override
  String get status => 'Status';

  @override
  String get statusAccepted => 'aanvaard';

  @override
  String get statusAfterwards => 'Status daarna';

  @override
  String get statusDraft => 'concept';

  @override
  String get statusRejected => 'geweigerd';

  @override
  String get statusSent => 'verzonden';

  @override
  String get statusSuperseded => 'vervangen';

  @override
  String get stopOnMatch => 'Stoppen na deze regel';

  @override
  String get stopOnMatchHelp =>
      'Als ze past, worden de regels erna overgeslagen.';

  @override
  String get stockAdjust => 'Corrigeren';

  @override
  String get stockAdjustReason => 'Waarom wordt de voorraad gecorrigeerd?';

  @override
  String get stockAdjustRequired =>
      'Kies een locatie, geef een hoeveelheid in en een reden.';

  @override
  String get stockAllWarehouses => 'Alle magazijnen';

  @override
  String get stockAssignedTo => 'Toegewezen aan';

  @override
  String get stockAvailable => 'Beschikbaar';

  @override
  String get stockBarcode => 'Barcode';

  @override
  String get stockBelowReorder => 'Onder bestelpunt';

  @override
  String get stockChangeBy => 'Wijzigen met (+/−)';

  @override
  String get stockCounts => 'Inventarisaties';

  @override
  String stockExpiredQty(String quantity) {
    return '$quantity vervallen';
  }

  @override
  String get stockExpiry => 'Vervaldatum';

  @override
  String get stockFrom => 'Van';

  @override
  String get stockInVans => 'In bestelwagens';

  @override
  String get stockInvalidNumbers =>
      'Kostprijs, bestelpunten en levertijd moeten getallen zijn.';

  @override
  String get stockIssue => 'Uitgeven';

  @override
  String get stockKindVan => 'Servicewagen';

  @override
  String get stockKindWarehouse => 'Magazijn';

  @override
  String get stockLeadTime => 'Levertijd (dagen)';

  @override
  String get stockLocation => 'Locatie';

  @override
  String get stockLocations => 'Voorraad per locatie';

  @override
  String get stockLot => 'Lot';

  @override
  String get stockLotNumber => 'Lotnummer';

  @override
  String get stockLotTrackingHelp => 'Loten / batches';

  @override
  String get stockMoves => 'Bewegingen';

  @override
  String get stockNewLocation => 'Nieuwe locatie';

  @override
  String get stockNewLot => 'Nieuw lot';

  @override
  String get stockNewQuantity => 'Nieuwe hoeveelheid';

  @override
  String get stockNewVan => 'Nieuwe servicewagen';

  @override
  String get stockNewWarehouse => 'Nieuw magazijn';

  @override
  String get stockNoMoves => 'Nog geen bewegingen';

  @override
  String get stockNoWarehouses =>
      'Nog geen magazijnen. Een beheerder maakt ze hier aan.';

  @override
  String get stockNote => 'Opmerking';

  @override
  String get stockNothingInStock => 'Niets op voorraad';

  @override
  String get stockOnHand => 'In voorraad';

  @override
  String get stockOnlyInStock => 'Alleen op voorraad';

  @override
  String get stockProductQuantityRequired =>
      'Kies een product en geef een hoeveelheid in.';

  @override
  String get stockReasonConsumption => 'Verbruik';

  @override
  String get stockReasonCorrection => 'Correctie';

  @override
  String get stockReasonCount => 'Inventarisatie';

  @override
  String get stockReasonManualReceipt => 'Handmatige ontvangst';

  @override
  String get stockReasonProductionOutput => 'Productie-oplevering';

  @override
  String get stockReasonPurchaseReceipt => 'Ontvangst inkoop';

  @override
  String get stockReasonRepairUse => 'Gebruikt bij herstelling';

  @override
  String get stockReasonReturn => 'Klantenretour';

  @override
  String get stockReasonReversal => 'Terugdraaiing';

  @override
  String get stockReasonScrap => 'Afschrijving';

  @override
  String get stockReasonShipment => 'Levering';

  @override
  String get stockReasonVanReplenishment => 'Bestelwagen aanvullen';

  @override
  String get stockReceive => 'Ontvangen';

  @override
  String get stockReorderMax => 'Maximumvoorraad';

  @override
  String get stockReorderMin => 'Minimumvoorraad';

  @override
  String get stockReservations => 'Gereserveerd voor orders';

  @override
  String get stockReserved => 'Gereserveerd';

  @override
  String get stockReverse => 'Terugdraaien';

  @override
  String get stockReverseAnyway => 'Toch terugdraaien';

  @override
  String get stockReverseTitle => 'Deze beweging terugdraaien';

  @override
  String get stockReversed => 'teruggedraaid';

  @override
  String stockShortBy(String quantity) {
    return 'Tekort van $quantity';
  }

  @override
  String get stockStandardCost => 'Standaardkostprijs';

  @override
  String get stockStateAvailable => 'Op voorraad';

  @override
  String get stockStateNotStocked => 'Geen voorraadartikel';

  @override
  String get stockStatePartial => 'Gedeeltelijk op voorraad';

  @override
  String get stockStateReserved => 'Gereserveerd';

  @override
  String get stockStateShort => 'Niet op voorraad';

  @override
  String get stockTitle => 'Voorraad';

  @override
  String get stockTo => 'Naar';

  @override
  String get stockTrackingLot => 'lot';

  @override
  String get stockTransfer => 'Verplaatsen';

  @override
  String get stockWarehouse => 'Magazijn';

  @override
  String get stockWarehouses => 'Magazijnen';

  @override
  String get street => 'Straat';

  @override
  String get streetAddress => 'Straat en nummer';

  @override
  String structureRevision(int revision) {
    return 'Structuur (revisie $revision)';
  }

  @override
  String get subassembly => 'subassemblage';

  @override
  String get subject => 'Onderwerp';

  @override
  String get subjectContains => 'Onderwerp bevat';

  @override
  String get subjectOptional => 'Onderwerp (optioneel)';

  @override
  String suggested(String value) {
    return 'Voorstel: $value';
  }

  @override
  String get tag => 'Tag';

  @override
  String get suspendContract => 'Opschorten';

  @override
  String get tags => 'Labels';

  @override
  String get takePhoto => 'Foto nemen';

  @override
  String get tasks => 'Taken';

  @override
  String tasksProgress(String done, String total) {
    return '$done van $total klaar';
  }

  @override
  String get team => 'Team';

  @override
  String get teamLead => 'Teamleider';

  @override
  String get teamMembers => 'Leden';

  @override
  String get teamName => 'Teamnaam';

  @override
  String get teams => 'Teams';

  @override
  String get technicians => 'Technici';

  @override
  String get text => 'Tekst';

  @override
  String get ticket => 'Ticket';

  @override
  String get ticketClosed => 'Gesloten';

  @override
  String get ticketDetails => 'Ticketgegevens';

  @override
  String get ticketInProgress => 'In behandeling';

  @override
  String get ticketMerged => 'Tickets samengevoegd';

  @override
  String get ticketOpened => 'Ticket aangemaakt';

  @override
  String ticketSplit(String number) {
    return 'Ticket $number aangemaakt';
  }

  @override
  String get ticketStatusClosed => 'afgesloten';

  @override
  String get ticketStatusNew => 'nieuw';

  @override
  String get ticketStatusOpen => 'open';

  @override
  String get ticketStatusPendingCustomer => 'wacht op klant';

  @override
  String get ticketStatusPendingInternal => 'wacht op collega';

  @override
  String get ticketVolume => 'Tickets aangemaakt en gesloten';

  @override
  String get ticketWaitingForYou => 'Wacht op uw antwoord';

  @override
  String get tickets => 'Tickets';

  @override
  String get timeLogged => 'Geregistreerde tijd';

  @override
  String get timeNote => 'Notitie';

  @override
  String timeTotal(String total, String billable) {
    return 'Totaal $total, factureerbaar $billable';
  }

  @override
  String timeTotals(String work, String travel) {
    return 'Werk $work · Verplaatsing $travel';
  }

  @override
  String get timeTracking => 'Tijdsregistratie';

  @override
  String get timeZone => 'Tijdzone';

  @override
  String get title => 'Titel';

  @override
  String get titleCustomerValueRequired =>
      'Titel, klant en een geldige waarde zijn verplicht.';

  @override
  String get titleMr => 'Dhr.';

  @override
  String get titleMs => 'Mevr.';

  @override
  String get titleNone => 'Niet opgegeven';

  @override
  String get to => 'Aan';

  @override
  String get topCategories => 'Top categorieën';

  @override
  String get topTags => 'Top tags';

  @override
  String get total => 'Totaal';

  @override
  String productsTotalChange(String from, String to, String difference) {
    return 'Producten excl. verzending en btw: $from → $to ($difference)';
  }

  @override
  String get totalExclVat => 'Totaal excl. btw';

  @override
  String get totalInclVat => 'Totaal incl. btw';

  @override
  String get totalsToBuyOrMake => 'Totalen aan te kopen of te maken';

  @override
  String get tracking => 'Tracering';

  @override
  String get twoLetters => '2 letters';

  @override
  String get type => 'Type';

  @override
  String get unassigned => 'Niet toegewezen';

  @override
  String get unchanged => 'Ongewijzigd';

  @override
  String get unit => 'Eenheid';

  @override
  String get unitPrice => 'Eenheidsprijs';

  @override
  String get unitPriceExclVat => 'Eenheidsprijs (excl. btw)';

  @override
  String get unknownCaller => 'Onbekende beller';

  @override
  String get until => 'Tot';

  @override
  String get upcomingVisits => 'Geplande bezoeken';

  @override
  String get updateToCurrentPrices => 'Bijwerken naar huidige prijzen';

  @override
  String get updated => 'Bijgewerkt';

  @override
  String get uploadingFile => 'Uploaden…';

  @override
  String get uploadingPhotos => 'Uploaden…';

  @override
  String get useAnotherPriceListDate => 'Andere prijslijstdatum gebruiken';

  @override
  String get validFrom => 'Geldig vanaf';

  @override
  String validFromDate(String date) {
    return 'Geldig vanaf $date';
  }

  @override
  String validUntil(String date) {
    return 'geldig tot $date';
  }

  @override
  String get value => 'Waarde';

  @override
  String get vat => 'Btw';

  @override
  String get vatNumber => 'Btw-nummer';

  @override
  String vatOn(String rate, String base) {
    return 'Btw $rate % op $base';
  }

  @override
  String get vatPercent => 'Btw %';

  @override
  String get viaPortal => 'Via het klantenportaal';

  @override
  String get visitTemplates => 'Bezoeken';

  @override
  String get visitTitleRequired => 'Elk bezoek heeft een titel nodig';

  @override
  String get warranty => 'Garantie';

  @override
  String get warrantyExpired => 'Garantie verlopen';

  @override
  String get warrantyIn => 'Onder garantie';

  @override
  String get warrantyOut => 'Buiten garantie';

  @override
  String get warrantyUnknown => 'Onbekend';

  @override
  String get weekdayFriday => 'Vrijdag';

  @override
  String get weekdayMonday => 'Maandag';

  @override
  String get weekdaySaturday => 'Zaterdag';

  @override
  String get weekdaySunday => 'Zondag';

  @override
  String get weekdayThursday => 'Donderdag';

  @override
  String get weekdayTuesday => 'Dinsdag';

  @override
  String get weekdayWednesday => 'Woensdag';

  @override
  String warrantyUntilDate(String date) {
    return 'tot $date';
  }

  @override
  String get warrantyUntilLabel => 'Garantie tot';

  @override
  String weighted(String amount) {
    return 'gewogen $amount';
  }

  @override
  String get whatWasAsked => 'Wat werd er gevraagd?';

  @override
  String get whoIsCalling => 'Wie belt er?';

  @override
  String get won => 'Gewonnen';

  @override
  String get workFrom => 'Van';

  @override
  String get workKindTravel => 'Verplaatsing';

  @override
  String get workKindWork => 'Werk';

  @override
  String get workLogs => 'Geregistreerde tijd';

  @override
  String get workUntil => 'Tot';

  @override
  String writeIn(String language) {
    return 'Schrijf in het $language';
  }

  @override
  String get yes => 'Ja';

  @override
  String get yourMessage => 'Uw bericht';

  @override
  String get yourReference => 'Uw referentie (RMA of bestelling)';

  @override
  String get zone => 'Zone';

  @override
  String zoneAndRebate(String zone, String percent) {
    return 'Zone $zone · algemene korting $percent %';
  }

  @override
  String get zonesNoneAll => 'Zones (geen selectie = alle)';

  @override
  String get kbTitle => 'Kennisbank';

  @override
  String get kbNewArticle => 'Nieuw artikel';

  @override
  String get kbSearchHint => 'Artikels zoeken';

  @override
  String get kbAllCategories => 'Alle categorieën';

  @override
  String get kbAllStatuses => 'Alle statussen';

  @override
  String get kbAllAudiences => 'Alle doelgroepen';

  @override
  String get kbManageCategories => 'Categorieën';

  @override
  String get kbStatusPublished => 'Gepubliceerd';

  @override
  String get kbStatusArchived => 'Gearchiveerd';

  @override
  String get kbAudience => 'Doelgroep';

  @override
  String get kbAudienceInternal => 'Intern (alleen personeel)';

  @override
  String get kbAudiencePortal => 'Klantenportaal';

  @override
  String get kbAudiencePublic => 'Publiek';

  @override
  String get kbArticleTitle => 'Titel';

  @override
  String get kbSummary => 'Samenvatting';

  @override
  String get kbBody => 'Tekst (Markdown)';

  @override
  String get kbPreview => 'Voorbeeld';

  @override
  String get kbWriteTab => 'Schrijven';

  @override
  String get kbMarkdownHelp =>
      'Gebruik # voor titels, **vet**, *cursief*, - voor lijsten, [tekst](https://…) voor links en ![omschrijving](image:ID) voor afbeeldingen.';

  @override
  String get kbTagsLabel => 'Labels (gescheiden door komma)';

  @override
  String get kbRelated => 'Gerelateerde artikels';

  @override
  String get kbAddRelated => 'Gerelateerd artikel toevoegen';

  @override
  String get kbImages => 'Afbeeldingen';

  @override
  String get kbUploadImage => 'Afbeelding uploaden';

  @override
  String get kbInsertImage => 'In tekst invoegen';

  @override
  String get kbPublish => 'Publiceren';

  @override
  String get kbUnpublish => 'Depubliceren';

  @override
  String get kbArchive => 'Archiveren';

  @override
  String get kbHistory => 'Versiegeschiedenis';

  @override
  String kbVersionLine(int version, String name, String date) {
    return 'Versie $version · $name · $date';
  }

  @override
  String get kbRestore => 'Deze versie herstellen';

  @override
  String kbRestoredFrom(int version) {
    return 'hersteld van versie $version';
  }

  @override
  String kbFeedback(int yes, int no) {
    return '$yes vonden dit nuttig, $no niet';
  }

  @override
  String kbViews(int count) {
    return '$count weergaven';
  }

  @override
  String get kbNoArticles => 'Geen artikels gevonden.';

  @override
  String get kbNoCategory => 'Geen categorie';

  @override
  String get kbMainCategory => 'Hoofdcategorie';

  @override
  String get kbSortOrder => 'Volgorde';

  @override
  String get kbNewCategory => 'Nieuwe categorie';

  @override
  String get kbCategoryNames => 'Naam per taal';

  @override
  String get kbDelete => 'Verwijderen';

  @override
  String get kbSuggestedArticles => 'Voorgestelde artikels';

  @override
  String get kbNoSuggestions => 'Geen passende artikels.';

  @override
  String get kbInsertText => 'Tekst invoegen';

  @override
  String get kbInsertLink => 'Link invoegen';

  @override
  String get kbInsertArticle => 'Artikel invoegen';

  @override
  String get kbNoPortalLink =>
      'Dit artikel is intern: enkel de tekst kan worden ingevoegd.';

  @override
  String get kbHelp => 'Hulp';

  @override
  String get kbHelpHeading => 'Hoe kunnen we helpen?';

  @override
  String get kbHelpSearch => 'Zoek in de hulpartikels';

  @override
  String get kbHelpEmpty =>
      'Geen artikels gevonden. U kunt in plaats daarvan een ticket openen.';

  @override
  String get kbWasHelpful => 'Was dit artikel nuttig?';

  @override
  String get kbYes => 'Ja';

  @override
  String get kbNo => 'Nee';

  @override
  String get kbThanks => 'Bedankt voor uw feedback.';

  @override
  String get kbStillNeedHelp => 'Nog hulp nodig? Open een ticket.';

  @override
  String get kbRelatedReading => 'Gerelateerde artikels';

  @override
  String get kbDeflectionTitle =>
      'Deze artikels beantwoorden uw vraag misschien al';

  @override
  String kbShownIn(String language) {
    return 'Niet beschikbaar in uw taal; getoond in $language.';
  }

  @override
  String kbUpdatedOn(String date) {
    return 'Bijgewerkt op $date';
  }

  @override
  String offlineWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen wachten op synchronisatie',
      one: '1 wijziging wacht op synchronisatie',
    );
    return '$_temp0';
  }

  @override
  String offlineFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vragen je aandacht',
      one: '1 vraagt je aandacht',
    );
    return '$_temp0';
  }

  @override
  String get offlineQueueTitle => 'Wijzigingen die wachten op synchronisatie';

  @override
  String get offlineSyncNow => 'Nu synchroniseren';

  @override
  String get offlineRetry => 'Opnieuw proberen';

  @override
  String get offlineDiscard => 'Weggooien';

  @override
  String get offlineDiscardQuestion =>
      'Deze wijziging weggooien? Ze wordt niet naar de server gestuurd.';

  @override
  String get offlineAllSynced => 'Alles is gesynchroniseerd.';

  @override
  String offlineAttempts(int count) {
    return 'Pogingen: $count';
  }

  @override
  String offlineLastError(String message) {
    return 'Laatste fout: $message';
  }

  @override
  String get offlineRejected =>
      'De server weigerde deze wijziging. De opdracht is misschien intussen herverdeeld, geannuleerd of aangepast.';

  @override
  String offlineDataFrom(String time) {
    return 'Offline: gegevens van $time';
  }

  @override
  String get offlinePendingSync => 'Wacht op synchronisatie';

  @override
  String get offlineQueuedMessage =>
      'Geen verbinding: bewaard op dit toestel, het wordt verstuurd zodra je weer online bent.';

  @override
  String offlinePhotosWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count foto\'s wachten om geüpload te worden',
      one: '1 foto wacht om geüpload te worden',
    );
    return '$_temp0';
  }

  @override
  String get offlineTooLarge =>
      'Te groot om offline te bewaren. Maak verbinding om het te versturen.';

  @override
  String get offlineReload => 'Herladen';

  @override
  String get offlineOpStart => 'Opdracht starten';

  @override
  String get offlineOpTaskDone => 'Taak afgevinkt';

  @override
  String get offlineOpTaskUndone => 'Vinkje bij taak weggehaald';

  @override
  String get offlineOpTaskAdd => 'Nieuwe taak';

  @override
  String get offlineOpWorkLog => 'Tijdregistratie';

  @override
  String get offlineOpPart => 'Gebruikt onderdeel';

  @override
  String get offlineOpComplete => 'Opdracht afronden';

  @override
  String get offlineOpDecline => 'Klant weigert te tekenen';

  @override
  String get offlineOpSignature => 'Handtekening klant';

  @override
  String get offlineOpPhoto => 'Foto';

  @override
  String get collabEscalate => 'Escaleren';

  @override
  String get collabEscalateTitle => 'Ticket escaleren';

  @override
  String get collabDelegate => 'Overdragen';

  @override
  String get collabDelegateTitle => 'Ticket overdragen';

  @override
  String get collabEscalateTo => 'Escaleren naar';

  @override
  String get collabNoTarget => 'Teamleiders van het ticketteam';

  @override
  String get collabPerson => 'Collega';

  @override
  String get collabTeam => 'Team';

  @override
  String get collabHandOverTo => 'Nieuwe eigenaar';

  @override
  String get collabReasonRequired => 'Reden (verplicht)';

  @override
  String get collabRaisePriority => 'Prioriteit één stap verhogen';

  @override
  String get collabCommentOptional =>
      'Opmerking voor de nieuwe eigenaar (optioneel)';

  @override
  String get collabInternalHint =>
      'Intern: wordt nooit naar de klant gestuurd.';

  @override
  String get collabEscalated => 'Ticket geëscaleerd';

  @override
  String get collabHandedOver => 'Ticket overgedragen';

  @override
  String get collabEscalatedBadge => 'Geëscaleerd';

  @override
  String collabEscalatedBy(String name) {
    return 'Geëscaleerd door $name';
  }

  @override
  String get collabWatch => 'Volgen';

  @override
  String get collabUnwatch => 'Niet meer volgen';

  @override
  String get collabWatchers => 'Volgers';

  @override
  String get collabNoWatchers => 'Niemand volgt dit ticket';

  @override
  String get collabAddWatcher => 'Volger toevoegen';

  @override
  String get collabActivity => 'Activiteit';

  @override
  String get collabNoActivity => 'Nog geen activiteit';

  @override
  String collabSeenBy(String readers) {
    return 'Gezien door $readers';
  }

  @override
  String get collabFilterUnread => 'Ongelezen';

  @override
  String get collabFilterWatching => 'Gevolgd';

  @override
  String get collabFilterEscalated => 'Geëscaleerd';

  @override
  String get collabUnreadTooltip => 'Ongelezen';

  @override
  String collabReplying(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names zijn aan het antwoorden',
      one: '$names is aan het antwoorden',
    );
    return '$_temp0 — stem af voor je verstuurt';
  }

  @override
  String collabViewing(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names bekijken dit ticket',
      one: '$names bekijkt dit ticket',
    );
    return '$_temp0';
  }

  @override
  String collabConfirmSend(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names zijn nu aan het antwoorden op dit ticket.',
      one: '$names is nu aan het antwoorden op dit ticket.',
    );
    return '$_temp0 Toch versturen?';
  }

  @override
  String get collabSendAnyway => 'Toch versturen';

  @override
  String get collabSystem => 'Systeem';

  @override
  String collabEventCreated(String actor) {
    return '$actor heeft het ticket aangemaakt';
  }

  @override
  String collabEventAssignedOwner(String actor, String owner) {
    return '$actor wees het ticket toe aan $owner';
  }

  @override
  String collabEventOwnerCleared(String actor) {
    return '$actor verwijderde de eigenaar';
  }

  @override
  String collabEventTeam(String actor, String team) {
    return '$actor verplaatste het ticket naar team $team';
  }

  @override
  String collabEventTeamCleared(String actor) {
    return '$actor verwijderde het team';
  }

  @override
  String collabEventDelegated(String actor, String owner) {
    return '$actor droeg het ticket over aan $owner';
  }

  @override
  String collabEventEscalated(String actor) {
    return '$actor escaleerde het ticket';
  }

  @override
  String collabEventStatus(String actor, String before, String after) {
    return '$actor wijzigde de status van $before naar $after';
  }

  @override
  String collabEventPriority(String actor, String before, String after) {
    return '$actor wijzigde de prioriteit van $before naar $after';
  }

  @override
  String collabEventMergedInto(String actor, String number) {
    return '$actor voegde dit ticket samen met $number';
  }

  @override
  String collabEventMergedFrom(String actor, String number) {
    return '$actor voegde $number samen met dit ticket';
  }

  @override
  String collabEventTagAdded(String actor, String tag) {
    return '$actor voegde de tag $tag toe';
  }

  @override
  String collabEventTagRemoved(String actor, String tag) {
    return '$actor verwijderde de tag $tag';
  }

  @override
  String collabMsgCustomer(String actor) {
    return '$actor (klant) schreef';
  }

  @override
  String collabMsgReply(String actor) {
    return '$actor antwoordde de klant';
  }

  @override
  String collabMsgNote(String actor) {
    return '$actor voegde een interne notitie toe';
  }

  @override
  String collabMsgCall(String actor) {
    return '$actor registreerde een gesprek';
  }

  @override
  String get planningTitle => 'Planning';

  @override
  String get planningDay => 'Dag';

  @override
  String get planningWeek => 'Week';

  @override
  String get planningToday => 'Vandaag';

  @override
  String get planningPrevious => 'Vorige';

  @override
  String get planningNext => 'Volgende';

  @override
  String get planningBacklog => 'In te plannen';

  @override
  String get planningBacklogEmpty => 'Niets meer te plannen.';

  @override
  String get planningSkillFilter => 'Vaardigheid';

  @override
  String get planningAllSkills => 'Alle vaardigheden';

  @override
  String get planningNoTechnicians =>
      'Geen technici om te tonen. Geef gebruikers de rol technicus.';

  @override
  String get planningPlan => 'Plan';

  @override
  String planningScheduleJob(String number) {
    return '$number plannen';
  }

  @override
  String get planningSuggestions => 'Suggesties';

  @override
  String get planningShowSuggestions => 'Toon suggesties';

  @override
  String get planningNoSuggestions =>
      'Geen vrij tijdslot gevonden in de komende twee weken.';

  @override
  String planningMissingSkills(int count) {
    return '$count vaardigheid/vaardigheden ontbreken';
  }

  @override
  String get planningRequiredSkills => 'Vereiste vaardigheden';

  @override
  String get planningChecking => 'Controleren…';

  @override
  String get planningNoConflicts => 'Geen conflicten.';

  @override
  String get planningConfirmTitle => 'Plannen met conflicten?';

  @override
  String get planningConfirmBody => 'Deze planning bevat fouten:';

  @override
  String get planningScheduleAnyway => 'Toch plannen';

  @override
  String get planningScheduled => 'Opdracht gepland.';

  @override
  String planningConflictDoubleBooked(String name) {
    return '$name heeft op dat moment een andere opdracht (inclusief reistijd).';
  }

  @override
  String planningConflictOutsideHours(String name) {
    return '$name valt buiten de werkuren.';
  }

  @override
  String planningConflictOnAbsence(String name) {
    return '$name is afwezig.';
  }

  @override
  String planningConflictMissingSkill(String name, String skill) {
    return '$name mist de vaardigheid $skill.';
  }

  @override
  String get planningConflictCrossesDays =>
      'De opdracht loopt over middernacht.';

  @override
  String get planningAbsenceVacation => 'Verlof';

  @override
  String get planningAbsenceSick => 'Ziek';

  @override
  String get planningAbsenceTraining => 'Opleiding';

  @override
  String get planningAbsenceOther => 'Andere afwezigheid';

  @override
  String get planningAgendaEmpty => 'Niets gepland.';

  @override
  String get planningSettingsTitle => 'Planningsinstellingen';

  @override
  String get planningAbsences => 'Afwezigheden';

  @override
  String get planningHours => 'Werkuren';

  @override
  String get planningSkills => 'Vaardigheden';

  @override
  String get planningGeneral => 'Algemeen';

  @override
  String get planningAddAbsence => 'Afwezigheid toevoegen';

  @override
  String get planningNoAbsences => 'Geen afwezigheden geregistreerd.';

  @override
  String get planningTechnician => 'Technicus';

  @override
  String get planningKind => 'Soort';

  @override
  String get planningDefaultHours => 'Standaard van het bedrijf';

  @override
  String get planningUsesDefault =>
      'Geen eigen uren: de standaard van het bedrijf geldt.';

  @override
  String get planningAddBlock => 'Blok toevoegen';

  @override
  String get planningAddSkill => 'Vaardigheid toevoegen';

  @override
  String get planningTechnicianSkills => 'Vaardigheden per technicus';

  @override
  String planningSkillLevel(int n) {
    return 'Niveau $n';
  }

  @override
  String get planningTravelBuffer => 'Reistijd tussen opdrachten (minuten)';

  @override
  String get planningTravelBufferHelp =>
      'Wordt vrijgehouden tussen twee opdrachten van een technicus op dezelfde dag.';

  @override
  String get planningDefaultJobMinutes =>
      'Standaardduur van een opdracht (minuten)';

  @override
  String get planningTimezone => 'Tijdzone';

  @override
  String get adminTitle => 'Beheer';

  @override
  String get adminUsers => 'Gebruikers';

  @override
  String get adminModules => 'Modules';

  @override
  String get newUser => 'Nieuwe gebruiker';

  @override
  String get editUser => 'Gebruiker bewerken';

  @override
  String get userDisabledModules => 'Uitgeschakelde modules';

  @override
  String get userNotSignedIn => 'Nog niet aangemeld';

  @override
  String get userResendInvitation => 'Uitnodiging opnieuw versturen';

  @override
  String get userInvitationSent => 'Uitnodiging verstuurd';

  @override
  String get userCreated => 'Gebruiker toegevoegd';

  @override
  String get userFilterAll => 'Alle leden';

  @override
  String get userFilterActive => 'Actieve leden';

  @override
  String get userFilterInactive => 'Gedeactiveerde leden';

  @override
  String get userActiveHelp =>
      'Een gedeactiveerd lid kan niet meer aanmelden bij dit bedrijf.';

  @override
  String get userCannotDeactivateSelf => 'U kunt uzelf niet deactiveren.';

  @override
  String get userCannotDropOwnAdmin =>
      'U kunt uw eigen beheerdersrol niet verwijderen.';

  @override
  String userRolePermissions(int count) {
    return '$count rechten';
  }

  @override
  String get userModulesHelp =>
      'Schakel modules uit voor deze persoon. Modules die het bedrijf heeft uitgeschakeld kunnen hier niet opnieuw worden ingeschakeld.';

  @override
  String get userModuleCompanyOff => 'Uitgeschakeld voor het hele bedrijf';

  @override
  String moduleRequires(String modules) {
    return 'Vereist $modules';
  }

  @override
  String get modulesIntro =>
      'Schakel de modules uit die dit bedrijf niet gebruikt. Mensen zien ze niet meer en de server weigert hun aanvragen.';

  @override
  String get modulesSaved => 'Modules opgeslagen';

  @override
  String moduleAlsoRequires(String modules) {
    return 'Heeft ook $modules nodig';
  }

  @override
  String moduleAlsoSwitchedOff(String modules) {
    return 'Zet ook uit: $modules';
  }

  @override
  String moduleAlsoSwitchedOn(String modules) {
    return 'Zet ook aan: $modules';
  }

  @override
  String moduleExpand(String module) {
    return '$module uitklappen';
  }

  @override
  String moduleCollapse(String module) {
    return '$module inklappen';
  }

  @override
  String get moduleOn => 'Aan';

  @override
  String get moduleOff => 'Uit';

  @override
  String moduleLevel(int level) {
    return 'Niveau $level';
  }

  @override
  String get userRoleAdmin => 'Beheerder';

  @override
  String get userRoleSalesManager => 'Verkoopverantwoordelijke';

  @override
  String get userRoleSales => 'Verkoop';

  @override
  String get userRoleSupport => 'Support';

  @override
  String get userRoleProduction => 'Productie';

  @override
  String get userRoleWarehouse => 'Magazijn';

  @override
  String get userRoleProductManager => 'Productbeheerder';

  @override
  String get userRoleWorkshop => 'Werkplaats';

  @override
  String get userRoleTechnician => 'Technicus';

  @override
  String get userRoleDispatcher => 'Planner';

  @override
  String get userRoleLogistics => 'Logistiek';

  @override
  String get userRoleViewer => 'Lezer';

  @override
  String get moduleCustomers => 'Klanten';

  @override
  String get moduleProducts => 'Producten';

  @override
  String get moduleSales => 'Verkoop';

  @override
  String get moduleEngineering => 'Engineering';

  @override
  String get moduleInventory => 'Voorraad';

  @override
  String get moduleHelpdesk => 'Helpdesk';

  @override
  String get moduleKb => 'Kennisbank';

  @override
  String get moduleRepairs => 'Herstellingen';

  @override
  String get moduleField => 'Buitendienst';

  @override
  String get purpose => 'Doel';

  @override
  String get purposeInstallation => 'Installatie';

  @override
  String get purposeStock => 'Voorraad';

  @override
  String get deliveryCountry => 'Leverland';

  @override
  String deliveryCountryDefault(String country) {
    return 'Standaard: $country';
  }

  @override
  String get deliveryCountryInvalid =>
      'Geef een landcode van twee letters in, bijvoorbeeld BE.';

  @override
  String get shippingNotRequired => 'niet nodig';

  @override
  String get shippingPending => 'in afwachting';

  @override
  String get shippingQuoted => 'geprijsd';

  @override
  String get shippingRequested => 'aangevraagd';

  @override
  String get shippingPendingBanner =>
      'Wacht op een verzendofferte van logistiek. De offerte kan pas verstuurd worden als de kost is ingevoerd.';

  @override
  String get shippingQuotedBanner =>
      'De verzendkost is geprijsd en staat als verzendlijn op de offerte.';

  @override
  String get shippingLineNote => 'Toegevoegd door logistiek';

  @override
  String get sendAnyway => 'Toch versturen';

  @override
  String sendAnywayHelp(String message) {
    return '$message\n\nAls logistiek mag u de offerte zonder verzendkost versturen. Toch versturen?';
  }

  @override
  String get shippingRequests => 'Verzendaanvragen';

  @override
  String get shippingQueue => 'Open en aangevraagd';

  @override
  String get markAsRequested => 'Markeer als aangevraagd';

  @override
  String get enterQuote => 'Prijs invoeren';

  @override
  String get carrier => 'Vervoerder';

  @override
  String get amount => 'Bedrag';

  @override
  String get currency => 'Munt';

  @override
  String get quotedAmount => 'Geprijsd bedrag';

  @override
  String get requestedAt => 'Aangevraagd op';

  @override
  String get amountRequired => 'Geef een geldig bedrag in.';

  @override
  String get carrierRequired => 'Geef de vervoerder in.';

  @override
  String get packagingCategory => 'Verpakkingscategorie';

  @override
  String get packagingCategories => 'Verpakkingscategorieën';

  @override
  String get newPackagingCategory => 'Nieuwe verpakkingscategorie';

  @override
  String get requiresShippingQuote => 'Vereist een verzendofferte';

  @override
  String get lengthMm => 'Lengte (mm)';

  @override
  String get widthMm => 'Breedte (mm)';

  @override
  String get heightMm => 'Hoogte (mm)';

  @override
  String get weightG => 'Gewicht (g)';

  @override
  String get dimensions => 'Afmetingen';

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
      'Afmetingen en gewicht moeten positieve gehele getallen zijn, of leeg.';

  @override
  String get powerTab => 'Voeding';

  @override
  String get powerNotElectrical =>
      'Er zijn geen voedingen opgegeven: dit is geen elektrisch product en wordt nooit met een stroomnet vergeleken.';

  @override
  String get powerAddSupply => 'Voeding toevoegen';

  @override
  String get currentType => 'Stroomsoort';

  @override
  String get currentAc => 'AC';

  @override
  String get currentDc => 'DC';

  @override
  String get voltageV => 'Spanning (V)';

  @override
  String get phases => 'Fasen';

  @override
  String get frequencyHz => 'Frequentie (Hz)';

  @override
  String get frequencyBoth => '50 en 60 Hz';

  @override
  String get tolerancePct => 'Tolerantie (%)';

  @override
  String get powerVoltageInvalid =>
      'Geef de spanning in als positief geheel getal.';

  @override
  String get powerToleranceInvalid =>
      'De tolerantie moet een geheel getal van 0 tot 50 zijn.';

  @override
  String get powerSupplyDuplicate =>
      'Dezelfde voeding staat twee keer in de lijst.';

  @override
  String get powerCheckTitle => 'Controle netcompatibiliteit';

  @override
  String get powerCheckHelp =>
      'Vergelijkt de opgeslagen voedingen met de stroomnetten van een land.';

  @override
  String get powerGrid => 'Stroomnet';

  @override
  String get powerAnyGrid => 'Elk net in dit land';

  @override
  String get powerCheck => 'Controleren';

  @override
  String powerResultCompatible(String country) {
    return 'Compatibel met het stroomnet van $country.';
  }

  @override
  String powerResultIncompatible(
    String country,
    String supported,
    String available,
  ) {
    return 'Past niet op het net van $country. Ondersteund: $supported. Daar beschikbaar: $available.';
  }

  @override
  String get powerResultExternal =>
      'Werkt alleen op gelijkstroom en heeft een externe voeding nodig; er is geen netcontrole.';

  @override
  String get powerResultNotApplicable =>
      'Geen elektrisch product; er valt niets te controleren.';

  @override
  String powerResultUnknown(String country) {
    return 'Er zijn geen netgegevens voor $country: de compatibiliteit kan niet worden gecontroleerd.';
  }

  @override
  String get powerStatusCompatible => 'Compatibel';

  @override
  String get powerStatusIncompatible => 'Niet compatibel';

  @override
  String get powerStatusExternal => 'Externe voeding nodig';

  @override
  String get powerStatusNotApplicable => 'Niet van toepassing';

  @override
  String get powerStatusUnknown => 'Net onbekend';

  @override
  String get relatedTab => 'Gerelateerd';

  @override
  String get relationRules => 'Regels';

  @override
  String get relationSuggestions => 'Suggesties';

  @override
  String get relationNoRules => 'Er gelden geen regels voor dit product.';

  @override
  String get relationNoSuggestions => 'Nog geen suggesties.';

  @override
  String get relationKindCompatible => 'Compatibel';

  @override
  String get relationKindIncompatible => 'Niet compatibel';

  @override
  String get relationKindSuggested => 'Aanbevolen';

  @override
  String get relationAddRule => 'Regel toevoegen';

  @override
  String get relationEdit => 'Relatie bewerken';

  @override
  String get relationsTitle => 'Productrelaties';

  @override
  String get newRelation => 'Nieuwe relatie';

  @override
  String get relationKindLabel => 'Soort';

  @override
  String get relationSideA => 'Eerste zijde';

  @override
  String get relationSideB => 'Tweede zijde';

  @override
  String get relationBidirectional => 'Geldt in beide richtingen';

  @override
  String get relationStrength => 'Sterkte (1-100)';

  @override
  String get relationStrengthHelp =>
      'Wordt alleen gebruikt door aanbevelingsregels.';

  @override
  String get relationNeedSides =>
      'Kies aan beide zijden een product of een familie.';

  @override
  String get relationStrengthInvalid =>
      'De sterkte moet een geheel getal van 1 tot 100 zijn.';

  @override
  String get relationsEmpty => 'Geen relaties.';

  @override
  String relationFamilyValue(String code) {
    return 'Familie $code';
  }

  @override
  String get suggestionReasonRule => 'Regel';

  @override
  String get suggestionReasonOften => 'Vaak samen gekocht';

  @override
  String suggestionStrength(int n) {
    return 'Sterkte $n';
  }

  @override
  String suggestionConfidence(int pct) {
    return 'Betrouwbaarheid $pct %';
  }

  @override
  String suggestionBecause(String code) {
    return 'Vanwege $code';
  }

  @override
  String get powerGridsTitle => 'Stroomnetten';

  @override
  String get newPowerGrid => 'Nieuw stroomnet';

  @override
  String get powerGridInvalid =>
      'Geef een landcode van twee letters, een spanning, 1 of 3 fasen en 50 of 60 Hz op.';

  @override
  String get warningKindPowerGrid => 'Stroomnet';

  @override
  String get warningKindIncompatible => 'Niet-compatibele producten';

  @override
  String hintsPowerIncompatible(String code) {
    return '$code past niet op het stroomnet op de leverlocatie.';
  }

  @override
  String hintsSupported(String value) {
    return 'Ondersteund: $value';
  }

  @override
  String hintsAvailable(String value) {
    return 'Beschikbaar: $value';
  }

  @override
  String hintsPowerExternal(String code) {
    return '$code werkt op gelijkstroom en heeft een externe voeding nodig.';
  }

  @override
  String hintsPowerUnknown(String country, String code) {
    return 'Geen netgegevens voor $country, dus $code kon niet worden gecontroleerd. Voeg het net van het land toe onder Stroomnetten op de pagina Producten.';
  }

  @override
  String hintsIncompatibleProducts(String a, String b) {
    return '$a en $b zijn niet compatibel.';
  }

  @override
  String get suggestionsTitle => 'Voorgestelde toevoegingen';

  @override
  String get hintsTitle => 'Waarschuwingen en suggesties';

  @override
  String revisionShippingExisting(String amount) {
    return 'Bestaande verzendkost: $amount';
  }

  @override
  String get revisionShippingReset =>
      'Met huidige prijzen wordt deze verzendkost gewist. Er is een nieuwe verzendofferte van logistiek nodig voordat de herziene offerte verstuurd kan worden.';

  @override
  String revisionShippingKept(String amount) {
    return 'Met afgesproken prijzen wordt de geoffreerde verzending overgenomen in de herziene offerte (huidige kost: $amount).';
  }

  @override
  String get packagesReceiving => 'Goederenontvangst';

  @override
  String get packagesIntake => 'Reparatie-intake';

  @override
  String get registerParcel => 'Pakket registreren';

  @override
  String get registeredParcels => 'Geregistreerde pakketten';

  @override
  String get noParcels => 'Geen pakketten.';

  @override
  String get sender => 'Afzender';

  @override
  String get trackingNumber => 'Trackingnummer';

  @override
  String get parcelCount => 'Aantal pakketten';

  @override
  String get packageCondition => 'Staat van de doos';

  @override
  String get conditionIntact => 'Intact';

  @override
  String get conditionDamaged => 'Beschadigd';

  @override
  String get conditionOpened => 'Geopend';

  @override
  String get conditionWet => 'Nat';

  @override
  String get conditionNote => 'Opmerking over de staat';

  @override
  String get removePhoto => 'Foto verwijderen';

  @override
  String parcelRegistered(String number) {
    return 'Pakket $number geregistreerd';
  }

  @override
  String get pkgStatusRegistered => 'Geregistreerd';

  @override
  String get pkgStatusOpened => 'Geopend';

  @override
  String get pkgStatusLinked => 'Gekoppeld aan reparatie';

  @override
  String get pkgStatusClosed => 'Afgesloten';

  @override
  String get packageKindRepair => 'Reparatie';

  @override
  String get packageKindOther => 'Andere (geen reparatie)';

  @override
  String get packageKindReturn => 'Terugsturen naar afzender';

  @override
  String get toOpen => 'Te openen';

  @override
  String get toProcess => 'Te verwerken';

  @override
  String get toRoute => 'Te routeren';

  @override
  String get nothingHere => 'Hier is niets te doen.';

  @override
  String get openParcel => 'Pakket openen';

  @override
  String get parcelContents => 'Wat zit er in het pakket?';

  @override
  String get closeParcel => 'Pakket afsluiten';

  @override
  String get noteRequired => 'Een opmerking is verplicht.';

  @override
  String get linkToRepair => 'Koppelen aan een reparatie';

  @override
  String get repairSuggestions => 'Voorgestelde reparaties';

  @override
  String get noSuggestions => 'Geen aangekondigde reparatie komt overeen.';

  @override
  String suggestedCustomer(String name) {
    return 'Voorgestelde klant: $name';
  }

  @override
  String suggestionScore(String score) {
    return 'Score $score';
  }

  @override
  String get reasonSerial => 'Zelfde serienummer';

  @override
  String get reasonCustomer => 'Zelfde klant';

  @override
  String get reasonReference => 'Zelfde referentie';

  @override
  String get reasonTicket => 'Zelfde ticket';

  @override
  String get reasonProduct => 'Gelijkaardig product';

  @override
  String get reasonRecent => 'Recent aangekondigd';

  @override
  String get confirmLinkTitle => 'Koppeling bevestigen';

  @override
  String confirmLinkBody(String parcel, String repair) {
    return 'Pakket $parcel bevat reparatie $repair. Een aangekondigde reparatie wordt als ontvangen gemarkeerd.';
  }

  @override
  String get customerMismatchWarning =>
      'De klant van het pakket is niet de klant van de reparatie.';

  @override
  String get confirmCustomerMismatch =>
      'Ja, het is door iemand anders gestuurd (bv. een collega)';

  @override
  String get confirmLink => 'Bevestigen en koppelen';

  @override
  String get linkConflict =>
      'De reparatie is intussen gewijzigd. De lijst is vernieuwd; controleer en probeer opnieuw.';

  @override
  String get createNewRepair => 'Nieuwe reparatie aanmaken';

  @override
  String get parcelsSection => 'Pakketten';

  @override
  String get noParcelsLinked => 'Geen pakket gekoppeld.';

  @override
  String get unlinkParcel => 'Pakket ontkoppelen';

  @override
  String get parcelsToLink => 'Pakketten die op deze reparatie wachten';

  @override
  String get linkParcel => 'Pakket koppelen';

  @override
  String get parcelLinked => 'Pakket gekoppeld';

  @override
  String get parcelUnlinked => 'Pakket ontkoppeld';

  @override
  String get customerUnknown => 'Klant niet gekend';

  @override
  String get findingsSection => 'Bevindingen';

  @override
  String get findingsLabel => 'Wat werd vastgesteld';

  @override
  String get diagnosisLabel => 'Diagnose';

  @override
  String get saveFindings => 'Bevindingen opslaan';

  @override
  String get warrantySection => 'Garantie';

  @override
  String get warrantyVoid => 'Vervallen (misbruik)';

  @override
  String get warrantyAutomatic => 'Automatisch resultaat';

  @override
  String warrantyComparedWith(String date) {
    return 'Vergeleken met de aankomstdatum $date';
  }

  @override
  String get warrantyProvisional =>
      'Nog niet ontvangen: vergeleken met vandaag, dus voorlopig.';

  @override
  String serialUnitLabel(String unit) {
    return 'Serie-eenheid: $unit';
  }

  @override
  String get noSerialUnit => 'Geen serie-eenheid gekoppeld';

  @override
  String get linkSerialUnit => 'Serie-eenheid koppelen';

  @override
  String get unlinkSerialUnit => 'Serie-eenheid ontkoppelen';

  @override
  String get serialUnitSeveral =>
      'Meerdere serie-eenheden komen overeen. Kies de juiste.';

  @override
  String get serialUnitNoResults => 'Geen serie-eenheden gevonden';

  @override
  String get recheckWarranty => 'Garantie opnieuw controleren';

  @override
  String get markWarrantyVoid => 'Garantie laten vervallen (misbruik)';

  @override
  String get removeWarrantyOverride => 'Overschrijving verwijderen';

  @override
  String get warrantyVoidTitle => 'Garantie laten vervallen';

  @override
  String get warrantyRemoveTitle => 'Overschrijving \'vervallen\' verwijderen';

  @override
  String get warrantyReasonLabel => 'Reden (verplicht)';

  @override
  String warrantyOverriddenBy(String name, String date, String reason) {
    return 'Op vervallen gezet door $name op $date: $reason';
  }

  @override
  String get eventFindings => 'Bevindingen bijgewerkt';

  @override
  String get eventSerialUnit => 'Serie-eenheid';

  @override
  String get eventWarrantyAuto => 'Automatische garantie';

  @override
  String get eventWarrantyManual => 'Garantie handmatig ingesteld';

  @override
  String get eventWarrantyVoid => 'Garantie vervallen';

  @override
  String get eventWarrantyVoidRemoved => 'Garantie-overschrijving verwijderd';

  @override
  String get csvMenu => 'CSV exporteren en importeren';

  @override
  String get csvExport => 'CSV exporteren';

  @override
  String get csvImport => 'CSV importeren';

  @override
  String csvExported(String name) {
    return '$name opgeslagen';
  }

  @override
  String csvExportFailed(String error) {
    return 'Exporteren mislukt: $error';
  }

  @override
  String csvImportTitle(String entity) {
    return 'CSV importeren: $entity';
  }

  @override
  String get csvImportHelp =>
      'Rijen worden gekoppeld op code: een bestaande code wordt bijgewerkt, een nieuwe code wordt aangemaakt. Kolommen die niet in het bestand staan, blijven ongewijzigd en er wordt nooit iets verwijderd. Alles of niets: bij een fout in een rij wordt niets geïmporteerd. Gescheiden door puntkomma of komma, UTF-8.';

  @override
  String get csvChooseFile => 'CSV-bestand kiezen';

  @override
  String get csvChooseOther => 'Ander bestand kiezen';

  @override
  String get csvChecking => 'Bestand controleren...';

  @override
  String get csvImporting => 'Importeren...';

  @override
  String get csvPreview => 'Voorbeeld: er is nog niets geïmporteerd';

  @override
  String get csvDone => 'Import voltooid';

  @override
  String get csvToCreate => 'Aan te maken';

  @override
  String get csvToUpdate => 'Bij te werken';

  @override
  String get csvUnchanged => 'Ongewijzigd';

  @override
  String get csvCreated => 'Aangemaakt';

  @override
  String get csvUpdated => 'Bijgewerkt';

  @override
  String get csvImportAction => 'Importeren';

  @override
  String get csvEmptyFile => 'Het bestand is leeg.';

  @override
  String get csvNotUtf8 =>
      'Het bestand is geen UTF-8-tekst. Sla het op als CSV (UTF-8) en probeer opnieuw.';

  @override
  String get csvReadFailed => 'Het bestand kon niet worden gelezen.';

  @override
  String csvErrorsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problemen gevonden',
      one: '1 probleem gevonden',
    );
    return '$_temp0. Er is niets geïmporteerd.';
  }

  @override
  String csvErrorRow(int row) {
    return 'Rij $row';
  }

  @override
  String csvErrorRowColumn(int row, String column) {
    return 'Rij $row, kolom $column';
  }

  @override
  String csvAndMore(int count) {
    return 'en nog $count';
  }

  @override
  String profileTooltip(String name) {
    return 'Profiel: $name';
  }

  @override
  String get tabTicket => 'Ticket';

  @override
  String get tabQuotation => 'Offerte';

  @override
  String get tabNewQuotation => 'Nieuwe offerte';

  @override
  String get tabOrder => 'Order';

  @override
  String get tabRepair => 'Reparatie';

  @override
  String get tabJob => 'Opdracht';

  @override
  String get tabProduct => 'Product';

  @override
  String get tabOpportunity => 'Kans';

  @override
  String get tabStock => 'Voorraad';

  @override
  String get tabArticle => 'Artikel';

  @override
  String get tabContract => 'Contract';

  @override
  String get tabCount => 'Telling';

  @override
  String get workspaceOverview => 'Overzicht';

  @override
  String get openTabs => 'Open tabbladen';

  @override
  String get closeTab => 'Tabblad sluiten';

  @override
  String get openInNewTab => 'Openen in nieuw tabblad';

  @override
  String get unsavedChangesTitle => 'Niet-opgeslagen wijzigingen';

  @override
  String get unsavedChangesBody =>
      'Dit tabblad heeft niet-opgeslagen wijzigingen. Sluiten en weggooien?';

  @override
  String get discardChanges => 'Wijzigingen weggooien';

  @override
  String get remarkProduction => 'Productieopmerking';

  @override
  String get remarkProductionHelp => 'Intern, wordt nooit aan de klant getoond';

  @override
  String get remarkCustomer => 'Klantopmerking';

  @override
  String get remarkCustomerHelp =>
      'Wordt afgedrukt op de offerte en de orderbevestiging';

  @override
  String get remarkHistory => 'Eerdere opmerkingen';

  @override
  String get remarkHistoryThisCustomer => 'Deze klant';

  @override
  String get remarkHistoryThisLanguage => 'Deze taal';

  @override
  String get remarkHistoryAll => 'Alle';

  @override
  String get remarkHistoryEmpty => 'Geen eerdere opmerkingen voor dit product.';

  @override
  String remarkHistoryUsed(int count, String quotation) {
    return '$count keer gebruikt, laatst op $quotation';
  }

  @override
  String get defaultProductionRemark => 'Standaard productieopmerking';

  @override
  String get optionsTab => 'Opties';

  @override
  String get optionsIntro =>
      'Producten die samen met dit product op een offerte worden aangeboden. Een verplichte optie wordt automatisch toegevoegd.';

  @override
  String get optionsNone => 'Dit product heeft geen opties.';

  @override
  String get optionAdd => 'Optie toevoegen';

  @override
  String get optionRequired => 'Verplicht';

  @override
  String get optionQuantity => 'Aantal per eenheid';

  @override
  String get optionRemove => 'Optie verwijderen';

  @override
  String get optionsSaved => 'Opties opgeslagen.';

  @override
  String get optionsInvalidQuantity =>
      'Geef voor elke optie een aantal groter dan 0 op.';

  @override
  String optionsChooseTitle(String product) {
    return 'Opties voor $product';
  }

  @override
  String get optionsChooseHelp =>
      'Verplichte opties worden automatisch toegevoegd. Vink de optionele opties aan die u wilt toevoegen.';

  @override
  String get optionsAddSelected => 'Toevoegen';

  @override
  String get optionsSkip => 'Zonder optionele opties';

  @override
  String get optionLine => 'Optie van de regel erboven';

  @override
  String get configurator => 'Configurator';

  @override
  String get configurators => 'Configuratoren';

  @override
  String get configure => 'Configureren';

  @override
  String get newConfiguration => 'Nieuwe configuratie';

  @override
  String get savedConfigurations => 'Bewaarde configuraties';

  @override
  String cfgAddRow(String item) {
    return '$item toevoegen';
  }

  @override
  String cfgAddRowToGroup(String group) {
    return 'Rij toevoegen aan $group';
  }

  @override
  String get cfgCalculated => 'Berekend';

  @override
  String get cfgChangeCustomer => 'Andere klant';

  @override
  String get cfgCreateQuotation => 'Offerte maken';

  @override
  String get cfgUpdateQuotation => 'Offerte bijwerken';

  @override
  String get cfgDeleteConfirm =>
      'Deze configuratie verwijderen? Offertes die ervan gemaakt zijn blijven bestaan.';

  @override
  String get cfgDeleteRow => 'Rij verwijderen';

  @override
  String get cfgDuplicateRow => 'Rij dupliceren';

  @override
  String get cfgDiscard => 'Verwerpen';

  @override
  String get cfgDiscardChanges => 'Niet-bewaarde wijzigingen verwerpen?';

  @override
  String cfgEach(String value) {
    return 'Per element: $value';
  }

  @override
  String get cfgErrors => 'Fouten';

  @override
  String get cfgWarnings => 'Waarschuwingen';

  @override
  String get cfgInfo => 'Informatie';

  @override
  String cfgEvalFailed(String message) {
    return 'Herberekenen mislukt: $message';
  }

  @override
  String get cfgInput => 'Invoer';

  @override
  String get cfgIssues => 'Meldingen';

  @override
  String get cfgLines => 'Lijnen';

  @override
  String get cfgWhy => 'Waarom?';

  @override
  String get cfgInvalidNumber => 'Geen geldig getal';

  @override
  String get cfgNewerRevision =>
      'Er is een nieuwere revisie van deze configurator.';

  @override
  String get cfgUpgrade => 'Bijwerken';

  @override
  String get cfgNoConfigurations => 'Nog geen bewaarde configuraties.';

  @override
  String get cfgNoModels => 'Er is nog geen configurator actief.';

  @override
  String get cfgNoCustomer => 'Geen klant';

  @override
  String get cfgNoIssues => 'Geen meldingen.';

  @override
  String get cfgNoLines => 'De configuratie levert nog geen lijnen op.';

  @override
  String get cfgNotInCatalogue => 'Niet in de productcatalogus';

  @override
  String get cfgPinned => 'Eigen waarde (vastgezet)';

  @override
  String get cfgPricesNeedCustomer => 'Kies een klant om prijzen te zien.';

  @override
  String get cfgQuoteBlocked => 'Los de fouten op voor je een offerte maakt.';

  @override
  String get cfgQuoteNeedsCustomer =>
      'Kies een klant voor je een offerte maakt.';

  @override
  String cfgQuoteCreated(String number) {
    return 'Offerte $number aangemaakt.';
  }

  @override
  String cfgQuoteUpdated(String number) {
    return 'Offerte $number bijgewerkt.';
  }

  @override
  String cfgQuoteRevised(String number) {
    return 'Offerte $number: er is een nieuwe revisie gemaakt.';
  }

  @override
  String cfgResetToCalculated(String value) {
    return 'Terug naar berekend ($value)';
  }

  @override
  String cfgStale(String value) {
    return 'De berekening geeft nu $value';
  }

  @override
  String cfgRevision(int revision) {
    return 'revisie $revision';
  }

  @override
  String cfgRule(String rule) {
    return 'Regel: $rule';
  }

  @override
  String get cfgSaved => 'Bewaard.';

  @override
  String get cfgSelectLine => 'Kies een lijn om te zien waar ze vandaan komt.';

  @override
  String get cfgSetForAll => 'Voor alle rijen instellen…';

  @override
  String cfgSetForAllTitle(String column) {
    return '$column voor alle rijen';
  }

  @override
  String get cfgStart => 'Starten';

  @override
  String get cfgUnsaved => 'Niet bewaard';

  @override
  String cfgNewerRevisionAvailable(int revision) {
    return 'revisie $revision beschikbaar';
  }

  @override
  String get cfgbActivate => 'Activeren';

  @override
  String get cfgbActivateConfirm =>
      'Dit ontwerp activeren? Verkopers gebruiken het voor nieuwe configuraties; de huidige actieve revisie vervalt.';

  @override
  String get cfgbActivated => 'Geactiveerd.';

  @override
  String cfgbActivatedOn(String date) {
    return 'geactiveerd op $date';
  }

  @override
  String get cfgbActivateModel => 'Beschikbaar maken';

  @override
  String cfgbActivateRefused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problemen',
      one: '1 probleem',
    );
    return 'Niet geactiveerd: $_temp0 op te lossen.';
  }

  @override
  String cfgbActiveRevision(int revision) {
    return 'actief: revisie $revision';
  }

  @override
  String get cfgbAddChild => 'Optieregel toevoegen';

  @override
  String get cfgbAddColumn => 'Kolom toevoegen';

  @override
  String get cfgbAddComputed => 'Berekende waarde toevoegen';

  @override
  String get cfgbAddField => 'Veld toevoegen';

  @override
  String get cfgbAddItemTable => 'Itemtabel toevoegen';

  @override
  String get cfgbAddOption => 'Optie toevoegen';

  @override
  String get cfgbAddRow => 'Rij toevoegen';

  @override
  String get cfgbAddRule => 'Uitvoerregel toevoegen';

  @override
  String get cfgbAddSection => 'Sectie toevoegen';

  @override
  String get cfgbAddTable => 'Tabel toevoegen';

  @override
  String get cfgbAddValidation => 'Controle toevoegen';

  @override
  String get cfgbApply => 'Toepassen';

  @override
  String cfgbChildRuleTitle(String id) {
    return 'Optieregel $id';
  }

  @override
  String get cfgbCode => 'Productcode (formule)';

  @override
  String get cfgbCodeExpr => 'Formule';

  @override
  String get cfgbCodeHelp => 'bv. \'BELT-M\' of motor_code';

  @override
  String get cfgbCodeTemplate => 'Productcode (sjabloon)';

  @override
  String get cfgbCodeTemplateHelp =>
      'Tekst met formules tussen accolades, bv. DRV- en daarna motor_size tussen accolades';

  @override
  String get cfgbColumn => 'Kolom';

  @override
  String get cfgbColumnName => 'Kolom';

  @override
  String get cfgbCommentTemplate => 'Opmerking (sjabloon)';

  @override
  String cfgbComputedOf(String scope) {
    return 'Berekende waarden: $scope';
  }

  @override
  String cfgbComputedTitle(String name) {
    return 'Berekende waarde $name';
  }

  @override
  String get cfgbConditions => 'Voorwaarden';

  @override
  String get cfgbCreate => 'Aanmaken';

  @override
  String get cfgbCsvExport => 'CSV exporteren';

  @override
  String get cfgbCsvImport => 'CSV importeren';

  @override
  String cfgbCsvImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rijen geïmporteerd.',
      one: '1 rij geïmporteerd.',
    );
    return '$_temp0';
  }

  @override
  String get cfgbCsvProblems => 'Het CSV-bestand werd niet geïmporteerd';

  @override
  String get cfgbDeactivateModel => 'Intrekken';

  @override
  String get cfgbDefault => 'Standaardwaarde';

  @override
  String get cfgbDefaultExpr => 'Standaardwaarde (formule)';

  @override
  String get cfgbDefaultExprHelp => 'In plaats van een vaste standaardwaarde';

  @override
  String get cfgbDescriptionTemplate => 'Omschrijving (sjabloon)';

  @override
  String get cfgbDesignTitle => 'Configuratoren ontwerpen';

  @override
  String get cfgbDimCurrent => 'Stroom';

  @override
  String get cfgbDimension => 'Grootheid';

  @override
  String get cfgbDimLength => 'Lengte';

  @override
  String get cfgbDimMass => 'Massa';

  @override
  String get cfgbDimPower => 'Vermogen';

  @override
  String get cfgbDimSpeed => 'Snelheid';

  @override
  String get cfgbDimVoltage => 'Spanning';

  @override
  String get cfgbDiscard => 'Verwerpen';

  @override
  String get cfgbDisplayUnits => 'Weergave-eenheden:';

  @override
  String cfgbDraftRevision(int revision) {
    return 'ontwerp: revisie $revision';
  }

  @override
  String get cfgbEditDraft => 'Ontwerp bewerken';

  @override
  String get cfgbEnabledIf => 'Ingeschakeld als';

  @override
  String cfgbExported(String name) {
    return '$name bewaard.';
  }

  @override
  String get cfgbExportJson => 'JSON exporteren';

  @override
  String get cfgbExpr => 'Formule';

  @override
  String get cfgbFamily => 'Productfamilie (code)';

  @override
  String cfgbFieldsOf(String scope) {
    return 'Velden: $scope';
  }

  @override
  String cfgbFieldTitle(String name) {
    return 'Veld $name';
  }

  @override
  String get cfgbForEach => 'Voor elk';

  @override
  String get cfgbForEachHelp =>
      'Een lijst: één regel per element, met each en each_index';

  @override
  String cfgbFormulaType(String type) {
    return 'Resultaat: $type';
  }

  @override
  String get cfgbGroupField => 'Groeperen op veld';

  @override
  String get cfgbGroupHelp =>
      'Een groep is een sectie rijen (bv. een hal): één per waarde van het groepeerveld van een itemtabel. Groepsvelden met de naam van een projectveld overschrijven dat binnen de groep.';

  @override
  String get cfgbGroupLabel => 'Naam van een groep';

  @override
  String get cfgbHelp => 'Helptekst';

  @override
  String get cfgbId => 'Id';

  @override
  String get cfgbImported =>
      'In de editor geïmporteerd; bewaar om het te behouden.';

  @override
  String cfgbImportFailed(String message) {
    return 'Niet geïmporteerd: $message';
  }

  @override
  String get cfgbImportJson => 'JSON importeren';

  @override
  String get cfgbImportNotExport => 'Dit bestand is geen configurator-export.';

  @override
  String cfgbImportReplace(String name) {
    return 'De hele definitie van dit ontwerp vervangen door $name?';
  }

  @override
  String get cfgbInactive => 'niet beschikbaar voor verkoop';

  @override
  String get cfgbItemLabel => 'Itemlabel (sjabloon)';

  @override
  String get cfgbItemLabelHelp =>
      'Benoemt één rij in opmerkingen en meldingen; formules tussen accolades, bv. group_name en index';

  @override
  String get cfgbItemTable => 'Itemtabel';

  @override
  String get cfgbKeys => 'Sleutelkolommen:';

  @override
  String get cfgbKindExact => 'Exact';

  @override
  String get cfgbKindRange => 'Bereik';

  @override
  String get cfgbLabel => 'Label';

  @override
  String get cfgbLayout => 'Opmaak';

  @override
  String get cfgbLayoutSections => 'Formuliersecties';

  @override
  String get cfgbLayoutSectionsHelp =>
      'Velden verwijzen in hun opmaak naar een sectie; het formulier toont ze onder die titel.';

  @override
  String get cfgbMax => 'Maximum';

  @override
  String get cfgbMaxLength => 'Maximale lengte';

  @override
  String get cfgbMaxRows => 'Maximum rijen';

  @override
  String get cfgbMergeIdentical => 'Identieke regels samenvoegen';

  @override
  String get cfgbMergeIdenticalHelp =>
      'Regels met dezelfde code worden één regel; de opmerking somt de items op';

  @override
  String get cfgbMessage => 'Melding (sjabloon)';

  @override
  String get cfgbMin => 'Minimum';

  @override
  String get cfgbMinRows => 'Minimum rijen';

  @override
  String get cfgbMoveDown => 'Omlaag';

  @override
  String get cfgbMoveUp => 'Omhoog';

  @override
  String get cfgbNewDraft => 'Nieuw ontwerp van de actieve revisie';

  @override
  String get cfgbNewDraftFromThis => 'Nieuw ontwerp van deze revisie';

  @override
  String get cfgbNewModel => 'Nieuwe configurator';

  @override
  String get cfgbNoProblems => 'Geen problemen';

  @override
  String get cfgbOnMissing => 'Als geen rij past';

  @override
  String get cfgbOnMissingClamp => 'Volgende hogere rij';

  @override
  String get cfgbOnMissingHelp =>
      'Volgende hogere rij: een waarde onder of tussen de bereiken neemt de rij met het volgende hogere bereik, een waarde boven alle bereiken de laatste rij; een offset voorbij een uiteinde stopt bij de eerste of laatste rij.';

  @override
  String get cfgbOnMissingError => 'Fout';

  @override
  String get cfgbOnMissingNull => 'Geen waarde';

  @override
  String get cfgbOptionsFamily => 'Productfamilie';

  @override
  String get cfgbOptionsFrom => 'Toegelaten alternatieven (formule)';

  @override
  String get cfgbOptionsFromHelp =>
      'Een lijst waaruit de gebruiker kan kiezen in plaats van de berekende waarde';

  @override
  String get cfgbOptionsStatic => 'Vaste lijst';

  @override
  String get cfgbOptionsTable => 'Tabelkolom';

  @override
  String get cfgbOrder => 'Volgorde';

  @override
  String get cfgbOutputRules => 'Uitvoerregels';

  @override
  String get cfgbOverridable => 'De gebruiker mag het overschrijven';

  @override
  String get cfgbOverridableHelp =>
      'Getoond als berekend, vastgezet of vastgezet maar verouderd';

  @override
  String get cfgbPattern => 'Patroon (reguliere expressie)';

  @override
  String get cfgbPercentBase => 'Percentage van';

  @override
  String get cfgbPercentBaseList => 'de lijstprijs van de hoofdregel';

  @override
  String get cfgbPercentBaseNet => 'de nettoprijs van de hoofdregel';

  @override
  String get cfgbPercentOfParent => 'Percentage van hoofdregel (formule)';

  @override
  String get cfgbPercentOfParentHelp =>
      'Prijst de regel als dit percentage van de hoofdregel, bv. 20';

  @override
  String cfgbProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problemen',
      one: '1 probleem',
    );
    return '$_temp0';
  }

  @override
  String get cfgbProductFilter => 'Productfilter (formule op p)';

  @override
  String get cfgbProductFilterHelp => 'bv. p.attr(\'kw\') >= 1';

  @override
  String get cfgbQuantity => 'Aantal (formule)';

  @override
  String get cfgbQuantityHelp => 'Standaard 1; nul of minder laat de regel weg';

  @override
  String get cfgbRangeKey => 'Bereiksleutel';

  @override
  String get cfgbRangeKeyHelp => 'De opzoeksleutel met de waarde';

  @override
  String get cfgbRangeMax => 'Maximumkolom';

  @override
  String get cfgbRangeMin => 'Minimumkolom';

  @override
  String get cfgbRawJson => 'Definitie als JSON';

  @override
  String get cfgbRemoveColumn => 'Kolom verwijderen';

  @override
  String get cfgbRemoveItemTable => 'Itemtabel verwijderen';

  @override
  String get cfgbRemoveRow => 'Rij verwijderen';

  @override
  String get cfgbReplace => 'Vervangen';

  @override
  String get cfgbRequired => 'Verplicht';

  @override
  String get cfgbRevisions => 'Revisies';

  @override
  String cfgbRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rijen',
      one: '1 rij',
    );
    return '$_temp0';
  }

  @override
  String cfgbRuleTitle(String id) {
    return 'Uitvoerregel $id';
  }

  @override
  String get cfgbSavedValid => 'Bewaard. Het ontwerp kan geactiveerd worden.';

  @override
  String cfgbSavedWithProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problemen',
      one: '1 probleem',
    );
    return 'Bewaard met $_temp0.';
  }

  @override
  String get cfgbScope => 'Niveau';

  @override
  String get cfgbScopeGroup => 'Groep';

  @override
  String get cfgbScopeItem => 'Item (rij)';

  @override
  String cfgbScopeItems(String table) {
    return 'Items: $table';
  }

  @override
  String get cfgbScopeProject => 'Project';

  @override
  String get cfgbScopes => 'Niveaus';

  @override
  String get cfgbSection => 'Sectie';

  @override
  String get cfgbSectionTemplate => 'Sectie (sjabloon)';

  @override
  String get cfgbSectionTemplateHelp =>
      'Standaard de groepsnaam bij groeps- en itemregels';

  @override
  String get cfgbSelectComputed =>
      'Kies een berekende waarde of voeg er een toe.';

  @override
  String get cfgbSelectField => 'Kies een veld of voeg er een toe.';

  @override
  String get cfgbSelectRule => 'Kies een uitvoerregel of voeg er een toe.';

  @override
  String get cfgbSelectTable => 'Kies een tabel of voeg er een toe.';

  @override
  String get cfgbSelectValidation => 'Kies een controle of voeg er een toe.';

  @override
  String get cfgbSeverity => 'Ernst';

  @override
  String get cfgbSeverityError => 'Fout';

  @override
  String get cfgbSeverityInfo => 'Informatie';

  @override
  String get cfgbSeverityWarning => 'Waarschuwing';

  @override
  String get cfgbShow => 'Zichtbaar voor de gebruiker';

  @override
  String get cfgbShownAt => 'Getoond bij veld';

  @override
  String get cfgbStatusActive => 'actief';

  @override
  String get cfgbStatusDraft => 'ontwerp';

  @override
  String get cfgbStatusObsolete => 'vervallen';

  @override
  String get cfgbStep => 'Stap';

  @override
  String get cfgbTabComputed => 'Berekende waarden';

  @override
  String get cfgbTabFields => 'Velden & opmaak';

  @override
  String get cfgbTabGeneral => 'Algemeen';

  @override
  String get cfgbTable => 'Tabel';

  @override
  String get cfgbTableKind => 'Soort';

  @override
  String get cfgbTables => 'Opzoektabellen';

  @override
  String cfgbTableTitle(String name) {
    return 'Tabel $name';
  }

  @override
  String get cfgbTabOutputs => 'Uitvoerregels';

  @override
  String get cfgbTabTables => 'Tabellen';

  @override
  String get cfgbTabTest => 'Testen';

  @override
  String get cfgbTabTransfer => 'Import/export';

  @override
  String get cfgbTabValidations => 'Controles';

  @override
  String get cfgbTestHelp =>
      'Probeer het bewaarde ontwerp zoals verkopers het zien. Er wordt niets bewaard; kies een regel om te zien waarom ze er staat.';

  @override
  String get cfgbTestNeedsValid =>
      'Het bewaarde ontwerp heeft problemen; de test kan mislukken tot ze opgelost zijn.';

  @override
  String get cfgbTestReset => 'Opnieuw beginnen';

  @override
  String get cfgbTestUnsaved =>
      'De test gebruikt het bewaarde ontwerp; bewaar om je laatste wijzigingen mee te nemen.';

  @override
  String get cfgbTranslations => 'Vertalingen';

  @override
  String get cfgbTypeBoolean => 'Ja/nee';

  @override
  String get cfgbTypeChoice => 'Keuze';

  @override
  String get cfgbTypeInteger => 'Geheel getal';

  @override
  String get cfgbTypeNumber => 'Getal';

  @override
  String get cfgbTypeProduct => 'Product';

  @override
  String get cfgbTypeText => 'Tekst';

  @override
  String get cfgbUnsavedText =>
      'Het ontwerp heeft wijzigingen die niet bewaard zijn.';

  @override
  String get cfgbUnsavedTitle => 'Niet-bewaarde wijzigingen';

  @override
  String get cfgbValidations => 'Controles';

  @override
  String cfgbValidationTitle(String id) {
    return 'Controle $id';
  }

  @override
  String get cfgbValidationWhenHelp =>
      'Als dit waar is, wordt de melding getoond';

  @override
  String get cfgbValue => 'Waarde';

  @override
  String get cfgbVisibleIf => 'Zichtbaar als';

  @override
  String get cfgbWhen => 'Als';

  @override
  String get cfgbWhenHelp => 'Regels worden enkel gemaakt als dit waar is';

  @override
  String get cfgbWidth => 'Breedte';

  @override
  String get tabProductionOrder => 'Productieorder';

  @override
  String get tabDeliveryNote => 'Pakbon';

  @override
  String get vatRegime => 'BTW-regime';

  @override
  String get vatRegimeDomestic => 'EU-klant, BTW aangerekend';

  @override
  String get vatRegimeIntraEu => 'EU-bedrijf, BTW verlegd';

  @override
  String get vatRegimeOutsideEu => 'Buiten de EU, geen BTW';

  @override
  String get addSubItem => 'Subitem toevoegen';

  @override
  String subItemsOptions(String product) {
    return 'Opties van $product';
  }

  @override
  String get subItemsNoOptions => 'Dit product heeft geen opties.';

  @override
  String get subItemsOtherProducts => 'Andere producten';

  @override
  String get crTitle => 'Rapporten';

  @override
  String get crNew => 'Nieuw rapport';

  @override
  String get crEmpty =>
      'Nog geen rapporten. Maak er een om je gegevens te groeperen en op te tellen.';

  @override
  String get crShared => 'Gedeeld';

  @override
  String get crPrivate => 'Privé';

  @override
  String get crShare => 'Delen met iedereen in het bedrijf';

  @override
  String crOwnedBy(String name) {
    return 'Door $name';
  }

  @override
  String get crObject => 'Rapport over';

  @override
  String get crJoin => 'Gerelateerde gegevens toevoegen';

  @override
  String get crGroupBy => 'Groeperen op';

  @override
  String get crAddGrouping => 'Groepering toevoegen';

  @override
  String get crColumns => 'Kolommen';

  @override
  String get crAddColumn => 'Kolom toevoegen';

  @override
  String get crField => 'Veld';

  @override
  String get crSummary => 'Samenvatting';

  @override
  String get crSummaryNone => 'Waarde tonen';

  @override
  String get crSumCount => 'Aantal';

  @override
  String get crSumSum => 'Som';

  @override
  String get crSumAvg => 'Gemiddelde';

  @override
  String get crSumMin => 'Minimum';

  @override
  String get crSumMax => 'Maximum';

  @override
  String get crFilters => 'Filters';

  @override
  String get crAddFilter => 'Filter toevoegen';

  @override
  String get crMatchAll => 'Alle filters moeten kloppen';

  @override
  String get crMatchAny => 'Minstens één filter moet kloppen';

  @override
  String get crOpEq => 'is gelijk aan';

  @override
  String get crOpNe => 'is niet gelijk aan';

  @override
  String get crOpGt => 'groter dan';

  @override
  String get crOpGte => 'minstens';

  @override
  String get crOpLt => 'kleiner dan';

  @override
  String get crOpLte => 'hoogstens';

  @override
  String get crOpContains => 'bevat';

  @override
  String get crOpStartsWith => 'begint met';

  @override
  String get crOpIn => 'is een van';

  @override
  String get crOpIsNull => 'is leeg';

  @override
  String get crOpNotNull => 'is niet leeg';

  @override
  String get crValue => 'Waarde';

  @override
  String get crValueListHint => 'Scheid waarden met komma\'s';

  @override
  String get crBucketNone => 'Exacte waarde';

  @override
  String get crBucketDay => 'Per dag';

  @override
  String get crBucketMonth => 'Per maand';

  @override
  String get crBucketYear => 'Per jaar';

  @override
  String get crSort => 'Sorteren';

  @override
  String get crAddSort => 'Sortering toevoegen';

  @override
  String get crDescending => 'Aflopend';

  @override
  String get crChart => 'Grafiek';

  @override
  String get crChartNone => 'Geen grafiek';

  @override
  String get crChartBar => 'Staaf';

  @override
  String get crChartLine => 'Lijn';

  @override
  String get crChartPie => 'Taart';

  @override
  String get crChartX => 'Categorieën';

  @override
  String get crChartY => 'Waarden';

  @override
  String crRows(int count) {
    return '$count rijen';
  }

  @override
  String crRowsShown(int shown, int total) {
    return '$shown van $total rijen getoond';
  }

  @override
  String crChartShareShown(int count) {
    return 'De aandelen gelden voor de $count getoonde groepen.';
  }

  @override
  String get crSaved => 'Rapport opgeslagen';

  @override
  String get crDeleted => 'Rapport verwijderd';

  @override
  String get crDelete => 'Verwijderen';

  @override
  String get crDeleteConfirm => 'Dit rapport verwijderen?';

  @override
  String get crExportCsv => 'CSV exporteren';

  @override
  String get crExportPdf => 'PDF exporteren';

  @override
  String get crNeedName => 'Geef het rapport een naam.';

  @override
  String get crNeedColumn => 'Voeg minstens één kolom toe.';

  @override
  String get crLoadMore => 'Meer rijen tonen';

  @override
  String get crNoRows => 'Geen rijen voor dit rapport.';

  @override
  String get crRun => 'Uitvoeren';

  @override
  String get crDateMode => 'Datum';

  @override
  String get crDateFixed => 'Vaste datum';

  @override
  String get crDateRelative => 'Relatief ten opzichte van vandaag';

  @override
  String get crRelativePeriod => 'Periode';

  @override
  String get crRelativeDays => 'Aantal dagen';

  @override
  String get crRelativeDaysInvalid =>
      'Vul een geheel aantal dagen in van 1 tot 3660.';

  @override
  String get crRelToday => 'Vandaag';

  @override
  String get crRelYesterday => 'Gisteren';

  @override
  String get crRelThisWeek => 'Deze week';

  @override
  String get crRelLastWeek => 'Vorige week';

  @override
  String get crRelThisMonth => 'Deze maand';

  @override
  String get crRelLastMonth => 'Vorige maand';

  @override
  String get crRelThisQuarter => 'Dit kwartaal';

  @override
  String get crRelLastQuarter => 'Vorig kwartaal';

  @override
  String get crRelThisYear => 'Dit jaar';

  @override
  String get crRelLastYear => 'Vorig jaar';

  @override
  String get crRelLastNDays => 'Laatste N dagen';

  @override
  String get crRelNextNDays => 'Komende N dagen';

  @override
  String get envLive => 'Live';

  @override
  String get envTest => 'Test';

  @override
  String get envTutorial => 'Tutorial';

  @override
  String envBannerSemantics(String name, String kind) {
    return 'Omgeving $name, $kind';
  }

  @override
  String get envSwitcherTitle => 'Omgevingen';

  @override
  String envSwitchMenu(String name) {
    return 'Omgeving: $name';
  }

  @override
  String get envSwitchTooltip => 'Omgeving wisselen';

  @override
  String get envActive => 'Actief';

  @override
  String get envAdd => 'Omgeving toevoegen';

  @override
  String get envName => 'Naam';

  @override
  String get envServerUrl => 'Serveradres';

  @override
  String get envCheck => 'Server controleren';

  @override
  String envDetected(String kind, String db) {
    return 'De server meldt: $kind-omgeving, database $db';
  }

  @override
  String get envInvalidUrl =>
      'Geef een volledig adres, zoals https://erp.example.com';

  @override
  String get envAlreadyListed => 'Deze server staat al in de lijst.';

  @override
  String envUnreachable(String error) {
    return 'De omgeving van deze server kon niet worden gelezen: $error';
  }

  @override
  String get envRemove => 'Verwijderen';

  @override
  String get envRemoveTitle => 'Omgeving verwijderen?';

  @override
  String envRemoveBody(String name) {
    return '$name wordt van dit toestel verwijderd, samen met de bewaarde aanmelding. Op de server verandert niets.';
  }

  @override
  String get envCannotRemoveActive => 'Wissel eerst naar een andere omgeving';

  @override
  String envUnsavedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open tabbladen hebben niet-opgeslagen wijzigingen',
      one: '1 open tabblad heeft niet-opgeslagen wijzigingen',
    );
    return '$_temp0. Bij het wisselen van omgeving worden alle tabbladen gesloten en gaan die wijzigingen verloren.';
  }

  @override
  String get envDiscardAndSwitch => 'Verwerpen en wisselen';

  @override
  String get adminPriceZones => 'Prijszones';

  @override
  String get newPriceZone => 'Nieuwe prijszone';

  @override
  String get editPriceZone => 'Prijszone bewerken';

  @override
  String get sortOrder => 'Sorteervolgorde';

  @override
  String get noPriceZones => 'Nog geen prijszones.';

  @override
  String get priceZoneDeleted => 'Prijszone verwijderd';

  @override
  String get delete => 'Verwijderen';

  @override
  String deletePriceZoneConfirm(String code) {
    return 'Prijszone $code verwijderen? Dit wordt geweigerd als prijzen of klanten ze gebruiken.';
  }

  @override
  String get sortOrderInvalid =>
      'De sorteervolgorde moet een geheel getal zijn.';

  @override
  String get envNotSaved =>
      'Gedaan, maar de lijst met omgevingen kon niet op dit toestel worden bewaard.';

  @override
  String get tutTitle => 'Tutorial';

  @override
  String get tutBack => 'Terug';

  @override
  String get tutNext => 'Volgende';

  @override
  String get tutSkipStep => 'Stap overslaan';

  @override
  String get tutPause => 'Pauzeren';

  @override
  String get tutResume => 'Hervatten';

  @override
  String get tutPaused => 'Tutorial gepauzeerd';

  @override
  String get tutTakeMe => 'Breng me erheen';

  @override
  String tutStepOf(int current, int total) {
    return 'Stap $current van $total';
  }

  @override
  String get tutOfferTitle => 'Welkom bij TradoCraft';

  @override
  String get tutOfferBody =>
      'Dit is een tutorialomgeving. Wil je een rondleiding die je stap voor stap de app leert, met oefendata?';

  @override
  String get tutOfferStart => 'Start het tutorial';

  @override
  String get tutOfferLater => 'Niet nu';

  @override
  String get tutLiveTitle => 'Het tutorial draait niet op live data';

  @override
  String get tutLiveBody =>
      'Het tutorial maakt records aan en draait daarom alleen in een test- of tutorialomgeving. Schakel over naar zo\'n omgeving, of voeg er een toe.';

  @override
  String get tutSwitchEnv => 'Omgeving wisselen';

  @override
  String get tutAddEnv => 'Omgeving toevoegen';

  @override
  String get tutMapIntro =>
      'Werk de hoofdstukken in volgorde af. Je kunt een hoofdstuk altijd pauzeren, opnieuw doen of overslaan.';

  @override
  String get tutStatusDone => 'Klaar';

  @override
  String get tutStatusCurrent => 'Aan de beurt';

  @override
  String get tutStatusLocked => 'Vergrendeld';

  @override
  String get tutStatusSkipped => 'Overgeslagen';

  @override
  String get tutStatusPaused => 'Bezig';

  @override
  String get tutStart => 'Starten';

  @override
  String get tutReplay => 'Opnieuw';

  @override
  String get tutSkipChapter => 'Hoofdstuk overslaan';

  @override
  String get tutWelcomeTitle => 'Welkom';

  @override
  String get tutWelcomeSummary =>
      'Wegwijs: de omgevingsbalk, de tabbladen en de bediening van het tutorial.';

  @override
  String get tutProductTitle => 'Je eerste product';

  @override
  String get tutProductSummary =>
      'Pet: productbeheerder. Maak drie componenten, een eindproduct en de stuklijst ervan.';

  @override
  String get tutWelcomeBannerTitle => 'De balk bovenaan';

  @override
  String get tutWelcomeBannerBody =>
      'Deze balk toont altijd in welke omgeving je zit: de naam en het soort. Amber betekent test, blauw tutorial en rood live data. Het tutorial draait alleen in test- en tutorialomgevingen, dus niets wat je hier doet raakt echte data.';

  @override
  String get tutWelcomeTabsTitle => 'Tabbladen en secties';

  @override
  String get tutWelcomeTabsBody =>
      'De secties staan links (of in de balk onderaan op een telefoon). Een record openen, zoals een product of offerte, voegt een tabblad toe aan de werkruimte, zodat je meerdere records open kunt houden en erop kunt terugkomen.';

  @override
  String get tutWelcomeControlsTitle => 'Deze kaart';

  @override
  String get tutWelcomeControlsBody =>
      'Ik ben je verteller. Met Volgende ga je verder als een stap alleen uitleg is. Stappen waarin je iets moet doen, zijn vanzelf klaar zodra je het gedaan hebt. Met Terug en Stap overslaan beweeg je vrij, en Pauzeren verbergt mij tot je op Hervatten drukt.';

  @override
  String get tutWelcomeMenuTitle => 'Waar je mij vindt';

  @override
  String get tutWelcomeMenuBody =>
      'Open het accountmenu voor het item Tutorial. Dat opent de hoofdstukkenkaart, waar je een hoofdstuk altijd kunt hervatten, opnieuw doen of overslaan.';

  @override
  String get tutWelcomeProductsTitle => 'Laten we beginnen';

  @override
  String get tutWelcomeProductsBody =>
      'Open de sectie Producten. Het volgende hoofdstuk begint daar.';

  @override
  String get tutProductOpenTitle => 'Producten';

  @override
  String get tutProductOpenBody =>
      'Vandaag ben jij de productbeheerder. Alles wat het bedrijf verkoopt of bouwt is een product. Open de sectie Producten.';

  @override
  String get tutProductMotorTitle => 'Component: Motor';

  @override
  String get tutProductMotorBody =>
      'Maak het eerste component aan. Kies Nieuw product, vul code TUT-MOTOR en naam Motor in, laat het type op Aangekocht staan en sla op.';

  @override
  String get tutProductMotorHint =>
      'Het voorvoegsel TUT- markeert tutorialdata, zodat je die later herkent.';

  @override
  String get tutProductFrameTitle => 'Component: Frame';

  @override
  String get tutProductFrameBody =>
      'Maak op dezelfde manier een tweede component: code TUT-FRAME, naam Frame, type Aangekocht.';

  @override
  String get tutProductControllerTitle => 'Component: Controller';

  @override
  String get tutProductControllerBody =>
      'En een derde: code TUT-CTRL, naam Controller, type Aangekocht.';

  @override
  String get tutProductCartTitle => 'Het eindproduct';

  @override
  String get tutProductCartBody =>
      'Nu het product dat je uit die onderdelen bouwt. Maak code TUT-CART, naam Cart aan en kies het type Eigen productie: alleen producten met eigen productie hebben een stuklijst.';

  @override
  String get tutProductOpenCartTitle => 'Open de cart';

  @override
  String get tutProductOpenCartBody =>
      'Open het nieuwe product Cart uit de lijst om de tabbladen te zien.';

  @override
  String get tutProductBomTabTitle => 'Stuklijst';

  @override
  String get tutProductBomTabBody =>
      'Kies het tabblad Stuklijst. Daarin staan de componenten om één stuk te bouwen. Een revisie is een concept dat je bewerkt, of de actieve die de productie gebruikt. Druk op Volgende als je er bent.';

  @override
  String get tutProductRevisionTitle => 'Een eerste revisie';

  @override
  String get tutProductRevisionBody =>
      'Kies Nieuwe revisie om een concept te starten.';

  @override
  String get tutProductLinesTitle => 'Voeg de componenten toe';

  @override
  String get tutProductLinesBody =>
      'Zoek elk component op en voeg het toe: Motor, Frame en Controller. Druk daarna op Concept opslaan.';

  @override
  String get tutProductLinesHint =>
      'Typ TUT in het zoekveld om de drie componenten te vinden.';

  @override
  String get tutProductActivateTitle => 'Activeer de revisie';

  @override
  String get tutProductActivateBody =>
      'Druk op Activeren. Vanaf nu gebruiken productie en offertes deze revisie; latere wijzigingen lopen via een nieuwe revisie.';

  @override
  String get tutProductDoneTitle => 'Goed gedaan';

  @override
  String get tutProductDoneBody =>
      'Je hebt een eindproduct met een stuklijst van drie componenten. Latere hoofdstukken bouwen hierop voort.';

  @override
  String get purchasing => 'Inkoop';

  @override
  String get tabSupplier => 'Leverancier';

  @override
  String get purchSuppliers => 'Leveranciers';

  @override
  String get purchNewSupplier => 'Nieuwe leverancier';

  @override
  String get purchPaymentTerms => 'Betalingstermijn';

  @override
  String purchDays(int count) {
    return '$count dagen';
  }

  @override
  String get purchActiveOnly => 'Alleen actieve';

  @override
  String get purchNameRequired => 'De naam is verplicht.';

  @override
  String get purchCountryInvalid =>
      'Het land moet een code van 2 letters zijn.';

  @override
  String get purchCurrencyInvalid =>
      'De munt moet een code van 3 letters zijn.';

  @override
  String get purchTermsInvalid =>
      'De betalingstermijn moet een geheel aantal dagen zijn.';

  @override
  String get purchInactive => 'Inactief';

  @override
  String get purchPriceList => 'Prijslijst';

  @override
  String get purchAddProduct => 'Product toevoegen';

  @override
  String get purchEditPrice => 'Prijs wijzigen';

  @override
  String get purchNoPrices => 'Nog geen producten in deze prijslijst.';

  @override
  String get purchPickProduct => 'Kies een product.';

  @override
  String get purchPriceInvalid => 'Geef een geldige eenheidsprijs in.';

  @override
  String get purchMoqInvalid =>
      'Geef een geldige minimale bestelhoeveelheid in.';

  @override
  String get purchLeadInvalid =>
      'De levertijd moet een geheel aantal dagen zijn.';

  @override
  String get purchSupplierArticleCode => 'Artikelcode leverancier';

  @override
  String get purchSupplierArticleName => 'Artikelnaam leverancier';

  @override
  String get purchMoq => 'Min. bestelhoeveelheid';

  @override
  String get purchLeadTimeDays => 'Levertijd (dagen)';

  @override
  String get purchPreferred => 'Voorkeursleverancier';

  @override
  String purchRemoveProductConfirm(String code) {
    return '$code uit deze prijslijst verwijderen?';
  }

  @override
  String purchMoqValue(String qty) {
    return 'MBH $qty';
  }

  @override
  String purchLeadValue(int days) {
    return 'levertijd $days d';
  }

  @override
  String get purchNoSuppliers => 'Geen leveranciers gevonden.';

  @override
  String get purchOrders => 'Inkooporders';

  @override
  String get purchNewOrder => 'Nieuwe inkooporder';

  @override
  String get purchNoOrders => 'Geen inkooporders gevonden.';

  @override
  String get purchOrderNumber => 'Nummer';

  @override
  String get purchSupplier => 'Leverancier';

  @override
  String get purchAllSuppliers => 'Alle leveranciers';

  @override
  String get purchOrderDate => 'Orderdatum';

  @override
  String get purchExpectedDate => 'Verwachte levering';

  @override
  String get purchStatusDraft => 'concept';

  @override
  String get purchStatusApproved => 'goedgekeurd';

  @override
  String get purchStatusSent => 'verzonden';

  @override
  String get purchStatusPartial => 'gedeeltelijk ontvangen';

  @override
  String get purchStatusReceived => 'ontvangen';

  @override
  String get purchStatusCancelled => 'geannuleerd';

  @override
  String get purchLines => 'Regels';

  @override
  String get purchAddLine => 'Regel toevoegen';

  @override
  String get purchPickSupplier => 'Kies een leverancier.';

  @override
  String get purchLineQtyInvalid =>
      'Aantal moet groter zijn dan nul, met maximaal 4 decimalen.';

  @override
  String get purchLinePriceInvalid =>
      'Eenheidsprijs moet nul of meer zijn, met maximaal 4 decimalen.';

  @override
  String get purchNeedLine => 'Voeg minstens een regel toe.';

  @override
  String get purchApprove => 'Goedkeuren';

  @override
  String get purchCancelOrder => 'Order annuleren';

  @override
  String purchCancelOrderConfirm(String number) {
    return 'Inkooporder $number annuleren? Dit kan niet ongedaan worden gemaakt.';
  }

  @override
  String get purchKeepOrder => 'Order behouden';

  @override
  String get purchQtyReceived => 'Ontvangen';

  @override
  String get purchLineTotal => 'Regeltotaal';

  @override
  String get purchSubtotal => 'Subtotaal';

  @override
  String get purchTax => 'Btw';

  @override
  String get tabPurchaseOrder => 'Inkooporder';

  @override
  String get purchReceiveGoods => 'Goederen ontvangen';

  @override
  String purchReceiveTitle(String number) {
    return 'Goederen ontvangen voor $number';
  }

  @override
  String get purchReceiveDestination => 'Bestemmingslocatie';

  @override
  String get purchReceiveQty => 'Te ontvangen aantal';

  @override
  String purchReceiveRemaining(String qty) {
    return 'Resterend: $qty';
  }

  @override
  String get purchReceiveSerialsHelp => 'Eén serienummer per regel';

  @override
  String get purchDeliveryNote => 'Leveringsbon leverancier';

  @override
  String purchReceiveQtyInvalid(String product, String max) {
    return '$product: voer een aantal in tussen 0 en $max.';
  }

  @override
  String purchReceiveLotNeeded(String product) {
    return '$product: voer een lotnummer in.';
  }

  @override
  String purchReceiveSerialWhole(String product) {
    return '$product: het aantal moet een geheel getal zijn.';
  }

  @override
  String purchReceiveSerialCount(String product, int count) {
    return '$product: voer precies $count verschillende serienummers in.';
  }

  @override
  String get purchReceiveNothing =>
      'Voer een aantal in voor minstens één regel.';

  @override
  String get purchReceiveLocationNeeded => 'Kies een bestemmingslocatie.';

  @override
  String purchReceiptBooked(String number) {
    return 'Goederenontvangst $number geboekt.';
  }

  @override
  String get purchOpenReceipt => 'Ontvangst openen';

  @override
  String get purchReceipts => 'Goederenontvangsten';

  @override
  String get purchReceivedDate => 'Ontvangen';

  @override
  String get purchOpenOrder => 'Inkooporder';

  @override
  String get tabGoodsReceipt => 'Goederenontvangst';

  @override
  String get setupTitle => 'Een nieuw bedrijf instellen';

  @override
  String get setupOffer => 'Een nieuw bedrijf instellen';

  @override
  String get setupOfferHint => 'Deze server heeft nog geen bedrijf.';

  @override
  String setupServer(String url) {
    return 'Server: $url';
  }

  @override
  String setupStepOf(int n, int total) {
    return 'Stap $n van $total';
  }

  @override
  String get setupStepCompany => 'Bedrijf';

  @override
  String get setupStepRegion => 'Land, valuta en taal';

  @override
  String get setupStepAdmin => 'Beheerder';

  @override
  String get setupStepToken => 'Installatietoken';

  @override
  String get setupStepReview => 'Controle';

  @override
  String get setupCompanyName => 'Bedrijfsnaam';

  @override
  String get setupLegalName => 'Juridische naam (optioneel)';

  @override
  String get setupVatNumber => 'Btw-nummer (optioneel)';

  @override
  String get setupCountry => 'Landcode (2 letters, bv. BE)';

  @override
  String get setupCurrency => 'Valuta (3 letters, bv. EUR)';

  @override
  String get setupLanguage => 'Standaardtaal';

  @override
  String get setupAdminEmail => 'E-mailadres van de beheerder';

  @override
  String get setupAdminName => 'Naam van de beheerder';

  @override
  String get setupToken => 'Installatietoken';

  @override
  String get setupTokenHelp => 'De waarde van BOOTSTRAP_TOKEN op de server.';

  @override
  String get setupErrName => 'Vul de bedrijfsnaam in.';

  @override
  String get setupErrVat => 'Een btw-nummer heeft 4 tot 20 letters en cijfers.';

  @override
  String get setupErrCountry => 'Vul een landcode van twee letters in.';

  @override
  String get setupErrCurrency => 'Vul een valutacode van drie letters in.';

  @override
  String get setupErrEmail => 'Vul een geldig e-mailadres in.';

  @override
  String get setupErrAdminName => 'Vul de naam van de beheerder in.';

  @override
  String get setupErrToken => 'Vul het installatietoken in.';

  @override
  String get setupNext => 'Volgende';

  @override
  String get setupBack => 'Terug';

  @override
  String get setupCreate => 'Bedrijf aanmaken';

  @override
  String get setupReviewHint =>
      'Controleer de gegevens. Op deze server kan maar één keer een bedrijf worden aangemaakt.';

  @override
  String get setupErr403 => 'Het installatietoken ontbreekt of is onjuist.';

  @override
  String get setupErr404 =>
      'Instellen is uitgeschakeld op deze server. Stel BOOTSTRAP_TOKEN in op de server en herstart die.';

  @override
  String get setupErr409 => 'Deze server heeft al een bedrijf.';

  @override
  String setupDone(String name) {
    return 'Bedrijf $name aangemaakt.';
  }

  @override
  String setupDoneDev(String email) {
    return 'Aanmelden als $email.';
  }

  @override
  String setupDoneOidc(String email) {
    return 'Meld u aan via uw identiteitsprovider met $email: dat account is de beheerder.';
  }

  @override
  String get setupToLogin => 'Naar aanmelden';

  @override
  String get setupAddOfferTitle => 'Deze server instellen?';

  @override
  String get setupAddOfferBody =>
      'Deze server heeft nog geen bedrijf. Nu een bedrijf instellen?';

  @override
  String get setupLater => 'Later';

  @override
  String get finMatchColumn => 'Match';

  @override
  String get finance => 'Financiën';

  @override
  String get finSupplierInvoices => 'Inkoopfacturen';

  @override
  String get finSettings => 'Instellingen';

  @override
  String get tabSupplierInvoice => 'Inkoopfactuur';

  @override
  String get finNewInvoice => 'Nieuwe inkoopfactuur';

  @override
  String get finNoInvoices => 'Geen inkoopfacturen gevonden.';

  @override
  String get finInvoiceNumber => 'Factuurnummer';

  @override
  String get finInternalNumber => 'Intern nummer';

  @override
  String get finInvoiceDate => 'Factuurdatum';

  @override
  String get finDueDate => 'Vervaldatum';

  @override
  String get finStatusDraft => 'concept';

  @override
  String get finStatusMatched => 'gematcht';

  @override
  String get finStatusDisputed => 'betwist';

  @override
  String get finStatusApproved => 'goedgekeurd';

  @override
  String get finStatusPaid => 'betaald';

  @override
  String get finMatchOk => 'in orde';

  @override
  String get finMatchNotReceived => 'niet ontvangen';

  @override
  String get finMatchOverInvoiced => 'te veel gefactureerd';

  @override
  String get finMatchPriceVariance => 'prijsafwijking';

  @override
  String get finMatchNoPoLine => 'geen orderregel';

  @override
  String get finOrderOptional => 'Inkooporder (optioneel)';

  @override
  String get finNoOrder => 'Geen inkooporder';

  @override
  String get finOrderPrefillHint =>
      'De regels worden ingevuld met de ontvangen, nog niet gefactureerde goederen.';

  @override
  String get finNumberRequired =>
      'Het factuurnummer is verplicht (maximaal 64 tekens).';

  @override
  String get finLineDescriptionRequired =>
      'Een vrije regel heeft een omschrijving nodig.';

  @override
  String get finVatInvalid =>
      'Het btw-tarief moet tussen 0 en 100 liggen, met maximaal 2 decimalen.';

  @override
  String get finOrdered => 'Besteld';

  @override
  String get finInvoiced => 'Gefactureerd';

  @override
  String get finOrderPrice => 'Orderprijs';

  @override
  String get finInvoicePrice => 'Factuurprijs';

  @override
  String get finVariance => 'Afwijking';

  @override
  String get finMatches =>
      'De factuur komt overeen met de order en de ontvangsten.';

  @override
  String get finNotMatches =>
      'De factuur komt niet overeen met de order en de ontvangsten.';

  @override
  String finTolerances(String qty, String price) {
    return 'Toleranties: hoeveelheid $qty %, prijs $price %';
  }

  @override
  String get finSubmitMatch => 'Match controleren';

  @override
  String get finApprove => 'Goedkeuren';

  @override
  String get finOverrideTitle => 'Goedkeuren ondanks afwijking';

  @override
  String get finOverrideHelp =>
      'De factuur komt niet overeen. Geef de reden om toch goed te keuren; die wordt bij de goedkeuring bewaard.';

  @override
  String get finOverrideReason => 'Reden voor afwijking';

  @override
  String get finReasonRequired => 'Een reden is verplicht.';

  @override
  String get finDispute => 'Betwisten';

  @override
  String get finDisputeReason => 'Reden van betwisting';

  @override
  String get finReopen => 'Heropenen';

  @override
  String get finMarkPaid => 'Markeren als betaald';

  @override
  String get finPaymentDate => 'Betaaldatum';

  @override
  String get finPaymentReference => 'Betalingskenmerk';

  @override
  String get finDeleteDraft => 'Concept verwijderen';

  @override
  String finDeleteConfirm(String number) {
    return 'Factuur $number verwijderen? Dit kan niet ongedaan worden gemaakt.';
  }

  @override
  String get finNetTotal => 'Netto';

  @override
  String get finGrossTotal => 'Totaal incl. btw';

  @override
  String get finDisputeReasonShown => 'Reden van betwisting';

  @override
  String get finOverrideShown => 'Reden voor afwijking';

  @override
  String get finPaidOn => 'Betaald op';

  @override
  String get finPurchaseOrder => 'Inkooporder';

  @override
  String get finQuantityTolerance => 'Hoeveelheidstolerantie (%)';

  @override
  String get finPriceTolerance => 'Prijstolerantie (%)';

  @override
  String get finToleranceInvalid => 'Geef een percentage tussen 0 en 100 op.';

  @override
  String get finSettingsSaved => 'Instellingen opgeslagen.';

  @override
  String get finSettingsHelp =>
      'Grootste toegestane verschil tussen order en factuur voordat een regel als afwijking telt.';

  @override
  String get finCreateInvoice => 'Inkoopfactuur aanmaken';

  @override
  String get userRoleFinance => 'Financiën';

  @override
  String get moduleFinance => 'Financiën';

  @override
  String get productionDivisionMembers => 'Leden';

  @override
  String get productionDivisionNoMembers => 'Geen leden';

  @override
  String get productionScopeMine => 'Mijn afdelingen';

  @override
  String get productionScopeAll => 'Alle afdelingen';

  @override
  String get productionScopeEmpty =>
      'Geen orders in uw afdelingen. Orders zonder afdeling zijn inbegrepen.';

  @override
  String get productionShowAllDivisions => 'Alle afdelingen tonen';

  @override
  String get productionYourDivisions => 'Uw afdelingen';

  @override
  String get setupErrInsecure =>
      'Het installatietoken wordt niet via een onversleutelde verbinding naar een andere computer gestuurd. Gebruik een https://-adres (gewone http mag alleen voor localhost).';

  @override
  String get setupUnavailable =>
      'Instellen is niet beschikbaar op deze server: er is al een bedrijf, of instellen is uitgeschakeld.';

  @override
  String get setupErrRedirect =>
      'De server stuurde de aanvraag door, dus het installatietoken is niet verder gestuurd. Controleer het serveradres (gebruik het definitieve https://-adres).';

  @override
  String get tutSuppliersTitle => 'Leveranciers';

  @override
  String get tutSuppliersSummary =>
      'Hoed: inkoper. Maak twee leveranciers en geef ze een prijslijst voor je componenten.';

  @override
  String get tutSuppliersNeedsTitle => 'Eerst hoofdstuk 1';

  @override
  String get tutSuppliersNeedsBody =>
      'Dit hoofdstuk heeft de vier producten uit hoofdstuk 1 nodig (TUT-MOTOR, TUT-FRAME, TUT-CTRL en TUT-CART) en vond ze niet. Ga terug naar de hoofdstukkaart en rond eerst hoofdstuk 1 af.';

  @override
  String get tutSuppliersOpenTitle => 'Zet de inkopershoed op';

  @override
  String get tutSuppliersOpenBody =>
      'Je componenten moeten ergens vandaan komen. Open Inkoop in het menu: de lijst Leveranciers is het eerste segment.';

  @override
  String get tutSuppliersSupplierATitle => 'De eerste leverancier';

  @override
  String get tutSuppliersSupplierABody =>
      'Maak een leverancier met code TUT-SUP-A en naam Voltaic Drives Ltd. Code en naam zijn de enige verplichte velden; betaaltermijn, btw-nummer en contactgegevens kunnen later.';

  @override
  String get tutSuppliersSupplierBTitle => 'Een tweede leverancier';

  @override
  String get tutSuppliersSupplierBBody =>
      'Een inkoper vergelijkt graag. Maak een tweede leverancier met code TUT-SUP-B en naam Ironbridge Frames.';

  @override
  String get tutSuppliersOpenATitle => 'Open de eerste leverancier';

  @override
  String get tutSuppliersOpenABody =>
      'Open Voltaic Drives Ltd uit de lijst. De prijslijst staat onderaan het leveranciersscherm.';

  @override
  String get tutSuppliersPriceMotorTitle => 'Een prijs voor de motor';

  @override
  String get tutSuppliersPriceMotorBody =>
      'Voeg TUT-MOTOR toe aan de prijslijst: stukprijs 120, levertijd 14 dagen, minimale bestelhoeveelheid 5. Inkooporders gebruiken deze waarden om hun regels voor te vullen.';

  @override
  String get tutSuppliersPriceMotorHint =>
      'Kies het product met het zoekveld in het dialoogvenster; typ TUT-MOTOR.';

  @override
  String get tutSuppliersPriceFrameTitle => 'Een prijs voor het frame';

  @override
  String get tutSuppliersPriceFrameBody =>
      'Hetzelfde voor TUT-FRAME: stukprijs 45, levertijd 10 dagen, minimale bestelhoeveelheid 5.';

  @override
  String get tutSuppliersPriceControllerTitle => 'Een prijs voor de controller';

  @override
  String get tutSuppliersPriceControllerBody =>
      'En TUT-CTRL: stukprijs 30, levertijd 7 dagen, minimale bestelhoeveelheid 5. Deze leverancier dekt nu alle drie de componenten.';

  @override
  String get tutSuppliersOpenBTitle => 'Open de tweede leverancier';

  @override
  String get tutSuppliersOpenBBody =>
      'Ga terug naar de lijst en open Ironbridge Frames.';

  @override
  String get tutSuppliersPriceMotorBTitle => 'Een concurrerende prijs';

  @override
  String get tutSuppliersPriceMotorBBody =>
      'Geef ook deze leverancier een prijs voor TUT-MOTOR: stukprijs 135, levertijd 5 dagen, minimale bestelhoeveelheid 1. Duurder maar sneller; precies zo\'n keuze helpt een prijslijst te maken.';

  @override
  String get tutSuppliersDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutSuppliersDoneBody =>
      'Een leverancier is een record met betaaltermijn en contactgegevens, en de prijslijst koppelt hem aan producten met prijs, levertijd en minimale bestelhoeveelheid. Volgende stap: de goederen bestellen.';

  @override
  String get tutBuyingTitle => 'Kopen en ontvangen';

  @override
  String get tutBuyingSummary =>
      'Hoeden: inkoper en goederenontvangst. Bestel de componenten, verstuur de order en ontvang de goederen in twee leveringen.';

  @override
  String get tutBuyingNeedsTitle => 'Eerst hoofdstuk 1 en 2';

  @override
  String get tutBuyingNeedsBody =>
      'Dit hoofdstuk heeft de producten uit hoofdstuk 1 en leverancier Voltaic Drives Ltd met prijslijst uit hoofdstuk 2 nodig, en vond de producten niet. Rond die hoofdstukken eerst af.';

  @override
  String get tutBuyingOpenTitle => 'De orderlijst';

  @override
  String get tutBuyingOpenBody =>
      'Open Inkoop. Naast Leveranciers staat een segment voor inkooporders; open dat.';

  @override
  String get tutBuyingOrderTitle => 'Bestel de componenten';

  @override
  String get tutBuyingOrderBody =>
      'Maak een inkooporder voor Voltaic Drives Ltd met drie regels: TUT-MOTOR, TUT-FRAME en TUT-CTRL, elk 30 stuks. De prijzen komen uit de prijslijst.';

  @override
  String get tutBuyingOrderHint =>
      'Kies eerst de leverancier: de regelprijzen worden ingevuld zodra de prijslijst geladen is. Gebruik Regel toevoegen voor de tweede en derde component.';

  @override
  String get tutBuyingOpenOrderTitle => 'Het orderscherm';

  @override
  String get tutBuyingOpenOrderBody =>
      'Open de order die je net maakte. Een inkooporder is eerst een concept; de knoppen bovenaan volgen zijn leven: goedkeuren, versturen, ontvangen.';

  @override
  String get tutBuyingApproveTitle => 'Keur de order goed';

  @override
  String get tutBuyingApproveBody =>
      'Goedkeuren is een apart recht, zodat een inkoper orders kan voorbereiden die een manager vrijgeeft. Als admin draag je beide hoeden: druk op Goedkeuren.';

  @override
  String get tutBuyingSendTitle => 'Verstuur naar de leverancier';

  @override
  String get tutBuyingSendBody =>
      'Druk op Verzenden. De order wordt als verstuurd gemarkeerd en de leverancier krijgt hem. In test- en tutorialomgevingen wordt uitgaande e-mail alleen naar bestanden op de server geschreven; er verlaat niets het gebouw.';

  @override
  String get tutBuyingReceivePartTitle => 'De eerste levering komt aan';

  @override
  String get tutBuyingReceivePartBody =>
      'Zet de hoed van goederenontvangst op. Druk op Goederen ontvangen, kies de magazijnlocatie MAIN en boek van elke component 10 stuks, minder dan besteld. De order wordt gedeeltelijk ontvangen.';

  @override
  String get tutBuyingReceivePartHint =>
      'Pas in het dialoogvenster de hoeveelheid van elke regel aan; de resterende hoeveelheid staat ernaast. Een leverbonnummer is optioneel.';

  @override
  String get tutBuyingReceiveRestTitle => 'De rest komt aan';

  @override
  String get tutBuyingReceiveRestBody =>
      'Ontvang de resterende 20 stuks van elke component op dezelfde manier. Is alles binnen, dan is de order volledig ontvangen; elke levering houdt haar eigen ontvangstbon.';

  @override
  String get tutBuyingStockTitle => 'Kijk naar de voorraad';

  @override
  String get tutBuyingStockBody =>
      'Open Voorraad. De 30 motoren, frames en controllers liggen in magazijn MAIN. Elke ontvangst maakte een voorraadbeweging, dus de hoeveelheid is altijd te herleiden.';

  @override
  String get tutBuyingDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutBuyingDoneBody =>
      'Een inkooporder gaat van concept naar goedgekeurd, verstuurd, ontvangen. Goederen mogen in meerdere leveringen komen en elke levering vult de voorraad aan. De factuur van de leverancier volgt.';

  @override
  String get tutInvoicesTitle => 'Facturen controleren';

  @override
  String get tutInvoicesSummary =>
      'Hoed: boekhouder. Registreer leveranciersfacturen, lees de driewegmatch, keur goed, betwist en betaal.';

  @override
  String get tutInvoicesNeedsTitle => 'Eerst hoofdstuk 3';

  @override
  String get tutInvoicesNeedsBody =>
      'Dit hoofdstuk heeft de volledig ontvangen inkooporder uit hoofdstuk 3 nodig en die is er (nog) niet. Rond eerst hoofdstuk 3 af.';

  @override
  String get tutInvoicesOpenOrderTitle => 'Terug naar de order';

  @override
  String get tutInvoicesOpenOrderBody =>
      'De factuur van de leverancier komt binnen. Open de inkooporder uit hoofdstuk 3 opnieuw: zodra er goederen ontvangen zijn, biedt hij een snelkoppeling om de factuur te registreren.';

  @override
  String get tutInvoicesCreateTitle => 'Registreer de factuur';

  @override
  String get tutInvoicesCreateBody =>
      'Druk op Inkoopfactuur aanmaken. Typ het eigen factuurnummer van de leverancier, bijvoorbeeld TUT-INV-001, en bewaar. De regels worden ingevuld vanuit wat besteld en ontvangen is, er valt niets te typen.';

  @override
  String get tutInvoicesCreateHint =>
      'Factuurdatum en vervaldatum staan standaard op vandaag en op de betaaltermijn van de leverancier.';

  @override
  String get tutInvoicesMatchTitle => 'De driewegmatch';

  @override
  String get tutInvoicesMatchBody =>
      'De banner vergelijkt drie documenten: wat besteld, wat ontvangen en wat gefactureerd is, regel voor regel. Groen betekent dat ze binnen de tolerantie overeenkomen; de tolerantie staat in de banner. Druk op Volgende als je gekeken hebt.';

  @override
  String get tutInvoicesApproveTitle => 'Keur de factuur goed';

  @override
  String get tutInvoicesApproveBody =>
      'De match is groen, dus druk op Goedkeuren. Een goedgekeurde factuur is klaar voor betaling.';

  @override
  String get tutInvoicesSecondTitle => 'Een verdachte factuur';

  @override
  String get tutInvoicesSecondBody =>
      'Nu komt een tweede factuur binnen van Voltaic Drives Ltd, deze keer zonder inkooporder: maak in Financiën een leveranciersfactuur voor die leverancier, nummer TUT-INV-002, laat de order leeg en voeg één regel toe met omschrijving Motoren, aantal 10, stukprijs 150.';

  @override
  String get tutInvoicesSecondHint =>
      'De echte motorprijs is 120 en deze regel heeft geen orderregel om mee te vergelijken. De app kan prijzen van een orderfactuur niet wijzigen, dus een vrije-tekstfactuur is hier de manier om een afwijking te zien.';

  @override
  String get tutInvoicesMismatchTitle => 'De match mislukt';

  @override
  String get tutInvoicesMismatchBody =>
      'De banner is oranje: een vrije-tekstregel heeft niets om mee te vergelijken en kan dus niet tegen een order of ontvangst gecontroleerd worden. De regel toont waarom. Druk op Volgende als je gekeken hebt.';

  @override
  String get tutInvoicesDisputeTitle => 'Betwist de factuur';

  @override
  String get tutInvoicesDisputeBody =>
      'Druk op Betwisten en geef een reden, bijvoorbeeld prijs komt niet overeen met de afspraak. Een betwiste factuur kan niet betaald worden tot ze heropend is. (Een goedkeurder kan een mislukte match ook goedkeuren met een afwijkingsreden, die op de factuur bewaard blijft.)';

  @override
  String get tutInvoicesTolerancesTitle => 'De toleranties';

  @override
  String get tutInvoicesTolerancesBody =>
      'Hoeveel een factuur mag afwijken is een instelling: open het segment Instellingen van Financiën om de hoeveelheids- en prijstolerantie in procenten te zien. Kijk en druk op Volgende; het wijzigen is aan jou.';

  @override
  String get tutInvoicesPayTitle => 'Betaal de goede factuur';

  @override
  String get tutInvoicesPayBody =>
      'Open de eerste leveranciersfactuur die je registreerde (die gematcht en goedgekeurd werd) en druk op Markeren als betaald. Voer een betalingsreferentie in zoals TUT-PAY-001. De app legt de betaling vast; de overschrijving zelf gebeurt elders.';

  @override
  String get tutInvoicesDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutInvoicesDoneBody =>
      'De driewegmatch vergelijkt order, ontvangst en factuur voordat er geld beweegt. Kloppende facturen worden goedgekeurd en betaald, twijfelachtige betwist. Volgende stap: de karretjes zelf bouwen.';

  @override
  String get tutManufacturingTitle => 'Produceren';

  @override
  String get tutManufacturingSummary =>
      'Hoeden: productiebeheerder en productiemedewerker. Richt een afdeling in en bouw vijf karretjes uit de componenten.';

  @override
  String get tutManufacturingNeedsTitle => 'Eerst hoofdstuk 1 tot 3';

  @override
  String get tutManufacturingNeedsBody =>
      'Dit hoofdstuk heeft het karretje met stuklijst (hoofdstuk 1) en componenten op voorraad (hoofdstuk 3) nodig en vond de producten niet. Rond die hoofdstukken eerst af.';

  @override
  String get tutManufacturingOpenDivisionsTitle => 'Afdelingen';

  @override
  String get tutManufacturingOpenDivisionsBody =>
      'Productiewerk is georganiseerd in afdelingen, bijvoorbeeld een assemblagelijn. Alleen een beheerder definieert ze. Open Productie en gebruik de tandwielknop rechtsboven om bij de afdelingen te komen.';

  @override
  String get tutManufacturingDivisionTitle => 'Maak een afdeling';

  @override
  String get tutManufacturingDivisionBody =>
      'Voeg een afdeling toe met code TUT-ASM en naam Tutorial assembly, en vink jezelf aan in de ledenlijst: leden zijn de werknemers van de afdeling.';

  @override
  String get tutManufacturingDivisionHint =>
      'Het dialoogvenster toont de gebruikers van het bedrijf; vink het label met je eigen naam aan.';

  @override
  String get tutManufacturingQueueTitle => 'De productiewachtrij';

  @override
  String get tutManufacturingQueueBody =>
      'Ga terug naar Productie. Kies bovenaan de wachtrij Mijn afdelingen: dat toont de orders van je afdelingen plus orders zonder afdeling, zodat niets onbeheerds verborgen blijft. Je bent lid van een afdeling, dus dit is voor jou de standaard; kies Alle afdelingen om alles te zien.';

  @override
  String get tutManufacturingReleaseTitle => 'Geef een productieorder vrij';

  @override
  String get tutManufacturingReleaseBody =>
      'Druk op Voor voorraad maken, kies TUT-CART met hoeveelheid 5 en geef vrij. De stuklijst wordt bevroren en de componenten worden gereserveerd. Normaal start productie vanuit een verkooporderregel; dat zie je in hoofdstuk 9.';

  @override
  String get tutManufacturingReleaseHint =>
      'Alleen geproduceerde producten met een actieve stuklijst kunnen vrijgegeven worden.';

  @override
  String get tutManufacturingAssignTitle => 'Wijs het toe aan de afdeling';

  @override
  String get tutManufacturingAssignBody =>
      'De nieuwe order staat open. Kies de afdeling Tutorial assembly in het veld Afdeling en druk op Opslaan, zodat de order in de wachtrij van die afdeling verschijnt.';

  @override
  String get tutManufacturingStartTitle => 'Start het werk';

  @override
  String get tutManufacturingStartBody =>
      'Zet de werknemershoed op en druk op Starten. De order gaat van vrijgegeven naar in uitvoering.';

  @override
  String get tutManufacturingCompleteTitle => 'Rond de order af';

  @override
  String get tutManufacturingCompleteBody =>
      'Druk op Afronden. Het dialoogvenster toont de uitvoerhoeveelheid (5) en de verbruikte componenten. Bevestig: de componenten verdwijnen uit de voorraad en vijf afgewerkte karretjes komen erin.';

  @override
  String get tutManufacturingCompleteHint =>
      'Laat de geplande waarden staan; het dialoogvenster laat je uitval of extra verbruik vastleggen als de werkelijkheid afwijkt.';

  @override
  String get tutManufacturingStockTitle => 'Controleer de voorraad';

  @override
  String get tutManufacturingStockBody =>
      'Open Voorraad: TUT-CART heeft nu 5 op voorraad en elke component is met 5 gedaald (25 over van elk). Productie is de schakel tussen inkoop en verkoop.';

  @override
  String get tutManufacturingDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutManufacturingDoneBody =>
      'Afdelingen groeperen productiemedewerkers; een productieorder bevriest de stuklijst, reserveert componenten, wordt gestart en voltooid en maakt van componenten eindproducten. Volgende stap: prijzen.';

  @override
  String get tutPricesTitle => 'Prijzen en zones';

  @override
  String get tutPricesSummary =>
      'Hoed: verkoopbeheerder. Maak een prijszone en geef het karretje een prijs in twee zones.';

  @override
  String get tutPricesNeedsTitle => 'Eerst hoofdstuk 1';

  @override
  String get tutPricesNeedsBody =>
      'Dit hoofdstuk heeft het karretje uit hoofdstuk 1 nodig en vond het niet. Rond eerst hoofdstuk 1 af.';

  @override
  String get tutPricesOpenAdminTitle => 'Open het beheer';

  @override
  String get tutPricesOpenAdminBody =>
      'Een prijs hangt af van de zone van de klant: een land of markt met een eigen prijslijst. Zones beheer je onder Beheer. Open Beheer en kies het segment Prijszones; het bedrijf heeft al zones Z1 tot Z5.';

  @override
  String get tutPricesZoneTitle => 'Maak een zone';

  @override
  String get tutPricesZoneBody =>
      'Voeg een prijszone toe met code TUT-EXPORT en naam Exportzone. Klanten krijgen later een zone, wanneer je er een aanmaakt.';

  @override
  String get tutPricesZoneHint =>
      'Kies eerst het segment Prijszones bovenaan de pagina Beheer.';

  @override
  String get tutPricesOpenCartTitle => 'Open het karretje';

  @override
  String get tutPricesOpenCartBody =>
      'Open het product TUT-CART uit de lijst Producten. Het eerste tabblad, Prijzen, bevat de prijzen per zone.';

  @override
  String get tutPricesPriceExportTitle => 'Een prijs in de nieuwe zone';

  @override
  String get tutPricesPriceExportBody =>
      'Druk op Nieuwe prijs, kies zone TUT-EXPORT, voer stukprijs 1450 (excl. btw) in en bewaar.';

  @override
  String get tutPricesPriceExportHint =>
      'De geldig-vanafdatum staat standaard op vandaag; een latere datum plant een prijswijziging.';

  @override
  String get tutPricesPriceHomeTitle => 'Een prijs in een andere zone';

  @override
  String get tutPricesPriceHomeBody =>
      'Voeg een tweede prijs voor het karretje toe in een van de bestaande zones, bijvoorbeeld Z1 voor 1200. Hetzelfde product kan nu verschillend kosten afhankelijk van de zone van de klant.';

  @override
  String get tutPricesDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutPricesDoneBody =>
      'Een prijszone groepeert klanten met dezelfde prijslijst en een product heeft één prijs per zone en datum. Offertes nemen de prijs van de zone van de klant. Volgende stap: een nieuwe klant neemt contact op.';

  @override
  String get tutCustomerTitle => 'Een nieuwe klant neemt contact op';

  @override
  String get tutCustomerSummary =>
      'Hoeden: verkoop en helpdesk. Een e-mail van een klant wordt een ticket; de afzender is nieuw, dus je vraagt bedrijfsgegevens en maakt de klant aan.';

  @override
  String get tutCustomerNeedsTitle => 'Eerst hoofdstuk 6';

  @override
  String get tutCustomerNeedsBody =>
      'Dit hoofdstuk heeft de prijszone TUT-EXPORT uit hoofdstuk 6 nodig (de nieuwe klant krijgt die) en vond ze niet. Rond eerst de vorige hoofdstukken af.';

  @override
  String get tutCustomerMail1Title => 'Er komt een e-mail binnen';

  @override
  String get tutCustomerMail1Body =>
      'Iemand die je niet kent vraagt een offerte voor je karretje. Een echte mailbox levert het bericht zelf af; hier speelt de knop hieronder de klant en geeft een kant-en-klare e-mail (van Maya Okafor, example.test) aan de helpdesk, precies zoals de mailimporter doet.';

  @override
  String get tutCustomerMail1Action => 'Klant-e-mail simuleren';

  @override
  String get tutCustomerOpenHelpdeskTitle => 'Het ticket';

  @override
  String get tutCustomerOpenHelpdeskBody =>
      'Elk binnenkomend bericht wordt een ticket. Open Helpdesk: het ticket van Maya Okafor staat in de lijst.';

  @override
  String get tutCustomerOpenTicketTitle => 'Open het ticket';

  @override
  String get tutCustomerOpenTicketBody =>
      'Open het ticket. Links staat het gesprek, rechts de eigenschappen. Er is nog geen klant gekoppeld, want niemand met dit adres bestaat in het systeem.';

  @override
  String get tutCustomerReplyTitle => 'Vraag bedrijfsgegevens';

  @override
  String get tutCustomerReplyBody =>
      'Antwoord Maya: bedank haar en vraag naar bedrijfsnaam, btw-nummer en adres, en druk op Verzenden. Het antwoord komt in de wachtrij van de mailworker. In test- en tutorialomgevingen wordt uitgaande mail alleen naar bestanden op de server geschreven, dus Maya ontvangt niets.';

  @override
  String get tutCustomerReplyHint =>
      'Zorg dat het tabblad Antwoord (niet Interne notitie) boven het berichtvak is gekozen.';

  @override
  String get tutCustomerMail2Title => 'De klant antwoordt';

  @override
  String get tutCustomerMail2Body =>
      'Gebruik de knop om het antwoord van Maya te spelen. Het is een antwoord op haar eerste bericht, dus het komt als nieuw bericht in hetzelfde ticket, met bedrijfsnaam, btw-nummer en adres.';

  @override
  String get tutCustomerMail2Action => 'Klant-e-mail simuleren';

  @override
  String get tutCustomerReadDetailsTitle => 'Lees de gegevens';

  @override
  String get tutCustomerReadDetailsBody =>
      'Ga terug naar het ticket (open het opnieuw als het nieuwe bericht nog niet getoond wordt) en lees het antwoord van Maya: bedrijf Brightwheel Logistics BV, btw-nummer BE0123456749, Voorbeeldlaan 12, 9000 Gent, België. Druk op Volgende als je het hebt.';

  @override
  String get tutCustomerCreateCustomerTitle => 'Maak de klant aan';

  @override
  String get tutCustomerCreateCustomerBody =>
      'Druk in de ticketeigenschappen op Nieuwe klant. Vul naam Brightwheel Logistics BV in, een code zoals TUT-CUST, btw-nummer, het adres, en kies de prijszone TUT-EXPORT. Het ticket wordt aan de nieuwe klant gekoppeld als je bewaart.';

  @override
  String get tutCustomerCreateCustomerHint =>
      'Straat Voorbeeldlaan 12, postcode 9000, plaats Gent, land BE. Taal en betaaltermijn mogen blijven zoals ze zijn.';

  @override
  String get tutCustomerLinkedTitle => 'Het ticket kent zijn klant';

  @override
  String get tutCustomerLinkedBody =>
      'Het ticket toont nu de klant en er verschijnen nieuwe knoppen: een lead maken of direct vanuit het ticket een offerte starten. Het volgende hoofdstuk maakt de offerte. Druk op Volgende.';

  @override
  String get tutCustomerDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutCustomerDoneBody =>
      'Binnenkomende mail wordt tickets, een antwoord vraagt de klant om wat ontbreekt, en vanuit het ticket kan een klant aangemaakt worden zodat alles gekoppeld blijft. Volgende stap: de offerte.';

  @override
  String get tutQuotationTitle => 'De offerte';

  @override
  String get tutQuotationSummary =>
      'Hoed: verkoper. Offreer 8 karretjes aan de nieuwe klant, vraag productie naar de timing en verstuur.';

  @override
  String get tutQuotationNeedsTitle => 'Eerst hoofdstuk 7';

  @override
  String get tutQuotationNeedsBody =>
      'Dit hoofdstuk heeft klant Brightwheel Logistics BV uit hoofdstuk 7 nodig en vond die niet. Rond eerst hoofdstuk 7 af.';

  @override
  String get tutQuotationOpenQuotationsTitle => 'Offertes';

  @override
  String get tutQuotationOpenQuotationsBody =>
      'Open Offertes in het menu. Deze lijst bevat elke offerte met nummer, klant en status.';

  @override
  String get tutQuotationCreateTitle => 'Maak de offerte';

  @override
  String get tutQuotationCreateBody =>
      'Druk op Nieuwe offerte, kies Brightwheel Logistics BV, voeg TUT-CART toe met aantal 8 en bewaar het concept. De stukprijs komt uit de prijszone van de klant, TUT-EXPORT, dus de 1450 die je in hoofdstuk 6 invoerde.';

  @override
  String get tutQuotationCreateHint =>
      'Gebruik het productzoekveld bij de regels; typ TUT-CART. Als de klant niet vooraf gekozen is, zoek op Brightwheel.';

  @override
  String get tutQuotationLeadTitle => 'Hoe lang duurt het?';

  @override
  String get tutQuotationLeadBody =>
      'De klant vroeg om een levertijd. Eerlijk gezegd: de app berekent nog geen levertijden automatisch en een offerte heeft geen leverdatumveld. Vraag het dus aan productie (zet die hoed op, kijk naar de productiewachtrij en de componenten op voorraad) en schrijf het antwoord in de notities van de offerte, bijvoorbeeld: levering ongeveer 3 weken na bestelling. Bewaar het concept.';

  @override
  String get tutQuotationLeadHint =>
      'Bij een order kun je productie een vraag als ticket sturen (dat zie je in hoofdstuk 9); offertes hebben die knop nog niet.';

  @override
  String get tutQuotationSendTitle => 'Verstuur de offerte';

  @override
  String get tutQuotationSendBody =>
      'Druk op Markeren als verzonden. Vanaf nu ligt de offerte vast: ze kan alleen nog aanvaard, afgewezen of herzien worden. (Deze knop verstuurt geen mail; je stuurt de pdf zelf of antwoordt in het ticket.)';

  @override
  String get tutQuotationPdfTitle => 'De pdf';

  @override
  String get tutQuotationPdfBody =>
      'De pdf-knop toont de offerte zoals de klant ze zou zien. Ze wordt op de server gemaakt met een zetprogramma; op een server zonder dat krijg je een foutmelding, die verder niets beïnvloedt. Kijk gerust en druk op Volgende.';

  @override
  String get tutQuotationPdfHint =>
      'Er breekt niets als de pdf mislukt: de offerte is al verstuurd.';

  @override
  String get tutQuotationDoneTitle => 'Wat je geleerd hebt';

  @override
  String get tutQuotationDoneBody =>
      'Een offerte neemt de prijs van de zone van de klant, draagt notities en ligt vast zodra ze verstuurd is. Levertijden blijven je eigen inschatting, samen met productie. Volgende stap: de klant wil een wijziging.';

  @override
  String get tutChangeTitle => 'Wijziging, order, productie';

  @override
  String get tutChangeSummary =>
      'Hoeden: verkoop en productie. Herzie de offerte, maak er een order van, bouw de karretjes en enkele extra voor voorraad.';

  @override
  String get tutChangeNeedsTitle => 'Eerst hoofdstuk 8';

  @override
  String get tutChangeNeedsBody =>
      'Dit hoofdstuk heeft de verstuurde offerte uit hoofdstuk 8 nodig en vond ze niet. Rond eerst hoofdstuk 8 af.';

  @override
  String get tutChangeMail3Title => 'De klant antwoordt opnieuw';

  @override
  String get tutChangeMail3Body =>
      'Maya is tevreden met de offerte maar wil 10 karretjes in plaats van 8. Gebruik de knop om haar e-mail te spelen; ze komt in hetzelfde ticket.';

  @override
  String get tutChangeMail3Action => 'Klant-e-mail simuleren';

  @override
  String get tutChangeOpenQuoteTitle => 'Open de verstuurde offerte';

  @override
  String get tutChangeOpenQuoteBody =>
      'Een verstuurde offerte ligt vast, dus een wijziging betekent een nieuwe revisie. Open de offerte uit hoofdstuk 8.';

  @override
  String get tutChangeReviseTitle => 'Maak een revisie';

  @override
  String get tutChangeReviseBody =>
      'Druk op Nieuwe revisie en kies Afgesproken prijzen behouden. De oude revisie wordt vervangen en een nieuw concept met hetzelfde nummer opent.';

  @override
  String get tutChangeReviseHint =>
      'Bijwerken naar actuele prijzen zou herprijzen met de prijslijst van vandaag; hier behoudt de klant de afgesproken prijs.';

  @override
  String get tutChangeEditTitle => 'Wijzig het aantal';

  @override
  String get tutChangeEditBody =>
      'Zet het aantal van TUT-CART op 10 en bewaar het concept.';

  @override
  String get tutChangeEditHint =>
      'De notities van de eerste revisie zijn gekopieerd; pas ze aan als de levertijd verandert.';

  @override
  String get tutChangeSendTitle => 'Verstuur de revisie';

  @override
  String get tutChangeSendBody =>
      'Markeer de nieuwe revisie als verzonden, zoals eerder.';

  @override
  String get tutChangeAcceptTitle => 'De klant gaat akkoord';

  @override
  String get tutChangeAcceptBody =>
      'Maya gaat akkoord met de nieuwe revisie: druk op Aanvaard om dat vast te leggen.';

  @override
  String get tutChangeConvertTitle => 'Maak er een verkooporder van';

  @override
  String get tutChangeConvertBody =>
      'Druk op Omzetten naar order. Uit de aanvaarde revisie ontstaat een conceptverkooporder die opent.';

  @override
  String get tutChangeConvertHint =>
      'Het dialoogvenster vraagt de eigen referentie van de klant; typ bijvoorbeeld TUT-PO-1 of laat het leeg.';

  @override
  String get tutChangeOpenOrderTitle => 'De verkooporder';

  @override
  String get tutChangeOpenOrderBody =>
      'Is de order niet vanzelf geopend, open hem dan via Orders. Hij heeft de 10 karretjes, de prijs en de klantreferentie. Orders gaan van concept naar verstuurd naar bevestigd.';

  @override
  String get tutChangeSendOrderTitle => 'Verstuur de orderbevestiging';

  @override
  String get tutChangeSendOrderBody =>
      'Druk op Orderbevestiging verzenden. De order wordt verstuurd: de klant kan hem nu bevestigen.';

  @override
  String get tutChangeSendOrderHint =>
      'Het bevestigingsdocument maken vraagt het zetprogramma van de server; ontbreekt dat, dan weigert de server deze stap en is een server met dat programma nodig om verder te gaan.';

  @override
  String get tutChangeConfirmTitle => 'Bevestig namens de klant';

  @override
  String get tutChangeConfirmBody =>
      'Maya zei al ja per e-mail, dus druk op Bevestigen namens de klant en voeg een notitie toe zoals per e-mail bevestigd. De order is nu bevestigd en kan naar productie.';

  @override
  String get tutChangeReleaseTitle => 'Vrij te geven';

  @override
  String get tutChangeReleaseBody =>
      'Zet de productiehoed op. Open Productie > Vrij te geven: de bevestigde orderregel met 10 karretjes wacht. Druk op Vrijgeven aan productie om de productieorder voor precies die regel te maken.';

  @override
  String get tutChangeStartTitle => 'Start de productie';

  @override
  String get tutChangeStartBody =>
      'Druk op Starten bij de nieuwe productieorder.';

  @override
  String get tutChangeCompleteTitle => 'Rond de productie af';

  @override
  String get tutChangeCompleteBody =>
      'Druk op Afronden en bevestig de 10 karretjes. De componenten worden verbruikt en de karretjes gaan naar de order.';

  @override
  String get tutChangeReadyTitle => 'Klaar voor verzending';

  @override
  String get tutChangeReadyBody =>
      'Open de order opnieuw: met alle regels geproduceerd is hij klaar voor verzending. Levering (picken, verzenden, de klant factureren) valt buiten deze tutorial. Druk op Volgende.';

  @override
  String get tutChangeStockTitle => 'Enkele extra voor voorraad';

  @override
  String get tutChangeStockBody =>
      'Productie loopt vaak vooruit op orders. Open Productie, druk op Voor voorraad maken en geef nog 4 karretjes TUT-CART vrij. Zonder order komen ze bij voltooiing gewoon op voorraad.';

  @override
  String get tutChangeStockHint =>
      'Je kunt die order starten en voltooien zoals in hoofdstuk 5, of hem vrijgegeven laten.';

  @override
  String get tutChangeDoneTitle => 'Goed gedaan: het hele verhaal';

  @override
  String get tutChangeDoneBody =>
      'Je ging van leveranciers naar inkoop, facturen, productie, prijzen, een ticket, een nieuwe klant, een herziene offerte, een order en productie voor de order en voor voorraad. Wat nu: leveringen en verzending, herstellingen, buitendienst en rapporten hebben elk hun eigen menu-item. Elk hoofdstuk kan opnieuw gespeeld worden vanuit de hoofdstukkaart; stappen die al klaar zijn worden overgeslagen.';

  @override
  String get tutInvoicesOpenSecondTitle => 'Open de verdachte factuur';

  @override
  String get tutInvoicesOpenSecondBody =>
      'Open factuur TUT-INV-002, die je net registreerde, vanuit de lijst in Financiën.';

  @override
  String tutActionFailed(String reason) {
    return 'Het gesimuleerde e-mailbericht kon niet verstuurd worden: $reason. Probeer het opnieuw.';
  }

  @override
  String get tutActionForbidden =>
      'Je mag geen e-mail in de helpdesk importeren (daarvoor is het schrijfrecht voor de helpdesk nodig). Vraag het aan een beheerder of meld je als beheerder aan en probeer opnieuw.';

  @override
  String workerDownBanner(String since) {
    return 'De achtergrondverwerking draait niet meer sinds $since: e-mail wordt niet verstuurd of opgehaald en SLA-overschrijdingen worden niet geëscaleerd.';
  }

  @override
  String get workerNeverSeenBanner =>
      'De achtergrondverwerking heeft nog nooit gedraaid: e-mail wordt niet verstuurd of opgehaald en SLA-overschrijdingen worden niet geëscaleerd.';

  @override
  String get workerBannerSemantics => 'Achtergrondverwerking';
}
