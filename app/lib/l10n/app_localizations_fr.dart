// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get accepted => 'Acceptée';

  @override
  String get accessToken => 'Jeton d\'accès';

  @override
  String get account => 'Compte';

  @override
  String get action => 'Action';

  @override
  String get actionAddTag => 'Ajouter une étiquette';

  @override
  String get actionSetCategory => 'Définir la catégorie';

  @override
  String get actionSetInternal => 'Marquer comme interne';

  @override
  String get actionSetOwner => 'Définir le responsable';

  @override
  String get actionSetPriority => 'Définir la priorité';

  @override
  String get actionSetTeam => 'Définir l\'équipe';

  @override
  String get actions => 'Actions';

  @override
  String get activate => 'Activer';

  @override
  String get active => 'Actif';

  @override
  String activeSince(String date) {
    return 'Active depuis le $date. Les modifications passent par une nouvelle révision.';
  }

  @override
  String get add => 'Ajouter';

  @override
  String get addAction => 'Ajouter une action';

  @override
  String get addClosure => 'Ajouter une fermeture';

  @override
  String get addComponent => 'Ajouter un composant';

  @override
  String get addComponentBySerial =>
      'Ajouter un composant par numéro de série (en stock)';

  @override
  String get addEquipment => 'Ajouter une installation';

  @override
  String get addMember => 'Ajouter un membre';

  @override
  String get addNote => 'Ajouter la note';

  @override
  String get addNoteHint => 'Ajouter une note interne';

  @override
  String get addPart => 'Ajouter une pièce';

  @override
  String get addPhone => 'Ajouter un numéro';

  @override
  String get addPhoto => 'Ajouter une photo';

  @override
  String get addProduct => 'Ajouter un produit';

  @override
  String get addRebate => 'Ajouter une remise';

  @override
  String get addTag => 'Ajouter une étiquette';

  @override
  String get addTask => 'Ajouter une tâche';

  @override
  String addedBy(String date, String name) {
    return 'ajouté le $date par $name';
  }

  @override
  String get addressForm => 'Forme d\'adresse';

  @override
  String get addressFormal => 'Formel (vous)';

  @override
  String get addressInformal => 'Informel (tu)';

  @override
  String get addVisit => 'Ajouter une visite';

  @override
  String get agreed => 'Convenu';

  @override
  String get all => 'Tous';

  @override
  String get allCategories => 'Toutes les catégories';

  @override
  String get allOwners => 'Tous les responsables';

  @override
  String get allProducts => 'Tous les produits';

  @override
  String get allStatuses => 'Tous les statuts';

  @override
  String get allTags => 'Toutes les étiquettes';

  @override
  String get allTeams => 'Toutes les équipes';

  @override
  String get always => 'toujours';

  @override
  String andMore(int count) {
    return '… et $count de plus';
  }

  @override
  String get announceRepair => 'Annoncer une réparation';

  @override
  String get announcedNotReceived => 'Annoncée, pas encore reçue';

  @override
  String answerFallback(String ticketLanguage, String usedLanguage) {
    return 'Pas encore de texte en $ticketLanguage : le texte en $usedLanguage a été utilisé. Traduisez-le avant l\'envoi.';
  }

  @override
  String get anyValue => 'Tous';

  @override
  String get appLanguage => 'Langue';

  @override
  String get appTitle => 'TradoCraft';

  @override
  String get apply => 'Appliquer';

  @override
  String get assignTo => 'Assigner à';

  @override
  String get attachFile => 'Joindre un fichier';

  @override
  String get attachments => 'Pièces jointes';

  @override
  String get attachmentsHelp =>
      'Images (JPEG, PNG, WebP) et PDF, jusqu\'à 12 Mo';

  @override
  String get automatic => 'Automatique';

  @override
  String get automationHelp =>
      'Les règles s\'exécutent dans cet ordre quand un ticket est créé, modifié ou qu\'un client répond. Une règle s\'applique si toutes ses conditions sont remplies. Les règles modifient les tickets ; elles n\'envoient pas d\'e-mail.';

  @override
  String get automationRules => 'Règles d\'automatisation';

  @override
  String get autoRenew => 'Renouveler automatiquement';

  @override
  String get backIntoWork => 'Remettre en cours';

  @override
  String get backToCurrentRevision => 'Retour à la révision actuelle';

  @override
  String get backlogByOwner => 'Tickets ouverts par responsable';

  @override
  String get backlogByPriority => 'Tickets ouverts par priorité';

  @override
  String get backlogByStatus => 'Tickets ouverts par statut';

  @override
  String get backlogByTeam => 'Tickets ouverts par équipe';

  @override
  String get basisBusiness => 'heures ouvrables';

  @override
  String get basisElapsed => 'temps écoulé';

  @override
  String get billOfMaterials => 'Nomenclature';

  @override
  String get billable => 'Facturable';

  @override
  String get bomActive => 'active';

  @override
  String get bomObsolete => 'obsolète';

  @override
  String get bomRev => 'Rév. nomencl.';

  @override
  String get bomRevision => 'Révision de nomenclature';

  @override
  String get breached => 'Dépassés';

  @override
  String get breachesByTeam => 'Dépassements du SLA par équipe';

  @override
  String get builtInto => 'Intégré dans';

  @override
  String get bulkKeepsQuotes =>
      'Les offres antérieures à cette date gardent les prix actuels';

  @override
  String get bulkPriceChange => 'Modification de prix groupée';

  @override
  String get businessHours => 'Heures ouvrables';

  @override
  String get businessHoursEnabled => 'Compter uniquement les heures ouvrables';

  @override
  String get businessHoursHelp =>
      'Les délais de service ne comptent que les heures ci-dessous, les jours non fériés. Désactivé, ils courent 24 h sur 24.';

  @override
  String get businessHoursInvalidTime =>
      'Saisissez les heures au format HH:MM.';

  @override
  String get businessHoursRecompute =>
      'L\'enregistrement recalcule les échéances de tous les tickets ouverts.';

  @override
  String get businessHoursSaved =>
      'Enregistré. Les tickets ouverts ont été recalculés.';

  @override
  String get byStage => 'selon l\'étape';

  @override
  String get callIncoming => 'Appel entrant';

  @override
  String get callLogged => 'Appel enregistré';

  @override
  String get callMinutes => 'Durée (minutes)';

  @override
  String get callOutgoing => 'Appel sortant';

  @override
  String get callSummary => 'Sujet de l\'appel';

  @override
  String callWith(String name) {
    return 'Appel avec $name';
  }

  @override
  String get canStillKeep => 'Vous pouvez toujours garder les prix convenus.';

  @override
  String get cancel => 'Annuler';

  @override
  String get cancelJob => 'Annuler';

  @override
  String get cancelOrder => 'Annuler la commande';

  @override
  String get cancelReasonLabel => 'Motif de l\'annulation';

  @override
  String get cancelRepair => 'Annuler la réparation';

  @override
  String get cancelled => 'annulée';

  @override
  String cancelledReason(String reason) {
    return 'Annulée : $reason';
  }

  @override
  String get cannotConfirmNewer =>
      'Une révision plus récente de cette commande est en préparation. Vous pourrez la confirmer dès qu\'elle vous aura été envoyée.';

  @override
  String get cannotConfirmOther => 'Cette commande ne peut pas être confirmée.';

  @override
  String get captureSignature => 'Recueillir la signature';

  @override
  String get category => 'Catégorie';

  @override
  String get categoryComplaint => 'réclamation';

  @override
  String get categoryLead => 'prospect (nouvelle demande)';

  @override
  String get categoryOrderConfirmation => 'confirmation de commande';

  @override
  String get categoryOther => 'autre';

  @override
  String get categoryProductionQuestion => 'question de la production';

  @override
  String get categoryQuestion => 'question';

  @override
  String get categoryQuoteChange => 'modification d\'offre';

  @override
  String get categoryService => 'service / réparation';

  @override
  String get cc => 'Cc';

  @override
  String get change => 'Modification';

  @override
  String get changePriority => 'Modifier la priorité';

  @override
  String get channel => 'Canal';

  @override
  String get channelEmail => 'E-mail';

  @override
  String get channelInternal => 'Question interne';

  @override
  String get channelManual => 'Saisi à la main';

  @override
  String get channelPhone => 'Téléphone';

  @override
  String get channelPortal => 'Portail';

  @override
  String get checklistOnePerLine => 'Liste de contrôle (une tâche par ligne)';

  @override
  String get chooseCustomerAndLine =>
      'Choisissez un client et ajoutez au moins une ligne valide.';

  @override
  String get choosePhoto => 'Choisir dans la galerie';

  @override
  String get chooseRebateTarget =>
      'Choisissez un produit ou une famille et saisissez un pourcentage.';

  @override
  String get chooseZonePrice => 'Choisissez une zone et saisissez un prix.';

  @override
  String get city => 'Localité';

  @override
  String get clear => 'Effacer';

  @override
  String get close => 'Fermer';

  @override
  String get closedLabel => 'clôturés';

  @override
  String get closes => 'Ferme';

  @override
  String get closureKindCollectiveLeave => 'Congé collectif';

  @override
  String get closureKindHoliday => 'Jour férié';

  @override
  String get closureKindInventory => 'Inventaire';

  @override
  String get closureKindLabel => 'Motif';

  @override
  String get closureKindOther => 'Autre';

  @override
  String get closureKindWorks => 'Travaux';

  @override
  String get closurePolicyBlock => 'Non autorisé';

  @override
  String get closurePolicyBlockHelp =>
      'Une livraison ne peut pas être planifiée un jour de fermeture ; choisissez une autre date.';

  @override
  String get closurePolicyOverride => 'Demande un motif et le droit de déroger';

  @override
  String get closurePolicyOverrideHelp =>
      'Seuls les utilisateurs autorisés à déroger peuvent planifier un jour de fermeture, avec un motif.';

  @override
  String get closurePolicyTitle =>
      'Lorsqu\'une livraison est planifiée un jour où le client est fermé';

  @override
  String get closurePolicyWarn => 'Avertir seulement';

  @override
  String get closurePolicyWarnHelp =>
      'La date est enregistrée et la fermeture est affichée comme avertissement.';

  @override
  String get closures => 'Jours de fermeture';

  @override
  String get closuresShowPast => 'Afficher les fermetures passées';

  @override
  String get code => 'Code';

  @override
  String get codeNameRequired => 'Le code et le nom sont obligatoires.';

  @override
  String get codeNameVatRequired =>
      'Le code, le nom et le taux de TVA sont obligatoires.';

  @override
  String get completeJob => 'Terminer';

  @override
  String get completionNotes => 'Ce qui a été fait (et ce qui reste ouvert)';

  @override
  String get component => 'Composant';

  @override
  String get componentHistory => 'Historique des composants';

  @override
  String componentSince(String product, String date) {
    return '$product · depuis le $date';
  }

  @override
  String get componentsAsBuilt => 'Composants (tels que construits)';

  @override
  String get confirm => 'confirmer';

  @override
  String get confirmOnBehalf => 'Confirmer au nom du client';

  @override
  String get confirmOnBehalfHelp =>
      'Enregistrez que le client a confirmé cette révision, par exemple par téléphone ou par e-mail.';

  @override
  String get confirmOrder => 'Confirmer la commande';

  @override
  String get confirmOrderHelp =>
      'En confirmant, vous acceptez cette commande telle qu\'affichée.';

  @override
  String get confirmation => 'Confirmation';

  @override
  String get confirmationDate => 'Confirmée le';

  @override
  String get confirmed => 'confirmée';

  @override
  String get confirmedRevision => 'Révision confirmée';

  @override
  String get confirmedVia => 'Confirmée via';

  @override
  String get confirmedViaPortal => 'portail client';

  @override
  String get confirmedViaStaff => 'collaborateur, au nom du client';

  @override
  String conflictsOnDate(int count) {
    return '$count ont déjà un prix à cette date';
  }

  @override
  String get contactName => 'Nom du contact';

  @override
  String get contactPerson => 'Personne de contact';

  @override
  String get contacts => 'Contacts';

  @override
  String get contractEnded => 'Terminé';

  @override
  String get contractJobs => 'Interventions de ce contrat';

  @override
  String contractLabel(String number) {
    return 'Contrat $number';
  }

  @override
  String contractOpenJobs(String count) {
    return '$count interventions ouvertes';
  }

  @override
  String get contracts => 'Contrats';

  @override
  String get contractSuspended => 'Suspendu';

  @override
  String get convertHelp =>
      'Le client souhaite des modifications ? Créez d\'abord une nouvelle révision de l\'offre, liez-la ici, puis convertissez.';

  @override
  String get convertToOrder => 'Convertir en commande';

  @override
  String get countAddLine => 'Ajouter du stock non listé';

  @override
  String get countCancel => 'Annuler l\'inventaire';

  @override
  String get countCounted => 'Compté';

  @override
  String get countDifference => 'Écart';

  @override
  String get countExpected => 'Attendu';

  @override
  String get countInvalidQuantity =>
      'Une quantité comptée n\'est pas un nombre.';

  @override
  String countMovedDuring(int count) {
    return '$count ligne(s) ont eu des mouvements pendant le comptage ; la quantité comptée les a remplacés.';
  }

  @override
  String get countNew => 'Nouvel inventaire';

  @override
  String countOf(int count, int total) {
    return '$count sur $total';
  }

  @override
  String get countOneProduct => 'Un seul produit (facultatif)';

  @override
  String get countOverwriteWarning =>
      'Les mouvements effectués pendant le comptage sont écrasés : à la comptabilisation, la quantité comptée devient le stock.';

  @override
  String get countPost => 'Comptabiliser l\'inventaire';

  @override
  String get countPostConfirm =>
      'Les écarts sont comptabilisés comme corrections de stock. Les lignes sans quantité comptée restent inchangées.';

  @override
  String get countProgress => 'Compté';

  @override
  String get countStart => 'Démarrer l\'inventaire';

  @override
  String get countStatusCounting => 'En cours';

  @override
  String get countStatusPosted => 'Comptabilisé';

  @override
  String countStockAtPost(String quantity) {
    return 'Stock à la comptabilisation : $quantity';
  }

  @override
  String get countWarehouseRequired => 'Choisissez un entrepôt.';

  @override
  String get countWholeWarehouse => 'Tout l\'entrepôt';

  @override
  String get countedBy => 'Démarré par';

  @override
  String get country => 'Pays';

  @override
  String get create => 'Créer';

  @override
  String get createLead => 'Créer une opportunité';

  @override
  String get createRepair => 'Créer une réparation';

  @override
  String get created => 'créés';

  @override
  String get csatAlready => 'Cette enquête a déjà reçu une réponse.';

  @override
  String get csatAverage => 'Satisfaction client';

  @override
  String get csatBad => 'Pas satisfait';

  @override
  String get csatComment => 'Commentaire (facultatif)';

  @override
  String get csatEnabled =>
      'Envoyer une enquête de satisfaction à la clôture d\'un ticket';

  @override
  String get csatExpired => 'Ce lien a expiré.';

  @override
  String get csatGood => 'Satisfait';

  @override
  String get csatNone => 'Pas encore d\'évaluation';

  @override
  String csatQuestion(String number) {
    return 'Êtes-vous satisfait du traitement du ticket $number ?';
  }

  @override
  String csatResponses(int count) {
    return '$count réponses';
  }

  @override
  String get csatThanks => 'Merci pour votre avis !';

  @override
  String get csatTitle => 'Satisfaction client';

  @override
  String get csvCopied => 'CSV copié dans le presse-papiers';

  @override
  String get current => 'Actuel';

  @override
  String get customer => 'Client';

  @override
  String get customerDeclinedToSign => 'Le client a refusé de signer';

  @override
  String get customerEquipment => 'Installations du client';

  @override
  String get customerLanguage => 'Langue du client';

  @override
  String customerMainNumber(String name) {
    return 'Numéro principal de $name';
  }

  @override
  String customerNamed(String name) {
    return 'Client : $name';
  }

  @override
  String get customerOptional => 'Client (facultatif)';

  @override
  String get customerReference => 'Référence client';

  @override
  String get customers => 'Clients';

  @override
  String get customerSignature => 'Signature du client';

  @override
  String get date => 'Date';

  @override
  String declinedToSignWithReason(String reason) {
    return 'A refusé de signer : $reason';
  }

  @override
  String get defaultTeam => 'Équipe par défaut pour les nouveaux tickets';

  @override
  String get deleteRuleConfirm =>
      'Supprimer cette règle ? Les tickets qu\'elle a modifiés gardent leurs modifications.';

  @override
  String get deliveries => 'Livraisons';

  @override
  String get deliveryBlocked =>
      'Livrer un jour de fermeture n\'est pas autorisé. Choisissez une autre date.';

  @override
  String get deliveryCancel => 'Annuler la livraison';

  @override
  String get deliveryCancelReason => 'Motif de l\'annulation';

  @override
  String get deliveryChooseSerial => 'Choisir le n° de série';

  @override
  String deliveryClosedWarning(String from, String to, String next) {
    return 'Le client est fermé du $from au $to. Prochain jour d\'ouverture : $next.';
  }

  @override
  String get deliveryFailed => 'non envoyé';

  @override
  String get deliveryLocation => 'Emplacement';

  @override
  String get deliveryLot => 'Lot';

  @override
  String get deliveryNew => 'Nouvelle livraison';

  @override
  String get deliveryNoDate => 'pas de date';

  @override
  String get deliveryNoLines =>
      'Rien à livrer pour l\'instant : réservez d\'abord du stock pour la commande.';

  @override
  String get deliveryOnClosure => 'pendant une fermeture';

  @override
  String get deliveryOverrideNeedsRight =>
      'Livrer un jour de fermeture demande un motif et le droit de déroger.';

  @override
  String get deliveryOverrideReason => 'Motif de livrer un jour de fermeture';

  @override
  String get deliveryPicking => 'Liste de préparation';

  @override
  String get deliveryPlannedDate => 'Date prévue';

  @override
  String get deliveryQueued => 'en attente d\'envoi';

  @override
  String get deliverySent => 'envoyé';

  @override
  String get deliverySerial => 'N° de série';

  @override
  String get deliverySettingsTitle => 'Paramètres de livraison';

  @override
  String get deliveryShip => 'Expédier';

  @override
  String get deliveryShipTo => 'Adresse de livraison';

  @override
  String get deliveryShippedSnack => 'Livraison expédiée';

  @override
  String get deliveryStatusPlanned => 'planifiée';

  @override
  String get deliveryStatusShipped => 'expédiée';

  @override
  String deliveryUseDay(String date) {
    return 'Choisir le $date';
  }

  @override
  String get department => 'Département';

  @override
  String get departmentCode => 'Code';

  @override
  String get departmentMembers => 'Collègues de ce département';

  @override
  String get departments => 'Départements';

  @override
  String get departmentsHelp =>
      'Les réparations sont transmises à ces départements. Seuls les collègues d\'un département peuvent traiter ses réparations.';

  @override
  String get description => 'Description';

  @override
  String get devModeHelp => 'Le serveur doit tourner avec AUTH_MODE=dev';

  @override
  String get developmentUser => 'Utilisateur de développement';

  @override
  String get deviceLanguage => 'Langue de l\'appareil';

  @override
  String get difference => 'Différence';

  @override
  String get dismiss => 'Rejeter';

  @override
  String get dismissRequest => 'Rejeter la demande';

  @override
  String get draftSaved => 'Brouillon enregistré';

  @override
  String get dryRun => 'Tester sur un ticket';

  @override
  String get dryRunHelp =>
      'Montre quelles règles s\'appliqueraient à un ticket et ce qu\'elles modifieraient. Rien n\'est modifié.';

  @override
  String get dryRunRun => 'Lancer le test';

  @override
  String get drawSignatureFirst => 'Dessinez d\'abord une signature';

  @override
  String dueOnDate(String date) {
    return 'À faire le $date';
  }

  @override
  String get edit => 'Modifier';

  @override
  String get editClosure => 'Modifier la fermeture';

  @override
  String get editContact => 'Modifier le contact';

  @override
  String get editDepartment => 'Modifier le département';

  @override
  String get editJob => 'Modifier l\'intervention';

  @override
  String get email => 'E-mail';

  @override
  String get emailAddresses => 'Adresses e-mail (la première est principale)';

  @override
  String get endContract => 'Terminer le contrat';

  @override
  String get endDate => 'Date de fin';

  @override
  String get enterChange =>
      'Saisissez la modification, p. ex. 4,5 pour +4,5 %.';

  @override
  String enterValidNumbersLine(int line) {
    return 'Ligne $line : saisissez des nombres valides.';
  }

  @override
  String get equipment => 'Installation';

  @override
  String get estimatedMinutes => 'Minutes estimées';

  @override
  String get expectedClose => 'Clôture prévue';

  @override
  String expectedCloseDate(String date) {
    return 'Clôture prévue le $date';
  }

  @override
  String get expectedValue => 'Valeur attendue';

  @override
  String get expectedValueEur => 'Valeur attendue (€)';

  @override
  String get expectedValueOptional => 'Valeur attendue (facultatif)';

  @override
  String get explode => 'Éclater';

  @override
  String get exportCsv => 'Copier en CSV';

  @override
  String get families => 'Familles';

  @override
  String get family => 'Famille';

  @override
  String familyNamed(String code) {
    return 'Famille $code';
  }

  @override
  String get faultDescription => 'Quel est le problème';

  @override
  String get firstDueDate => 'Première échéance';

  @override
  String get firstName => 'Prénom';

  @override
  String get firstResponseMinutes => 'Première réponse (min)';

  @override
  String get firstResponseTime => 'Première réponse';

  @override
  String get from => 'À partir du';

  @override
  String get fromYou => 'Vous';

  @override
  String generalRebateInfo(String percent) {
    return 'Remise générale sur tous les produits : $percent % (les produits à prix net ne sont jamais remisés).';
  }

  @override
  String get generalRebatePercent => 'Remise générale %';

  @override
  String greetingPreview(String greeting) {
    return 'Salutation : $greeting';
  }

  @override
  String get helpdesk => 'Service client';

  @override
  String get helpdeskReports => 'Rapports';

  @override
  String get helpdeskSettings => 'Paramètres du helpdesk';

  @override
  String get history => 'Historique';

  @override
  String get holidayDate => 'Date';

  @override
  String get holidayInvalid => 'Saisissez une date (AAAA-MM-JJ) et un nom.';

  @override
  String get holidays => 'Jours fériés';

  @override
  String get holidaysHelp => 'Jours où le helpdesk est fermé.';

  @override
  String get calendarFor => 'Calendrier de';

  @override
  String get calendarCompanyWide => 'Toute l\'entreprise';

  @override
  String get calendarInherited =>
      'Cette équipe n\'a pas de calendrier propre et utilise celui de l\'entreprise. Enregistrer en crée un pour l\'équipe.';

  @override
  String get calendarHolidaysInherited =>
      'Les jours fériés de l\'entreprise s\'appliquent aussi à cette équipe. Les jours fériés ajoutés ici sont propres à l\'équipe.';

  @override
  String get calendarUseCompany => 'Utiliser le calendrier de l\'entreprise';

  @override
  String get calendarRemoved =>
      'L\'équipe utilise de nouveau le calendrier de l\'entreprise.';

  @override
  String get basisMixed => 'heures ouvrables ou temps écoulé, selon l\'équipe';

  @override
  String get inactive => 'inactif';

  @override
  String get inactiveContact => 'N\'est plus actif (parti)';

  @override
  String indicativeLine(String description) {
    return '$description (indicatif, à confirmer)';
  }

  @override
  String indicativeToConfirm(int count) {
    return '$count prix indicatif(s) à confirmer avant l\'envoi de l\'offre : saisissez le prix convenu dans le champ prix catalogue.';
  }

  @override
  String get insertPreparedAnswer => 'Insérer une réponse type';

  @override
  String get instructions => 'Instructions';

  @override
  String get internalNote => 'Note interne';

  @override
  String internalQuestionHelp(String language) {
    return 'Question interne. Posez la question au client en $language par une réponse, puis notez la réponse pour votre collègue en note interne.';
  }

  @override
  String get internalTicket => 'Ticket interne';

  @override
  String get internalTicketHelp =>
      'Une question entre collègues ; rien n\'est envoyé au client.';

  @override
  String get interval => 'Intervalle';

  @override
  String get jobCancelled => 'Annulée';

  @override
  String get jobCompleted => 'Terminée';

  @override
  String jobCount(String count) {
    return '$count interventions';
  }

  @override
  String jobCreatedOnDate(String date) {
    return 'intervention créée le $date';
  }

  @override
  String get jobInProgress => 'En cours';

  @override
  String get jobKindInspection => 'Inspection';

  @override
  String get jobKindInstallation => 'Installation';

  @override
  String get jobKindMaintenance => 'Maintenance';

  @override
  String get jobKindOther => 'Autre';

  @override
  String get jobKindRepair => 'Réparation';

  @override
  String get jobName => 'Titre';

  @override
  String get jobPlanned => 'Planifiée';

  @override
  String get jobTitle => 'Fonction';

  @override
  String get jobs => 'Interventions';

  @override
  String get keepAgreedPrices => 'Garder les prix convenus';

  @override
  String get language => 'Langue';

  @override
  String languageSameAsCustomer(String language) {
    return 'Comme l\'entreprise ($language)';
  }

  @override
  String lastDays(int days) {
    return '$days derniers jours';
  }

  @override
  String get lastName => 'Nom';

  @override
  String get leadCreated => 'Opportunité créée';

  @override
  String get leadDays => 'Créer l\'intervention (jours avant)';

  @override
  String get lineDiscount => 'Rem. suppl. ±';

  @override
  String get listPrice => 'Prix catalogue';

  @override
  String get loadMore => 'Charger plus';

  @override
  String get logCall => 'Enregistrer un appel';

  @override
  String get logTime => 'Enregistrer du temps';

  @override
  String get logWork => 'Enregistrer le travail';

  @override
  String get loginLinkInvalid =>
      'Ce lien a expiré ou a déjà été utilisé. Demandez-en un nouveau.';

  @override
  String get loginLinkSent =>
      'Si cette adresse peut utiliser le portail, un lien de connexion vous a été envoyé. Vérifiez votre boîte de réception.';

  @override
  String get lookUp => 'Rechercher';

  @override
  String get lost => 'Perdue';

  @override
  String get lostReason => 'Motif de perte';

  @override
  String get markAsLost => 'Marquer comme perdue';

  @override
  String get markAsSent => 'Marquer comme envoyée';

  @override
  String get markCompleted => 'Marquer comme terminée';

  @override
  String get markReceived => 'Marquer comme reçue';

  @override
  String get markShipped => 'Marquer comme renvoyée';

  @override
  String get markWaitingCustomer => 'En attente du client';

  @override
  String get markWaitingParts => 'En attente de pièces';

  @override
  String get materialRequirements => 'Besoins en matières (révision active)';

  @override
  String get mergeAction => 'Fusionner';

  @override
  String get mergeHelp =>
      'Tous les messages, fichiers, étiquettes et temps enregistrés passent au ticket choisi du même client. Ce ticket est fermé. Cette action est irréversible.';

  @override
  String get mergeNoCandidates => 'Aucun autre ticket ouvert de ce client.';

  @override
  String get mergeTicket => 'Fusionner avec un autre ticket…';

  @override
  String mergedInto(String number) {
    return 'Fusionné avec $number';
  }

  @override
  String get message => 'Message';

  @override
  String get messageSent => 'Message envoyé';

  @override
  String get minutes => 'Minutes';

  @override
  String minutesShort(String minutes) {
    return '$minutes min';
  }

  @override
  String get moduleDelivery => 'Livraison';

  @override
  String get moduleProduction => 'Production';

  @override
  String get moveDown => 'Descendre';

  @override
  String get moveUp => 'Monter';

  @override
  String get months => 'Mois';

  @override
  String get myJobs => 'Mes interventions';

  @override
  String get myOrders => 'Mes commandes';

  @override
  String get myProfile => 'Mes données';

  @override
  String get myRepairs => 'Mes réparations';

  @override
  String get myTickets => 'Mes tickets';

  @override
  String get name => 'Nom';

  @override
  String get navigate => 'Naviguer';

  @override
  String get netPrice => 'Prix net';

  @override
  String get newAnswer => 'Nouvelle réponse';

  @override
  String get newContact => 'Nouveau contact';

  @override
  String get newContract => 'Nouveau contrat';

  @override
  String get newCustomer => 'Nouveau client';

  @override
  String get newDepartment => 'Nouveau département';

  @override
  String get newFamily => 'Nouvelle famille';

  @override
  String get newItem => 'Nouveau';

  @override
  String get newJob => 'Nouvelle intervention';

  @override
  String get newLabel => 'Nouveau';

  @override
  String get newOpportunity => 'Nouvelle opportunité';

  @override
  String get newPrice => 'Nouveau prix';

  @override
  String newPricesValidFrom(String date) {
    return 'Nouveaux prix valables à partir du $date';
  }

  @override
  String get newPriority => 'Nouvelle priorité';

  @override
  String get newProduct => 'Nouveau produit';

  @override
  String get newQuotation => 'Nouvelle offre';

  @override
  String get newRepair => 'Nouvelle réparation';

  @override
  String get newRevision => 'Nouvelle révision';

  @override
  String newRevisionOf(String number) {
    return 'Nouvelle révision de $number';
  }

  @override
  String get newRule => 'Nouvelle règle';

  @override
  String get newTeam => 'Nouvelle équipe';

  @override
  String get newTicket => 'Nouveau ticket';

  @override
  String get no => 'Non';

  @override
  String get noAccess =>
      'Votre compte n\'a pas encore accès à une section. Demandez à un administrateur.';

  @override
  String get noActiveBom => 'Aucune nomenclature active.';

  @override
  String get noBom => 'Pas encore de nomenclature.';

  @override
  String get noClosures => 'Aucune fermeture enregistrée.';

  @override
  String get noContactLinked => 'Aucune personne de contact liée';

  @override
  String get noContacts => 'Pas encore de contacts.';

  @override
  String get noContracts => 'Aucun contrat';

  @override
  String get noCustomerEquipment => 'Ce client n\'a aucun appareil installé';

  @override
  String get noCustomerLinked => 'Aucun client lié';

  @override
  String get noEquipment => 'Aucune installation liée';

  @override
  String get noExpectedClose => 'Pas de date de clôture prévue';

  @override
  String get noJobsAssigned => 'Aucune intervention ne vous est assignée.';

  @override
  String get noLines => 'Pas encore de lignes.';

  @override
  String get noOrdersYet => 'Vous n\'avez pas encore de commandes.';

  @override
  String get noParts => 'Aucune pièce enregistrée';

  @override
  String get noPermission =>
      'Vous n\'avez pas le droit de modifier ces paramètres.';

  @override
  String get noPhotos => 'Pas encore de photos.';

  @override
  String get noPrices => 'Pas encore de prix.';

  @override
  String get noPriorityChanges => 'Aucun changement de priorité.';

  @override
  String get noPriorityRequests => 'Aucune demande.';

  @override
  String get noQuotations => 'Pas encore d\'offres.';

  @override
  String get noRebates => 'Aucune remise produit ou famille.';

  @override
  String get noRepairs => 'Aucune réparation.';

  @override
  String get noRepairsYet => 'Vous n\'avez pas encore de réparations.';

  @override
  String get noRules => 'Aucune règle.';

  @override
  String get noSerialComponents => 'Aucun composant sérialisé.';

  @override
  String get noSignature => 'Pas encore signé';

  @override
  String get noTeam => 'Aucune équipe';

  @override
  String get noTechnicians => 'Personne d\'assigné';

  @override
  String get noTicketsYet => 'Vous n\'avez pas encore de tickets.';

  @override
  String get noTimeEntries => 'Aucun temps enregistré.';

  @override
  String get nobodyFound => 'Personne trouvé avec ce numéro.';

  @override
  String get nonBillable => 'Non facturable';

  @override
  String get none => 'Aucun';

  @override
  String get notClosed => 'Non clôturés';

  @override
  String get notRouted => 'Pas encore transmise';

  @override
  String get notScheduled => 'Non planifié';

  @override
  String get noteAdded => 'Note ajoutée';

  @override
  String get noteOptional => 'Remarque (facultatif)';

  @override
  String get notes => 'Remarques';

  @override
  String get noUpcomingVisits => 'Aucune visite prévue';

  @override
  String get number => 'Numéro';

  @override
  String get numberRequired => 'Nombre';

  @override
  String get obsoleteRevision => 'Révision obsolète (lecture seule).';

  @override
  String get oidcAccessToken => 'Jeton d\'accès OIDC';

  @override
  String get ok => 'OK';

  @override
  String get onSiteContact => 'Contact sur place';

  @override
  String get openEnded => 'ouvert';

  @override
  String get openJobsOnly => 'Actives seulement';

  @override
  String get openOnly => 'Ouvertes uniquement';

  @override
  String get openOpportunity => 'Ouvrir l\'opportunité';

  @override
  String openPriorityRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count demandes de priorité en cours',
      one: '1 demande de priorité en cours',
    );
    return '$_temp0';
  }

  @override
  String openRepairsCount(String count) {
    return '$count ouvertes';
  }

  @override
  String get opens => 'Ouvre';

  @override
  String get opportunities => 'Opportunités';

  @override
  String get opportunity => 'Opportunité';

  @override
  String get opportunityOptional => 'Opportunité (facultatif)';

  @override
  String get order => 'Commande';

  @override
  String orderAlreadyConfirmed(String date) {
    return 'Cette commande a été confirmée le $date.';
  }

  @override
  String get orderAwaitingConfirmation => 'en attente de votre confirmation';

  @override
  String get orderConfirmationQueued =>
      'La confirmation de commande est en attente d\'envoi.';

  @override
  String get orderConfirmedSnack => 'Commande confirmée.';

  @override
  String get orderConfirmedThanks => 'Merci, votre commande est confirmée.';

  @override
  String get orderCreated => 'Commande créée';

  @override
  String get orderSaved => 'Commande enregistrée.';

  @override
  String get orderStatusInPlanning => 'en planification';

  @override
  String get orderStatusInProduction => 'en production';

  @override
  String get orderStatusPartiallyShipped => 'partiellement expédiée';

  @override
  String get orderStatusPlanned => 'planifiée';

  @override
  String get orderStatusReadyForShipping => 'prête à l\'expédition';

  @override
  String get orderStatusShipped => 'expédiée';

  @override
  String get orderStockRelease => 'Libérer';

  @override
  String get orderStockReserve => 'Réserver';

  @override
  String get orderStockReserveHint =>
      'Le stock peut être réservé une fois la commande confirmée par le client.';

  @override
  String orderStockThisLine(String quantity) {
    return '$quantity réservé pour cette ligne';
  }

  @override
  String get orderStockTitle => 'Disponibilité du stock';

  @override
  String get orders => 'Commandes';

  @override
  String get owner => 'Responsable';

  @override
  String get ownerEmpty => 'Personne';

  @override
  String get ownerSet => 'Quelqu\'un';

  @override
  String get p90 => '90 % en dessous de';

  @override
  String get partFreeTextHint =>
      'Choisissez un produit ou saisissez une description';

  @override
  String get partsUsed => 'Pièces utilisées';

  @override
  String get paymentDays => 'Délai de paiement (jours)';

  @override
  String get pdf => 'PDF';

  @override
  String get perDay => 'Par jour';

  @override
  String get perWeek => 'Par semaine';

  @override
  String get personTitle => 'Titre';

  @override
  String get phone => 'Téléphone';

  @override
  String get phoneCall => 'Appel téléphonique';

  @override
  String get phoneDirect => 'Direct';

  @override
  String get phoneHint => 'Avec indicatif, p. ex. +32 475 12 34 56';

  @override
  String get phoneMobile => 'Mobile';

  @override
  String get phoneNumber => 'Numéro de téléphone';

  @override
  String get phoneNumbers => 'Numéros de téléphone';

  @override
  String get phoneOther => 'Autre';

  @override
  String get phoneWork => 'Bureau';

  @override
  String photoBy(String name) {
    return 'par $name';
  }

  @override
  String get photos => 'Photos';

  @override
  String get photosAdded => 'Photos ajoutées';

  @override
  String get placeholdersHelp =>
      'Variables (cliquer pour insérer dans la langue affichée) :';

  @override
  String get portalAccess => 'Accès au portail client';

  @override
  String get portalScope => 'Voit dans le portail';

  @override
  String get portalScopeCustomer => 'Tous les tickets de l\'entreprise';

  @override
  String get portalScopeOwn => 'Uniquement ses tickets';

  @override
  String get portalSignInIntro =>
      'Saisissez votre adresse e-mail. Nous vous envoyons un lien de connexion, sans mot de passe.';

  @override
  String get portalTitle => 'Portail client';

  @override
  String get postalCode => 'Code postal';

  @override
  String get preparedAnswers => 'Réponses types';

  @override
  String get preparedAnswersHelp =>
      'Réponses réutilisables aux questions récurrentes, un texte par langue. Les variables comme «quotation.number» sont complétées pour le ticket ; le texte reste modifiable avant l\'envoi.';

  @override
  String get preview => 'Aperçu';

  @override
  String priceListOf(String date) {
    return 'Tarif du $date';
  }

  @override
  String get priceListValidOn => 'Tarif valable le';

  @override
  String get priceZone => 'Zone de prix';

  @override
  String pricedOnPriceListOf(String date) {
    return 'Chiffrée selon le tarif du $date';
  }

  @override
  String get prices => 'Prix';

  @override
  String pricesCreated(int count, String date) {
    return '$count prix créés, valables à partir du $date';
  }

  @override
  String pricesWillChange(int count) {
    return '$count prix vont changer';
  }

  @override
  String get pricing => 'Tarification';

  @override
  String get pricingIndicative => 'indicatif';

  @override
  String get pricingIndicativeHelp => 'Indicatif (à confirmer par offre)';

  @override
  String get pricingList => 'prix catalogue';

  @override
  String get pricingListHelp => 'Prix catalogue (remises applicables)';

  @override
  String get pricingNet => 'net';

  @override
  String get pricingNetHelp => 'Prix net (jamais de remise)';

  @override
  String get priority => 'Priorité';

  @override
  String priorityChangeLine(String date, String from, String to, String name) {
    return '$date : $from → $to par $name';
  }

  @override
  String get priorityChangedSnack => 'Priorité modifiée.';

  @override
  String get priorityExpedite => 'urgente';

  @override
  String get priorityHigh => 'haute';

  @override
  String get priorityHistory => 'Historique de la priorité';

  @override
  String get priorityLow => 'basse';

  @override
  String get priorityNormal => 'normale';

  @override
  String get priorityRequestHelp =>
      'Notre équipe décide si et comment la priorité est modifiée.';

  @override
  String priorityRequestLine(String name, String priority) {
    return '$name demande la priorité : $priority';
  }

  @override
  String get priorityRequestSent => 'Votre demande a été envoyée.';

  @override
  String get priorityRequests => 'Demandes de priorité du client';

  @override
  String get priorityUrgent => 'urgente';

  @override
  String get probability => 'Probabilité';

  @override
  String get probabilityPercent => 'Probabilité %';

  @override
  String get probabilityShort => 'Prob.';

  @override
  String get product => 'Produit';

  @override
  String productCount(int count) {
    return '$count produits';
  }

  @override
  String get productDescription => 'Produit';

  @override
  String get productFamilies => 'Familles de produits';

  @override
  String get productFamily => 'Famille de produits';

  @override
  String get productRebates => 'Remises produits';

  @override
  String get productTypeConfigurable => 'configurable';

  @override
  String get productTypeManufactured => 'fabriqué';

  @override
  String get productTypePurchased => 'acheté';

  @override
  String get productTypeService => 'service';

  @override
  String get production => 'Production';

  @override
  String productionBomRevision(String revision) {
    return 'Révision de nomenclature $revision';
  }

  @override
  String get productionBuildComponent => 'Fabriquer';

  @override
  String get productionBuildForStock => 'Fabriquer pour le stock';

  @override
  String get productionCancel => 'Annuler l\'ordre de fabrication';

  @override
  String get productionCancelReason => 'Motif de l\'annulation';

  @override
  String get productionChooseSerials => 'Choisir les numéros de série';

  @override
  String get productionComplete => 'Terminer';

  @override
  String get productionCompleted => 'Ordre de fabrication terminé';

  @override
  String get productionComponents => 'Composants';

  @override
  String get productionConsumed => 'Consommé';

  @override
  String get productionDivision => 'Division';

  @override
  String get productionDivisionAdd => 'Ajouter une division';

  @override
  String get productionDivisionEdit => 'Modifier la division';

  @override
  String get productionDivisions => 'Divisions';

  @override
  String get productionExpiry => 'Date de péremption';

  @override
  String get productionExtraFrom => 'Stock supplémentaire pris dans';

  @override
  String get productionLocation => 'Ranger dans';

  @override
  String get productionLot => 'Numéro de lot';

  @override
  String get productionNoDivision => 'pas de division';

  @override
  String get productionNothingToRelease =>
      'Rien à lancer : chaque ligne à fabriquer est couverte par des ordres de fabrication.';

  @override
  String get productionOrderCancelled =>
      'La commande client a été annulée. Annulez cet ordre de fabrication pour libérer ses composants.';

  @override
  String get productionOrdersOfOrder => 'Ordres de fabrication';

  @override
  String get productionOutput => 'Production obtenue';

  @override
  String get productionPlannedReady => 'Prêt prévu';

  @override
  String get productionPromised => 'Promis';

  @override
  String get productionQuantityBuilt => 'Quantité fabriquée';

  @override
  String get productionRelease => 'Lancer en production';

  @override
  String get productionReleased => 'Lancé en production';

  @override
  String get productionRequired => 'Requis';

  @override
  String get productionReserveAgain => 'Réserver à nouveau';

  @override
  String get productionReserved => 'Réservé';

  @override
  String get productionScrap => 'Rebut';

  @override
  String get productionSerials => 'Numéros de série, un par ligne';

  @override
  String productionSerialsNeeded(String count) {
    return 'Choisissez $count numéros de série';
  }

  @override
  String get productionShort => 'stock insuffisant';

  @override
  String get productionStart => 'Démarrer';

  @override
  String get productionStatusCompleted => 'terminé';

  @override
  String get productionStatusInProgress => 'en cours';

  @override
  String get productionStatusReleased => 'lancé';

  @override
  String get productionToRelease => 'À lancer';

  @override
  String get products => 'Produits';

  @override
  String get profileHelp =>
      'Choisissez la langue et la façon dont nous nous adressons à vous dans nos e-mails et ce portail.';

  @override
  String get quantity => 'Quantité';

  @override
  String get question => 'Question';

  @override
  String get questionToSales => 'Question au commercial';

  @override
  String questionToSalesHelp(String salesperson) {
    return '$salesperson reçoit cette question et la pose au client dans sa langue.';
  }

  @override
  String get quotation => 'Offre';

  @override
  String get quotations => 'Offres';

  @override
  String raisedBy(String name) {
    return 'Créé par $name';
  }

  @override
  String get reason => 'Motif';

  @override
  String get reasonRequired => 'Un motif est obligatoire.';

  @override
  String get rebate => 'Remise std';

  @override
  String rebateFor(String target, String percent) {
    return '$target : $percent %';
  }

  @override
  String get rebatePercent => 'Remise %';

  @override
  String get rebateSourceFamily => 'famille';

  @override
  String get rebateSourceGeneral => 'générale';

  @override
  String get rebateSourceProduct => 'produit';

  @override
  String rebatesOf(String customer) {
    return 'Remises · $customer';
  }

  @override
  String get recurrenceMonthList => 'Les mois choisis';

  @override
  String get recurrenceMonths => 'Tous les N mois';

  @override
  String get recurrenceWeeks => 'Toutes les N semaines';

  @override
  String registerProduct(String product) {
    return 'Enregistrer $product';
  }

  @override
  String get registerUnit => 'Enregistrer une unité';

  @override
  String get registered => 'Enregistré';

  @override
  String get rejected => 'Refusée';

  @override
  String get remove => 'Supprimer';

  @override
  String get removeAndScrap => 'Retirer et mettre au rebut';

  @override
  String get removeBackToStock => 'Retirer, retour en stock';

  @override
  String get removeLine => 'Supprimer la ligne';

  @override
  String removedBy(String date, String name) {
    return 'retiré le $date par $name';
  }

  @override
  String get reopenJob => 'Rouvrir';

  @override
  String get repairAnnouncedByTicket =>
      'Le client l\'a annoncée (le produit n\'est pas encore arrivé)';

  @override
  String get repairAnnouncedOk =>
      'Réparation annoncée. Inscrivez le numéro sur le colis et envoyez-nous le produit.';

  @override
  String get repairPhotosHelp =>
      'Des photos du produit et du défaut nous aident beaucoup.';

  @override
  String get repairPortalAnnounced => 'Annoncée, pas encore reçue';

  @override
  String get repairPortalInRepair => 'En réparation';

  @override
  String get repairPortalReady => 'Réparée, prête à l\'expédition';

  @override
  String get repairPortalWaitingCustomer => 'En attente de votre réponse';

  @override
  String get repairStatusAnnounced => 'Annoncée';

  @override
  String get repairStatusCancelled => 'Annulée';

  @override
  String get repairStatusCompleted => 'Terminée';

  @override
  String get repairStatusInProgress => 'En cours';

  @override
  String get repairStatusReceived => 'Reçue';

  @override
  String get repairStatusRouted => 'En file du département';

  @override
  String get repairStatusShipped => 'Renvoyée';

  @override
  String get repairStatusWaitingCustomer => 'En attente du client';

  @override
  String get repairStatusWaitingParts => 'En attente de pièces';

  @override
  String get repairs => 'Réparations';

  @override
  String get replaceSignature => 'Remplacer la signature';

  @override
  String get replyQueued => 'Réponse en file d\'envoi';

  @override
  String get replyToCustomer => 'Répondre au client';

  @override
  String get reportQueued => 'Le rapport va être envoyé';

  @override
  String get reportSend => 'Envoyer le rapport par e-mail';

  @override
  String reportSentTo(String to, String date) {
    return 'Envoyé à $to le $date';
  }

  @override
  String get reportView => 'Voir le rapport (PDF)';

  @override
  String repricingFailed(String error) {
    return 'Les prix du jour n\'ont pas pu être calculés : $error';
  }

  @override
  String get requestDismissedSnack => 'Demande rejetée.';

  @override
  String get requestLessUrgent => 'Moins urgent';

  @override
  String get requestMoreUrgent => 'Plus urgent (urgente)';

  @override
  String get requestPriorityChange => 'Demander un changement de priorité';

  @override
  String get requestStatusApplied => 'appliquée';

  @override
  String get requestStatusDismissed => 'rejetée';

  @override
  String get requestStatusOpen => 'ouverte';

  @override
  String get required => 'Obligatoire';

  @override
  String get resolutionHours => 'Résolution sous (heures)';

  @override
  String get resolutionMinutes => 'Résolution (min)';

  @override
  String get resolutionTime => 'Résolution';

  @override
  String get responseTimes => 'Délais de réponse et de résolution';

  @override
  String get responseHours => 'Réponse sous (heures)';

  @override
  String get retry => 'Réessayer';

  @override
  String get revisionActivated => 'Révision activée';

  @override
  String revisionItem(int revision, String status, int lines) {
    return 'Révision $revision · $status · $lines lignes';
  }

  @override
  String get revisionNotes => 'Notes de révision';

  @override
  String revisionNumber(int revision) {
    return 'Révision $revision';
  }

  @override
  String revisionPriceLists(String agreed, String current) {
    return 'Prix convenus : tarif du $agreed. Prix actuels : tarif du $current.';
  }

  @override
  String revisionViewNotice(int revision, int current) {
    return 'Vous consultez la révision $revision (lecture seule). La révision actuelle est la $current.';
  }

  @override
  String get revisions => 'Révisions';

  @override
  String get roleInvoicing => 'Facturation';

  @override
  String get roleManagement => 'Direction';

  @override
  String get roleOther => 'Autre';

  @override
  String get rolePurchasing => 'Achats';

  @override
  String get roleQuality => 'Qualité';

  @override
  String get roleSalesContact => 'Contact commercial';

  @override
  String get roleTechnical => 'Technicien';

  @override
  String get roles => 'Rôles';

  @override
  String get roundTo => 'Arrondir à';

  @override
  String get routeNote => 'Remarque pour le département';

  @override
  String get routeRepair => 'Transmettre à un département';

  @override
  String get ruleActions => 'Actions';

  @override
  String get ruleConditions => 'Conditions (toutes doivent correspondre)';

  @override
  String get ruleConditionsHelp =>
      'Choisissez autant de valeurs que souhaité par ligne ; un ticket doit en avoir une. Les lignes vides sont ignorées.';

  @override
  String get ruleNameRequired => 'Une règle doit avoir un nom.';

  @override
  String get ruleResultAfterStop => 'ignorée (arrêt)';

  @override
  String get ruleResultInactive => 'désactivée';

  @override
  String get ruleResultMatched => 's\'applique';

  @override
  String get ruleResultNoMatch => 'ne correspond pas';

  @override
  String get ruleResultOtherTrigger => 'autre événement';

  @override
  String get ruleTrigger => 'Quand';

  @override
  String get ruleTriggerCreated => 'Un ticket est créé';

  @override
  String get ruleTriggerCustomerReplied => 'Le client répond';

  @override
  String get ruleTriggerUpdated => 'Un ticket est modifié par un agent';

  @override
  String get salesperson => 'Commercial';

  @override
  String get save => 'Enregistrer';

  @override
  String get saveChanges => 'Enregistrer les modifications';

  @override
  String get saveDraft => 'Enregistrer le brouillon';

  @override
  String get saved => 'Enregistré';

  @override
  String savedNumber(String number) {
    return '$number enregistré';
  }

  @override
  String get scheduledEnd => 'Fin';

  @override
  String get scheduledStart => 'Début';

  @override
  String get scrapPercent => 'Rebut %';

  @override
  String get search => 'Rechercher';

  @override
  String get send => 'Envoyer';

  @override
  String get sendBackToTriage => 'Renvoyer au tri';

  @override
  String get sendLoginLink => 'Envoyer le lien de connexion';

  @override
  String get sendOrderConfirmation => 'Envoyer la confirmation de commande';

  @override
  String get sendOrderConfirmationHelp =>
      'La confirmation de commande est envoyée au client par e-mail en PDF. La révision ne pourra plus être modifiée ensuite.';

  @override
  String get senderDomain => 'Domaine de l\'expéditeur';

  @override
  String get serial => 'n° de série';

  @override
  String get serialBuiltIn => 'intégré';

  @override
  String get serialDelivered => 'livré';

  @override
  String get serialInStock => 'en stock';

  @override
  String get serialInstalled => 'installé';

  @override
  String get serialNumber => 'Numéro de série';

  @override
  String get serialNumbers => 'Numéros de série';

  @override
  String get serialNumbersHelp =>
      'Chaque unité reçoit son propre numéro de série et historique';

  @override
  String get serialScrapped => 'mis au rebut';

  @override
  String get server => 'Serveur';

  @override
  String get serviceReport => 'Rapport d\'intervention';

  @override
  String get setWarranty => 'Définir la garantie';

  @override
  String get showInactive => 'Afficher les inactifs';

  @override
  String signedByOn(String name, String date) {
    return 'Signé par $name le $date';
  }

  @override
  String get signerName => 'Nom du signataire';

  @override
  String get signHere => 'Signez ici';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String signedInAs(String name) {
    return 'Connecté en tant que $name';
  }

  @override
  String get signingIn => 'Connexion…';

  @override
  String get singleProduct => 'Produit unique';

  @override
  String get siteAddress => 'Où aller';

  @override
  String get siteName => 'Nom du site';

  @override
  String skippedWithoutPrice(int count) {
    return '$count combinaisons produit/zone n\'ont pas de prix et sont ignorées';
  }

  @override
  String get sla => 'SLA';

  @override
  String get slaAndSatisfaction => 'SLA et satisfaction';

  @override
  String get slaAtRisk => 'À risque';

  @override
  String get slaBreached => 'Dépassé';

  @override
  String get slaCompliance => 'Respect du SLA';

  @override
  String slaComplianceDetail(int breached, int total) {
    return '$breached sur $total dépassés';
  }

  @override
  String slaDue(String date) {
    return 'Échéance $date';
  }

  @override
  String get slaFilterAny => 'Tout état SLA';

  @override
  String get slaFirstResponse => 'Première réponse';

  @override
  String slaLeft(String time) {
    return 'encore $time';
  }

  @override
  String get slaMet => 'Respecté';

  @override
  String get slaNone => 'Pas de SLA';

  @override
  String get slaOnTime => 'Dans les temps';

  @override
  String slaOverdue(String time) {
    return '$time de retard';
  }

  @override
  String get slaPaused => 'Chrono arrêté : en attente du client';

  @override
  String get slaPolicies => 'Niveaux de service (SLA)';

  @override
  String get slaPoliciesHelp =>
      'Temps écoulé réel, les heures ouvrables ne sont pas prises en compte. Le chrono s\'arrête tant qu\'un ticket attend le client.';

  @override
  String get slaResolution => 'Résolution';

  @override
  String get splitAction => 'Scinder';

  @override
  String splitFiles(int count) {
    return '$count fichier(s)';
  }

  @override
  String get splitHelp =>
      'Choisissez les messages qui passent dans un nouveau ticket du même client. Leurs fichiers suivent. Irréversible (les tickets peuvent être refusionnés).';

  @override
  String get splitKeepOne => 'Au moins un message doit rester dans ce ticket.';

  @override
  String get splitSubjectOptional => 'Sujet du nouveau ticket (facultatif)';

  @override
  String get splitTicket => 'Scinder le ticket…';

  @override
  String get stage => 'Étape';

  @override
  String get stageLead => 'prospect';

  @override
  String get stageLost => 'perdue';

  @override
  String get stageNegotiation => 'négociation';

  @override
  String get stageProposal => 'proposition';

  @override
  String get stageQualified => 'qualifiée';

  @override
  String get stageWon => 'gagnée';

  @override
  String get startDate => 'Date de début';

  @override
  String get startJob => 'Démarrer';

  @override
  String get startWork => 'Commencer le travail';

  @override
  String get status => 'Statut';

  @override
  String get statusAccepted => 'acceptée';

  @override
  String get statusAfterwards => 'Statut ensuite';

  @override
  String get statusDraft => 'brouillon';

  @override
  String get statusRejected => 'refusée';

  @override
  String get statusSent => 'envoyée';

  @override
  String get statusSuperseded => 'remplacée';

  @override
  String get stopOnMatch => 'Arrêter après cette règle';

  @override
  String get stopOnMatchHelp =>
      'Si elle s\'applique, les règles suivantes sont ignorées.';

  @override
  String get stockAdjust => 'Corriger';

  @override
  String get stockAdjustReason => 'Pourquoi corriger le stock ?';

  @override
  String get stockAdjustRequired =>
      'Choisissez un emplacement, saisissez une quantité et un motif.';

  @override
  String get stockAllWarehouses => 'Tous les entrepôts';

  @override
  String get stockAssignedTo => 'Attribué à';

  @override
  String get stockAvailable => 'Disponible';

  @override
  String get stockBarcode => 'Code-barres';

  @override
  String get stockBelowReorder => 'Sous le seuil de réappro.';

  @override
  String get stockChangeBy => 'Modifier de (+/−)';

  @override
  String get stockCounts => 'Inventaires';

  @override
  String stockExpiredQty(String quantity) {
    return '$quantity périmé(s)';
  }

  @override
  String get stockExpiry => 'Date de péremption';

  @override
  String get stockFrom => 'De';

  @override
  String get stockInVans => 'Dans les camionnettes';

  @override
  String get stockInvalidNumbers =>
      'Le coût, les seuils et le délai doivent être des nombres.';

  @override
  String get stockIssue => 'Sortir';

  @override
  String get stockKindVan => 'Camionnette de service';

  @override
  String get stockKindWarehouse => 'Entrepôt';

  @override
  String get stockLeadTime => 'Délai (jours)';

  @override
  String get stockLocation => 'Emplacement';

  @override
  String get stockLocations => 'Stock par emplacement';

  @override
  String get stockLot => 'Lot';

  @override
  String get stockLotNumber => 'Numéro de lot';

  @override
  String get stockLotTrackingHelp => 'Lots / batchs';

  @override
  String get stockMoves => 'Mouvements';

  @override
  String get stockNewLocation => 'Nouvel emplacement';

  @override
  String get stockNewLot => 'Nouveau lot';

  @override
  String get stockNewQuantity => 'Nouvelle quantité';

  @override
  String get stockNewVan => 'Nouvelle camionnette de service';

  @override
  String get stockNewWarehouse => 'Nouvel entrepôt';

  @override
  String get stockNoMoves => 'Aucun mouvement';

  @override
  String get stockNoWarehouses =>
      'Aucun entrepôt. Un administrateur les crée ici.';

  @override
  String get stockNote => 'Remarque';

  @override
  String get stockNothingInStock => 'Rien en stock';

  @override
  String get stockOnHand => 'En stock';

  @override
  String get stockOnlyInStock => 'Seulement en stock';

  @override
  String get stockProductQuantityRequired =>
      'Choisissez un produit et saisissez une quantité.';

  @override
  String get stockReasonConsumption => 'Consommation';

  @override
  String get stockReasonCorrection => 'Correction';

  @override
  String get stockReasonCount => 'Inventaire';

  @override
  String get stockReasonManualReceipt => 'Réception manuelle';

  @override
  String get stockReasonProductionOutput => 'Production terminée';

  @override
  String get stockReasonPurchaseReceipt => 'Réception d\'achat';

  @override
  String get stockReasonRepairUse => 'Utilisé en réparation';

  @override
  String get stockReasonReturn => 'Retour client';

  @override
  String get stockReasonReversal => 'Annulation';

  @override
  String get stockReasonScrap => 'Rebut';

  @override
  String get stockReasonShipment => 'Expédition';

  @override
  String get stockReasonVanReplenishment => 'Réapprovisionnement camionnette';

  @override
  String get stockReceive => 'Réceptionner';

  @override
  String get stockReorderMax => 'Stock maximum';

  @override
  String get stockReorderMin => 'Stock minimum';

  @override
  String get stockReservations => 'Réservé pour des commandes';

  @override
  String get stockReserved => 'Réservé';

  @override
  String get stockReverse => 'Annuler';

  @override
  String get stockReverseAnyway => 'Annuler quand même';

  @override
  String get stockReverseTitle => 'Annuler ce mouvement';

  @override
  String get stockReversed => 'annulé';

  @override
  String stockShortBy(String quantity) {
    return 'Manque $quantity';
  }

  @override
  String get stockStandardCost => 'Coût standard';

  @override
  String get stockStateAvailable => 'En stock';

  @override
  String get stockStateNotStocked => 'Non stocké';

  @override
  String get stockStatePartial => 'En stock partiellement';

  @override
  String get stockStateReserved => 'Réservé';

  @override
  String get stockStateShort => 'Pas en stock';

  @override
  String get stockTitle => 'Stock';

  @override
  String get stockTo => 'Vers';

  @override
  String get stockTrackingLot => 'lot';

  @override
  String get stockTransfer => 'Transférer';

  @override
  String get stockWarehouse => 'Entrepôt';

  @override
  String get stockWarehouses => 'Entrepôts';

  @override
  String get street => 'Rue';

  @override
  String get streetAddress => 'Rue et numéro';

  @override
  String structureRevision(int revision) {
    return 'Structure (révision $revision)';
  }

  @override
  String get subassembly => 'sous-ensemble';

  @override
  String get subject => 'Objet';

  @override
  String get subjectContains => 'Le sujet contient';

  @override
  String get subjectOptional => 'Objet (facultatif)';

  @override
  String suggested(String value) {
    return 'Suggestion : $value';
  }

  @override
  String get tag => 'Étiquette';

  @override
  String get suspendContract => 'Suspendre';

  @override
  String get tags => 'Étiquettes';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get tasks => 'Tâches';

  @override
  String tasksProgress(String done, String total) {
    return '$done sur $total terminées';
  }

  @override
  String get team => 'Équipe';

  @override
  String get teamLead => 'Responsable';

  @override
  String get teamMembers => 'Membres';

  @override
  String get teamName => 'Nom de l\'équipe';

  @override
  String get teams => 'Équipes';

  @override
  String get technicians => 'Techniciens';

  @override
  String get text => 'Texte';

  @override
  String get ticket => 'Ticket';

  @override
  String get ticketClosed => 'Clôturé';

  @override
  String get ticketDetails => 'Détails du ticket';

  @override
  String get ticketInProgress => 'En cours de traitement';

  @override
  String get ticketMerged => 'Tickets fusionnés';

  @override
  String get ticketOpened => 'Ticket créé';

  @override
  String ticketSplit(String number) {
    return 'Ticket $number créé';
  }

  @override
  String get ticketStatusClosed => 'clôturé';

  @override
  String get ticketStatusNew => 'nouveau';

  @override
  String get ticketStatusOpen => 'ouvert';

  @override
  String get ticketStatusPendingCustomer => 'en attente du client';

  @override
  String get ticketStatusPendingInternal => 'en attente d\'un collègue';

  @override
  String get ticketVolume => 'Tickets créés et clôturés';

  @override
  String get ticketWaitingForYou => 'En attente de votre réponse';

  @override
  String get tickets => 'Tickets';

  @override
  String get timeLogged => 'Temps enregistré';

  @override
  String get timeNote => 'Note';

  @override
  String timeTotal(String total, String billable) {
    return 'Total $total, facturable $billable';
  }

  @override
  String timeTotals(String work, String travel) {
    return 'Travail $work · Déplacement $travel';
  }

  @override
  String get timeTracking => 'Suivi du temps';

  @override
  String get timeZone => 'Fuseau horaire';

  @override
  String get title => 'Titre';

  @override
  String get titleCustomerValueRequired =>
      'Le titre, le client et une valeur valide sont obligatoires.';

  @override
  String get titleMr => 'M.';

  @override
  String get titleMs => 'Mme';

  @override
  String get titleNone => 'Non précisé';

  @override
  String get to => 'À';

  @override
  String get topCategories => 'Principales catégories';

  @override
  String get topTags => 'Principales étiquettes';

  @override
  String get total => 'Total';

  @override
  String productsTotalChange(String from, String to, String difference) {
    return 'Produits hors livraison et TVA : $from → $to ($difference)';
  }

  @override
  String get totalExclVat => 'Total HTVA';

  @override
  String get totalInclVat => 'Total TVAC';

  @override
  String get totalsToBuyOrMake => 'Totaux à acheter ou fabriquer';

  @override
  String get tracking => 'Traçabilité';

  @override
  String get twoLetters => '2 lettres';

  @override
  String get type => 'Type';

  @override
  String get unassigned => 'Non attribués';

  @override
  String get unchanged => 'Inchangé';

  @override
  String get unit => 'Unité';

  @override
  String get unitPrice => 'Prix unitaire';

  @override
  String get unitPriceExclVat => 'Prix unitaire (HTVA)';

  @override
  String get unknownCaller => 'Appelant inconnu';

  @override
  String get until => 'Jusqu\'au';

  @override
  String get upcomingVisits => 'Visites à venir';

  @override
  String get updateToCurrentPrices => 'Mettre à jour aux prix actuels';

  @override
  String get updated => 'Mis à jour';

  @override
  String get uploadingFile => 'Envoi…';

  @override
  String get uploadingPhotos => 'Envoi…';

  @override
  String get useAnotherPriceListDate => 'Utiliser une autre date de tarif';

  @override
  String get validFrom => 'Valable à partir du';

  @override
  String validFromDate(String date) {
    return 'Valable à partir du $date';
  }

  @override
  String validUntil(String date) {
    return 'valable jusqu\'au $date';
  }

  @override
  String get value => 'Valeur';

  @override
  String get vat => 'TVA';

  @override
  String get vatNumber => 'Numéro de TVA';

  @override
  String vatOn(String rate, String base) {
    return 'TVA $rate % sur $base';
  }

  @override
  String get vatPercent => 'TVA %';

  @override
  String get viaPortal => 'Via le portail client';

  @override
  String get visitTemplates => 'Visites';

  @override
  String get visitTitleRequired => 'Chaque visite doit avoir un titre';

  @override
  String get warranty => 'Garantie';

  @override
  String get warrantyExpired => 'Garantie expirée';

  @override
  String get warrantyIn => 'Sous garantie';

  @override
  String get warrantyOut => 'Hors garantie';

  @override
  String get warrantyUnknown => 'Inconnue';

  @override
  String get weekdayFriday => 'Vendredi';

  @override
  String get weekdayMonday => 'Lundi';

  @override
  String get weekdaySaturday => 'Samedi';

  @override
  String get weekdaySunday => 'Dimanche';

  @override
  String get weekdayThursday => 'Jeudi';

  @override
  String get weekdayTuesday => 'Mardi';

  @override
  String get weekdayWednesday => 'Mercredi';

  @override
  String warrantyUntilDate(String date) {
    return 'jusqu\'au $date';
  }

  @override
  String get warrantyUntilLabel => 'Garantie jusqu\'au';

  @override
  String weighted(String amount) {
    return 'pondéré $amount';
  }

  @override
  String get whatWasAsked => 'Quelle est la demande ?';

  @override
  String get whoIsCalling => 'Qui appelle ?';

  @override
  String get won => 'Gagnée';

  @override
  String get workFrom => 'De';

  @override
  String get workKindTravel => 'Déplacement';

  @override
  String get workKindWork => 'Travail';

  @override
  String get workLogs => 'Temps enregistré';

  @override
  String get workUntil => 'À';

  @override
  String writeIn(String language) {
    return 'Rédiger en $language';
  }

  @override
  String get yes => 'Oui';

  @override
  String get yourMessage => 'Votre message';

  @override
  String get yourReference => 'Votre référence (RMA ou commande)';

  @override
  String get zone => 'Zone';

  @override
  String zoneAndRebate(String zone, String percent) {
    return 'Zone $zone · remise générale $percent %';
  }

  @override
  String get zonesNoneAll => 'Zones (aucune sélection = toutes)';

  @override
  String get kbTitle => 'Base de connaissances';

  @override
  String get kbNewArticle => 'Nouvel article';

  @override
  String get kbSearchHint => 'Rechercher des articles';

  @override
  String get kbAllCategories => 'Toutes les catégories';

  @override
  String get kbAllStatuses => 'Tous les statuts';

  @override
  String get kbAllAudiences => 'Tous les publics';

  @override
  String get kbManageCategories => 'Catégories';

  @override
  String get kbStatusPublished => 'Publié';

  @override
  String get kbStatusArchived => 'Archivé';

  @override
  String get kbAudience => 'Public';

  @override
  String get kbAudienceInternal => 'Interne (personnel uniquement)';

  @override
  String get kbAudiencePortal => 'Portail client';

  @override
  String get kbAudiencePublic => 'Public';

  @override
  String get kbArticleTitle => 'Titre';

  @override
  String get kbSummary => 'Résumé';

  @override
  String get kbBody => 'Texte (Markdown)';

  @override
  String get kbPreview => 'Aperçu';

  @override
  String get kbWriteTab => 'Rédiger';

  @override
  String get kbMarkdownHelp =>
      'Utilisez # pour les titres, **gras**, *italique*, - pour les listes, [texte](https://…) pour les liens et ![description](image:ID) pour les images.';

  @override
  String get kbTagsLabel => 'Étiquettes (séparées par des virgules)';

  @override
  String get kbRelated => 'Articles liés';

  @override
  String get kbAddRelated => 'Ajouter un article lié';

  @override
  String get kbImages => 'Images';

  @override
  String get kbUploadImage => 'Téléverser une image';

  @override
  String get kbInsertImage => 'Insérer dans le texte';

  @override
  String get kbPublish => 'Publier';

  @override
  String get kbUnpublish => 'Dépublier';

  @override
  String get kbArchive => 'Archiver';

  @override
  String get kbHistory => 'Historique des versions';

  @override
  String kbVersionLine(int version, String name, String date) {
    return 'Version $version · $name · $date';
  }

  @override
  String get kbRestore => 'Restaurer cette version';

  @override
  String kbRestoredFrom(int version) {
    return 'restaurée depuis la version $version';
  }

  @override
  String kbFeedback(int yes, int no) {
    return '$yes l\'ont trouvé utile, $no non';
  }

  @override
  String kbViews(int count) {
    return '$count vues';
  }

  @override
  String get kbNoArticles => 'Aucun article trouvé.';

  @override
  String get kbNoCategory => 'Aucune catégorie';

  @override
  String get kbMainCategory => 'Catégorie principale';

  @override
  String get kbSortOrder => 'Ordre';

  @override
  String get kbNewCategory => 'Nouvelle catégorie';

  @override
  String get kbCategoryNames => 'Nom par langue';

  @override
  String get kbDelete => 'Supprimer';

  @override
  String get kbSuggestedArticles => 'Articles suggérés';

  @override
  String get kbNoSuggestions => 'Aucun article correspondant.';

  @override
  String get kbInsertText => 'Insérer le texte';

  @override
  String get kbInsertLink => 'Insérer le lien';

  @override
  String get kbInsertArticle => 'Insérer un article';

  @override
  String get kbNoPortalLink =>
      'Cet article est interne : seul son texte peut être inséré.';

  @override
  String get kbHelp => 'Aide';

  @override
  String get kbHelpHeading => 'Comment pouvons-nous vous aider ?';

  @override
  String get kbHelpSearch => 'Rechercher dans les articles d\'aide';

  @override
  String get kbHelpEmpty =>
      'Aucun article trouvé. Vous pouvez ouvrir un ticket.';

  @override
  String get kbWasHelpful => 'Cet article vous a-t-il aidé ?';

  @override
  String get kbYes => 'Oui';

  @override
  String get kbNo => 'Non';

  @override
  String get kbThanks => 'Merci pour votre retour.';

  @override
  String get kbStillNeedHelp => 'Besoin d\'aide ? Ouvrez un ticket.';

  @override
  String get kbRelatedReading => 'Articles liés';

  @override
  String get kbDeflectionTitle =>
      'Ces articles répondent peut-être déjà à votre question';

  @override
  String kbShownIn(String language) {
    return 'Non disponible dans votre langue ; affiché en $language.';
  }

  @override
  String kbUpdatedOn(String date) {
    return 'Mis à jour le $date';
  }

  @override
  String offlineWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications en attente de synchronisation',
      one: '1 modification en attente de synchronisation',
    );
    return '$_temp0';
  }

  @override
  String offlineFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count demandent votre attention',
      one: '1 demande votre attention',
    );
    return '$_temp0';
  }

  @override
  String get offlineQueueTitle => 'Modifications en attente de synchronisation';

  @override
  String get offlineSyncNow => 'Synchroniser maintenant';

  @override
  String get offlineRetry => 'Réessayer';

  @override
  String get offlineDiscard => 'Abandonner';

  @override
  String get offlineDiscardQuestion =>
      'Abandonner cette modification ? Elle ne sera pas envoyée au serveur.';

  @override
  String get offlineAllSynced => 'Tout est synchronisé.';

  @override
  String offlineAttempts(int count) {
    return 'Tentatives : $count';
  }

  @override
  String offlineLastError(String message) {
    return 'Dernière erreur : $message';
  }

  @override
  String get offlineRejected =>
      'Le serveur a refusé cette modification. L\'intervention a peut-être été réaffectée, annulée ou modifiée entre-temps.';

  @override
  String offlineDataFrom(String time) {
    return 'Hors ligne : données du $time';
  }

  @override
  String get offlinePendingSync => 'En attente de synchronisation';

  @override
  String get offlineQueuedMessage =>
      'Pas de connexion : enregistré sur cet appareil, il sera envoyé dès le retour en ligne.';

  @override
  String offlinePhotosWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos en attente d\'envoi',
      one: '1 photo en attente d\'envoi',
    );
    return '$_temp0';
  }

  @override
  String get offlineTooLarge =>
      'Trop volumineux pour être conservé hors ligne. Connectez-vous pour l\'envoyer.';

  @override
  String get offlineReload => 'Recharger';

  @override
  String get offlineOpStart => 'Démarrer l\'intervention';

  @override
  String get offlineOpTaskDone => 'Tâche cochée';

  @override
  String get offlineOpTaskUndone => 'Tâche décochée';

  @override
  String get offlineOpTaskAdd => 'Nouvelle tâche';

  @override
  String get offlineOpWorkLog => 'Saisie de temps';

  @override
  String get offlineOpPart => 'Pièce utilisée';

  @override
  String get offlineOpComplete => 'Terminer l\'intervention';

  @override
  String get offlineOpDecline => 'Le client refuse de signer';

  @override
  String get offlineOpSignature => 'Signature du client';

  @override
  String get offlineOpPhoto => 'Photo';

  @override
  String get collabEscalate => 'Escalader';

  @override
  String get collabEscalateTitle => 'Escalader le ticket';

  @override
  String get collabDelegate => 'Transmettre';

  @override
  String get collabDelegateTitle => 'Transmettre le ticket';

  @override
  String get collabEscalateTo => 'Escalader vers';

  @override
  String get collabNoTarget => 'Responsables de l\'équipe du ticket';

  @override
  String get collabPerson => 'Collègue';

  @override
  String get collabTeam => 'Équipe';

  @override
  String get collabHandOverTo => 'Nouveau responsable';

  @override
  String get collabReasonRequired => 'Motif (obligatoire)';

  @override
  String get collabRaisePriority => 'Augmenter la priorité d\'un niveau';

  @override
  String get collabCommentOptional =>
      'Commentaire pour le nouveau responsable (facultatif)';

  @override
  String get collabInternalHint => 'Interne : jamais envoyé au client.';

  @override
  String get collabEscalated => 'Ticket escaladé';

  @override
  String get collabHandedOver => 'Ticket transmis';

  @override
  String get collabEscalatedBadge => 'Escaladé';

  @override
  String collabEscalatedBy(String name) {
    return 'Escaladé par $name';
  }

  @override
  String get collabWatch => 'Suivre';

  @override
  String get collabUnwatch => 'Ne plus suivre';

  @override
  String get collabWatchers => 'Abonnés';

  @override
  String get collabNoWatchers => 'Personne ne suit ce ticket';

  @override
  String get collabAddWatcher => 'Ajouter un abonné';

  @override
  String get collabActivity => 'Activité';

  @override
  String get collabNoActivity => 'Aucune activité';

  @override
  String collabSeenBy(String readers) {
    return 'Vu par $readers';
  }

  @override
  String get collabFilterUnread => 'Non lus';

  @override
  String get collabFilterWatching => 'Suivis';

  @override
  String get collabFilterEscalated => 'Escaladés';

  @override
  String get collabUnreadTooltip => 'Non lu';

  @override
  String collabReplying(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names sont en train de répondre',
      one: '$names est en train de répondre',
    );
    return '$_temp0 — coordonnez-vous avant d\'envoyer';
  }

  @override
  String collabViewing(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names consultent ce ticket',
      one: '$names consulte ce ticket',
    );
    return '$_temp0';
  }

  @override
  String collabConfirmSend(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names sont en train de répondre à ce ticket.',
      one: '$names est en train de répondre à ce ticket.',
    );
    return '$_temp0 Envoyer quand même ?';
  }

  @override
  String get collabSendAnyway => 'Envoyer quand même';

  @override
  String get collabSystem => 'Système';

  @override
  String collabEventCreated(String actor) {
    return '$actor a créé le ticket';
  }

  @override
  String collabEventAssignedOwner(String actor, String owner) {
    return '$actor a attribué le ticket à $owner';
  }

  @override
  String collabEventOwnerCleared(String actor) {
    return '$actor a retiré le responsable';
  }

  @override
  String collabEventTeam(String actor, String team) {
    return '$actor a déplacé le ticket vers l\'équipe $team';
  }

  @override
  String collabEventTeamCleared(String actor) {
    return '$actor a retiré l\'équipe';
  }

  @override
  String collabEventDelegated(String actor, String owner) {
    return '$actor a transmis le ticket à $owner';
  }

  @override
  String collabEventEscalated(String actor) {
    return '$actor a escaladé le ticket';
  }

  @override
  String collabEventStatus(String actor, String before, String after) {
    return '$actor a changé le statut de $before à $after';
  }

  @override
  String collabEventPriority(String actor, String before, String after) {
    return '$actor a changé la priorité de $before à $after';
  }

  @override
  String collabEventMergedInto(String actor, String number) {
    return '$actor a fusionné ce ticket dans $number';
  }

  @override
  String collabEventMergedFrom(String actor, String number) {
    return '$actor a fusionné $number dans ce ticket';
  }

  @override
  String collabEventTagAdded(String actor, String tag) {
    return '$actor a ajouté l\'étiquette $tag';
  }

  @override
  String collabEventTagRemoved(String actor, String tag) {
    return '$actor a retiré l\'étiquette $tag';
  }

  @override
  String collabMsgCustomer(String actor) {
    return '$actor (client) a écrit';
  }

  @override
  String collabMsgReply(String actor) {
    return '$actor a répondu au client';
  }

  @override
  String collabMsgNote(String actor) {
    return '$actor a ajouté une note interne';
  }

  @override
  String collabMsgCall(String actor) {
    return '$actor a enregistré un appel';
  }

  @override
  String get planningTitle => 'Planification';

  @override
  String get planningDay => 'Jour';

  @override
  String get planningWeek => 'Semaine';

  @override
  String get planningToday => 'Aujourd\'hui';

  @override
  String get planningPrevious => 'Précédent';

  @override
  String get planningNext => 'Suivant';

  @override
  String get planningBacklog => 'À planifier';

  @override
  String get planningBacklogEmpty => 'Plus rien à planifier.';

  @override
  String get planningSkillFilter => 'Compétence';

  @override
  String get planningAllSkills => 'Toutes les compétences';

  @override
  String get planningNoTechnicians =>
      'Aucun technicien à afficher. Donnez le rôle de technicien aux utilisateurs.';

  @override
  String get planningPlan => 'Planifier';

  @override
  String planningScheduleJob(String number) {
    return 'Planifier $number';
  }

  @override
  String get planningSuggestions => 'Suggestions';

  @override
  String get planningShowSuggestions => 'Afficher les suggestions';

  @override
  String get planningNoSuggestions =>
      'Aucun créneau libre dans les deux prochaines semaines.';

  @override
  String planningMissingSkills(int count) {
    return '$count compétence(s) manquante(s)';
  }

  @override
  String get planningRequiredSkills => 'Compétences requises';

  @override
  String get planningChecking => 'Vérification…';

  @override
  String get planningNoConflicts => 'Aucun conflit.';

  @override
  String get planningConfirmTitle => 'Planifier malgré les conflits ?';

  @override
  String get planningConfirmBody =>
      'Cette planification comporte des erreurs :';

  @override
  String get planningScheduleAnyway => 'Planifier quand même';

  @override
  String get planningScheduled => 'Mission planifiée.';

  @override
  String planningConflictDoubleBooked(String name) {
    return '$name a une autre mission à ce moment (trajet compris).';
  }

  @override
  String planningConflictOutsideHours(String name) {
    return '$name est en dehors des heures de travail.';
  }

  @override
  String planningConflictOnAbsence(String name) {
    return '$name est absent(e).';
  }

  @override
  String planningConflictMissingSkill(String name, String skill) {
    return '$name n\'a pas la compétence $skill.';
  }

  @override
  String get planningConflictCrossesDays => 'La mission dépasse minuit.';

  @override
  String get planningAbsenceVacation => 'Congé';

  @override
  String get planningAbsenceSick => 'Maladie';

  @override
  String get planningAbsenceTraining => 'Formation';

  @override
  String get planningAbsenceOther => 'Autre absence';

  @override
  String get planningAgendaEmpty => 'Rien de prévu.';

  @override
  String get planningSettingsTitle => 'Paramètres de planification';

  @override
  String get planningAbsences => 'Absences';

  @override
  String get planningHours => 'Heures de travail';

  @override
  String get planningSkills => 'Compétences';

  @override
  String get planningGeneral => 'Général';

  @override
  String get planningAddAbsence => 'Ajouter une absence';

  @override
  String get planningNoAbsences => 'Aucune absence enregistrée.';

  @override
  String get planningTechnician => 'Technicien';

  @override
  String get planningKind => 'Type';

  @override
  String get planningDefaultHours => 'Par défaut de l\'entreprise';

  @override
  String get planningUsesDefault =>
      'Pas d\'heures propres : l\'horaire par défaut de l\'entreprise s\'applique.';

  @override
  String get planningAddBlock => 'Ajouter une plage';

  @override
  String get planningAddSkill => 'Ajouter une compétence';

  @override
  String get planningTechnicianSkills => 'Compétences par technicien';

  @override
  String planningSkillLevel(int n) {
    return 'Niveau $n';
  }

  @override
  String get planningTravelBuffer => 'Temps de trajet entre missions (minutes)';

  @override
  String get planningTravelBufferHelp =>
      'Réservé entre deux missions d\'un technicien le même jour.';

  @override
  String get planningDefaultJobMinutes =>
      'Durée par défaut d\'une mission (minutes)';

  @override
  String get planningTimezone => 'Fuseau horaire';

  @override
  String get adminTitle => 'Administration';

  @override
  String get adminUsers => 'Utilisateurs';

  @override
  String get adminModules => 'Modules';

  @override
  String get newUser => 'Nouvel utilisateur';

  @override
  String get editUser => 'Modifier l\'utilisateur';

  @override
  String get userDisabledModules => 'Modules désactivés';

  @override
  String get userNotSignedIn => 'Pas encore connecté';

  @override
  String get userResendInvitation => 'Renvoyer l\'invitation';

  @override
  String get userInvitationSent => 'Invitation envoyée';

  @override
  String get userCreated => 'Utilisateur ajouté';

  @override
  String get userFilterAll => 'Tous les membres';

  @override
  String get userFilterActive => 'Membres actifs';

  @override
  String get userFilterInactive => 'Membres désactivés';

  @override
  String get userActiveHelp =>
      'Un membre désactivé ne peut plus se connecter à cette société.';

  @override
  String get userCannotDeactivateSelf =>
      'Vous ne pouvez pas vous désactiver vous-même.';

  @override
  String get userCannotDropOwnAdmin =>
      'Vous ne pouvez pas retirer votre propre rôle d\'administrateur.';

  @override
  String userRolePermissions(int count) {
    return '$count droits';
  }

  @override
  String get userModulesHelp =>
      'Désactivez des modules pour cette personne. Les modules désactivés par la société ne peuvent pas être réactivés ici.';

  @override
  String get userModuleCompanyOff => 'Désactivé pour toute la société';

  @override
  String moduleRequires(String modules) {
    return 'Nécessite $modules';
  }

  @override
  String get modulesIntro =>
      'Désactivez les modules que cette société n\'utilise pas. Ils disparaissent pour les utilisateurs et le serveur refuse leurs requêtes.';

  @override
  String get modulesSaved => 'Modules enregistrés';

  @override
  String moduleAlsoRequires(String modules) {
    return 'Nécessite aussi $modules';
  }

  @override
  String moduleAlsoSwitchedOff(String modules) {
    return 'Désactive aussi : $modules';
  }

  @override
  String moduleAlsoSwitchedOn(String modules) {
    return 'Active aussi : $modules';
  }

  @override
  String moduleExpand(String module) {
    return 'Développer $module';
  }

  @override
  String moduleCollapse(String module) {
    return 'Réduire $module';
  }

  @override
  String get moduleOn => 'Activé';

  @override
  String get moduleOff => 'Désactivé';

  @override
  String moduleLevel(int level) {
    return 'Niveau $level';
  }

  @override
  String get userRoleAdmin => 'Administrateur';

  @override
  String get userRoleSalesManager => 'Responsable commercial';

  @override
  String get userRoleSales => 'Ventes';

  @override
  String get userRoleSupport => 'Support';

  @override
  String get userRoleProduction => 'Production';

  @override
  String get userRoleWarehouse => 'Entrepôt';

  @override
  String get userRoleProductManager => 'Gestionnaire de produits';

  @override
  String get userRoleWorkshop => 'Atelier';

  @override
  String get userRoleTechnician => 'Technicien';

  @override
  String get userRoleDispatcher => 'Planificateur';

  @override
  String get userRoleLogistics => 'Logistique';

  @override
  String get userRoleViewer => 'Lecteur';

  @override
  String get moduleCustomers => 'Clients';

  @override
  String get moduleProducts => 'Produits';

  @override
  String get moduleSales => 'Ventes';

  @override
  String get moduleEngineering => 'Ingénierie';

  @override
  String get moduleInventory => 'Stock';

  @override
  String get moduleHelpdesk => 'Helpdesk';

  @override
  String get moduleKb => 'Base de connaissances';

  @override
  String get moduleRepairs => 'Réparations';

  @override
  String get moduleField => 'Service sur site';

  @override
  String get purpose => 'Destination';

  @override
  String get purposeInstallation => 'Installation';

  @override
  String get purposeStock => 'Stock';

  @override
  String get deliveryCountry => 'Pays de livraison';

  @override
  String deliveryCountryDefault(String country) {
    return 'Par défaut : $country';
  }

  @override
  String get deliveryCountryInvalid =>
      'Saisissez un code pays de deux lettres, par exemple BE.';

  @override
  String get shippingNotRequired => 'non requis';

  @override
  String get shippingPending => 'en attente';

  @override
  String get shippingQuoted => 'chiffré';

  @override
  String get shippingRequested => 'demandé';

  @override
  String get shippingPendingBanner =>
      'En attente d\'un devis de transport de la logistique. Le devis ne peut être envoyé qu\'une fois le coût saisi.';

  @override
  String get shippingQuotedBanner =>
      'Le coût de transport est chiffré et figure sur le devis comme ligne de transport.';

  @override
  String get shippingLineNote => 'Ajouté par la logistique';

  @override
  String get sendAnyway => 'Envoyer quand même';

  @override
  String sendAnywayHelp(String message) {
    return '$message\n\nEn tant que logistique, vous pouvez envoyer le devis sans le coût de transport. L\'envoyer quand même ?';
  }

  @override
  String get shippingRequests => 'Demandes de transport';

  @override
  String get shippingQueue => 'Ouverts et demandés';

  @override
  String get markAsRequested => 'Marquer comme demandé';

  @override
  String get enterQuote => 'Saisir le prix';

  @override
  String get carrier => 'Transporteur';

  @override
  String get amount => 'Montant';

  @override
  String get currency => 'Devise';

  @override
  String get quotedAmount => 'Montant chiffré';

  @override
  String get requestedAt => 'Demandé le';

  @override
  String get amountRequired => 'Saisissez un montant valide.';

  @override
  String get carrierRequired => 'Saisissez le transporteur.';

  @override
  String get packagingCategory => 'Catégorie d\'emballage';

  @override
  String get packagingCategories => 'Catégories d\'emballage';

  @override
  String get newPackagingCategory => 'Nouvelle catégorie d\'emballage';

  @override
  String get requiresShippingQuote => 'Nécessite un devis de transport';

  @override
  String get lengthMm => 'Longueur (mm)';

  @override
  String get widthMm => 'Largeur (mm)';

  @override
  String get heightMm => 'Hauteur (mm)';

  @override
  String get weightG => 'Poids (g)';

  @override
  String get dimensions => 'Dimensions';

  @override
  String dimensionsValue(int length, int width, int height) {
    return '$length x $width x $height mm';
  }

  @override
  String get weight => 'Poids';

  @override
  String weightValue(int grams) {
    return '$grams g';
  }

  @override
  String get positiveWholeNumbers =>
      'Les dimensions et le poids doivent être des entiers positifs, ou vides.';

  @override
  String get powerTab => 'Alimentation';

  @override
  String get powerNotElectrical =>
      'Aucune alimentation n\'est indiquée : ce n\'est pas un produit électrique et il n\'est jamais comparé à un réseau.';

  @override
  String get powerAddSupply => 'Ajouter une alimentation';

  @override
  String get currentType => 'Type de courant';

  @override
  String get currentAc => 'CA';

  @override
  String get currentDc => 'CC';

  @override
  String get voltageV => 'Tension (V)';

  @override
  String get phases => 'Phases';

  @override
  String get frequencyHz => 'Fréquence (Hz)';

  @override
  String get frequencyBoth => '50 et 60 Hz';

  @override
  String get tolerancePct => 'Tolérance (%)';

  @override
  String get powerVoltageInvalid =>
      'Saisissez la tension sous forme d\'entier positif.';

  @override
  String get powerToleranceInvalid =>
      'La tolérance doit être un entier de 0 à 50.';

  @override
  String get powerSupplyDuplicate => 'La même alimentation figure deux fois.';

  @override
  String get powerCheckTitle => 'Contrôle de compatibilité réseau';

  @override
  String get powerCheckHelp =>
      'Compare les alimentations enregistrées aux réseaux électriques d\'un pays.';

  @override
  String get powerGrid => 'Réseau électrique';

  @override
  String get powerAnyGrid => 'N\'importe quel réseau du pays';

  @override
  String get powerCheck => 'Vérifier';

  @override
  String powerResultCompatible(String country) {
    return 'Compatible avec le réseau électrique de $country.';
  }

  @override
  String powerResultIncompatible(
    String country,
    String supported,
    String available,
  ) {
    return 'Ne convient pas au réseau de $country. Pris en charge : $supported. Disponible sur place : $available.';
  }

  @override
  String get powerResultExternal =>
      'Fonctionne uniquement en courant continu et nécessite une alimentation externe ; il n\'est pas comparé au réseau.';

  @override
  String get powerResultNotApplicable =>
      'Produit non électrique ; rien à vérifier.';

  @override
  String powerResultUnknown(String country) {
    return 'Aucune donnée de réseau pour $country : la compatibilité ne peut pas être vérifiée.';
  }

  @override
  String get powerStatusCompatible => 'Compatible';

  @override
  String get powerStatusIncompatible => 'Incompatible';

  @override
  String get powerStatusExternal => 'Alimentation externe nécessaire';

  @override
  String get powerStatusNotApplicable => 'Sans objet';

  @override
  String get powerStatusUnknown => 'Réseau inconnu';

  @override
  String get relatedTab => 'Associés';

  @override
  String get relationRules => 'Règles';

  @override
  String get relationSuggestions => 'Suggestions';

  @override
  String get relationNoRules => 'Aucune règle ne s\'applique à ce produit.';

  @override
  String get relationNoSuggestions => 'Pas encore de suggestions.';

  @override
  String get relationKindCompatible => 'Compatible';

  @override
  String get relationKindIncompatible => 'Incompatible';

  @override
  String get relationKindSuggested => 'Suggéré';

  @override
  String get relationAddRule => 'Ajouter une règle';

  @override
  String get relationEdit => 'Modifier la relation';

  @override
  String get relationsTitle => 'Relations entre produits';

  @override
  String get newRelation => 'Nouvelle relation';

  @override
  String get relationKindLabel => 'Type';

  @override
  String get relationSideA => 'Premier côté';

  @override
  String get relationSideB => 'Second côté';

  @override
  String get relationBidirectional => 'S\'applique dans les deux sens';

  @override
  String get relationStrength => 'Force (1-100)';

  @override
  String get relationStrengthHelp =>
      'Utilisée uniquement par les règles de suggestion.';

  @override
  String get relationNeedSides =>
      'Choisissez un produit ou une famille de chaque côté.';

  @override
  String get relationStrengthInvalid =>
      'La force doit être un entier de 1 à 100.';

  @override
  String get relationsEmpty => 'Aucune relation.';

  @override
  String relationFamilyValue(String code) {
    return 'Famille $code';
  }

  @override
  String get suggestionReasonRule => 'Règle';

  @override
  String get suggestionReasonOften => 'Souvent achetés ensemble';

  @override
  String suggestionStrength(int n) {
    return 'Force $n';
  }

  @override
  String suggestionConfidence(int pct) {
    return 'Confiance $pct %';
  }

  @override
  String suggestionBecause(String code) {
    return 'En raison de $code';
  }

  @override
  String get powerGridsTitle => 'Réseaux électriques';

  @override
  String get newPowerGrid => 'Nouveau réseau électrique';

  @override
  String get powerGridInvalid =>
      'Saisissez un code pays à deux lettres, une tension, 1 ou 3 phases et 50 ou 60 Hz.';

  @override
  String get warningKindPowerGrid => 'Réseau électrique';

  @override
  String get warningKindIncompatible => 'Produits incompatibles';

  @override
  String hintsPowerIncompatible(String code) {
    return '$code ne convient pas au réseau électrique du lieu de livraison.';
  }

  @override
  String hintsSupported(String value) {
    return 'Pris en charge : $value';
  }

  @override
  String hintsAvailable(String value) {
    return 'Disponible : $value';
  }

  @override
  String hintsPowerExternal(String code) {
    return '$code fonctionne en courant continu et nécessite une alimentation externe.';
  }

  @override
  String hintsPowerUnknown(String country, String code) {
    return 'Pas de données de réseau pour $country : $code n\'a pas pu être vérifié. Ajoutez le réseau du pays sous Réseaux électriques dans la page Produits.';
  }

  @override
  String hintsIncompatibleProducts(String a, String b) {
    return '$a et $b ne sont pas compatibles.';
  }

  @override
  String get suggestionsTitle => 'Ajouts suggérés';

  @override
  String get hintsTitle => 'Avertissements et suggestions';

  @override
  String revisionShippingExisting(String amount) {
    return 'Frais de livraison existants : $amount';
  }

  @override
  String get revisionShippingReset =>
      'Avec les prix actuels, ces frais de livraison seront réinitialisés. Un nouveau devis de livraison de la logistique est nécessaire avant de pouvoir envoyer le devis révisé.';

  @override
  String revisionShippingKept(String amount) {
    return 'Avec les prix convenus, la livraison chiffrée est reprise dans le devis révisé (frais actuels : $amount).';
  }

  @override
  String get packagesReceiving => 'Réception des marchandises';

  @override
  String get packagesIntake => 'Réception réparations';

  @override
  String get registerParcel => 'Enregistrer le colis';

  @override
  String get registeredParcels => 'Colis enregistrés';

  @override
  String get noParcels => 'Aucun colis.';

  @override
  String get sender => 'Expéditeur';

  @override
  String get trackingNumber => 'Numéro de suivi';

  @override
  String get parcelCount => 'Nombre de colis';

  @override
  String get packageCondition => 'État du carton';

  @override
  String get conditionIntact => 'Intact';

  @override
  String get conditionDamaged => 'Endommagé';

  @override
  String get conditionOpened => 'Ouvert';

  @override
  String get conditionWet => 'Mouillé';

  @override
  String get conditionNote => 'Remarque sur l\'état';

  @override
  String get removePhoto => 'Retirer la photo';

  @override
  String parcelRegistered(String number) {
    return 'Colis $number enregistré';
  }

  @override
  String get pkgStatusRegistered => 'Enregistré';

  @override
  String get pkgStatusOpened => 'Ouvert';

  @override
  String get pkgStatusLinked => 'Associé à une réparation';

  @override
  String get pkgStatusClosed => 'Clôturé';

  @override
  String get packageKindRepair => 'Réparation';

  @override
  String get packageKindOther => 'Autre (pas de réparation)';

  @override
  String get packageKindReturn => 'Retour à l\'expéditeur';

  @override
  String get toOpen => 'À ouvrir';

  @override
  String get toProcess => 'À traiter';

  @override
  String get toRoute => 'À orienter';

  @override
  String get nothingHere => 'Rien à faire ici.';

  @override
  String get openParcel => 'Ouvrir le colis';

  @override
  String get parcelContents => 'Que contient le colis ?';

  @override
  String get closeParcel => 'Clôturer le colis';

  @override
  String get noteRequired => 'Une remarque est obligatoire.';

  @override
  String get linkToRepair => 'Associer à une réparation';

  @override
  String get repairSuggestions => 'Réparations suggérées';

  @override
  String get noSuggestions => 'Aucune réparation annoncée ne correspond.';

  @override
  String suggestedCustomer(String name) {
    return 'Client suggéré : $name';
  }

  @override
  String suggestionScore(String score) {
    return 'Score $score';
  }

  @override
  String get reasonSerial => 'Même numéro de série';

  @override
  String get reasonCustomer => 'Même client';

  @override
  String get reasonReference => 'Même référence';

  @override
  String get reasonTicket => 'Même ticket';

  @override
  String get reasonProduct => 'Produit similaire';

  @override
  String get reasonRecent => 'Annoncé récemment';

  @override
  String get confirmLinkTitle => 'Confirmer l\'association';

  @override
  String confirmLinkBody(String parcel, String repair) {
    return 'Le colis $parcel contient la réparation $repair. Une réparation annoncée sera marquée comme reçue.';
  }

  @override
  String get customerMismatchWarning =>
      'Le client du colis n\'est pas celui de la réparation.';

  @override
  String get confirmCustomerMismatch =>
      'Oui, il a été envoyé par une autre personne (p. ex. un collègue)';

  @override
  String get confirmLink => 'Confirmer et associer';

  @override
  String get linkConflict =>
      'La réparation a changé entre-temps. La liste a été actualisée ; vérifiez et réessayez.';

  @override
  String get createNewRepair => 'Créer une nouvelle réparation';

  @override
  String get parcelsSection => 'Colis';

  @override
  String get noParcelsLinked => 'Aucun colis associé.';

  @override
  String get unlinkParcel => 'Dissocier le colis';

  @override
  String get parcelsToLink => 'Colis en attente de cette réparation';

  @override
  String get linkParcel => 'Associer le colis';

  @override
  String get parcelLinked => 'Colis associé';

  @override
  String get parcelUnlinked => 'Colis dissocié';

  @override
  String get customerUnknown => 'Client inconnu';

  @override
  String get findingsSection => 'Constatations';

  @override
  String get findingsLabel => 'Ce qui a été constaté';

  @override
  String get diagnosisLabel => 'Diagnostic';

  @override
  String get saveFindings => 'Enregistrer les constatations';

  @override
  String get warrantySection => 'Garantie';

  @override
  String get warrantyVoid => 'Annulée (mauvais usage)';

  @override
  String get warrantyAutomatic => 'Résultat automatique';

  @override
  String warrantyComparedWith(String date) {
    return 'Comparé à la date d\'arrivée $date';
  }

  @override
  String get warrantyProvisional =>
      'Pas encore reçu : comparé à aujourd\'hui, donc provisoire.';

  @override
  String serialUnitLabel(String unit) {
    return 'Unité sérialisée : $unit';
  }

  @override
  String get noSerialUnit => 'Aucune unité sérialisée liée';

  @override
  String get linkSerialUnit => 'Lier une unité sérialisée';

  @override
  String get unlinkSerialUnit => 'Délier l\'unité sérialisée';

  @override
  String get serialUnitSeveral =>
      'Plusieurs unités sérialisées correspondent. Choisissez la bonne.';

  @override
  String get serialUnitNoResults => 'Aucune unité sérialisée trouvée';

  @override
  String get recheckWarranty => 'Revérifier la garantie';

  @override
  String get markWarrantyVoid => 'Annuler la garantie (mauvais usage)';

  @override
  String get removeWarrantyOverride => 'Supprimer la dérogation';

  @override
  String get warrantyVoidTitle => 'Annuler la garantie';

  @override
  String get warrantyRemoveTitle => 'Supprimer la dérogation « annulée »';

  @override
  String get warrantyReasonLabel => 'Motif (obligatoire)';

  @override
  String warrantyOverriddenBy(String name, String date, String reason) {
    return 'Annulée par $name le $date : $reason';
  }

  @override
  String get eventFindings => 'Constatations mises à jour';

  @override
  String get eventSerialUnit => 'Unité sérialisée';

  @override
  String get eventWarrantyAuto => 'Garantie automatique';

  @override
  String get eventWarrantyManual => 'Garantie définie à la main';

  @override
  String get eventWarrantyVoid => 'Garantie annulée';

  @override
  String get eventWarrantyVoidRemoved => 'Dérogation de garantie supprimée';

  @override
  String get csvMenu => 'Export et import CSV';

  @override
  String get csvExport => 'Exporter en CSV';

  @override
  String get csvImport => 'Importer un CSV';

  @override
  String csvExported(String name) {
    return '$name enregistré';
  }

  @override
  String csvExportFailed(String error) {
    return 'Échec de l\'export : $error';
  }

  @override
  String csvImportTitle(String entity) {
    return 'Import CSV : $entity';
  }

  @override
  String get csvImportHelp =>
      'Les lignes sont rapprochées par code : un code existant est mis à jour, un nouveau code est créé. Les colonnes absentes du fichier restent inchangées et rien n\'est jamais supprimé. Tout ou rien : si une ligne contient une erreur, rien n\'est importé. Séparateur point-virgule ou virgule, UTF-8.';

  @override
  String get csvChooseFile => 'Choisir un fichier CSV';

  @override
  String get csvChooseOther => 'Choisir un autre fichier';

  @override
  String get csvChecking => 'Vérification du fichier...';

  @override
  String get csvImporting => 'Import en cours...';

  @override
  String get csvPreview => 'Aperçu : rien n\'a encore été importé';

  @override
  String get csvDone => 'Import terminé';

  @override
  String get csvToCreate => 'À créer';

  @override
  String get csvToUpdate => 'À mettre à jour';

  @override
  String get csvUnchanged => 'Inchangés';

  @override
  String get csvCreated => 'Créés';

  @override
  String get csvUpdated => 'Mis à jour';

  @override
  String get csvImportAction => 'Importer';

  @override
  String get csvEmptyFile => 'Le fichier est vide.';

  @override
  String get csvNotUtf8 =>
      'Le fichier n\'est pas en texte UTF-8. Enregistrez-le en CSV (UTF-8) et réessayez.';

  @override
  String get csvReadFailed => 'Le fichier n\'a pas pu être lu.';

  @override
  String csvErrorsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problèmes trouvés',
      one: '1 problème trouvé',
    );
    return '$_temp0. Rien n\'a été importé.';
  }

  @override
  String csvErrorRow(int row) {
    return 'Ligne $row';
  }

  @override
  String csvErrorRowColumn(int row, String column) {
    return 'Ligne $row, colonne $column';
  }

  @override
  String csvAndMore(int count) {
    return 'et $count de plus';
  }

  @override
  String profileTooltip(String name) {
    return 'Profil : $name';
  }

  @override
  String get tabTicket => 'Ticket';

  @override
  String get tabQuotation => 'Devis';

  @override
  String get tabNewQuotation => 'Nouveau devis';

  @override
  String get tabOrder => 'Commande';

  @override
  String get tabRepair => 'Réparation';

  @override
  String get tabJob => 'Intervention';

  @override
  String get tabProduct => 'Produit';

  @override
  String get tabOpportunity => 'Opportunité';

  @override
  String get tabStock => 'Stock';

  @override
  String get tabArticle => 'Article';

  @override
  String get tabContract => 'Contrat';

  @override
  String get tabCount => 'Inventaire';

  @override
  String get workspaceOverview => 'Aperçu';

  @override
  String get openTabs => 'Onglets ouverts';

  @override
  String get closeTab => 'Fermer l’onglet';

  @override
  String get openInNewTab => 'Ouvrir dans un nouvel onglet';

  @override
  String get unsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get unsavedChangesBody =>
      'Cet onglet contient des modifications non enregistrées. Le fermer et les abandonner ?';

  @override
  String get discardChanges => 'Abandonner les modifications';

  @override
  String get remarkProduction => 'Remarque de production';

  @override
  String get remarkProductionHelp => 'Interne, jamais montrée au client';

  @override
  String get remarkCustomer => 'Remarque pour le client';

  @override
  String get remarkCustomerHelp =>
      'Imprimée sur l\'offre et la confirmation de commande';

  @override
  String get remarkHistory => 'Remarques précédentes';

  @override
  String get remarkHistoryThisCustomer => 'Ce client';

  @override
  String get remarkHistoryThisLanguage => 'Cette langue';

  @override
  String get remarkHistoryAll => 'Toutes';

  @override
  String get remarkHistoryEmpty =>
      'Aucune remarque précédente pour ce produit.';

  @override
  String remarkHistoryUsed(int count, String quotation) {
    return 'Utilisée $count fois, dernière sur $quotation';
  }

  @override
  String get defaultProductionRemark => 'Remarque de production par défaut';

  @override
  String get optionsTab => 'Options';

  @override
  String get optionsIntro =>
      'Produits proposés avec celui-ci sur une offre. Une option obligatoire est ajoutée automatiquement.';

  @override
  String get optionsNone => 'Ce produit n\'a pas d\'options.';

  @override
  String get optionAdd => 'Ajouter une option';

  @override
  String get optionRequired => 'Obligatoire';

  @override
  String get optionQuantity => 'Quantité par unité';

  @override
  String get optionRemove => 'Retirer l\'option';

  @override
  String get optionsSaved => 'Options enregistrées.';

  @override
  String get optionsInvalidQuantity =>
      'Saisissez une quantité supérieure à 0 pour chaque option.';

  @override
  String optionsChooseTitle(String product) {
    return 'Options pour $product';
  }

  @override
  String get optionsChooseHelp =>
      'Les options obligatoires sont ajoutées automatiquement. Cochez les options facultatives à ajouter.';

  @override
  String get optionsAddSelected => 'Ajouter';

  @override
  String get optionsSkip => 'Sans options facultatives';

  @override
  String get optionLine => 'Option de la ligne au-dessus';

  @override
  String get configurator => 'Configurateur';

  @override
  String get configurators => 'Configurateurs';

  @override
  String get configure => 'Configurer';

  @override
  String get newConfiguration => 'Nouvelle configuration';

  @override
  String get savedConfigurations => 'Configurations enregistrées';

  @override
  String cfgAddRow(String item) {
    return 'Ajouter : $item';
  }

  @override
  String cfgAddRowToGroup(String group) {
    return 'Ajouter une ligne à $group';
  }

  @override
  String get cfgCalculated => 'Calculé';

  @override
  String get cfgChangeCustomer => 'Autre client';

  @override
  String get cfgCreateQuotation => 'Créer l\'offre';

  @override
  String get cfgUpdateQuotation => 'Mettre l\'offre à jour';

  @override
  String get cfgDeleteConfirm =>
      'Supprimer cette configuration ? Les offres créées à partir d\'elle restent.';

  @override
  String get cfgDeleteRow => 'Supprimer la ligne';

  @override
  String get cfgDuplicateRow => 'Dupliquer la ligne';

  @override
  String get cfgDiscard => 'Abandonner';

  @override
  String get cfgDiscardChanges =>
      'Abandonner les modifications non enregistrées ?';

  @override
  String cfgEach(String value) {
    return 'Pour chaque : $value';
  }

  @override
  String get cfgErrors => 'Erreurs';

  @override
  String get cfgWarnings => 'Avertissements';

  @override
  String get cfgInfo => 'Information';

  @override
  String cfgEvalFailed(String message) {
    return 'Recalcul impossible : $message';
  }

  @override
  String get cfgInput => 'Saisie';

  @override
  String get cfgIssues => 'Remarques';

  @override
  String get cfgLines => 'Lignes';

  @override
  String get cfgWhy => 'Pourquoi ?';

  @override
  String get cfgInvalidNumber => 'Nombre non valide';

  @override
  String get cfgNewerRevision =>
      'Une révision plus récente de ce configurateur est disponible.';

  @override
  String get cfgUpgrade => 'Mettre à niveau';

  @override
  String get cfgNoConfigurations => 'Aucune configuration enregistrée.';

  @override
  String get cfgNoModels => 'Aucun configurateur n\'est encore actif.';

  @override
  String get cfgNoCustomer => 'Pas de client';

  @override
  String get cfgNoIssues => 'Aucune remarque.';

  @override
  String get cfgNoLines => 'La configuration ne produit encore aucune ligne.';

  @override
  String get cfgNotInCatalogue => 'Absent du catalogue produits';

  @override
  String get cfgPinned => 'Votre valeur (fixée)';

  @override
  String get cfgPricesNeedCustomer =>
      'Choisissez un client pour voir les prix.';

  @override
  String get cfgQuoteBlocked =>
      'Corrigez les erreurs avant de créer une offre.';

  @override
  String get cfgQuoteNeedsCustomer =>
      'Choisissez un client avant de créer une offre.';

  @override
  String cfgQuoteCreated(String number) {
    return 'Offre $number créée.';
  }

  @override
  String cfgQuoteUpdated(String number) {
    return 'Offre $number mise à jour.';
  }

  @override
  String cfgQuoteRevised(String number) {
    return 'Offre $number : une nouvelle révision a été créée.';
  }

  @override
  String cfgResetToCalculated(String value) {
    return 'Revenir au calcul ($value)';
  }

  @override
  String cfgStale(String value) {
    return 'Le calcul donne maintenant $value';
  }

  @override
  String cfgRevision(int revision) {
    return 'révision $revision';
  }

  @override
  String cfgRule(String rule) {
    return 'Règle : $rule';
  }

  @override
  String get cfgSaved => 'Enregistré.';

  @override
  String get cfgSelectLine =>
      'Sélectionnez une ligne pour voir d\'où elle vient.';

  @override
  String get cfgSetForAll => 'Définir pour toutes les lignes…';

  @override
  String cfgSetForAllTitle(String column) {
    return '$column pour toutes les lignes';
  }

  @override
  String get cfgStart => 'Commencer';

  @override
  String get cfgUnsaved => 'Modifications non enregistrées';

  @override
  String cfgNewerRevisionAvailable(int revision) {
    return 'révision $revision disponible';
  }

  @override
  String get cfgbActivate => 'Activer';

  @override
  String get cfgbActivateConfirm =>
      'Activer ce brouillon ? La vente l\'utilisera pour les nouvelles configurations ; la révision active devient obsolète.';

  @override
  String get cfgbActivated => 'Activé.';

  @override
  String cfgbActivatedOn(String date) {
    return 'activé le $date';
  }

  @override
  String get cfgbActivateModel => 'Rendre disponible';

  @override
  String cfgbActivateRefused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problèmes',
      one: '1 problème',
    );
    return 'Non activé : $_temp0 à résoudre.';
  }

  @override
  String cfgbActiveRevision(int revision) {
    return 'active : révision $revision';
  }

  @override
  String get cfgbAddChild => 'Ajouter une ligne d\'option';

  @override
  String get cfgbAddColumn => 'Ajouter une colonne';

  @override
  String get cfgbAddComputed => 'Ajouter une valeur calculée';

  @override
  String get cfgbAddField => 'Ajouter un champ';

  @override
  String get cfgbAddItemTable => 'Ajouter une table d\'éléments';

  @override
  String get cfgbAddOption => 'Ajouter une option';

  @override
  String get cfgbAddRow => 'Ajouter une ligne';

  @override
  String get cfgbAddRule => 'Ajouter une règle de sortie';

  @override
  String get cfgbAddSection => 'Ajouter une section';

  @override
  String get cfgbAddTable => 'Ajouter une table';

  @override
  String get cfgbAddValidation => 'Ajouter un contrôle';

  @override
  String get cfgbApply => 'Appliquer';

  @override
  String cfgbChildRuleTitle(String id) {
    return 'Ligne d\'option $id';
  }

  @override
  String get cfgbCode => 'Code produit (formule)';

  @override
  String get cfgbCodeExpr => 'Formule';

  @override
  String get cfgbCodeHelp => 'p. ex. \'BELT-M\' ou motor_code';

  @override
  String get cfgbCodeTemplate => 'Code produit (modèle)';

  @override
  String get cfgbCodeTemplateHelp =>
      'Texte avec des formules entre accolades, p. ex. DRV- puis motor_size entre accolades';

  @override
  String get cfgbColumn => 'Colonne';

  @override
  String get cfgbColumnName => 'Colonne';

  @override
  String get cfgbCommentTemplate => 'Commentaire (modèle)';

  @override
  String cfgbComputedOf(String scope) {
    return 'Valeurs calculées : $scope';
  }

  @override
  String cfgbComputedTitle(String name) {
    return 'Valeur calculée $name';
  }

  @override
  String get cfgbConditions => 'Conditions';

  @override
  String get cfgbCreate => 'Créer';

  @override
  String get cfgbCsvExport => 'Exporter en CSV';

  @override
  String get cfgbCsvImport => 'Importer un CSV';

  @override
  String cfgbCsvImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes importées.',
      one: '1 ligne importée.',
    );
    return '$_temp0';
  }

  @override
  String get cfgbCsvProblems => 'Le fichier CSV n\'a pas été importé';

  @override
  String get cfgbDeactivateModel => 'Retirer';

  @override
  String get cfgbDefault => 'Valeur par défaut';

  @override
  String get cfgbDefaultExpr => 'Valeur par défaut (formule)';

  @override
  String get cfgbDefaultExprHelp => 'Au lieu d\'une valeur fixe';

  @override
  String get cfgbDescriptionTemplate => 'Description (modèle)';

  @override
  String get cfgbDesignTitle => 'Concevoir les configurateurs';

  @override
  String get cfgbDimCurrent => 'Courant';

  @override
  String get cfgbDimension => 'Grandeur';

  @override
  String get cfgbDimLength => 'Longueur';

  @override
  String get cfgbDimMass => 'Masse';

  @override
  String get cfgbDimPower => 'Puissance';

  @override
  String get cfgbDimSpeed => 'Vitesse';

  @override
  String get cfgbDimVoltage => 'Tension';

  @override
  String get cfgbDiscard => 'Abandonner';

  @override
  String get cfgbDisplayUnits => 'Unités d\'affichage :';

  @override
  String cfgbDraftRevision(int revision) {
    return 'brouillon : révision $revision';
  }

  @override
  String get cfgbEditDraft => 'Modifier le brouillon';

  @override
  String get cfgbEnabledIf => 'Actif si';

  @override
  String cfgbExported(String name) {
    return '$name enregistré.';
  }

  @override
  String get cfgbExportJson => 'Exporter en JSON';

  @override
  String get cfgbExpr => 'Formule';

  @override
  String get cfgbFamily => 'Famille de produits (code)';

  @override
  String cfgbFieldsOf(String scope) {
    return 'Champs : $scope';
  }

  @override
  String cfgbFieldTitle(String name) {
    return 'Champ $name';
  }

  @override
  String get cfgbForEach => 'Pour chaque';

  @override
  String get cfgbForEachHelp =>
      'Une liste : une ligne par élément, avec each et each_index';

  @override
  String cfgbFormulaType(String type) {
    return 'Résultat : $type';
  }

  @override
  String get cfgbGroupField => 'Grouper par champ';

  @override
  String get cfgbGroupHelp =>
      'Un groupe est une section de lignes (p. ex. un hall) : un par valeur du champ de regroupement d\'une table d\'éléments. Un champ de groupe portant le nom d\'un champ du projet le remplace dans le groupe.';

  @override
  String get cfgbGroupLabel => 'Nom d\'un groupe';

  @override
  String get cfgbHelp => 'Texte d\'aide';

  @override
  String get cfgbId => 'Id';

  @override
  String get cfgbImported =>
      'Importé dans l\'éditeur ; enregistrez pour le conserver.';

  @override
  String cfgbImportFailed(String message) {
    return 'Non importé : $message';
  }

  @override
  String get cfgbImportJson => 'Importer un JSON';

  @override
  String get cfgbImportNotExport =>
      'Ce fichier n\'est pas un export de configurateur.';

  @override
  String cfgbImportReplace(String name) {
    return 'Remplacer toute la définition de ce brouillon par $name ?';
  }

  @override
  String get cfgbInactive => 'non disponible pour la vente';

  @override
  String get cfgbItemLabel => 'Libellé d\'élément (modèle)';

  @override
  String get cfgbItemLabelHelp =>
      'Nomme une ligne dans les commentaires et messages ; formules entre accolades, p. ex. group_name et index';

  @override
  String get cfgbItemTable => 'Table d\'éléments';

  @override
  String get cfgbKeys => 'Colonnes clés :';

  @override
  String get cfgbKindExact => 'Exacte';

  @override
  String get cfgbKindRange => 'Plage';

  @override
  String get cfgbLabel => 'Libellé';

  @override
  String get cfgbLayout => 'Mise en page';

  @override
  String get cfgbLayoutSections => 'Sections du formulaire';

  @override
  String get cfgbLayoutSectionsHelp =>
      'Les champs désignent une section dans leur mise en page ; le formulaire les affiche sous son titre.';

  @override
  String get cfgbMax => 'Maximum';

  @override
  String get cfgbMaxLength => 'Longueur maximale';

  @override
  String get cfgbMaxRows => 'Lignes maximum';

  @override
  String get cfgbMergeIdentical => 'Fusionner les lignes identiques';

  @override
  String get cfgbMergeIdenticalHelp =>
      'Les lignes de même code n\'en font qu\'une ; le commentaire liste les éléments';

  @override
  String get cfgbMessage => 'Message (modèle)';

  @override
  String get cfgbMin => 'Minimum';

  @override
  String get cfgbMinRows => 'Lignes minimum';

  @override
  String get cfgbMoveDown => 'Descendre';

  @override
  String get cfgbMoveUp => 'Monter';

  @override
  String get cfgbNewDraft => 'Nouveau brouillon depuis la révision active';

  @override
  String get cfgbNewDraftFromThis => 'Nouveau brouillon depuis cette révision';

  @override
  String get cfgbNewModel => 'Nouveau configurateur';

  @override
  String get cfgbNoProblems => 'Aucun problème';

  @override
  String get cfgbOnMissing => 'Si aucune ligne ne convient';

  @override
  String get cfgbOnMissingClamp => 'Ligne supérieure suivante';

  @override
  String get cfgbOnMissingHelp =>
      'Ligne supérieure suivante : une valeur sous les plages ou entre elles prend la ligne de la plage supérieure suivante, une valeur au-dessus de toutes les plages la dernière ligne ; un décalage au-delà d\'une extrémité s\'arrête à la première ou à la dernière ligne.';

  @override
  String get cfgbOnMissingError => 'Erreur';

  @override
  String get cfgbOnMissingNull => 'Aucune valeur';

  @override
  String get cfgbOptionsFamily => 'Famille de produits';

  @override
  String get cfgbOptionsFrom => 'Alternatives autorisées (formule)';

  @override
  String get cfgbOptionsFromHelp =>
      'Une liste parmi laquelle l\'utilisateur peut choisir au lieu de la valeur calculée';

  @override
  String get cfgbOptionsStatic => 'Liste fixe';

  @override
  String get cfgbOptionsTable => 'Colonne de table';

  @override
  String get cfgbOrder => 'Ordre';

  @override
  String get cfgbOutputRules => 'Règles de sortie';

  @override
  String get cfgbOverridable => 'L\'utilisateur peut la remplacer';

  @override
  String get cfgbOverridableHelp =>
      'Affichée comme calculée, fixée ou fixée mais périmée';

  @override
  String get cfgbPattern => 'Motif (expression régulière)';

  @override
  String get cfgbPercentBase => 'Pourcentage de';

  @override
  String get cfgbPercentBaseList => 'le prix catalogue de la ligne parente';

  @override
  String get cfgbPercentBaseNet => 'le prix net de la ligne parente';

  @override
  String get cfgbPercentOfParent => 'Pourcentage du parent (formule)';

  @override
  String get cfgbPercentOfParentHelp =>
      'Valorise la ligne à ce pourcentage de la ligne parente, p. ex. 20';

  @override
  String cfgbProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problèmes',
      one: '1 problème',
    );
    return '$_temp0';
  }

  @override
  String get cfgbProductFilter => 'Filtre de produits (formule sur p)';

  @override
  String get cfgbProductFilterHelp => 'p. ex. p.attr(\'kw\') >= 1';

  @override
  String get cfgbQuantity => 'Quantité (formule)';

  @override
  String get cfgbQuantityHelp => '1 par défaut ; zéro ou moins omet la ligne';

  @override
  String get cfgbRangeKey => 'Clé de plage';

  @override
  String get cfgbRangeKeyHelp => 'La clé de recherche portant la valeur';

  @override
  String get cfgbRangeMax => 'Colonne maximum';

  @override
  String get cfgbRangeMin => 'Colonne minimum';

  @override
  String get cfgbRawJson => 'Définition en JSON';

  @override
  String get cfgbRemoveColumn => 'Supprimer la colonne';

  @override
  String get cfgbRemoveItemTable => 'Supprimer la table d\'éléments';

  @override
  String get cfgbRemoveRow => 'Supprimer la ligne';

  @override
  String get cfgbReplace => 'Remplacer';

  @override
  String get cfgbRequired => 'Obligatoire';

  @override
  String get cfgbRevisions => 'Révisions';

  @override
  String cfgbRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes',
      one: '1 ligne',
    );
    return '$_temp0';
  }

  @override
  String cfgbRuleTitle(String id) {
    return 'Règle de sortie $id';
  }

  @override
  String get cfgbSavedValid => 'Enregistré. Le brouillon peut être activé.';

  @override
  String cfgbSavedWithProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problèmes',
      one: '1 problème',
    );
    return 'Enregistré avec $_temp0.';
  }

  @override
  String get cfgbScope => 'Niveau';

  @override
  String get cfgbScopeGroup => 'Groupe';

  @override
  String get cfgbScopeItem => 'Élément (ligne)';

  @override
  String cfgbScopeItems(String table) {
    return 'Éléments : $table';
  }

  @override
  String get cfgbScopeProject => 'Projet';

  @override
  String get cfgbScopes => 'Niveaux';

  @override
  String get cfgbSection => 'Section';

  @override
  String get cfgbSectionTemplate => 'Section (modèle)';

  @override
  String get cfgbSectionTemplateHelp =>
      'Par défaut le nom du groupe pour les règles de groupe et d\'élément';

  @override
  String get cfgbSelectComputed =>
      'Choisissez une valeur calculée ou ajoutez-en une.';

  @override
  String get cfgbSelectField => 'Choisissez un champ ou ajoutez-en un.';

  @override
  String get cfgbSelectRule =>
      'Choisissez une règle de sortie ou ajoutez-en une.';

  @override
  String get cfgbSelectTable => 'Choisissez une table ou ajoutez-en une.';

  @override
  String get cfgbSelectValidation => 'Choisissez un contrôle ou ajoutez-en un.';

  @override
  String get cfgbSeverity => 'Gravité';

  @override
  String get cfgbSeverityError => 'Erreur';

  @override
  String get cfgbSeverityInfo => 'Information';

  @override
  String get cfgbSeverityWarning => 'Avertissement';

  @override
  String get cfgbShow => 'Affichée à l\'utilisateur';

  @override
  String get cfgbShownAt => 'Affiché au champ';

  @override
  String get cfgbStatusActive => 'active';

  @override
  String get cfgbStatusDraft => 'brouillon';

  @override
  String get cfgbStatusObsolete => 'obsolète';

  @override
  String get cfgbStep => 'Pas';

  @override
  String get cfgbTabComputed => 'Valeurs calculées';

  @override
  String get cfgbTabFields => 'Champs et mise en page';

  @override
  String get cfgbTabGeneral => 'Général';

  @override
  String get cfgbTable => 'Table';

  @override
  String get cfgbTableKind => 'Type';

  @override
  String get cfgbTables => 'Tables de correspondance';

  @override
  String cfgbTableTitle(String name) {
    return 'Table $name';
  }

  @override
  String get cfgbTabOutputs => 'Règles de sortie';

  @override
  String get cfgbTabTables => 'Tables';

  @override
  String get cfgbTabTest => 'Tester';

  @override
  String get cfgbTabTransfer => 'Import/export';

  @override
  String get cfgbTabValidations => 'Contrôles';

  @override
  String get cfgbTestHelp =>
      'Essayez le brouillon enregistré tel que la vente le verra. Rien n\'est enregistré ; choisissez une ligne pour voir pourquoi elle est là.';

  @override
  String get cfgbTestNeedsValid =>
      'Le brouillon enregistré a des problèmes ; le test peut échouer tant qu\'ils ne sont pas résolus.';

  @override
  String get cfgbTestReset => 'Recommencer';

  @override
  String get cfgbTestUnsaved =>
      'Le test utilise le brouillon enregistré ; enregistrez pour inclure vos dernières modifications.';

  @override
  String get cfgbTranslations => 'Traductions';

  @override
  String get cfgbTypeBoolean => 'Oui/non';

  @override
  String get cfgbTypeChoice => 'Choix';

  @override
  String get cfgbTypeInteger => 'Nombre entier';

  @override
  String get cfgbTypeNumber => 'Nombre';

  @override
  String get cfgbTypeProduct => 'Produit';

  @override
  String get cfgbTypeText => 'Texte';

  @override
  String get cfgbUnsavedText =>
      'Le brouillon a des modifications non enregistrées.';

  @override
  String get cfgbUnsavedTitle => 'Modifications non enregistrées';

  @override
  String get cfgbValidations => 'Contrôles';

  @override
  String cfgbValidationTitle(String id) {
    return 'Contrôle $id';
  }

  @override
  String get cfgbValidationWhenHelp => 'Si vrai, le message est affiché';

  @override
  String get cfgbValue => 'Valeur';

  @override
  String get cfgbVisibleIf => 'Visible si';

  @override
  String get cfgbWhen => 'Si';

  @override
  String get cfgbWhenHelp => 'Les lignes ne sont créées que si c\'est vrai';

  @override
  String get cfgbWidth => 'Largeur';

  @override
  String get tabProductionOrder => 'Ordre de fabrication';

  @override
  String get tabDeliveryNote => 'Bon de livraison';

  @override
  String get vatRegime => 'Régime TVA';

  @override
  String get vatRegimeDomestic => 'Client UE, TVA facturée';

  @override
  String get vatRegimeIntraEu => 'Entreprise UE, TVA en autoliquidation';

  @override
  String get vatRegimeOutsideEu => 'Hors UE, sans TVA';

  @override
  String get addSubItem => 'Ajouter un sous-article';

  @override
  String subItemsOptions(String product) {
    return 'Options de $product';
  }

  @override
  String get subItemsNoOptions => 'Ce produit n\'a pas d\'options.';

  @override
  String get subItemsOtherProducts => 'Autres produits';

  @override
  String get crTitle => 'Rapports';

  @override
  String get crNew => 'Nouveau rapport';

  @override
  String get crEmpty =>
      'Aucun rapport pour l\'instant. Créez-en un pour regrouper et totaliser vos données.';

  @override
  String get crShared => 'Partagé';

  @override
  String get crPrivate => 'Privé';

  @override
  String get crShare => 'Partager avec toute l\'entreprise';

  @override
  String crOwnedBy(String name) {
    return 'Par $name';
  }

  @override
  String get crObject => 'Rapport sur';

  @override
  String get crJoin => 'Ajouter des données liées';

  @override
  String get crGroupBy => 'Regrouper par';

  @override
  String get crAddGrouping => 'Ajouter un regroupement';

  @override
  String get crColumns => 'Colonnes';

  @override
  String get crAddColumn => 'Ajouter une colonne';

  @override
  String get crField => 'Champ';

  @override
  String get crSummary => 'Synthèse';

  @override
  String get crSummaryNone => 'Afficher la valeur';

  @override
  String get crSumCount => 'Nombre';

  @override
  String get crSumSum => 'Somme';

  @override
  String get crSumAvg => 'Moyenne';

  @override
  String get crSumMin => 'Minimum';

  @override
  String get crSumMax => 'Maximum';

  @override
  String get crFilters => 'Filtres';

  @override
  String get crAddFilter => 'Ajouter un filtre';

  @override
  String get crMatchAll => 'Tous les filtres doivent correspondre';

  @override
  String get crMatchAny => 'Au moins un filtre doit correspondre';

  @override
  String get crOpEq => 'est égal à';

  @override
  String get crOpNe => 'n\'est pas égal à';

  @override
  String get crOpGt => 'supérieur à';

  @override
  String get crOpGte => 'au moins';

  @override
  String get crOpLt => 'inférieur à';

  @override
  String get crOpLte => 'au plus';

  @override
  String get crOpContains => 'contient';

  @override
  String get crOpStartsWith => 'commence par';

  @override
  String get crOpIn => 'est parmi';

  @override
  String get crOpIsNull => 'est vide';

  @override
  String get crOpNotNull => 'n\'est pas vide';

  @override
  String get crValue => 'Valeur';

  @override
  String get crValueListHint => 'Séparez les valeurs par des virgules';

  @override
  String get crBucketNone => 'Valeur exacte';

  @override
  String get crBucketDay => 'Par jour';

  @override
  String get crBucketMonth => 'Par mois';

  @override
  String get crBucketYear => 'Par année';

  @override
  String get crSort => 'Trier';

  @override
  String get crAddSort => 'Ajouter un tri';

  @override
  String get crDescending => 'Décroissant';

  @override
  String get crChart => 'Graphique';

  @override
  String get crChartNone => 'Pas de graphique';

  @override
  String get crChartBar => 'Barres';

  @override
  String get crChartLine => 'Ligne';

  @override
  String get crChartPie => 'Secteurs';

  @override
  String get crChartX => 'Catégories';

  @override
  String get crChartY => 'Valeurs';

  @override
  String crRows(int count) {
    return '$count lignes';
  }

  @override
  String crRowsShown(int shown, int total) {
    return '$shown lignes affichées sur $total';
  }

  @override
  String crChartShareShown(int count) {
    return 'Les parts portent sur les $count groupes affichés.';
  }

  @override
  String get crSaved => 'Rapport enregistré';

  @override
  String get crDeleted => 'Rapport supprimé';

  @override
  String get crDelete => 'Supprimer';

  @override
  String get crDeleteConfirm => 'Supprimer ce rapport ?';

  @override
  String get crExportCsv => 'Exporter en CSV';

  @override
  String get crExportPdf => 'Exporter en PDF';

  @override
  String get crNeedName => 'Donnez un nom au rapport.';

  @override
  String get crNeedColumn => 'Ajoutez au moins une colonne.';

  @override
  String get crLoadMore => 'Afficher plus de lignes';

  @override
  String get crNoRows => 'Aucune ligne pour ce rapport.';

  @override
  String get crRun => 'Exécuter';

  @override
  String get crDateMode => 'Date';

  @override
  String get crDateFixed => 'Date fixe';

  @override
  String get crDateRelative => 'Relative à aujourd\'hui';

  @override
  String get crRelativePeriod => 'Période';

  @override
  String get crRelativeDays => 'Nombre de jours';

  @override
  String get crRelativeDaysInvalid =>
      'Saisissez un nombre entier de jours de 1 à 3660.';

  @override
  String get crRelToday => 'Aujourd\'hui';

  @override
  String get crRelYesterday => 'Hier';

  @override
  String get crRelThisWeek => 'Cette semaine';

  @override
  String get crRelLastWeek => 'La semaine dernière';

  @override
  String get crRelThisMonth => 'Ce mois-ci';

  @override
  String get crRelLastMonth => 'Le mois dernier';

  @override
  String get crRelThisQuarter => 'Ce trimestre';

  @override
  String get crRelLastQuarter => 'Le trimestre dernier';

  @override
  String get crRelThisYear => 'Cette année';

  @override
  String get crRelLastYear => 'L\'année dernière';

  @override
  String get crRelLastNDays => 'N derniers jours';

  @override
  String get crRelNextNDays => 'N prochains jours';

  @override
  String get envLive => 'Production';

  @override
  String get envTest => 'Test';

  @override
  String get envTutorial => 'Tutoriel';

  @override
  String envBannerSemantics(String name, String kind) {
    return 'Environnement $name, $kind';
  }

  @override
  String get envSwitcherTitle => 'Environnements';

  @override
  String envSwitchMenu(String name) {
    return 'Environnement : $name';
  }

  @override
  String get envSwitchTooltip => 'Changer d\'environnement';

  @override
  String get envActive => 'Actif';

  @override
  String get envAdd => 'Ajouter un environnement';

  @override
  String get envName => 'Nom';

  @override
  String get envServerUrl => 'Adresse du serveur';

  @override
  String get envCheck => 'Vérifier le serveur';

  @override
  String envDetected(String kind, String db) {
    return 'Le serveur indique : environnement $kind, base de données $db';
  }

  @override
  String get envInvalidUrl =>
      'Saisissez une adresse complète, par exemple https://erp.example.com';

  @override
  String get envAlreadyListed => 'Ce serveur figure déjà dans la liste.';

  @override
  String envUnreachable(String error) {
    return 'Impossible de lire l\'environnement de ce serveur : $error';
  }

  @override
  String get envRemove => 'Retirer';

  @override
  String get envRemoveTitle => 'Retirer l\'environnement ?';

  @override
  String envRemoveBody(String name) {
    return '$name est retiré de cet appareil, avec sa connexion enregistrée. Rien ne change sur le serveur.';
  }

  @override
  String get envCannotRemoveActive =>
      'Passez d\'abord à un autre environnement';

  @override
  String envUnsavedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count onglets ouverts contiennent des modifications non enregistrées',
      one: '1 onglet ouvert contient des modifications non enregistrées',
    );
    return '$_temp0. Changer d\'environnement ferme tous les onglets et abandonne ces modifications.';
  }

  @override
  String get envDiscardAndSwitch => 'Abandonner et changer';

  @override
  String get adminPriceZones => 'Zones de prix';

  @override
  String get newPriceZone => 'Nouvelle zone de prix';

  @override
  String get editPriceZone => 'Modifier la zone de prix';

  @override
  String get sortOrder => 'Ordre de tri';

  @override
  String get noPriceZones => 'Aucune zone de prix.';

  @override
  String get priceZoneDeleted => 'Zone de prix supprimée';

  @override
  String get delete => 'Supprimer';

  @override
  String deletePriceZoneConfirm(String code) {
    return 'Supprimer la zone de prix $code ? Refusé si des prix ou des clients l\'utilisent.';
  }

  @override
  String get sortOrderInvalid => 'L\'ordre de tri doit être un nombre entier.';

  @override
  String get envNotSaved =>
      'Fait, mais la liste des environnements n\'a pas pu être enregistrée sur cet appareil.';

  @override
  String get tutTitle => 'Tutoriel';

  @override
  String get tutBack => 'Retour';

  @override
  String get tutNext => 'Suivant';

  @override
  String get tutSkipStep => 'Passer l\'étape';

  @override
  String get tutPause => 'Pause';

  @override
  String get tutResume => 'Reprendre';

  @override
  String get tutPaused => 'Tutoriel en pause';

  @override
  String get tutTakeMe => 'M\'y emmener';

  @override
  String tutStepOf(int current, int total) {
    return 'Étape $current sur $total';
  }

  @override
  String get tutOfferTitle => 'Bienvenue dans TradoCraft';

  @override
  String get tutOfferBody =>
      'Ceci est un environnement de tutoriel. Souhaitez-vous une visite guidée qui vous apprend l\'application pas à pas, avec des données d\'exercice ?';

  @override
  String get tutOfferStart => 'Démarrer le tutoriel';

  @override
  String get tutOfferLater => 'Pas maintenant';

  @override
  String get tutLiveTitle =>
      'Le tutoriel ne s\'exécute pas sur des données réelles';

  @override
  String get tutLiveBody =>
      'Le tutoriel crée des enregistrements ; il ne s\'exécute donc que dans un environnement de test ou de tutoriel. Changez d\'environnement ou ajoutez-en un.';

  @override
  String get tutSwitchEnv => 'Changer d\'environnement';

  @override
  String get tutAddEnv => 'Ajouter un environnement';

  @override
  String get tutMapIntro =>
      'Parcourez les chapitres dans l\'ordre. Vous pouvez à tout moment mettre un chapitre en pause, le rejouer ou le passer.';

  @override
  String get tutStatusDone => 'Terminé';

  @override
  String get tutStatusCurrent => 'À suivre';

  @override
  String get tutStatusLocked => 'Verrouillé';

  @override
  String get tutStatusSkipped => 'Passé';

  @override
  String get tutStatusPaused => 'En cours';

  @override
  String get tutStart => 'Démarrer';

  @override
  String get tutReplay => 'Rejouer';

  @override
  String get tutSkipChapter => 'Passer le chapitre';

  @override
  String get tutWelcomeTitle => 'Bienvenue';

  @override
  String get tutWelcomeSummary =>
      'Premiers repères : la bannière d\'environnement, les onglets et les commandes du tutoriel.';

  @override
  String get tutProductTitle => 'Votre premier produit';

  @override
  String get tutProductSummary =>
      'Casquette : responsable produit. Créez trois composants, un produit fini et sa nomenclature.';

  @override
  String get tutWelcomeBannerTitle => 'La bande en haut';

  @override
  String get tutWelcomeBannerBody =>
      'Cette bande indique toujours dans quel environnement vous êtes : son nom et son type. Orange = test, bleu = tutoriel, rouge = données réelles. Le tutoriel ne s\'exécute que dans un environnement de test ou de tutoriel : rien de ce que vous faites ici ne touche aux données réelles.';

  @override
  String get tutWelcomeTabsTitle => 'Onglets et sections';

  @override
  String get tutWelcomeTabsBody =>
      'Les sections se trouvent à gauche (ou dans la barre du bas sur un téléphone). Ouvrir un enregistrement, comme un produit ou un devis, ajoute un onglet à l\'espace de travail : vous pouvez garder plusieurs enregistrements ouverts.';

  @override
  String get tutWelcomeControlsTitle => 'Cette carte';

  @override
  String get tutWelcomeControlsBody =>
      'Je suis votre narrateur. « Suivant » avance quand une étape n\'est qu\'une explication. Les étapes où vous devez agir se terminent d\'elles-mêmes dès que c\'est fait. « Retour » et « Passer l\'étape » vous laissent circuler, et « Pause » me cache jusqu\'à « Reprendre ».';

  @override
  String get tutWelcomeMenuTitle => 'Où me trouver';

  @override
  String get tutWelcomeMenuBody =>
      'Ouvrez le menu du compte pour trouver l\'entrée Tutoriel. Elle ouvre la carte des chapitres, où vous pouvez à tout moment reprendre, rejouer ou passer un chapitre.';

  @override
  String get tutWelcomeProductsTitle => 'Commençons';

  @override
  String get tutWelcomeProductsBody =>
      'Ouvrez la section Produits. Le chapitre suivant commence là.';

  @override
  String get tutProductOpenTitle => 'Produits';

  @override
  String get tutProductOpenBody =>
      'Aujourd\'hui, vous êtes le responsable produit. Tout ce que l\'entreprise vend ou fabrique est un produit. Ouvrez la section Produits.';

  @override
  String get tutProductMotorTitle => 'Composant : Motor';

  @override
  String get tutProductMotorBody =>
      'Créez le premier composant. Appuyez sur Nouveau produit, saisissez le code TUT-MOTOR et le nom Motor, gardez le type Acheté et enregistrez.';

  @override
  String get tutProductMotorHint =>
      'Le préfixe TUT- marque les données du tutoriel, pour les reconnaître plus tard.';

  @override
  String get tutProductFrameTitle => 'Composant : Frame';

  @override
  String get tutProductFrameBody =>
      'Créez un deuxième composant de la même façon : code TUT-FRAME, nom Frame, type Acheté.';

  @override
  String get tutProductControllerTitle => 'Composant : Controller';

  @override
  String get tutProductControllerBody =>
      'Puis un troisième : code TUT-CTRL, nom Controller, type Acheté.';

  @override
  String get tutProductCartTitle => 'Le produit fini';

  @override
  String get tutProductCartBody =>
      'Voici le produit que vous fabriquez avec ces pièces. Créez le code TUT-CART, le nom Cart et choisissez le type Fabriqué : seuls les produits fabriqués ont une nomenclature.';

  @override
  String get tutProductOpenCartTitle => 'Ouvrir le Cart';

  @override
  String get tutProductOpenCartBody =>
      'Ouvrez le nouveau produit Cart dans la liste pour voir ses onglets.';

  @override
  String get tutProductBomTabTitle => 'Nomenclature';

  @override
  String get tutProductBomTabBody =>
      'Choisissez l\'onglet Nomenclature. Il liste les composants nécessaires pour fabriquer une unité. Une révision est un brouillon que vous modifiez, ou la révision active utilisée par la production. Appuyez sur Suivant une fois sur place.';

  @override
  String get tutProductRevisionTitle => 'Une première révision';

  @override
  String get tutProductRevisionBody =>
      'Appuyez sur Nouvelle révision pour commencer un brouillon.';

  @override
  String get tutProductLinesTitle => 'Ajoutez les composants';

  @override
  String get tutProductLinesBody =>
      'Cherchez chaque composant et ajoutez-le : Motor, Frame et Controller. Appuyez ensuite sur Enregistrer le brouillon.';

  @override
  String get tutProductLinesHint =>
      'Saisissez TUT dans le champ de recherche pour trouver les trois composants.';

  @override
  String get tutProductActivateTitle => 'Activez-la';

  @override
  String get tutProductActivateBody =>
      'Appuyez sur Activer. Dès maintenant, la production et les devis utilisent cette révision ; les changements ultérieurs passent par une nouvelle révision.';

  @override
  String get tutProductDoneTitle => 'Bravo';

  @override
  String get tutProductDoneBody =>
      'Vous avez un produit fini avec une nomenclature de trois composants. Les chapitres suivants s\'appuient dessus.';

  @override
  String get purchasing => 'Achats';

  @override
  String get tabSupplier => 'Fournisseur';

  @override
  String get purchSuppliers => 'Fournisseurs';

  @override
  String get purchNewSupplier => 'Nouveau fournisseur';

  @override
  String get purchPaymentTerms => 'Conditions de paiement';

  @override
  String purchDays(int count) {
    return '$count jours';
  }

  @override
  String get purchActiveOnly => 'Actifs uniquement';

  @override
  String get purchNameRequired => 'Le nom est obligatoire.';

  @override
  String get purchCountryInvalid => 'Le pays doit être un code à 2 lettres.';

  @override
  String get purchCurrencyInvalid => 'La devise doit être un code à 3 lettres.';

  @override
  String get purchTermsInvalid =>
      'Les conditions de paiement doivent être un nombre entier de jours.';

  @override
  String get purchInactive => 'Inactif';

  @override
  String get purchPriceList => 'Liste de prix';

  @override
  String get purchAddProduct => 'Ajouter un produit';

  @override
  String get purchEditPrice => 'Modifier le prix';

  @override
  String get purchNoPrices => 'Aucun produit dans cette liste de prix.';

  @override
  String get purchPickProduct => 'Choisissez un produit.';

  @override
  String get purchPriceInvalid => 'Saisissez un prix unitaire valide.';

  @override
  String get purchMoqInvalid =>
      'Saisissez une quantité minimale de commande valide.';

  @override
  String get purchLeadInvalid =>
      'Le délai doit être un nombre entier de jours.';

  @override
  String get purchSupplierArticleCode => 'Code article fournisseur';

  @override
  String get purchSupplierArticleName => 'Désignation fournisseur';

  @override
  String get purchMoq => 'Qté min. de commande';

  @override
  String get purchLeadTimeDays => 'Délai (jours)';

  @override
  String get purchPreferred => 'Fournisseur préféré';

  @override
  String purchRemoveProductConfirm(String code) {
    return 'Retirer $code de cette liste de prix ?';
  }

  @override
  String purchMoqValue(String qty) {
    return 'QMC $qty';
  }

  @override
  String purchLeadValue(int days) {
    return 'délai $days j';
  }

  @override
  String get purchNoSuppliers => 'Aucun fournisseur trouvé.';

  @override
  String get purchOrders => 'Commandes d\'achat';

  @override
  String get purchNewOrder => 'Nouvelle commande d\'achat';

  @override
  String get purchNoOrders => 'Aucune commande d\'achat trouvée.';

  @override
  String get purchOrderNumber => 'Numéro';

  @override
  String get purchSupplier => 'Fournisseur';

  @override
  String get purchAllSuppliers => 'Tous les fournisseurs';

  @override
  String get purchOrderDate => 'Date de commande';

  @override
  String get purchExpectedDate => 'Livraison prévue';

  @override
  String get purchStatusDraft => 'brouillon';

  @override
  String get purchStatusApproved => 'approuvée';

  @override
  String get purchStatusSent => 'envoyée';

  @override
  String get purchStatusPartial => 'partiellement reçue';

  @override
  String get purchStatusReceived => 'reçue';

  @override
  String get purchStatusCancelled => 'annulée';

  @override
  String get purchLines => 'Lignes';

  @override
  String get purchAddLine => 'Ajouter une ligne';

  @override
  String get purchPickSupplier => 'Choisissez un fournisseur.';

  @override
  String get purchLineQtyInvalid =>
      'La quantité doit être supérieure à zéro, avec au plus 4 décimales.';

  @override
  String get purchLinePriceInvalid =>
      'Le prix unitaire doit être nul ou positif, avec au plus 4 décimales.';

  @override
  String get purchNeedLine => 'Ajoutez au moins une ligne.';

  @override
  String get purchApprove => 'Approuver';

  @override
  String get purchCancelOrder => 'Annuler la commande';

  @override
  String purchCancelOrderConfirm(String number) {
    return 'Annuler la commande d\'achat $number ? Cette action est irréversible.';
  }

  @override
  String get purchKeepOrder => 'Conserver la commande';

  @override
  String get purchQtyReceived => 'Reçu';

  @override
  String get purchLineTotal => 'Total de la ligne';

  @override
  String get purchSubtotal => 'Sous-total';

  @override
  String get purchTax => 'TVA';

  @override
  String get tabPurchaseOrder => 'Commande d\'achat';

  @override
  String get purchReceiveGoods => 'Réceptionner les marchandises';

  @override
  String purchReceiveTitle(String number) {
    return 'Réceptionner les marchandises de $number';
  }

  @override
  String get purchReceiveDestination => 'Emplacement de destination';

  @override
  String get purchReceiveQty => 'Quantité à réceptionner';

  @override
  String purchReceiveRemaining(String qty) {
    return 'Restant : $qty';
  }

  @override
  String get purchReceiveSerialsHelp => 'Un numéro de série par ligne';

  @override
  String get purchDeliveryNote => 'Bon de livraison du fournisseur';

  @override
  String purchReceiveQtyInvalid(String product, String max) {
    return '$product : saisissez une quantité entre 0 et $max.';
  }

  @override
  String purchReceiveLotNeeded(String product) {
    return '$product : saisissez un numéro de lot.';
  }

  @override
  String purchReceiveSerialWhole(String product) {
    return '$product : la quantité doit être un nombre entier.';
  }

  @override
  String purchReceiveSerialCount(String product, int count) {
    return '$product : saisissez exactement $count numéros de série différents.';
  }

  @override
  String get purchReceiveNothing =>
      'Saisissez une quantité pour au moins une ligne.';

  @override
  String get purchReceiveLocationNeeded =>
      'Choisissez un emplacement de destination.';

  @override
  String purchReceiptBooked(String number) {
    return 'Réception $number enregistrée.';
  }

  @override
  String get purchOpenReceipt => 'Ouvrir la réception';

  @override
  String get purchReceipts => 'Réceptions de marchandises';

  @override
  String get purchReceivedDate => 'Reçu le';

  @override
  String get purchOpenOrder => 'Commande d\'achat';

  @override
  String get tabGoodsReceipt => 'Réception';

  @override
  String get setupTitle => 'Configurer une nouvelle société';

  @override
  String get setupOffer => 'Configurer une nouvelle société';

  @override
  String get setupOfferHint => 'Ce serveur n\'a pas encore de société.';

  @override
  String setupServer(String url) {
    return 'Serveur : $url';
  }

  @override
  String setupStepOf(int n, int total) {
    return 'Étape $n sur $total';
  }

  @override
  String get setupStepCompany => 'Société';

  @override
  String get setupStepRegion => 'Pays, devise et langue';

  @override
  String get setupStepAdmin => 'Administrateur';

  @override
  String get setupStepToken => 'Jeton d\'installation';

  @override
  String get setupStepReview => 'Vérification';

  @override
  String get setupCompanyName => 'Nom de la société';

  @override
  String get setupLegalName => 'Raison sociale (facultatif)';

  @override
  String get setupVatNumber => 'Numéro de TVA (facultatif)';

  @override
  String get setupCountry => 'Code pays (2 lettres, p. ex. BE)';

  @override
  String get setupCurrency => 'Devise (3 lettres, p. ex. EUR)';

  @override
  String get setupLanguage => 'Langue par défaut';

  @override
  String get setupAdminEmail => 'E-mail de l\'administrateur';

  @override
  String get setupAdminName => 'Nom de l\'administrateur';

  @override
  String get setupToken => 'Jeton d\'installation';

  @override
  String get setupTokenHelp => 'La valeur de BOOTSTRAP_TOKEN sur le serveur.';

  @override
  String get setupErrName => 'Saisissez le nom de la société.';

  @override
  String get setupErrVat =>
      'Un numéro de TVA comporte de 4 à 20 lettres et chiffres.';

  @override
  String get setupErrCountry => 'Saisissez un code pays de deux lettres.';

  @override
  String get setupErrCurrency =>
      'Saisissez un code de devise de trois lettres.';

  @override
  String get setupErrEmail => 'Saisissez une adresse e-mail valide.';

  @override
  String get setupErrAdminName => 'Saisissez le nom de l\'administrateur.';

  @override
  String get setupErrToken => 'Saisissez le jeton d\'installation.';

  @override
  String get setupNext => 'Suivant';

  @override
  String get setupBack => 'Retour';

  @override
  String get setupCreate => 'Créer la société';

  @override
  String get setupReviewHint =>
      'Vérifiez les données. Une société ne peut être créée qu\'une seule fois sur ce serveur.';

  @override
  String get setupErr403 => 'Le jeton d\'installation est absent ou incorrect.';

  @override
  String get setupErr404 =>
      'La configuration est désactivée sur ce serveur. Définissez BOOTSTRAP_TOKEN sur le serveur et redémarrez-le.';

  @override
  String get setupErr409 => 'Ce serveur a déjà une société.';

  @override
  String setupDone(String name) {
    return 'Société $name créée.';
  }

  @override
  String setupDoneDev(String email) {
    return 'Connexion en tant que $email.';
  }

  @override
  String setupDoneOidc(String email) {
    return 'Connectez-vous via votre fournisseur d\'identité avec $email : ce compte est l\'administrateur.';
  }

  @override
  String get setupToLogin => 'Aller à la connexion';

  @override
  String get setupAddOfferTitle => 'Configurer ce serveur ?';

  @override
  String get setupAddOfferBody =>
      'Ce serveur n\'a pas encore de société. En configurer une maintenant ?';

  @override
  String get setupLater => 'Plus tard';

  @override
  String get finMatchColumn => 'Rapprochement';

  @override
  String get finance => 'Finance';

  @override
  String get finSupplierInvoices => 'Factures fournisseur';

  @override
  String get finSettings => 'Paramètres';

  @override
  String get tabSupplierInvoice => 'Facture fournisseur';

  @override
  String get finNewInvoice => 'Nouvelle facture fournisseur';

  @override
  String get finNoInvoices => 'Aucune facture fournisseur trouvée.';

  @override
  String get finInvoiceNumber => 'Numéro de facture';

  @override
  String get finInternalNumber => 'Numéro interne';

  @override
  String get finInvoiceDate => 'Date de facture';

  @override
  String get finDueDate => 'Échéance';

  @override
  String get finStatusDraft => 'brouillon';

  @override
  String get finStatusMatched => 'rapprochée';

  @override
  String get finStatusDisputed => 'contestée';

  @override
  String get finStatusApproved => 'approuvée';

  @override
  String get finStatusPaid => 'payée';

  @override
  String get finMatchOk => 'conforme';

  @override
  String get finMatchNotReceived => 'non reçu';

  @override
  String get finMatchOverInvoiced => 'surfacturé';

  @override
  String get finMatchPriceVariance => 'écart de prix';

  @override
  String get finMatchNoPoLine => 'pas de ligne de commande';

  @override
  String get finOrderOptional => 'Commande d\'achat (facultatif)';

  @override
  String get finNoOrder => 'Pas de commande d\'achat';

  @override
  String get finOrderPrefillHint =>
      'Les lignes sont remplies avec les marchandises reçues et pas encore facturées.';

  @override
  String get finNumberRequired =>
      'Le numéro de facture est obligatoire (64 caractères au maximum).';

  @override
  String get finLineDescriptionRequired =>
      'Une ligne libre nécessite une description.';

  @override
  String get finVatInvalid =>
      'Le taux de TVA doit être compris entre 0 et 100, avec 2 décimales au maximum.';

  @override
  String get finOrdered => 'Commandé';

  @override
  String get finInvoiced => 'Facturé';

  @override
  String get finOrderPrice => 'Prix de commande';

  @override
  String get finInvoicePrice => 'Prix facturé';

  @override
  String get finVariance => 'Écart';

  @override
  String get finMatches =>
      'La facture correspond à la commande et aux réceptions.';

  @override
  String get finNotMatches =>
      'La facture ne correspond pas à la commande et aux réceptions.';

  @override
  String finTolerances(String qty, String price) {
    return 'Tolérances : quantité $qty %, prix $price %';
  }

  @override
  String get finSubmitMatch => 'Vérifier le rapprochement';

  @override
  String get finApprove => 'Approuver';

  @override
  String get finOverrideTitle => 'Approuver malgré l\'écart';

  @override
  String get finOverrideHelp =>
      'La facture ne correspond pas. Indiquez pourquoi vous l\'approuvez quand même ; le motif est enregistré avec l\'approbation.';

  @override
  String get finOverrideReason => 'Motif de dérogation';

  @override
  String get finReasonRequired => 'Un motif est obligatoire.';

  @override
  String get finDispute => 'Contester';

  @override
  String get finDisputeReason => 'Motif de la contestation';

  @override
  String get finReopen => 'Rouvrir';

  @override
  String get finMarkPaid => 'Marquer comme payée';

  @override
  String get finPaymentDate => 'Date de paiement';

  @override
  String get finPaymentReference => 'Référence de paiement';

  @override
  String get finDeleteDraft => 'Supprimer le brouillon';

  @override
  String finDeleteConfirm(String number) {
    return 'Supprimer la facture $number ? Cette action est irréversible.';
  }

  @override
  String get finNetTotal => 'Net';

  @override
  String get finGrossTotal => 'Total TTC';

  @override
  String get finDisputeReasonShown => 'Motif de la contestation';

  @override
  String get finOverrideShown => 'Motif de dérogation';

  @override
  String get finPaidOn => 'Payée le';

  @override
  String get finPurchaseOrder => 'Commande d\'achat';

  @override
  String get finQuantityTolerance => 'Tolérance de quantité (%)';

  @override
  String get finPriceTolerance => 'Tolérance de prix (%)';

  @override
  String get finToleranceInvalid => 'Saisissez un pourcentage entre 0 et 100.';

  @override
  String get finSettingsSaved => 'Paramètres enregistrés.';

  @override
  String get finSettingsHelp =>
      'Écart maximal accepté entre la commande et la facture avant qu\'une ligne soit comptée comme écart.';

  @override
  String get finCreateInvoice => 'Créer une facture fournisseur';

  @override
  String get userRoleFinance => 'Finance';

  @override
  String get moduleFinance => 'Finance';

  @override
  String get productionDivisionMembers => 'Membres';

  @override
  String get productionDivisionNoMembers => 'Aucun membre';

  @override
  String get productionScopeMine => 'Mes divisions';

  @override
  String get productionScopeAll => 'Toutes les divisions';

  @override
  String get productionScopeEmpty =>
      'Aucun ordre dans vos divisions. Les ordres sans division sont inclus.';

  @override
  String get productionShowAllDivisions => 'Afficher toutes les divisions';

  @override
  String get productionYourDivisions => 'Vos divisions';

  @override
  String get setupErrInsecure =>
      'Le jeton d\'installation n\'est pas envoyé par une connexion non chiffrée vers un autre ordinateur. Utilisez une adresse https:// (http simple n\'est autorisé que pour localhost).';

  @override
  String get setupUnavailable =>
      'La configuration n\'est pas disponible sur ce serveur : il a déjà une société, ou la configuration est désactivée.';

  @override
  String get setupErrRedirect =>
      'Le serveur a redirigé la requête, le jeton d\'installation n\'a donc pas été transmis. Vérifiez l\'adresse du serveur (utilisez l\'adresse https:// définitive).';

  @override
  String get tutSuppliersTitle => 'Fournisseurs';

  @override
  String get tutSuppliersSummary =>
      'Casquette : acheteur. Créez deux fournisseurs et donnez-leur un tarif pour vos composants.';

  @override
  String get tutSuppliersNeedsTitle => 'D\'abord le chapitre 1';

  @override
  String get tutSuppliersNeedsBody =>
      'Ce chapitre a besoin des quatre produits du chapitre 1 (TUT-MOTOR, TUT-FRAME, TUT-CTRL et TUT-CART) et ne les a pas trouvés. Retournez à la carte des chapitres et terminez d\'abord le chapitre 1.';

  @override
  String get tutSuppliersOpenTitle => 'Mettez la casquette d\'acheteur';

  @override
  String get tutSuppliersOpenBody =>
      'Vos composants doivent venir de quelque part. Ouvrez Achats dans le menu : la liste des fournisseurs est le premier segment.';

  @override
  String get tutSuppliersSupplierATitle => 'Le premier fournisseur';

  @override
  String get tutSuppliersSupplierABody =>
      'Créez un fournisseur avec le code TUT-SUP-A et le nom Voltaic Drives Ltd. Le code et le nom sont les seuls champs obligatoires ; les conditions de paiement, le numéro de TVA et les contacts peuvent suivre.';

  @override
  String get tutSuppliersSupplierBTitle => 'Un second fournisseur';

  @override
  String get tutSuppliersSupplierBBody =>
      'Un acheteur aime comparer. Créez un second fournisseur avec le code TUT-SUP-B et le nom Ironbridge Frames.';

  @override
  String get tutSuppliersOpenATitle => 'Ouvrez le premier fournisseur';

  @override
  String get tutSuppliersOpenABody =>
      'Ouvrez Voltaic Drives Ltd dans la liste. Son tarif se trouve en bas de l\'écran du fournisseur.';

  @override
  String get tutSuppliersPriceMotorTitle => 'Un prix pour le moteur';

  @override
  String get tutSuppliersPriceMotorBody =>
      'Ajoutez TUT-MOTOR au tarif : prix unitaire 120, délai 14 jours, quantité minimale de commande 5. Les commandes d\'achat s\'en servent pour préremplir leurs lignes.';

  @override
  String get tutSuppliersPriceMotorHint =>
      'Choisissez le produit avec la zone de recherche du dialogue ; tapez TUT-MOTOR.';

  @override
  String get tutSuppliersPriceFrameTitle => 'Un prix pour le châssis';

  @override
  String get tutSuppliersPriceFrameBody =>
      'Même chose pour TUT-FRAME : prix unitaire 45, délai 10 jours, quantité minimale 5.';

  @override
  String get tutSuppliersPriceControllerTitle => 'Un prix pour le contrôleur';

  @override
  String get tutSuppliersPriceControllerBody =>
      'Et TUT-CTRL : prix unitaire 30, délai 7 jours, quantité minimale 5. Ce fournisseur couvre désormais les trois composants.';

  @override
  String get tutSuppliersOpenBTitle => 'Ouvrez le second fournisseur';

  @override
  String get tutSuppliersOpenBBody =>
      'Retournez à la liste et ouvrez Ironbridge Frames.';

  @override
  String get tutSuppliersPriceMotorBTitle => 'Un prix concurrent';

  @override
  String get tutSuppliersPriceMotorBBody =>
      'Donnez aussi à ce fournisseur un prix pour TUT-MOTOR : prix unitaire 135, délai 5 jours, quantité minimale 1. Plus cher mais plus rapide : c\'est le genre de choix qu\'un tarif aide à faire.';

  @override
  String get tutSuppliersDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutSuppliersDoneBody =>
      'Un fournisseur est une fiche avec conditions de paiement et contacts ; son tarif le relie à des produits avec un prix, un délai et une quantité minimale. Ensuite : commander les marchandises.';

  @override
  String get tutBuyingTitle => 'Acheter et réceptionner';

  @override
  String get tutBuyingSummary =>
      'Casquettes : acheteur et réception. Commandez les composants, envoyez la commande et réceptionnez la marchandise en deux livraisons.';

  @override
  String get tutBuyingNeedsTitle => 'D\'abord les chapitres 1 et 2';

  @override
  String get tutBuyingNeedsBody =>
      'Ce chapitre a besoin des produits du chapitre 1 et du fournisseur Voltaic Drives Ltd avec son tarif du chapitre 2, et n\'a pas trouvé les produits. Terminez d\'abord ces chapitres.';

  @override
  String get tutBuyingOpenTitle => 'La liste des commandes';

  @override
  String get tutBuyingOpenBody =>
      'Ouvrez Achats. À côté de Fournisseurs se trouve un segment pour les commandes d\'achat ; ouvrez-le.';

  @override
  String get tutBuyingOrderTitle => 'Commandez les composants';

  @override
  String get tutBuyingOrderBody =>
      'Créez une commande d\'achat pour Voltaic Drives Ltd avec trois lignes : TUT-MOTOR, TUT-FRAME et TUT-CTRL, 30 pièces chacune. Les prix viennent du tarif.';

  @override
  String get tutBuyingOrderHint =>
      'Choisissez d\'abord le fournisseur : les prix des lignes se remplissent une fois son tarif chargé. Utilisez Ajouter une ligne pour le deuxième et le troisième composant.';

  @override
  String get tutBuyingOpenOrderTitle => 'L\'écran de la commande';

  @override
  String get tutBuyingOpenOrderBody =>
      'Ouvrez la commande que vous venez de créer. Une commande d\'achat est d\'abord un brouillon ; les boutons en haut suivent sa vie : approuver, envoyer, réceptionner.';

  @override
  String get tutBuyingApproveTitle => 'Approuvez la commande';

  @override
  String get tutBuyingApproveBody =>
      'Approuver est un droit distinct : un acheteur prépare des commandes qu\'un responsable libère. En tant qu\'admin, vous portez les deux casquettes : appuyez sur Approuver.';

  @override
  String get tutBuyingSendTitle => 'Envoyez-la au fournisseur';

  @override
  String get tutBuyingSendBody =>
      'Appuyez sur Envoyer. La commande est marquée comme envoyée et le fournisseur la reçoit. Dans les environnements de test et de tutoriel, le courrier sortant n\'est écrit que dans des fichiers sur le serveur : rien ne sort.';

  @override
  String get tutBuyingReceivePartTitle => 'La première livraison arrive';

  @override
  String get tutBuyingReceivePartBody =>
      'Mettez la casquette de réception. Appuyez sur Réceptionner les marchandises, choisissez l\'emplacement MAIN de l\'entrepôt et enregistrez 10 pièces de chaque composant, moins que commandé. La commande devient partiellement reçue.';

  @override
  String get tutBuyingReceivePartHint =>
      'Modifiez la quantité de chaque ligne dans le dialogue ; la quantité restante est indiquée à côté. Le numéro de bon de livraison est facultatif.';

  @override
  String get tutBuyingReceiveRestTitle => 'Le reste arrive';

  @override
  String get tutBuyingReceiveRestBody =>
      'Réceptionnez de la même façon les 20 pièces restantes de chaque composant. Quand tout est arrivé, la commande est entièrement reçue ; chaque livraison garde son propre bon de réception.';

  @override
  String get tutBuyingStockTitle => 'Regardez le stock';

  @override
  String get tutBuyingStockBody =>
      'Ouvrez Stock. Les 30 moteurs, châssis et contrôleurs sont disponibles dans l\'entrepôt MAIN. Chaque réception a créé un mouvement de stock : la quantité reste toujours traçable.';

  @override
  String get tutBuyingDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutBuyingDoneBody =>
      'Une commande d\'achat passe de brouillon à approuvée, envoyée, reçue. Les marchandises peuvent arriver en plusieurs livraisons et chacune alimente le stock. La facture du fournisseur suit.';

  @override
  String get tutInvoicesTitle => 'Contrôler les factures';

  @override
  String get tutInvoicesSummary =>
      'Casquette : comptable. Enregistrez des factures fournisseur, lisez le rapprochement à trois, approuvez, contestez et payez.';

  @override
  String get tutInvoicesNeedsTitle => 'D\'abord le chapitre 3';

  @override
  String get tutInvoicesNeedsBody =>
      'Ce chapitre a besoin de la commande d\'achat du chapitre 3, entièrement reçue, et elle ne l\'est pas (encore). Terminez d\'abord le chapitre 3.';

  @override
  String get tutInvoicesOpenOrderTitle => 'Retour à la commande';

  @override
  String get tutInvoicesOpenOrderBody =>
      'La facture du fournisseur arrive. Rouvrez la commande d\'achat du chapitre 3 : dès que des marchandises sont reçues, elle propose un raccourci pour enregistrer la facture.';

  @override
  String get tutInvoicesCreateTitle => 'Enregistrez la facture';

  @override
  String get tutInvoicesCreateBody =>
      'Appuyez sur Créer une facture fournisseur. Saisissez le numéro de facture du fournisseur, par exemple TUT-INV-001, et enregistrez. Les lignes sont préremplies d\'après ce qui a été commandé et reçu.';

  @override
  String get tutInvoicesCreateHint =>
      'La date de facture et l\'échéance valent par défaut aujourd\'hui et les conditions de paiement du fournisseur.';

  @override
  String get tutInvoicesMatchTitle => 'Le rapprochement à trois';

  @override
  String get tutInvoicesMatchBody =>
      'Le bandeau compare trois documents : ce qui a été commandé, reçu et facturé, ligne par ligne. Vert signifie qu\'ils concordent dans les tolérances, indiquées dans le bandeau. Appuyez sur Suivant après avoir regardé.';

  @override
  String get tutInvoicesApproveTitle => 'Approuvez la facture';

  @override
  String get tutInvoicesApproveBody =>
      'Le rapprochement est vert : appuyez sur Approuver. Une facture approuvée est prête à être payée.';

  @override
  String get tutInvoicesSecondTitle => 'Une facture suspecte';

  @override
  String get tutInvoicesSecondBody =>
      'Une seconde facture arrive de Voltaic Drives Ltd, cette fois sans commande d\'achat : dans Finance, créez une facture fournisseur pour ce fournisseur, numéro TUT-INV-002, laissez la commande vide et ajoutez une ligne avec la description Moteurs, quantité 10, prix unitaire 150.';

  @override
  String get tutInvoicesSecondHint =>
      'Le vrai prix du moteur est 120 et cette ligne n\'a aucune ligne de commande à comparer. L\'app ne permet pas de changer les prix d\'une facture liée à une commande : une facture en texte libre sert donc ici à voir un écart.';

  @override
  String get tutInvoicesMismatchTitle => 'Le rapprochement échoue';

  @override
  String get tutInvoicesMismatchBody =>
      'Le bandeau est orange : une ligne en texte libre ne peut être rapprochée de rien, elle ne peut donc être vérifiée ni avec une commande ni avec une réception. La ligne indique pourquoi. Appuyez sur Suivant après avoir regardé.';

  @override
  String get tutInvoicesDisputeTitle => 'Contestez la facture';

  @override
  String get tutInvoicesDisputeBody =>
      'Appuyez sur Contester et donnez un motif, par exemple le prix ne correspond pas à l\'accord. Une facture contestée ne peut pas être payée avant d\'être rouverte. (Un approbateur peut aussi approuver un rapprochement échoué avec un motif de dérogation, conservé sur la facture.)';

  @override
  String get tutInvoicesTolerancesTitle => 'Les tolérances';

  @override
  String get tutInvoicesTolerancesBody =>
      'L\'écart permis d\'une facture est un réglage : ouvrez le segment Réglages de Finance pour voir les tolérances de quantité et de prix en pourcentage. Regardez puis appuyez sur Suivant ; les modifier est votre choix.';

  @override
  String get tutInvoicesPayTitle => 'Payez la bonne facture';

  @override
  String get tutInvoicesPayBody =>
      'Ouvrez la première facture fournisseur que vous avez enregistrée (celle qui concordait et a été approuvée) et appuyez sur Marquer comme payée. Saisissez une référence de paiement comme TUT-PAY-001. L\'app enregistre le paiement ; le virement se fait ailleurs.';

  @override
  String get tutInvoicesDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutInvoicesDoneBody =>
      'Le rapprochement à trois compare commande, réception et facture avant tout paiement. Les factures conformes sont approuvées et payées, les douteuses contestées. Ensuite : fabriquer les chariots.';

  @override
  String get tutManufacturingTitle => 'Fabrication';

  @override
  String get tutManufacturingSummary =>
      'Casquettes : responsable de production et opérateur. Créez une division puis fabriquez cinq chariots avec les composants.';

  @override
  String get tutManufacturingNeedsTitle => 'D\'abord les chapitres 1 à 3';

  @override
  String get tutManufacturingNeedsBody =>
      'Ce chapitre a besoin du chariot avec sa nomenclature (chapitre 1) et de composants en stock (chapitre 3), et n\'a pas trouvé les produits. Terminez d\'abord ces chapitres.';

  @override
  String get tutManufacturingOpenDivisionsTitle => 'Divisions';

  @override
  String get tutManufacturingOpenDivisionsBody =>
      'Le travail de production est organisé en divisions, par exemple une ligne d\'assemblage. Seul un administrateur les définit. Ouvrez Production et utilisez le bouton roue dentée en haut à droite pour atteindre les divisions.';

  @override
  String get tutManufacturingDivisionTitle => 'Créez une division';

  @override
  String get tutManufacturingDivisionBody =>
      'Ajoutez une division avec le code TUT-ASM et le nom Tutorial assembly, et cochez-vous dans la liste des membres : les membres sont les opérateurs de la division.';

  @override
  String get tutManufacturingDivisionHint =>
      'Le dialogue liste les utilisateurs de la société ; cochez la pastille à votre nom.';

  @override
  String get tutManufacturingQueueTitle => 'La file de production';

  @override
  String get tutManufacturingQueueBody =>
      'Retournez à Production. Dans l\'en-tête de la file, choisissez Mes divisions : cela montre les ordres de vos divisions plus ceux sans division, rien de non attribué n\'est caché. Vous êtes membre d\'une division, c\'est donc le réglage par défaut ; choisissez Toutes les divisions pour tout voir.';

  @override
  String get tutManufacturingReleaseTitle => 'Lancez un ordre de production';

  @override
  String get tutManufacturingReleaseBody =>
      'Appuyez sur Fabriquer pour le stock, choisissez TUT-CART et la quantité 5, puis lancez. La nomenclature est figée et les composants sont réservés. Normalement la production part d\'une ligne de commande client ; vous le verrez au chapitre 9.';

  @override
  String get tutManufacturingReleaseHint =>
      'Seuls les produits fabriqués avec une nomenclature active peuvent être lancés.';

  @override
  String get tutManufacturingAssignTitle => 'Attribuez-le à la division';

  @override
  String get tutManufacturingAssignBody =>
      'Le nouvel ordre est ouvert. Choisissez la division Tutorial assembly dans le champ Division et appuyez sur Enregistrer, pour qu\'il apparaisse dans la file de cette division.';

  @override
  String get tutManufacturingStartTitle => 'Démarrez le travail';

  @override
  String get tutManufacturingStartBody =>
      'Mettez la casquette d\'opérateur et appuyez sur Démarrer. L\'ordre passe de lancé à en cours.';

  @override
  String get tutManufacturingCompleteTitle => 'Terminez l\'ordre';

  @override
  String get tutManufacturingCompleteBody =>
      'Appuyez sur Terminer. Le dialogue montre la quantité produite (5) et les composants consommés. Confirmez : les composants sortent du stock et cinq chariots finis y entrent.';

  @override
  String get tutManufacturingCompleteHint =>
      'Laissez les valeurs prévues ; le dialogue permet d\'enregistrer rebuts ou surconsommation si la réalité diffère.';

  @override
  String get tutManufacturingStockTitle => 'Vérifiez le stock';

  @override
  String get tutManufacturingStockBody =>
      'Ouvrez Stock : TUT-CART en a maintenant 5 et chaque composant a baissé de 5 (25 restants de chacun). La production relie les achats à la vente.';

  @override
  String get tutManufacturingDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutManufacturingDoneBody =>
      'Les divisions regroupent les opérateurs ; un ordre de production fige la nomenclature, réserve les composants, est démarré puis terminé et transforme les composants en produits finis. Ensuite : les prix.';

  @override
  String get tutPricesTitle => 'Prix et zones';

  @override
  String get tutPricesSummary =>
      'Casquette : responsable des ventes. Créez une zone de prix et donnez au chariot un prix dans deux zones.';

  @override
  String get tutPricesNeedsTitle => 'D\'abord le chapitre 1';

  @override
  String get tutPricesNeedsBody =>
      'Ce chapitre a besoin du chariot du chapitre 1 et ne l\'a pas trouvé. Terminez d\'abord le chapitre 1.';

  @override
  String get tutPricesOpenAdminTitle => 'Ouvrez l\'administration';

  @override
  String get tutPricesOpenAdminBody =>
      'Un prix dépend de la zone du client : un pays ou marché avec son propre tarif. Les zones se gèrent sous Administration. Ouvrez Administration et choisissez le segment Zones de prix ; la société a déjà les zones Z1 à Z5.';

  @override
  String get tutPricesZoneTitle => 'Créez une zone';

  @override
  String get tutPricesZoneBody =>
      'Ajoutez une zone de prix avec le code TUT-EXPORT et le nom Zone export. Les clients reçoivent une zone plus tard, à leur création.';

  @override
  String get tutPricesZoneHint =>
      'Choisissez d\'abord le segment Zones de prix en haut de la page Administration.';

  @override
  String get tutPricesOpenCartTitle => 'Ouvrez le chariot';

  @override
  String get tutPricesOpenCartBody =>
      'Ouvrez le produit TUT-CART depuis la liste Produits. Son premier onglet, Prix, contient les prix par zone.';

  @override
  String get tutPricesPriceExportTitle => 'Un prix dans la nouvelle zone';

  @override
  String get tutPricesPriceExportBody =>
      'Appuyez sur Nouveau prix, choisissez la zone TUT-EXPORT, saisissez le prix unitaire 1450 (hors TVA) et enregistrez.';

  @override
  String get tutPricesPriceExportHint =>
      'La date de début de validité est aujourd\'hui par défaut ; une date ultérieure programme un changement de prix.';

  @override
  String get tutPricesPriceHomeTitle => 'Un prix dans une autre zone';

  @override
  String get tutPricesPriceHomeBody =>
      'Ajoutez un second prix pour le chariot dans l\'une des zones existantes, par exemple Z1 à 1200. Le même produit peut maintenant coûter différemment selon la zone du client.';

  @override
  String get tutPricesDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutPricesDoneBody =>
      'Une zone de prix regroupe les clients qui ont le même tarif et un produit a un prix par zone et par date. Les devis prennent le prix de la zone du client. Ensuite : un nouveau client écrit.';

  @override
  String get tutCustomerTitle => 'Un nouveau client écrit';

  @override
  String get tutCustomerSummary =>
      'Casquettes : ventes et helpdesk. Un e-mail client devient un ticket ; l\'expéditeur est nouveau : vous demandez les coordonnées de la société et créez le client.';

  @override
  String get tutCustomerNeedsTitle => 'D\'abord le chapitre 6';

  @override
  String get tutCustomerNeedsBody =>
      'Ce chapitre a besoin de la zone de prix TUT-EXPORT du chapitre 6 (le nouveau client la reçoit) et ne l\'a pas trouvée. Terminez d\'abord les chapitres précédents.';

  @override
  String get tutCustomerMail1Title => 'Un e-mail arrive';

  @override
  String get tutCustomerMail1Body =>
      'Quelqu\'un que vous ne connaissez pas demande un devis pour votre chariot. Une vraie boîte aux lettres livrerait le message elle-même ; ici le bouton ci-dessous joue le client et remet un e-mail tout prêt (de Maya Okafor, example.test) au helpdesk, exactement comme l\'importateur de courrier.';

  @override
  String get tutCustomerMail1Action => 'Simuler l\'e-mail du client';

  @override
  String get tutCustomerOpenHelpdeskTitle => 'Le ticket';

  @override
  String get tutCustomerOpenHelpdeskBody =>
      'Chaque message entrant devient un ticket. Ouvrez Helpdesk : le ticket de Maya Okafor est dans la liste.';

  @override
  String get tutCustomerOpenTicketTitle => 'Ouvrez le ticket';

  @override
  String get tutCustomerOpenTicketBody =>
      'Ouvrez le ticket. La conversation est à gauche, ses propriétés à droite. Aucun client n\'est encore lié, car personne avec cette adresse n\'existe dans le système.';

  @override
  String get tutCustomerReplyTitle => 'Demandez les coordonnées';

  @override
  String get tutCustomerReplyBody =>
      'Répondez à Maya : remerciez-la et demandez la raison sociale, le numéro de TVA et l\'adresse, puis appuyez sur Envoyer. La réponse est mise en file pour le worker de courrier. Dans les environnements de test et de tutoriel, le courrier sortant n\'est écrit que dans des fichiers du serveur : Maya ne reçoit rien.';

  @override
  String get tutCustomerReplyHint =>
      'Vérifiez que l\'onglet Réponse (pas Note interne) est sélectionné au-dessus de la zone de message.';

  @override
  String get tutCustomerMail2Title => 'Le client répond';

  @override
  String get tutCustomerMail2Body =>
      'Utilisez le bouton pour jouer la réponse de Maya. C\'est une réponse à son premier message : elle arrive dans le même ticket comme nouveau message, avec raison sociale, numéro de TVA et adresse.';

  @override
  String get tutCustomerMail2Action => 'Simuler l\'e-mail du client';

  @override
  String get tutCustomerReadDetailsTitle => 'Lisez les coordonnées';

  @override
  String get tutCustomerReadDetailsBody =>
      'Retournez au ticket (rouvrez-le s\'il n\'affiche pas encore le nouveau message) et lisez la réponse de Maya : société Brightwheel Logistics BV, numéro de TVA BE0123456749, Voorbeeldlaan 12, 9000 Gand, Belgique. Appuyez sur Suivant quand vous les avez.';

  @override
  String get tutCustomerCreateCustomerTitle => 'Créez le client';

  @override
  String get tutCustomerCreateCustomerBody =>
      'Dans les propriétés du ticket, appuyez sur Nouveau client. Saisissez le nom Brightwheel Logistics BV, un code comme TUT-CUST, le numéro de TVA, l\'adresse, et choisissez la zone de prix TUT-EXPORT. Le ticket est lié au nouveau client à l\'enregistrement.';

  @override
  String get tutCustomerCreateCustomerHint =>
      'Rue Voorbeeldlaan 12, code postal 9000, ville Gand, pays BE. La langue et les conditions de paiement peuvent rester telles quelles.';

  @override
  String get tutCustomerLinkedTitle => 'Le ticket connaît son client';

  @override
  String get tutCustomerLinkedBody =>
      'Le ticket affiche maintenant le client et de nouveaux boutons apparaissent : créer une piste ou démarrer un devis directement depuis le ticket. Le chapitre suivant fait le devis. Appuyez sur Suivant.';

  @override
  String get tutCustomerDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutCustomerDoneBody =>
      'Le courrier entrant devient des tickets, une réponse demande au client ce qui manque, et un client peut être créé depuis le ticket pour que tout reste lié. Ensuite : le devis.';

  @override
  String get tutQuotationTitle => 'Le devis';

  @override
  String get tutQuotationSummary =>
      'Casquette : commercial. Proposez 8 chariots au nouveau client, obtenez l\'avis de la production sur le délai et envoyez.';

  @override
  String get tutQuotationNeedsTitle => 'D\'abord le chapitre 7';

  @override
  String get tutQuotationNeedsBody =>
      'Ce chapitre a besoin du client Brightwheel Logistics BV du chapitre 7 et ne l\'a pas trouvé. Terminez d\'abord le chapitre 7.';

  @override
  String get tutQuotationOpenQuotationsTitle => 'Devis';

  @override
  String get tutQuotationOpenQuotationsBody =>
      'Ouvrez Devis dans le menu. Cette liste contient chaque devis avec son numéro, son client et son statut.';

  @override
  String get tutQuotationCreateTitle => 'Rédigez le devis';

  @override
  String get tutQuotationCreateBody =>
      'Appuyez sur Nouvelle offre, choisissez Brightwheel Logistics BV, ajoutez TUT-CART en quantité 8 et enregistrez le brouillon. Le prix unitaire vient de la zone de prix du client, TUT-EXPORT : ce sont les 1450 saisis au chapitre 6.';

  @override
  String get tutQuotationCreateHint =>
      'Utilisez la recherche de produit dans les lignes ; tapez TUT-CART. Si le client n\'est pas présélectionné, cherchez Brightwheel.';

  @override
  String get tutQuotationLeadTitle => 'Combien de temps cela prendra-t-il ?';

  @override
  String get tutQuotationLeadBody =>
      'La client a demandé un délai de livraison. Franchement : l\'app ne calcule pas encore automatiquement les délais et un devis n\'a pas de champ date de livraison. Demandez donc à la production (mettez cette casquette, regardez la file de production et les composants en stock) et écrivez la réponse dans les notes du devis, par exemple : livraison environ 3 semaines après commande. Enregistrez le brouillon.';

  @override
  String get tutQuotationLeadHint =>
      'Sur une commande vous pouvez poser une question à la production sous forme de ticket (vu au chapitre 9) ; les devis n\'ont pas encore ce bouton.';

  @override
  String get tutQuotationSendTitle => 'Envoyez le devis';

  @override
  String get tutQuotationSendBody =>
      'Appuyez sur Marquer comme envoyé. Dès lors le devis est figé : il ne peut plus qu\'être accepté, refusé ou révisé. (Ce bouton n\'envoie pas de courrier ; vous envoyez le PDF vous-même ou répondez dans le ticket.)';

  @override
  String get tutQuotationPdfTitle => 'Le PDF';

  @override
  String get tutQuotationPdfBody =>
      'Le bouton PDF montre le devis tel que le client le verrait. Il est produit sur le serveur avec un outil de composition ; sans cet outil sur le serveur vous obtenez un message d\'erreur, sans autre conséquence. Regardez si vous voulez, puis appuyez sur Suivant.';

  @override
  String get tutQuotationPdfHint =>
      'Rien ne casse si le PDF échoue : le devis est déjà envoyé.';

  @override
  String get tutQuotationDoneTitle => 'Ce que vous avez appris';

  @override
  String get tutQuotationDoneBody =>
      'Un devis prend le prix de la zone du client, porte des notes et se fige à l\'envoi. Les délais restent votre appréciation, avec la production. Ensuite : le client veut une modification.';

  @override
  String get tutChangeTitle => 'Modification, commande, production';

  @override
  String get tutChangeSummary =>
      'Casquettes : ventes et production. Révisez le devis, transformez-le en commande, fabriquez les chariots et quelques-uns de plus pour le stock.';

  @override
  String get tutChangeNeedsTitle => 'D\'abord le chapitre 8';

  @override
  String get tutChangeNeedsBody =>
      'Ce chapitre a besoin du devis envoyé au chapitre 8 et ne l\'a pas trouvé. Terminez d\'abord le chapitre 8.';

  @override
  String get tutChangeMail3Title => 'Le client répond de nouveau';

  @override
  String get tutChangeMail3Body =>
      'Maya est satisfaite du devis mais veut 10 chariots au lieu de 8. Utilisez le bouton pour jouer son e-mail ; il rejoint le même ticket.';

  @override
  String get tutChangeMail3Action => 'Simuler l\'e-mail du client';

  @override
  String get tutChangeOpenQuoteTitle => 'Ouvrez le devis envoyé';

  @override
  String get tutChangeOpenQuoteBody =>
      'Un devis envoyé est figé : une modification passe par une nouvelle révision. Ouvrez le devis du chapitre 8.';

  @override
  String get tutChangeReviseTitle => 'Créez une révision';

  @override
  String get tutChangeReviseBody =>
      'Appuyez sur Nouvelle révision et choisissez Garder les prix convenus. L\'ancienne révision est marquée remplacée et un nouveau brouillon avec le même numéro s\'ouvre.';

  @override
  String get tutChangeReviseHint =>
      'Mettre à jour les prix recalculerait avec le tarif du jour ; ici le client garde le prix convenu.';

  @override
  String get tutChangeEditTitle => 'Modifiez la quantité';

  @override
  String get tutChangeEditBody =>
      'Mettez la quantité de TUT-CART à 10 et enregistrez le brouillon.';

  @override
  String get tutChangeEditHint =>
      'Les notes de la première révision ont été copiées ; adaptez-les si le délai change.';

  @override
  String get tutChangeSendTitle => 'Envoyez la révision';

  @override
  String get tutChangeSendBody =>
      'Marquez la nouvelle révision comme envoyée, comme avant.';

  @override
  String get tutChangeAcceptTitle => 'Le client accepte';

  @override
  String get tutChangeAcceptBody =>
      'Maya est d\'accord avec la nouvelle révision : appuyez sur Acceptée pour l\'enregistrer.';

  @override
  String get tutChangeConvertTitle => 'Transformez-le en commande client';

  @override
  String get tutChangeConvertBody =>
      'Appuyez sur Convertir en commande. Une commande client brouillon est créée à partir de la révision acceptée et s\'ouvre.';

  @override
  String get tutChangeConvertHint =>
      'Le dialogue demande la référence propre du client ; saisissez par exemple TUT-PO-1 ou laissez vide.';

  @override
  String get tutChangeOpenOrderTitle => 'La commande client';

  @override
  String get tutChangeOpenOrderBody =>
      'Si la commande ne s\'est pas ouverte seule, ouvrez-la depuis Commandes. Elle contient les 10 chariots, le prix et la référence client. Les commandes passent de brouillon à envoyée puis confirmée.';

  @override
  String get tutChangeSendOrderTitle => 'Envoyez la confirmation de commande';

  @override
  String get tutChangeSendOrderBody =>
      'Appuyez sur Envoyer la confirmation de commande. La commande passe à envoyée : le client peut maintenant la confirmer.';

  @override
  String get tutChangeSendOrderHint =>
      'Produire le document de confirmation demande l\'outil de composition du serveur ; s\'il manque, le serveur refuse cette étape et il faut un serveur qui l\'a pour continuer.';

  @override
  String get tutChangeConfirmTitle => 'Confirmez au nom du client';

  @override
  String get tutChangeConfirmBody =>
      'Maya a déjà dit oui par e-mail : appuyez sur Confirmer au nom du client et ajoutez une note comme confirmé par e-mail. La commande est confirmée et peut aller en production.';

  @override
  String get tutChangeReleaseTitle => 'À lancer';

  @override
  String get tutChangeReleaseBody =>
      'Mettez la casquette de production. Ouvrez Production > À lancer : la ligne de commande confirmée avec 10 chariots attend. Appuyez sur Lancer en production pour créer l\'ordre de production de cette ligne.';

  @override
  String get tutChangeStartTitle => 'Démarrez la production';

  @override
  String get tutChangeStartBody =>
      'Appuyez sur Démarrer sur le nouvel ordre de production.';

  @override
  String get tutChangeCompleteTitle => 'Terminez la production';

  @override
  String get tutChangeCompleteBody =>
      'Appuyez sur Terminer et confirmez les 10 chariots. Les composants sont consommés et les chariots vont à la commande.';

  @override
  String get tutChangeReadyTitle => 'Prêt à expédier';

  @override
  String get tutChangeReadyBody =>
      'Rouvrez la commande : toutes ses lignes produites, elle est prête à expédier. La livraison (préparation, expédition, facturation du client) sort de ce tutoriel. Appuyez sur Suivant.';

  @override
  String get tutChangeStockTitle => 'Quelques-uns de plus pour le stock';

  @override
  String get tutChangeStockBody =>
      'La production devance souvent les commandes. Ouvrez Production, appuyez sur Fabriquer pour le stock et lancez encore 4 chariots TUT-CART. Sans commande ils arrivent simplement en stock à la fin.';

  @override
  String get tutChangeStockHint =>
      'Vous pouvez démarrer et terminer cet ordre comme au chapitre 5, ou le laisser lancé.';

  @override
  String get tutChangeDoneTitle => 'Bravo : toute l\'histoire';

  @override
  String get tutChangeDoneBody =>
      'Vous êtes passé des fournisseurs aux achats, factures, production, prix, un ticket, un nouveau client, un devis révisé, une commande et la production pour la commande et pour le stock. Et ensuite : livraisons et expéditions, réparations, service terrain et rapports ont chacun leur entrée de menu. Tout chapitre peut être rejoué depuis la carte des chapitres ; les étapes déjà faites sont sautées.';

  @override
  String get tutInvoicesOpenSecondTitle => 'Ouvrez la facture suspecte';

  @override
  String get tutInvoicesOpenSecondBody =>
      'Ouvrez la facture TUT-INV-002, celle que vous venez d\'enregistrer, depuis la liste de Finance.';

  @override
  String tutActionFailed(String reason) {
    return 'Impossible d\'envoyer l\'e-mail simulé : $reason. Réessayez.';
  }

  @override
  String get tutActionForbidden =>
      'Vous n\'avez pas le droit d\'importer des e-mails dans le helpdesk (il faut le droit d\'écriture du helpdesk). Demandez à un administrateur ou connectez-vous comme tel, puis réessayez.';
}
