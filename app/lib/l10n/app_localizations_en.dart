// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accepted => 'Accepted';

  @override
  String get accessToken => 'Access token';

  @override
  String get account => 'Account';

  @override
  String get action => 'Action';

  @override
  String get actionAddTag => 'Add tag';

  @override
  String get actionSetCategory => 'Set category';

  @override
  String get actionSetInternal => 'Mark as internal';

  @override
  String get actionSetOwner => 'Set owner';

  @override
  String get actionSetPriority => 'Set priority';

  @override
  String get actionSetTeam => 'Set team';

  @override
  String get actions => 'Actions';

  @override
  String get activate => 'Activate';

  @override
  String get active => 'Active';

  @override
  String activeSince(String date) {
    return 'Active since $date. Changes go through a new revision.';
  }

  @override
  String get add => 'Add';

  @override
  String get addAction => 'Add action';

  @override
  String get addClosure => 'Add closure';

  @override
  String get addComponent => 'Add component';

  @override
  String get addComponentBySerial =>
      'Add component by serial number (in stock)';

  @override
  String get addEquipment => 'Add equipment';

  @override
  String get addMember => 'Add member';

  @override
  String get addNote => 'Add note';

  @override
  String get addNoteHint => 'Add an internal note';

  @override
  String get addPart => 'Add part';

  @override
  String get addPhone => 'Add phone number';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get addProduct => 'Add product';

  @override
  String get addRebate => 'Add rebate';

  @override
  String get addTag => 'Add tag';

  @override
  String get addTask => 'Add task';

  @override
  String addedBy(String date, String name) {
    return 'added $date by $name';
  }

  @override
  String get addressForm => 'Form of address';

  @override
  String get addressFormal => 'Formal (Dear Mr. Smith)';

  @override
  String get addressInformal => 'Informal (Hi Sam)';

  @override
  String get addVisit => 'Add visit';

  @override
  String get agreed => 'Agreed';

  @override
  String get all => 'All';

  @override
  String get allCategories => 'All categories';

  @override
  String get allOwners => 'All owners';

  @override
  String get allProducts => 'All products';

  @override
  String get allStatuses => 'All statuses';

  @override
  String get allTags => 'All tags';

  @override
  String get allTeams => 'All teams';

  @override
  String get always => 'always';

  @override
  String andMore(int count) {
    return '… and $count more';
  }

  @override
  String get announceRepair => 'Announce a repair';

  @override
  String get announcedNotReceived => 'Announced, not received yet';

  @override
  String answerFallback(String ticketLanguage, String usedLanguage) {
    return 'No $ticketLanguage text yet: the $usedLanguage text was used. Translate it before sending.';
  }

  @override
  String get anyValue => 'Any';

  @override
  String get appLanguage => 'Language';

  @override
  String get appTitle => 'TradoCraft';

  @override
  String get apply => 'Apply';

  @override
  String get assignTo => 'Assign to';

  @override
  String get attachFile => 'Attach file';

  @override
  String get attachments => 'Attachments';

  @override
  String get attachmentsHelp => 'Images (JPEG, PNG, WebP) and PDF, up to 12 MB';

  @override
  String get automatic => 'Automatic';

  @override
  String get automationHelp =>
      'Rules run in this order when a ticket is created, changed or answered by the customer. A rule applies when all its conditions match. Rules change tickets only; they send no e-mail.';

  @override
  String get automationRules => 'Automation rules';

  @override
  String get autoRenew => 'Renew automatically';

  @override
  String get backIntoWork => 'Back into work';

  @override
  String get backToCurrentRevision => 'Back to current revision';

  @override
  String get backlogByOwner => 'Open tickets by owner';

  @override
  String get backlogByPriority => 'Open tickets by priority';

  @override
  String get backlogByStatus => 'Open tickets by status';

  @override
  String get backlogByTeam => 'Open tickets by team';

  @override
  String get basisBusiness => 'business hours';

  @override
  String get basisElapsed => 'elapsed time';

  @override
  String get billOfMaterials => 'Bill of materials';

  @override
  String get billable => 'Billable';

  @override
  String get bomActive => 'active';

  @override
  String get bomObsolete => 'obsolete';

  @override
  String get bomRev => 'BOM rev.';

  @override
  String get bomRevision => 'BOM revision';

  @override
  String get breached => 'Breached';

  @override
  String get breachesByTeam => 'SLA breaches by team';

  @override
  String get builtInto => 'Built into';

  @override
  String get bulkKeepsQuotes =>
      'Quotations before this date keep using the current prices';

  @override
  String get bulkPriceChange => 'Bulk price change';

  @override
  String get businessHours => 'Business hours';

  @override
  String get businessHoursEnabled => 'Count business hours only';

  @override
  String get businessHoursHelp =>
      'Service level times count only the hours below, on days that are not holidays. Switched off, they run around the clock.';

  @override
  String get businessHoursInvalidTime => 'Enter times as HH:MM.';

  @override
  String get businessHoursRecompute =>
      'Saving recalculates the due times of all open tickets.';

  @override
  String get businessHoursSaved => 'Saved. Open tickets were recalculated.';

  @override
  String get byStage => 'by stage';

  @override
  String get callIncoming => 'Incoming call';

  @override
  String get callLogged => 'Call logged';

  @override
  String get callMinutes => 'Duration (minutes)';

  @override
  String get callOutgoing => 'Outgoing call';

  @override
  String get callSummary => 'What was discussed';

  @override
  String callWith(String name) {
    return 'Call with $name';
  }

  @override
  String get canStillKeep => 'You can still keep the agreed prices.';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelJob => 'Cancel job';

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get cancelReasonLabel => 'Reason for cancelling';

  @override
  String get cancelRepair => 'Cancel repair';

  @override
  String get cancelled => 'cancelled';

  @override
  String cancelledReason(String reason) {
    return 'Cancelled: $reason';
  }

  @override
  String get cannotConfirmNewer =>
      'A newer revision of this order is being prepared. You can confirm it once it has been sent to you.';

  @override
  String get cannotConfirmOther => 'This order cannot be confirmed.';

  @override
  String get captureSignature => 'Capture signature';

  @override
  String get category => 'Category';

  @override
  String get categoryComplaint => 'complaint';

  @override
  String get categoryLead => 'lead (new business)';

  @override
  String get categoryOrderConfirmation => 'order confirmation';

  @override
  String get categoryOther => 'other';

  @override
  String get categoryProductionQuestion => 'production question';

  @override
  String get categoryQuestion => 'question';

  @override
  String get categoryQuoteChange => 'quote change';

  @override
  String get categoryService => 'service / repair';

  @override
  String get cc => 'Cc';

  @override
  String get change => 'Change';

  @override
  String get changePriority => 'Change priority';

  @override
  String get channel => 'Channel';

  @override
  String get channelEmail => 'E-mail';

  @override
  String get channelInternal => 'Internal question';

  @override
  String get channelManual => 'Entered by hand';

  @override
  String get channelPhone => 'Phone';

  @override
  String get channelPortal => 'Portal';

  @override
  String get checklistOnePerLine => 'Checklist (one task per line)';

  @override
  String get chooseCustomerAndLine =>
      'Choose a customer and add at least one valid line.';

  @override
  String get choosePhoto => 'Choose from gallery';

  @override
  String get chooseRebateTarget =>
      'Choose a product or family and enter a percentage.';

  @override
  String get chooseZonePrice => 'Choose a zone and enter a price.';

  @override
  String get city => 'City';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get closedLabel => 'closed';

  @override
  String get closes => 'Closes';

  @override
  String get closureKindCollectiveLeave => 'Collective leave';

  @override
  String get closureKindHoliday => 'Holiday';

  @override
  String get closureKindInventory => 'Inventory';

  @override
  String get closureKindLabel => 'Reason';

  @override
  String get closureKindOther => 'Other';

  @override
  String get closureKindWorks => 'Works';

  @override
  String get closurePolicyBlock => 'Not allowed';

  @override
  String get closurePolicyBlockHelp =>
      'A delivery cannot be planned on a closed day; another date has to be chosen.';

  @override
  String get closurePolicyOverride =>
      'Needs a reason and the right to override';

  @override
  String get closurePolicyOverrideHelp =>
      'Only users who may override can plan on a closed day, and they must give a reason.';

  @override
  String get closurePolicyTitle =>
      'When a delivery is planned on a day the customer is closed';

  @override
  String get closurePolicyWarn => 'Warn only';

  @override
  String get closurePolicyWarnHelp =>
      'The date is saved and the closure is shown as a warning.';

  @override
  String get closures => 'Closed days';

  @override
  String get closuresShowPast => 'Show past closures';

  @override
  String get code => 'Code';

  @override
  String get codeNameRequired => 'Code and name are required.';

  @override
  String get codeNameVatRequired => 'Code, name and VAT rate are required.';

  @override
  String get completeJob => 'Complete job';

  @override
  String get completionNotes => 'What was done (and anything left open)';

  @override
  String get component => 'Component';

  @override
  String get componentHistory => 'Component history';

  @override
  String componentSince(String product, String date) {
    return '$product · since $date';
  }

  @override
  String get componentsAsBuilt => 'Components (as built)';

  @override
  String get confirm => 'confirm';

  @override
  String get confirmOnBehalf => 'Confirm on behalf of customer';

  @override
  String get confirmOnBehalfHelp =>
      'Record that the customer has confirmed this revision, for example by phone or e-mail.';

  @override
  String get confirmOrder => 'Confirm order';

  @override
  String get confirmOrderHelp =>
      'By confirming you accept this order as shown.';

  @override
  String get confirmation => 'Confirmation';

  @override
  String get confirmationDate => 'Confirmed on';

  @override
  String get confirmed => 'confirmed';

  @override
  String get confirmedRevision => 'Confirmed revision';

  @override
  String get confirmedVia => 'Confirmed via';

  @override
  String get confirmedViaPortal => 'customer portal';

  @override
  String get confirmedViaStaff => 'staff, on behalf of the customer';

  @override
  String conflictsOnDate(int count) {
    return '$count already have a price on this date';
  }

  @override
  String get contactName => 'Contact name';

  @override
  String get contactPerson => 'Contact person';

  @override
  String get contacts => 'Contacts';

  @override
  String get contractEnded => 'Ended';

  @override
  String get contractJobs => 'Jobs of this contract';

  @override
  String contractLabel(String number) {
    return 'Contract $number';
  }

  @override
  String contractOpenJobs(String count) {
    return '$count open jobs';
  }

  @override
  String get contracts => 'Contracts';

  @override
  String get contractSuspended => 'Suspended';

  @override
  String get convertHelp =>
      'Does the customer want changes? Make a new revision of the quotation first, link it here, then convert.';

  @override
  String get convertToOrder => 'Convert to order';

  @override
  String get countAddLine => 'Add stock not listed';

  @override
  String get countCancel => 'Cancel count';

  @override
  String get countCounted => 'Counted';

  @override
  String get countDifference => 'Difference';

  @override
  String get countExpected => 'Expected';

  @override
  String get countInvalidQuantity => 'A counted quantity is not a number.';

  @override
  String countMovedDuring(int count) {
    return '$count line(s) had stock movements during the count; the counted quantity replaced them.';
  }

  @override
  String get countNew => 'New count';

  @override
  String countOf(int count, int total) {
    return '$count of $total';
  }

  @override
  String get countOneProduct => 'Only one product (optional)';

  @override
  String get countOverwriteWarning =>
      'Movements made while you count are overwritten: when the count is posted, the counted quantity becomes the stock.';

  @override
  String get countPost => 'Post count';

  @override
  String get countPostConfirm =>
      'The differences are posted as stock adjustments. Lines without a counted quantity are left alone.';

  @override
  String get countProgress => 'Counted';

  @override
  String get countStart => 'Start count';

  @override
  String get countStatusCounting => 'Counting';

  @override
  String get countStatusPosted => 'Posted';

  @override
  String countStockAtPost(String quantity) {
    return 'Stock when posted: $quantity';
  }

  @override
  String get countWarehouseRequired => 'Choose a warehouse.';

  @override
  String get countWholeWarehouse => 'Whole warehouse';

  @override
  String get countedBy => 'Started by';

  @override
  String get country => 'Country';

  @override
  String get create => 'Create';

  @override
  String get createLead => 'Create lead';

  @override
  String get createRepair => 'Create repair';

  @override
  String get created => 'created';

  @override
  String get csatAlready => 'This survey was already answered.';

  @override
  String get csatAverage => 'Customer satisfaction';

  @override
  String get csatBad => 'Not satisfied';

  @override
  String get csatComment => 'Comment (optional)';

  @override
  String get csatEnabled =>
      'Send a satisfaction survey when a ticket is closed';

  @override
  String get csatExpired => 'This survey link has expired.';

  @override
  String get csatGood => 'Satisfied';

  @override
  String get csatNone => 'No rating yet';

  @override
  String csatQuestion(String number) {
    return 'How satisfied are you with the handling of ticket $number?';
  }

  @override
  String csatResponses(int count) {
    return '$count responses';
  }

  @override
  String get csatThanks => 'Thank you for your feedback!';

  @override
  String get csatTitle => 'Customer satisfaction';

  @override
  String get csvCopied => 'CSV copied to the clipboard';

  @override
  String get current => 'Current';

  @override
  String get customer => 'Customer';

  @override
  String get customerDeclinedToSign => 'The customer declined to sign';

  @override
  String get customerEquipment => 'Customer equipment';

  @override
  String get customerLanguage => 'Customer language';

  @override
  String customerMainNumber(String name) {
    return 'Main number of $name';
  }

  @override
  String customerNamed(String name) {
    return 'Customer: $name';
  }

  @override
  String get customerOptional => 'Customer (optional)';

  @override
  String get customerReference => 'Customer reference';

  @override
  String get customers => 'Customers';

  @override
  String get customerSignature => 'Customer signature';

  @override
  String get date => 'Date';

  @override
  String declinedToSignWithReason(String reason) {
    return 'Declined to sign: $reason';
  }

  @override
  String get defaultTeam => 'Default team for new tickets';

  @override
  String get deleteRuleConfirm =>
      'Delete this rule? Tickets that it changed keep their changes.';

  @override
  String get deliveries => 'Deliveries';

  @override
  String get deliveryBlocked =>
      'Deliveries on a closed day are not allowed. Choose another date.';

  @override
  String get deliveryCancel => 'Cancel delivery';

  @override
  String get deliveryCancelReason => 'Reason for cancelling';

  @override
  String get deliveryChooseSerial => 'Choose serial number';

  @override
  String deliveryClosedWarning(String from, String to, String next) {
    return 'The customer is closed from $from to $to. Next open day: $next.';
  }

  @override
  String get deliveryFailed => 'not sent';

  @override
  String get deliveryLocation => 'Location';

  @override
  String get deliveryLot => 'Lot';

  @override
  String get deliveryNew => 'New delivery';

  @override
  String get deliveryNoDate => 'no date';

  @override
  String get deliveryNoLines =>
      'Nothing to deliver yet: reserve stock for the order first.';

  @override
  String get deliveryOnClosure => 'on a closure';

  @override
  String get deliveryOverrideNeedsRight =>
      'Delivering on a closed day needs a reason and the right to override.';

  @override
  String get deliveryOverrideReason => 'Reason for delivering on a closed day';

  @override
  String get deliveryPicking => 'Picking list';

  @override
  String get deliveryPlannedDate => 'Planned date';

  @override
  String get deliveryQueued => 'waiting to send';

  @override
  String get deliverySent => 'sent';

  @override
  String get deliverySerial => 'Serial number';

  @override
  String get deliverySettingsTitle => 'Delivery settings';

  @override
  String get deliveryShip => 'Ship';

  @override
  String get deliveryShipTo => 'Deliver to';

  @override
  String get deliveryShippedSnack => 'Delivery shipped';

  @override
  String get deliveryStatusPlanned => 'planned';

  @override
  String get deliveryStatusShipped => 'shipped';

  @override
  String deliveryUseDay(String date) {
    return 'Use $date';
  }

  @override
  String get department => 'Department';

  @override
  String get departmentCode => 'Code';

  @override
  String get departmentMembers => 'Colleagues in this department';

  @override
  String get departments => 'Departments';

  @override
  String get departmentsHelp =>
      'Repairs are routed to these departments. Only colleagues who belong to a department can work on its repairs.';

  @override
  String get description => 'Description';

  @override
  String get devModeHelp => 'Server must run with AUTH_MODE=dev';

  @override
  String get developmentUser => 'Development user';

  @override
  String get deviceLanguage => 'Device language';

  @override
  String get difference => 'Difference';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get dismissRequest => 'Dismiss request';

  @override
  String get draftSaved => 'Draft saved';

  @override
  String get dryRun => 'Try on a ticket';

  @override
  String get dryRunHelp =>
      'Shows which rules would apply to a ticket and what they would change. Nothing is changed.';

  @override
  String get dryRunRun => 'Run test';

  @override
  String get drawSignatureFirst => 'Draw a signature first';

  @override
  String dueOnDate(String date) {
    return 'Due $date';
  }

  @override
  String get edit => 'Edit';

  @override
  String get editClosure => 'Edit closure';

  @override
  String get editContact => 'Edit contact';

  @override
  String get editDepartment => 'Edit department';

  @override
  String get editJob => 'Edit job';

  @override
  String get email => 'E-mail';

  @override
  String get emailAddresses => 'E-mail addresses (the first is primary)';

  @override
  String get endContract => 'End contract';

  @override
  String get endDate => 'End date';

  @override
  String get enterChange => 'Enter the change, e.g. 4.5 for +4.5 %.';

  @override
  String enterValidNumbersLine(int line) {
    return 'Line $line: enter valid numbers.';
  }

  @override
  String get equipment => 'Equipment';

  @override
  String get estimatedMinutes => 'Estimated minutes';

  @override
  String get expectedClose => 'Expected close';

  @override
  String expectedCloseDate(String date) {
    return 'Expected close $date';
  }

  @override
  String get expectedValue => 'Expected value';

  @override
  String get expectedValueEur => 'Expected value (€)';

  @override
  String get expectedValueOptional => 'Expected value (optional)';

  @override
  String get explode => 'Explode';

  @override
  String get exportCsv => 'Copy as CSV';

  @override
  String get families => 'Families';

  @override
  String get family => 'Family';

  @override
  String familyNamed(String code) {
    return 'Family $code';
  }

  @override
  String get faultDescription => 'What is wrong';

  @override
  String get firstDueDate => 'First due date';

  @override
  String get firstName => 'First name';

  @override
  String get firstResponseMinutes => 'First response (min)';

  @override
  String get firstResponseTime => 'First response';

  @override
  String get from => 'From';

  @override
  String get fromYou => 'You';

  @override
  String generalRebateInfo(String percent) {
    return 'General rebate on all products: $percent % (net-priced products are never discounted).';
  }

  @override
  String get generalRebatePercent => 'General rebate %';

  @override
  String greetingPreview(String greeting) {
    return 'Greeting: $greeting';
  }

  @override
  String get helpdesk => 'Helpdesk';

  @override
  String get helpdeskReports => 'Reports';

  @override
  String get helpdeskSettings => 'Helpdesk settings';

  @override
  String get history => 'History';

  @override
  String get holidayDate => 'Date';

  @override
  String get holidayInvalid => 'Enter a date (YYYY-MM-DD) and a name.';

  @override
  String get holidays => 'Holidays';

  @override
  String get holidaysHelp => 'Days on which the helpdesk is closed.';

  @override
  String get calendarFor => 'Calendar for';

  @override
  String get calendarCompanyWide => 'Whole company';

  @override
  String get calendarInherited =>
      'This team has no calendar of its own and uses the company calendar. Saving creates one for the team.';

  @override
  String get calendarHolidaysInherited =>
      'The company holidays apply to this team as well. Holidays added here are the team\'s own.';

  @override
  String get calendarUseCompany => 'Use the company calendar';

  @override
  String get calendarRemoved => 'The team uses the company calendar again.';

  @override
  String get basisMixed => 'business hours or elapsed time, per team';

  @override
  String get inactive => 'inactive';

  @override
  String get inactiveContact => 'No longer active (left the company)';

  @override
  String indicativeLine(String description) {
    return '$description (indicative, to confirm)';
  }

  @override
  String indicativeToConfirm(int count) {
    return '$count indicative price(s) to confirm before the quotation can be sent: enter the agreed price in the list price field.';
  }

  @override
  String get insertPreparedAnswer => 'Insert prepared answer';

  @override
  String get instructions => 'Instructions';

  @override
  String get internalNote => 'Internal note';

  @override
  String internalQuestionHelp(String language) {
    return 'Internal question. Ask the customer in $language with a reply, then post the answer for your colleague as an internal note.';
  }

  @override
  String get internalTicket => 'Internal ticket';

  @override
  String get internalTicketHelp =>
      'A question between colleagues; nothing is sent to the customer.';

  @override
  String get interval => 'Interval';

  @override
  String get jobCancelled => 'Cancelled';

  @override
  String get jobCompleted => 'Completed';

  @override
  String jobCount(String count) {
    return '$count jobs';
  }

  @override
  String jobCreatedOnDate(String date) {
    return 'job created on $date';
  }

  @override
  String get jobInProgress => 'In progress';

  @override
  String get jobKindInspection => 'Inspection';

  @override
  String get jobKindInstallation => 'Installation';

  @override
  String get jobKindMaintenance => 'Maintenance';

  @override
  String get jobKindOther => 'Other';

  @override
  String get jobKindRepair => 'Repair';

  @override
  String get jobName => 'Title';

  @override
  String get jobPlanned => 'Planned';

  @override
  String get jobTitle => 'Job title';

  @override
  String get jobs => 'Jobs';

  @override
  String get keepAgreedPrices => 'Keep agreed prices';

  @override
  String get language => 'Language';

  @override
  String languageSameAsCustomer(String language) {
    return 'Same as company ($language)';
  }

  @override
  String lastDays(int days) {
    return 'Last $days days';
  }

  @override
  String get lastName => 'Last name';

  @override
  String get leadCreated => 'Lead created';

  @override
  String get leadDays => 'Create the job (days before)';

  @override
  String get lineDiscount => 'Extra disc. ±';

  @override
  String get listPrice => 'List price';

  @override
  String get loadMore => 'Load more';

  @override
  String get logCall => 'Log call';

  @override
  String get logTime => 'Log time';

  @override
  String get logWork => 'Log work';

  @override
  String get loginLinkInvalid =>
      'This login link has expired or was already used. Request a new one.';

  @override
  String get loginLinkSent =>
      'If this address may use the portal, a login link is on its way. Check your inbox.';

  @override
  String get lookUp => 'Look up';

  @override
  String get lost => 'Lost';

  @override
  String get lostReason => 'Lost reason';

  @override
  String get markAsLost => 'Mark as lost';

  @override
  String get markAsSent => 'Mark as sent';

  @override
  String get markCompleted => 'Mark as completed';

  @override
  String get markReceived => 'Mark as received';

  @override
  String get markShipped => 'Mark as shipped back';

  @override
  String get markWaitingCustomer => 'Waiting for customer';

  @override
  String get markWaitingParts => 'Waiting for parts';

  @override
  String get materialRequirements => 'Material requirements (active revision)';

  @override
  String get mergeAction => 'Merge';

  @override
  String get mergeHelp =>
      'All messages, files, tags and time entries move to the chosen ticket of the same customer. This ticket is closed. This cannot be undone.';

  @override
  String get mergeNoCandidates => 'No other open ticket of this customer.';

  @override
  String get mergeTicket => 'Merge into another ticket…';

  @override
  String mergedInto(String number) {
    return 'Merged into $number';
  }

  @override
  String get message => 'Message';

  @override
  String get messageSent => 'Message sent';

  @override
  String get minutes => 'Minutes';

  @override
  String minutesShort(String minutes) {
    return '$minutes min';
  }

  @override
  String get moduleDelivery => 'Delivery';

  @override
  String get moduleProduction => 'Production';

  @override
  String get moveDown => 'Move down';

  @override
  String get moveUp => 'Move up';

  @override
  String get months => 'Months';

  @override
  String get myJobs => 'My jobs';

  @override
  String get myOrders => 'My orders';

  @override
  String get myProfile => 'My details';

  @override
  String get myRepairs => 'My repairs';

  @override
  String get myTickets => 'My tickets';

  @override
  String get name => 'Name';

  @override
  String get navigate => 'Navigate';

  @override
  String get netPrice => 'Net price';

  @override
  String get newAnswer => 'New answer';

  @override
  String get newContact => 'New contact';

  @override
  String get newContract => 'New contract';

  @override
  String get newCustomer => 'New customer';

  @override
  String get newDepartment => 'New department';

  @override
  String get newFamily => 'New family';

  @override
  String get newItem => 'New';

  @override
  String get newJob => 'New job';

  @override
  String get newLabel => 'New';

  @override
  String get newOpportunity => 'New opportunity';

  @override
  String get newPrice => 'New price';

  @override
  String newPricesValidFrom(String date) {
    return 'New prices valid from $date';
  }

  @override
  String get newPriority => 'New priority';

  @override
  String get newProduct => 'New product';

  @override
  String get newQuotation => 'New quotation';

  @override
  String get newRepair => 'New repair';

  @override
  String get newRevision => 'New revision';

  @override
  String newRevisionOf(String number) {
    return 'New revision of $number';
  }

  @override
  String get newRule => 'New rule';

  @override
  String get newTeam => 'New team';

  @override
  String get newTicket => 'New ticket';

  @override
  String get no => 'No';

  @override
  String get noAccess =>
      'Your account has no access to any section yet. Ask an administrator.';

  @override
  String get noActiveBom => 'No active bill of materials.';

  @override
  String get noBom => 'No bill of materials yet.';

  @override
  String get noClosures => 'No closures recorded.';

  @override
  String get noContactLinked => 'No contact person linked';

  @override
  String get noContacts => 'No contacts yet.';

  @override
  String get noContracts => 'No contracts';

  @override
  String get noCustomerEquipment => 'This customer has no installed units';

  @override
  String get noCustomerLinked => 'No customer linked';

  @override
  String get noEquipment => 'No equipment linked';

  @override
  String get noExpectedClose => 'No expected close date';

  @override
  String get noJobsAssigned => 'No jobs assigned to you.';

  @override
  String get noLines => 'No lines yet.';

  @override
  String get noOrdersYet => 'You have no orders yet.';

  @override
  String get noParts => 'No parts recorded';

  @override
  String get noPermission =>
      'You do not have permission to change these settings.';

  @override
  String get noPhotos => 'No photos yet.';

  @override
  String get noPrices => 'No prices yet.';

  @override
  String get noPriorityChanges => 'No priority changes yet.';

  @override
  String get noPriorityRequests => 'No requests.';

  @override
  String get noQuotations => 'No quotations yet.';

  @override
  String get noRebates => 'No product or family rebates.';

  @override
  String get noRepairs => 'No repairs.';

  @override
  String get noRepairsYet => 'You have no repairs yet.';

  @override
  String get noRules => 'No rules yet.';

  @override
  String get noSerialComponents => 'No serialised components.';

  @override
  String get noSignature => 'Not signed yet';

  @override
  String get noTeam => 'No team';

  @override
  String get noTechnicians => 'Nobody assigned';

  @override
  String get noTicketsYet => 'You have no tickets yet.';

  @override
  String get noTimeEntries => 'No time logged yet.';

  @override
  String get nobodyFound => 'Nobody found with this number.';

  @override
  String get nonBillable => 'Not billable';

  @override
  String get none => 'None';

  @override
  String get notClosed => 'Not closed';

  @override
  String get notRouted => 'Not routed yet';

  @override
  String get notScheduled => 'Not scheduled';

  @override
  String get noteAdded => 'Note added';

  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get notes => 'Notes';

  @override
  String get noUpcomingVisits => 'No visits due';

  @override
  String get number => 'Number';

  @override
  String get numberRequired => 'Number';

  @override
  String get obsoleteRevision => 'Obsolete revision (read-only).';

  @override
  String get oidcAccessToken => 'OIDC access token';

  @override
  String get ok => 'OK';

  @override
  String get onSiteContact => 'Person on site';

  @override
  String get openEnded => 'open';

  @override
  String get openJobsOnly => 'Active only';

  @override
  String get openOnly => 'Open only';

  @override
  String get openOpportunity => 'Open opportunity';

  @override
  String openPriorityRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open priority requests',
      one: '1 open priority request',
    );
    return '$_temp0';
  }

  @override
  String openRepairsCount(String count) {
    return '$count open';
  }

  @override
  String get opens => 'Opens';

  @override
  String get opportunities => 'Opportunities';

  @override
  String get opportunity => 'Opportunity';

  @override
  String get opportunityOptional => 'Opportunity (optional)';

  @override
  String get order => 'Order';

  @override
  String orderAlreadyConfirmed(String date) {
    return 'This order was confirmed on $date.';
  }

  @override
  String get orderAwaitingConfirmation => 'awaiting your confirmation';

  @override
  String get orderConfirmationQueued =>
      'Order confirmation queued for sending.';

  @override
  String get orderConfirmedSnack => 'Order confirmed.';

  @override
  String get orderConfirmedThanks => 'Thank you, your order is confirmed.';

  @override
  String get orderCreated => 'Order created';

  @override
  String get orderSaved => 'Order saved.';

  @override
  String get orderStatusInPlanning => 'in planning';

  @override
  String get orderStatusInProduction => 'in production';

  @override
  String get orderStatusPartiallyShipped => 'partially shipped';

  @override
  String get orderStatusPlanned => 'planned';

  @override
  String get orderStatusReadyForShipping => 'ready for shipping';

  @override
  String get orderStatusShipped => 'shipped';

  @override
  String get orderStockRelease => 'Release';

  @override
  String get orderStockReserve => 'Reserve';

  @override
  String get orderStockReserveHint =>
      'Stock can be reserved once the customer has confirmed the order.';

  @override
  String orderStockThisLine(String quantity) {
    return '$quantity reserved for this line';
  }

  @override
  String get orderStockTitle => 'Stock availability';

  @override
  String get orders => 'Orders';

  @override
  String get owner => 'Owner';

  @override
  String get ownerEmpty => 'Nobody';

  @override
  String get ownerSet => 'Somebody';

  @override
  String get p90 => '90% within';

  @override
  String get partFreeTextHint => 'Pick a product or type a description';

  @override
  String get partsUsed => 'Parts used';

  @override
  String get paymentDays => 'Payment days';

  @override
  String get pdf => 'PDF';

  @override
  String get perDay => 'Per day';

  @override
  String get perWeek => 'Per week';

  @override
  String get personTitle => 'Title';

  @override
  String get phone => 'Phone';

  @override
  String get phoneCall => 'Phone call';

  @override
  String get phoneDirect => 'Direct';

  @override
  String get phoneHint => 'With country code, e.g. +32 475 12 34 56';

  @override
  String get phoneMobile => 'Mobile';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phoneNumbers => 'Phone numbers';

  @override
  String get phoneOther => 'Other';

  @override
  String get phoneWork => 'Work';

  @override
  String photoBy(String name) {
    return 'by $name';
  }

  @override
  String get photos => 'Photos';

  @override
  String get photosAdded => 'Photos added';

  @override
  String get placeholdersHelp =>
      'Placeholders (click to insert in the current language):';

  @override
  String get portalAccess => 'Customer portal access';

  @override
  String get portalScope => 'Sees in the portal';

  @override
  String get portalScopeCustomer => 'All tickets of the company';

  @override
  String get portalScopeOwn => 'Own tickets only';

  @override
  String get portalSignInIntro =>
      'Enter your e-mail address. We will send you a link to sign in, no password needed.';

  @override
  String get portalTitle => 'Customer portal';

  @override
  String get postalCode => 'Postal code';

  @override
  String get preparedAnswers => 'Prepared answers';

  @override
  String get preparedAnswersHelp =>
      'Reusable answers to recurring questions, one text per language. Placeholders such as «quotation.number» are filled in for the ticket; the text can still be edited before sending.';

  @override
  String get preview => 'Preview';

  @override
  String priceListOf(String date) {
    return 'Price list of $date';
  }

  @override
  String get priceListValidOn => 'Price list valid on';

  @override
  String get priceZone => 'Price zone';

  @override
  String pricedOnPriceListOf(String date) {
    return 'Priced on the price list of $date';
  }

  @override
  String get prices => 'Prices';

  @override
  String pricesCreated(int count, String date) {
    return '$count prices created, valid from $date';
  }

  @override
  String pricesWillChange(int count) {
    return '$count prices will change';
  }

  @override
  String get pricing => 'Pricing';

  @override
  String get pricingIndicative => 'indicative';

  @override
  String get pricingIndicativeHelp => 'Indicative (confirm per quote)';

  @override
  String get pricingList => 'list price';

  @override
  String get pricingListHelp => 'List price (rebates apply)';

  @override
  String get pricingNet => 'net';

  @override
  String get pricingNetHelp => 'Net price (never discounted)';

  @override
  String get priority => 'Priority';

  @override
  String priorityChangeLine(String date, String from, String to, String name) {
    return '$date: $from → $to by $name';
  }

  @override
  String get priorityChangedSnack => 'Priority changed.';

  @override
  String get priorityExpedite => 'expedite';

  @override
  String get priorityHigh => 'high';

  @override
  String get priorityHistory => 'Priority history';

  @override
  String get priorityLow => 'low';

  @override
  String get priorityNormal => 'normal';

  @override
  String get priorityRequestHelp =>
      'Our team decides whether and how the priority is changed.';

  @override
  String priorityRequestLine(String name, String priority) {
    return '$name asks for priority: $priority';
  }

  @override
  String get priorityRequestSent => 'Your request has been sent.';

  @override
  String get priorityRequests => 'Customer priority requests';

  @override
  String get priorityUrgent => 'urgent';

  @override
  String get probability => 'Probability';

  @override
  String get probabilityPercent => 'Probability %';

  @override
  String get probabilityShort => 'Prob.';

  @override
  String get product => 'Product';

  @override
  String productCount(int count) {
    return '$count products';
  }

  @override
  String get productDescription => 'Product';

  @override
  String get productFamilies => 'Product families';

  @override
  String get productFamily => 'Product family';

  @override
  String get productRebates => 'Product rebates';

  @override
  String get productTypeConfigurable => 'configurable';

  @override
  String get productTypeManufactured => 'manufactured';

  @override
  String get productTypePurchased => 'purchased';

  @override
  String get productTypeService => 'service';

  @override
  String get production => 'Production';

  @override
  String productionBomRevision(String revision) {
    return 'BOM revision $revision';
  }

  @override
  String get productionBuildComponent => 'Build it';

  @override
  String get productionBuildForStock => 'Build for stock';

  @override
  String get productionCancel => 'Cancel production order';

  @override
  String get productionCancelReason => 'Reason for cancelling';

  @override
  String get productionChooseSerials => 'Choose serial numbers';

  @override
  String get productionComplete => 'Complete';

  @override
  String get productionCompleted => 'Production order completed';

  @override
  String get productionComponents => 'Components';

  @override
  String get productionConsumed => 'Consumed';

  @override
  String get productionDivision => 'Division';

  @override
  String get productionDivisionAdd => 'Add division';

  @override
  String get productionDivisionEdit => 'Edit division';

  @override
  String get productionDivisions => 'Divisions';

  @override
  String get productionExpiry => 'Expiry date';

  @override
  String get productionExtraFrom => 'Extra stock taken from';

  @override
  String get productionLocation => 'Put into';

  @override
  String get productionLot => 'Lot number';

  @override
  String get productionNoDivision => 'no division';

  @override
  String get productionNothingToRelease =>
      'Nothing to release: every manufactured line is covered by production orders.';

  @override
  String get productionOrderCancelled =>
      'The sales order was cancelled. Cancel this production order to free its components.';

  @override
  String get productionOrdersOfOrder => 'Production orders';

  @override
  String get productionOutput => 'Output';

  @override
  String get productionPlannedReady => 'Planned ready';

  @override
  String get productionPromised => 'Promised';

  @override
  String get productionQuantityBuilt => 'Quantity built';

  @override
  String get productionRelease => 'Release to production';

  @override
  String get productionReleased => 'Released to production';

  @override
  String get productionRequired => 'Required';

  @override
  String get productionReserveAgain => 'Reserve again';

  @override
  String get productionReserved => 'Reserved';

  @override
  String get productionScrap => 'Scrap';

  @override
  String get productionSerials => 'Serial numbers, one per line';

  @override
  String productionSerialsNeeded(String count) {
    return 'Choose $count serial numbers';
  }

  @override
  String get productionShort => 'short of stock';

  @override
  String get productionStart => 'Start';

  @override
  String get productionStatusCompleted => 'completed';

  @override
  String get productionStatusInProgress => 'in progress';

  @override
  String get productionStatusReleased => 'released';

  @override
  String get productionToRelease => 'To release';

  @override
  String get products => 'Products';

  @override
  String get profileHelp =>
      'Choose the language and the way we address you in our e-mails and in this portal.';

  @override
  String get quantity => 'Quantity';

  @override
  String get question => 'Question';

  @override
  String get questionToSales => 'Question to sales';

  @override
  String questionToSalesHelp(String salesperson) {
    return '$salesperson gets this question and asks the customer in their language.';
  }

  @override
  String get quotation => 'Quotation';

  @override
  String get quotations => 'Quotations';

  @override
  String raisedBy(String name) {
    return 'Raised by $name';
  }

  @override
  String get reason => 'Reason';

  @override
  String get reasonRequired => 'A reason is required.';

  @override
  String get rebate => 'Std. rebate';

  @override
  String rebateFor(String target, String percent) {
    return '$target: $percent %';
  }

  @override
  String get rebatePercent => 'Rebate %';

  @override
  String get rebateSourceFamily => 'family';

  @override
  String get rebateSourceGeneral => 'general';

  @override
  String get rebateSourceProduct => 'product';

  @override
  String rebatesOf(String customer) {
    return 'Rebates · $customer';
  }

  @override
  String get recurrenceMonthList => 'In chosen months';

  @override
  String get recurrenceMonths => 'Every N months';

  @override
  String get recurrenceWeeks => 'Every N weeks';

  @override
  String registerProduct(String product) {
    return 'Register $product';
  }

  @override
  String get registerUnit => 'Register unit';

  @override
  String get registered => 'Registered';

  @override
  String get rejected => 'Rejected';

  @override
  String get remove => 'Remove';

  @override
  String get removeAndScrap => 'Remove and scrap';

  @override
  String get removeBackToStock => 'Remove, back to stock';

  @override
  String get removeLine => 'Remove line';

  @override
  String removedBy(String date, String name) {
    return 'removed $date by $name';
  }

  @override
  String get reopenJob => 'Reopen job';

  @override
  String get repairAnnouncedByTicket =>
      'The customer announced it (the product has not arrived yet)';

  @override
  String get repairAnnouncedOk =>
      'Repair announced. Write the number on the parcel and send the product to us.';

  @override
  String get repairPhotosHelp =>
      'Photos of the product and the fault help us a lot.';

  @override
  String get repairPortalAnnounced => 'Announced, not received yet';

  @override
  String get repairPortalInRepair => 'In repair';

  @override
  String get repairPortalReady => 'Repaired, ready to ship';

  @override
  String get repairPortalWaitingCustomer => 'Waiting for your answer';

  @override
  String get repairStatusAnnounced => 'Announced';

  @override
  String get repairStatusCancelled => 'Cancelled';

  @override
  String get repairStatusCompleted => 'Completed';

  @override
  String get repairStatusInProgress => 'In progress';

  @override
  String get repairStatusReceived => 'Received';

  @override
  String get repairStatusRouted => 'In department queue';

  @override
  String get repairStatusShipped => 'Shipped back';

  @override
  String get repairStatusWaitingCustomer => 'Waiting for customer';

  @override
  String get repairStatusWaitingParts => 'Waiting for parts';

  @override
  String get repairs => 'Repairs';

  @override
  String get replaceSignature => 'Replace signature';

  @override
  String get replyQueued => 'Reply queued for sending';

  @override
  String get replyToCustomer => 'Reply to customer';

  @override
  String get reportQueued => 'The report will be sent';

  @override
  String get reportSend => 'Send report by e-mail';

  @override
  String reportSentTo(String to, String date) {
    return 'Sent to $to on $date';
  }

  @override
  String get reportView => 'View report (PDF)';

  @override
  String repricingFailed(String error) {
    return 'Today\'s prices could not be calculated: $error';
  }

  @override
  String get requestDismissedSnack => 'Request dismissed.';

  @override
  String get requestLessUrgent => 'Less urgent';

  @override
  String get requestMoreUrgent => 'More urgent (expedite)';

  @override
  String get requestPriorityChange => 'Request priority change';

  @override
  String get requestStatusApplied => 'applied';

  @override
  String get requestStatusDismissed => 'dismissed';

  @override
  String get requestStatusOpen => 'open';

  @override
  String get required => 'Required';

  @override
  String get resolutionHours => 'Resolution within (hours)';

  @override
  String get resolutionMinutes => 'Resolution (min)';

  @override
  String get resolutionTime => 'Resolution';

  @override
  String get responseTimes => 'Response and resolution times';

  @override
  String get responseHours => 'Response within (hours)';

  @override
  String get retry => 'Retry';

  @override
  String get revisionActivated => 'Revision activated';

  @override
  String revisionItem(int revision, String status, int lines) {
    return 'Revision $revision · $status · $lines lines';
  }

  @override
  String get revisionNotes => 'Revision notes';

  @override
  String revisionNumber(int revision) {
    return 'Revision $revision';
  }

  @override
  String revisionPriceLists(String agreed, String current) {
    return 'Agreed prices: price list of $agreed. Current prices: price list of $current.';
  }

  @override
  String revisionViewNotice(int revision, int current) {
    return 'You are viewing revision $revision (read-only). The current revision is $current.';
  }

  @override
  String get revisions => 'Revisions';

  @override
  String get roleInvoicing => 'Invoicing';

  @override
  String get roleManagement => 'Management';

  @override
  String get roleOther => 'Other';

  @override
  String get rolePurchasing => 'Purchasing';

  @override
  String get roleQuality => 'Quality';

  @override
  String get roleSalesContact => 'Sales contact';

  @override
  String get roleTechnical => 'Technician';

  @override
  String get roles => 'Roles';

  @override
  String get roundTo => 'Round to';

  @override
  String get routeNote => 'Note for the department';

  @override
  String get routeRepair => 'Route to department';

  @override
  String get ruleActions => 'Actions';

  @override
  String get ruleConditions => 'Conditions (all must match)';

  @override
  String get ruleConditionsHelp =>
      'Pick any number of values per line; a ticket needs one of them. Empty lines are ignored.';

  @override
  String get ruleNameRequired => 'A rule needs a name.';

  @override
  String get ruleResultAfterStop => 'skipped (stopped)';

  @override
  String get ruleResultInactive => 'off';

  @override
  String get ruleResultMatched => 'applies';

  @override
  String get ruleResultNoMatch => 'no match';

  @override
  String get ruleResultOtherTrigger => 'other event';

  @override
  String get ruleTrigger => 'When';

  @override
  String get ruleTriggerCreated => 'A ticket is created';

  @override
  String get ruleTriggerCustomerReplied => 'The customer replies';

  @override
  String get ruleTriggerUpdated => 'A ticket is updated by staff';

  @override
  String get salesperson => 'Salesperson';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get saveDraft => 'Save draft';

  @override
  String get saved => 'Saved';

  @override
  String savedNumber(String number) {
    return 'Saved $number';
  }

  @override
  String get scheduledEnd => 'End';

  @override
  String get scheduledStart => 'Start';

  @override
  String get scrapPercent => 'Scrap %';

  @override
  String get search => 'Search';

  @override
  String get send => 'Send';

  @override
  String get sendBackToTriage => 'Send back to triage';

  @override
  String get sendLoginLink => 'Send login link';

  @override
  String get sendOrderConfirmation => 'Send order confirmation';

  @override
  String get sendOrderConfirmationHelp =>
      'The order confirmation is e-mailed to the customer as a PDF. The revision can no longer be edited afterwards.';

  @override
  String get senderDomain => 'Sender domain';

  @override
  String get serial => 'serial';

  @override
  String get serialBuiltIn => 'built in';

  @override
  String get serialDelivered => 'delivered';

  @override
  String get serialInStock => 'in stock';

  @override
  String get serialInstalled => 'installed';

  @override
  String get serialNumber => 'Serial number';

  @override
  String get serialNumbers => 'Serial numbers';

  @override
  String get serialNumbersHelp =>
      'Every unit gets its own serial number and history';

  @override
  String get serialScrapped => 'scrapped';

  @override
  String get server => 'Server';

  @override
  String get serviceReport => 'Service report';

  @override
  String get setWarranty => 'Set warranty';

  @override
  String get showInactive => 'Show inactive';

  @override
  String signedByOn(String name, String date) {
    return 'Signed by $name on $date';
  }

  @override
  String get signerName => 'Name of the signer';

  @override
  String get signHere => 'Sign here';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String signedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get signingIn => 'Signing in…';

  @override
  String get singleProduct => 'Single product';

  @override
  String get siteAddress => 'Where to go';

  @override
  String get siteName => 'Site name';

  @override
  String skippedWithoutPrice(int count) {
    return '$count product/zone combinations have no price and are skipped';
  }

  @override
  String get sla => 'SLA';

  @override
  String get slaAndSatisfaction => 'SLA and satisfaction';

  @override
  String get slaAtRisk => 'At risk';

  @override
  String get slaBreached => 'Breached';

  @override
  String get slaCompliance => 'SLA compliance';

  @override
  String slaComplianceDetail(int breached, int total) {
    return '$breached of $total breached';
  }

  @override
  String slaDue(String date) {
    return 'Due $date';
  }

  @override
  String get slaFilterAny => 'Any SLA state';

  @override
  String get slaFirstResponse => 'First response';

  @override
  String slaLeft(String time) {
    return '$time left';
  }

  @override
  String get slaMet => 'Met';

  @override
  String get slaNone => 'No SLA';

  @override
  String get slaOnTime => 'On time';

  @override
  String slaOverdue(String time) {
    return '$time overdue';
  }

  @override
  String get slaPaused => 'Clock stopped: waiting for the customer';

  @override
  String get slaPolicies => 'Service levels (SLA)';

  @override
  String get slaPoliciesHelp =>
      'Plain elapsed time, business hours are not taken into account. The clock stops while a ticket waits for the customer.';

  @override
  String get slaResolution => 'Resolution';

  @override
  String get splitAction => 'Split';

  @override
  String splitFiles(int count) {
    return '$count file(s)';
  }

  @override
  String get splitHelp =>
      'Choose the messages that move to a new ticket for the same customer. Their files move with them. This cannot be undone (tickets can be merged again).';

  @override
  String get splitKeepOne => 'At least one message must stay in this ticket.';

  @override
  String get splitSubjectOptional => 'Subject of the new ticket (optional)';

  @override
  String get splitTicket => 'Split ticket…';

  @override
  String get stage => 'Stage';

  @override
  String get stageLead => 'lead';

  @override
  String get stageLost => 'lost';

  @override
  String get stageNegotiation => 'negotiation';

  @override
  String get stageProposal => 'proposal';

  @override
  String get stageQualified => 'qualified';

  @override
  String get stageWon => 'won';

  @override
  String get startDate => 'Start date';

  @override
  String get startJob => 'Start job';

  @override
  String get startWork => 'Start work';

  @override
  String get status => 'Status';

  @override
  String get statusAccepted => 'accepted';

  @override
  String get statusAfterwards => 'Status afterwards';

  @override
  String get statusDraft => 'draft';

  @override
  String get statusRejected => 'rejected';

  @override
  String get statusSent => 'sent';

  @override
  String get statusSuperseded => 'superseded';

  @override
  String get stopOnMatch => 'Stop after this rule';

  @override
  String get stopOnMatchHelp =>
      'When it matches, the rules after it are skipped.';

  @override
  String get stockAdjust => 'Adjust';

  @override
  String get stockAdjustReason => 'Why is the stock corrected?';

  @override
  String get stockAdjustRequired =>
      'Choose a location, enter a quantity and give a reason.';

  @override
  String get stockAllWarehouses => 'All warehouses';

  @override
  String get stockAssignedTo => 'Assigned to';

  @override
  String get stockAvailable => 'Available';

  @override
  String get stockBarcode => 'Barcode';

  @override
  String get stockBelowReorder => 'Below reorder level';

  @override
  String get stockChangeBy => 'Change by (+/−)';

  @override
  String get stockCounts => 'Stock counts';

  @override
  String stockExpiredQty(String quantity) {
    return '$quantity expired';
  }

  @override
  String get stockExpiry => 'Expiry date';

  @override
  String get stockFrom => 'From';

  @override
  String get stockInVans => 'In vans';

  @override
  String get stockInvalidNumbers =>
      'Cost, reorder levels and lead time must be numbers.';

  @override
  String get stockIssue => 'Issue';

  @override
  String get stockKindVan => 'Service van';

  @override
  String get stockKindWarehouse => 'Warehouse';

  @override
  String get stockLeadTime => 'Lead time (days)';

  @override
  String get stockLocation => 'Location';

  @override
  String get stockLocations => 'Stock by location';

  @override
  String get stockLot => 'Lot';

  @override
  String get stockLotNumber => 'Lot number';

  @override
  String get stockLotTrackingHelp => 'Lots / batches';

  @override
  String get stockMoves => 'Movements';

  @override
  String get stockNewLocation => 'New location';

  @override
  String get stockNewLot => 'New lot';

  @override
  String get stockNewQuantity => 'New quantity';

  @override
  String get stockNewVan => 'New service van';

  @override
  String get stockNewWarehouse => 'New warehouse';

  @override
  String get stockNoMoves => 'No movements yet';

  @override
  String get stockNoWarehouses =>
      'No warehouses yet. An administrator creates them here.';

  @override
  String get stockNote => 'Note';

  @override
  String get stockNothingInStock => 'Nothing in stock';

  @override
  String get stockOnHand => 'On hand';

  @override
  String get stockOnlyInStock => 'Only in stock';

  @override
  String get stockProductQuantityRequired =>
      'Choose a product and enter a quantity.';

  @override
  String get stockReasonConsumption => 'Consumption';

  @override
  String get stockReasonCorrection => 'Correction';

  @override
  String get stockReasonCount => 'Count';

  @override
  String get stockReasonManualReceipt => 'Manual receipt';

  @override
  String get stockReasonProductionOutput => 'Production output';

  @override
  String get stockReasonPurchaseReceipt => 'Purchase receipt';

  @override
  String get stockReasonRepairUse => 'Used in repair';

  @override
  String get stockReasonReturn => 'Customer return';

  @override
  String get stockReasonReversal => 'Reversal';

  @override
  String get stockReasonScrap => 'Scrap';

  @override
  String get stockReasonShipment => 'Shipment';

  @override
  String get stockReasonVanReplenishment => 'Van replenishment';

  @override
  String get stockReceive => 'Receive';

  @override
  String get stockReorderMax => 'Reorder maximum';

  @override
  String get stockReorderMin => 'Reorder minimum';

  @override
  String get stockReservations => 'Reserved for orders';

  @override
  String get stockReserved => 'Reserved';

  @override
  String get stockReverse => 'Reverse';

  @override
  String get stockReverseAnyway => 'Reverse anyway';

  @override
  String get stockReverseTitle => 'Reverse this movement';

  @override
  String get stockReversed => 'reversed';

  @override
  String stockShortBy(String quantity) {
    return 'Short by $quantity';
  }

  @override
  String get stockStandardCost => 'Standard cost';

  @override
  String get stockStateAvailable => 'In stock';

  @override
  String get stockStateNotStocked => 'Not stocked';

  @override
  String get stockStatePartial => 'Partly in stock';

  @override
  String get stockStateReserved => 'Reserved';

  @override
  String get stockStateShort => 'Not in stock';

  @override
  String get stockTitle => 'Stock';

  @override
  String get stockTo => 'To';

  @override
  String get stockTrackingLot => 'lot';

  @override
  String get stockTransfer => 'Transfer';

  @override
  String get stockWarehouse => 'Warehouse';

  @override
  String get stockWarehouses => 'Warehouses';

  @override
  String get street => 'Street';

  @override
  String get streetAddress => 'Street and number';

  @override
  String structureRevision(int revision) {
    return 'Structure (revision $revision)';
  }

  @override
  String get subassembly => 'subassembly';

  @override
  String get subject => 'Subject';

  @override
  String get subjectContains => 'Subject contains';

  @override
  String get subjectOptional => 'Subject (optional)';

  @override
  String suggested(String value) {
    return 'Suggested: $value';
  }

  @override
  String get tag => 'Tag';

  @override
  String get suspendContract => 'Suspend';

  @override
  String get tags => 'Tags';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get tasks => 'Tasks';

  @override
  String tasksProgress(String done, String total) {
    return '$done of $total done';
  }

  @override
  String get team => 'Team';

  @override
  String get teamLead => 'Lead';

  @override
  String get teamMembers => 'Members';

  @override
  String get teamName => 'Team name';

  @override
  String get teams => 'Teams';

  @override
  String get technicians => 'Technicians';

  @override
  String get text => 'Text';

  @override
  String get ticket => 'Ticket';

  @override
  String get ticketClosed => 'Closed';

  @override
  String get ticketDetails => 'Ticket details';

  @override
  String get ticketInProgress => 'In progress';

  @override
  String get ticketMerged => 'Tickets merged';

  @override
  String get ticketOpened => 'Ticket opened';

  @override
  String ticketSplit(String number) {
    return 'Created ticket $number';
  }

  @override
  String get ticketStatusClosed => 'closed';

  @override
  String get ticketStatusNew => 'new';

  @override
  String get ticketStatusOpen => 'open';

  @override
  String get ticketStatusPendingCustomer => 'waiting for customer';

  @override
  String get ticketStatusPendingInternal => 'waiting for colleague';

  @override
  String get ticketVolume => 'Tickets created and closed';

  @override
  String get ticketWaitingForYou => 'Waiting for your reply';

  @override
  String get tickets => 'Tickets';

  @override
  String get timeLogged => 'Time logged';

  @override
  String get timeNote => 'Note';

  @override
  String timeTotal(String total, String billable) {
    return 'Total $total, billable $billable';
  }

  @override
  String timeTotals(String work, String travel) {
    return 'Work $work · Travel $travel';
  }

  @override
  String get timeTracking => 'Time tracking';

  @override
  String get timeZone => 'Time zone';

  @override
  String get title => 'Title';

  @override
  String get titleCustomerValueRequired =>
      'Title, customer and a valid value are required.';

  @override
  String get titleMr => 'Mr.';

  @override
  String get titleMs => 'Ms.';

  @override
  String get titleNone => 'Not specified';

  @override
  String get to => 'To';

  @override
  String get topCategories => 'Top categories';

  @override
  String get topTags => 'Top tags';

  @override
  String get total => 'Total';

  @override
  String productsTotalChange(String from, String to, String difference) {
    return 'Products excl. shipping and VAT: $from → $to ($difference)';
  }

  @override
  String get totalExclVat => 'Total excl. VAT';

  @override
  String get totalInclVat => 'Total incl. VAT';

  @override
  String get totalsToBuyOrMake => 'Totals to buy or make';

  @override
  String get tracking => 'Tracking';

  @override
  String get twoLetters => '2 letters';

  @override
  String get type => 'Type';

  @override
  String get unassigned => 'Unassigned';

  @override
  String get unchanged => 'Unchanged';

  @override
  String get unit => 'Unit';

  @override
  String get unitPrice => 'Unit price';

  @override
  String get unitPriceExclVat => 'Unit price (excl. VAT)';

  @override
  String get unknownCaller => 'Unknown caller';

  @override
  String get until => 'Until';

  @override
  String get upcomingVisits => 'Upcoming visits';

  @override
  String get updateToCurrentPrices => 'Update to current prices';

  @override
  String get updated => 'Updated';

  @override
  String get uploadingFile => 'Uploading…';

  @override
  String get uploadingPhotos => 'Uploading…';

  @override
  String get useAnotherPriceListDate => 'Use another price list date';

  @override
  String get validFrom => 'Valid from';

  @override
  String validFromDate(String date) {
    return 'Valid from $date';
  }

  @override
  String validUntil(String date) {
    return 'valid until $date';
  }

  @override
  String get value => 'Value';

  @override
  String get vat => 'VAT';

  @override
  String get vatNumber => 'VAT number';

  @override
  String vatOn(String rate, String base) {
    return 'VAT $rate % on $base';
  }

  @override
  String get vatPercent => 'VAT %';

  @override
  String get viaPortal => 'Via the customer portal';

  @override
  String get visitTemplates => 'Visits';

  @override
  String get visitTitleRequired => 'Every visit needs a title';

  @override
  String get warranty => 'Warranty';

  @override
  String get warrantyExpired => 'Warranty expired';

  @override
  String get warrantyIn => 'In warranty';

  @override
  String get warrantyOut => 'Out of warranty';

  @override
  String get warrantyUnknown => 'Unknown';

  @override
  String get weekdayFriday => 'Friday';

  @override
  String get weekdayMonday => 'Monday';

  @override
  String get weekdaySaturday => 'Saturday';

  @override
  String get weekdaySunday => 'Sunday';

  @override
  String get weekdayThursday => 'Thursday';

  @override
  String get weekdayTuesday => 'Tuesday';

  @override
  String get weekdayWednesday => 'Wednesday';

  @override
  String warrantyUntilDate(String date) {
    return 'until $date';
  }

  @override
  String get warrantyUntilLabel => 'Warranty until';

  @override
  String weighted(String amount) {
    return 'weighted $amount';
  }

  @override
  String get whatWasAsked => 'What was asked?';

  @override
  String get whoIsCalling => 'Who is calling?';

  @override
  String get won => 'Won';

  @override
  String get workFrom => 'From';

  @override
  String get workKindTravel => 'Travel';

  @override
  String get workKindWork => 'Work';

  @override
  String get workLogs => 'Time registered';

  @override
  String get workUntil => 'Until';

  @override
  String writeIn(String language) {
    return 'Write in $language';
  }

  @override
  String get yes => 'Yes';

  @override
  String get yourMessage => 'Your message';

  @override
  String get yourReference => 'Your reference (RMA or order)';

  @override
  String get zone => 'Zone';

  @override
  String zoneAndRebate(String zone, String percent) {
    return 'Zone $zone · general rebate $percent %';
  }

  @override
  String get zonesNoneAll => 'Zones (none selected = all)';

  @override
  String get kbTitle => 'Knowledge base';

  @override
  String get kbNewArticle => 'New article';

  @override
  String get kbSearchHint => 'Search articles';

  @override
  String get kbAllCategories => 'All categories';

  @override
  String get kbAllStatuses => 'All statuses';

  @override
  String get kbAllAudiences => 'All audiences';

  @override
  String get kbManageCategories => 'Categories';

  @override
  String get kbStatusPublished => 'Published';

  @override
  String get kbStatusArchived => 'Archived';

  @override
  String get kbAudience => 'Audience';

  @override
  String get kbAudienceInternal => 'Internal (staff only)';

  @override
  String get kbAudiencePortal => 'Customer portal';

  @override
  String get kbAudiencePublic => 'Public';

  @override
  String get kbArticleTitle => 'Title';

  @override
  String get kbSummary => 'Summary';

  @override
  String get kbBody => 'Text (Markdown)';

  @override
  String get kbPreview => 'Preview';

  @override
  String get kbWriteTab => 'Write';

  @override
  String get kbMarkdownHelp =>
      'Use # for headings, **bold**, *italic*, - for lists, [text](https://…) for links and ![description](image:ID) for pictures.';

  @override
  String get kbTagsLabel => 'Tags (comma separated)';

  @override
  String get kbRelated => 'Related articles';

  @override
  String get kbAddRelated => 'Add related article';

  @override
  String get kbImages => 'Images';

  @override
  String get kbUploadImage => 'Upload image';

  @override
  String get kbInsertImage => 'Insert in text';

  @override
  String get kbPublish => 'Publish';

  @override
  String get kbUnpublish => 'Unpublish';

  @override
  String get kbArchive => 'Archive';

  @override
  String get kbHistory => 'Version history';

  @override
  String kbVersionLine(int version, String name, String date) {
    return 'Version $version · $name · $date';
  }

  @override
  String get kbRestore => 'Restore this version';

  @override
  String kbRestoredFrom(int version) {
    return 'restored from version $version';
  }

  @override
  String kbFeedback(int yes, int no) {
    return '$yes found this helpful, $no did not';
  }

  @override
  String kbViews(int count) {
    return '$count views';
  }

  @override
  String get kbNoArticles => 'No articles found.';

  @override
  String get kbNoCategory => 'No category';

  @override
  String get kbMainCategory => 'Main category';

  @override
  String get kbSortOrder => 'Sort order';

  @override
  String get kbNewCategory => 'New category';

  @override
  String get kbCategoryNames => 'Name per language';

  @override
  String get kbDelete => 'Delete';

  @override
  String get kbSuggestedArticles => 'Suggested articles';

  @override
  String get kbNoSuggestions => 'No matching articles.';

  @override
  String get kbInsertText => 'Insert text';

  @override
  String get kbInsertLink => 'Insert link';

  @override
  String get kbInsertArticle => 'Insert article';

  @override
  String get kbNoPortalLink =>
      'This article is internal: only its text can be inserted.';

  @override
  String get kbHelp => 'Help';

  @override
  String get kbHelpHeading => 'How can we help?';

  @override
  String get kbHelpSearch => 'Search the help articles';

  @override
  String get kbHelpEmpty => 'No articles found. You can open a ticket instead.';

  @override
  String get kbWasHelpful => 'Was this article helpful?';

  @override
  String get kbYes => 'Yes';

  @override
  String get kbNo => 'No';

  @override
  String get kbThanks => 'Thank you for your feedback.';

  @override
  String get kbStillNeedHelp => 'Still need help? Open a ticket.';

  @override
  String get kbRelatedReading => 'Related articles';

  @override
  String get kbDeflectionTitle =>
      'These articles may already answer your question';

  @override
  String kbShownIn(String language) {
    return 'Not available in your language; shown in $language.';
  }

  @override
  String kbUpdatedOn(String date) {
    return 'Updated $date';
  }

  @override
  String offlineWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to sync',
      one: '1 change waiting to sync',
    );
    return '$_temp0';
  }

  @override
  String offlineFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need your attention',
      one: '1 needs your attention',
    );
    return '$_temp0';
  }

  @override
  String get offlineQueueTitle => 'Changes waiting to sync';

  @override
  String get offlineSyncNow => 'Sync now';

  @override
  String get offlineRetry => 'Try again';

  @override
  String get offlineDiscard => 'Discard';

  @override
  String get offlineDiscardQuestion =>
      'Discard this change? It will not be sent to the server.';

  @override
  String get offlineAllSynced => 'Everything is synced.';

  @override
  String offlineAttempts(int count) {
    return 'Attempts: $count';
  }

  @override
  String offlineLastError(String message) {
    return 'Last error: $message';
  }

  @override
  String get offlineRejected =>
      'The server refused this change. The job may have been reassigned, cancelled or changed in the meantime.';

  @override
  String offlineDataFrom(String time) {
    return 'Offline: data from $time';
  }

  @override
  String get offlinePendingSync => 'Waiting to sync';

  @override
  String get offlineQueuedMessage =>
      'No connection: saved on this device, it will be sent when you are back online.';

  @override
  String offlinePhotosWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos waiting to upload',
      one: '1 photo waiting to upload',
    );
    return '$_temp0';
  }

  @override
  String get offlineTooLarge =>
      'Too large to keep offline. Connect to send it.';

  @override
  String get offlineReload => 'Reload';

  @override
  String get offlineOpStart => 'Start job';

  @override
  String get offlineOpTaskDone => 'Task ticked';

  @override
  String get offlineOpTaskUndone => 'Task unticked';

  @override
  String get offlineOpTaskAdd => 'New task';

  @override
  String get offlineOpWorkLog => 'Time entry';

  @override
  String get offlineOpPart => 'Part used';

  @override
  String get offlineOpComplete => 'Complete job';

  @override
  String get offlineOpDecline => 'Customer declined to sign';

  @override
  String get offlineOpSignature => 'Customer signature';

  @override
  String get offlineOpPhoto => 'Photo';

  @override
  String get collabEscalate => 'Escalate';

  @override
  String get collabEscalateTitle => 'Escalate ticket';

  @override
  String get collabDelegate => 'Hand over';

  @override
  String get collabDelegateTitle => 'Hand over ticket';

  @override
  String get collabEscalateTo => 'Escalate to';

  @override
  String get collabNoTarget => 'Leads of the ticket\'s team';

  @override
  String get collabPerson => 'Colleague';

  @override
  String get collabTeam => 'Team';

  @override
  String get collabHandOverTo => 'New owner';

  @override
  String get collabReasonRequired => 'Reason (required)';

  @override
  String get collabRaisePriority => 'Raise priority one step';

  @override
  String get collabCommentOptional => 'Comment for the new owner (optional)';

  @override
  String get collabInternalHint => 'Internal: never sent to the customer.';

  @override
  String get collabEscalated => 'Ticket escalated';

  @override
  String get collabHandedOver => 'Ticket handed over';

  @override
  String get collabEscalatedBadge => 'Escalated';

  @override
  String collabEscalatedBy(String name) {
    return 'Escalated by $name';
  }

  @override
  String get collabWatch => 'Watch';

  @override
  String get collabUnwatch => 'Stop watching';

  @override
  String get collabWatchers => 'Watchers';

  @override
  String get collabNoWatchers => 'Nobody follows this ticket';

  @override
  String get collabAddWatcher => 'Add watcher';

  @override
  String get collabActivity => 'Activity';

  @override
  String get collabNoActivity => 'No activity yet';

  @override
  String collabSeenBy(String readers) {
    return 'Seen by $readers';
  }

  @override
  String get collabFilterUnread => 'Unread';

  @override
  String get collabFilterWatching => 'Watching';

  @override
  String get collabFilterEscalated => 'Escalated';

  @override
  String get collabUnreadTooltip => 'Unread';

  @override
  String collabReplying(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names are replying',
      one: '$names is replying',
    );
    return '$_temp0 — coordinate before sending';
  }

  @override
  String collabViewing(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names are viewing this ticket',
      one: '$names is viewing this ticket',
    );
    return '$_temp0';
  }

  @override
  String collabConfirmSend(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names are replying to this ticket right now.',
      one: '$names is replying to this ticket right now.',
    );
    return '$_temp0 Send anyway?';
  }

  @override
  String get collabSendAnyway => 'Send anyway';

  @override
  String get collabSystem => 'System';

  @override
  String collabEventCreated(String actor) {
    return '$actor created the ticket';
  }

  @override
  String collabEventAssignedOwner(String actor, String owner) {
    return '$actor assigned the ticket to $owner';
  }

  @override
  String collabEventOwnerCleared(String actor) {
    return '$actor removed the owner';
  }

  @override
  String collabEventTeam(String actor, String team) {
    return '$actor moved the ticket to team $team';
  }

  @override
  String collabEventTeamCleared(String actor) {
    return '$actor removed the team';
  }

  @override
  String collabEventDelegated(String actor, String owner) {
    return '$actor handed the ticket over to $owner';
  }

  @override
  String collabEventEscalated(String actor) {
    return '$actor escalated the ticket';
  }

  @override
  String collabEventStatus(String actor, String before, String after) {
    return '$actor changed the status from $before to $after';
  }

  @override
  String collabEventPriority(String actor, String before, String after) {
    return '$actor changed the priority from $before to $after';
  }

  @override
  String collabEventMergedInto(String actor, String number) {
    return '$actor merged this ticket into $number';
  }

  @override
  String collabEventMergedFrom(String actor, String number) {
    return '$actor merged $number into this ticket';
  }

  @override
  String collabEventTagAdded(String actor, String tag) {
    return '$actor added the tag $tag';
  }

  @override
  String collabEventTagRemoved(String actor, String tag) {
    return '$actor removed the tag $tag';
  }

  @override
  String collabMsgCustomer(String actor) {
    return '$actor (customer) wrote';
  }

  @override
  String collabMsgReply(String actor) {
    return '$actor replied to the customer';
  }

  @override
  String collabMsgNote(String actor) {
    return '$actor added an internal note';
  }

  @override
  String collabMsgCall(String actor) {
    return '$actor logged a call';
  }

  @override
  String get planningTitle => 'Planning';

  @override
  String get planningDay => 'Day';

  @override
  String get planningWeek => 'Week';

  @override
  String get planningToday => 'Today';

  @override
  String get planningPrevious => 'Previous';

  @override
  String get planningNext => 'Next';

  @override
  String get planningBacklog => 'To plan';

  @override
  String get planningBacklogEmpty => 'Nothing left to plan.';

  @override
  String get planningSkillFilter => 'Skill';

  @override
  String get planningAllSkills => 'All skills';

  @override
  String get planningNoTechnicians =>
      'No technicians to show. Give users the technician role.';

  @override
  String get planningPlan => 'Plan';

  @override
  String planningScheduleJob(String number) {
    return 'Schedule $number';
  }

  @override
  String get planningSuggestions => 'Suggestions';

  @override
  String get planningShowSuggestions => 'Show suggestions';

  @override
  String get planningNoSuggestions =>
      'No free slot found in the next two weeks.';

  @override
  String planningMissingSkills(int count) {
    return '$count skill(s) missing';
  }

  @override
  String get planningRequiredSkills => 'Required skills';

  @override
  String get planningChecking => 'Checking…';

  @override
  String get planningNoConflicts => 'No conflicts.';

  @override
  String get planningConfirmTitle => 'Schedule with conflicts?';

  @override
  String get planningConfirmBody => 'This placement has errors:';

  @override
  String get planningScheduleAnyway => 'Schedule anyway';

  @override
  String get planningScheduled => 'Job scheduled.';

  @override
  String planningConflictDoubleBooked(String name) {
    return '$name has another job at that time (travel time included).';
  }

  @override
  String planningConflictOutsideHours(String name) {
    return '$name is outside working hours.';
  }

  @override
  String planningConflictOnAbsence(String name) {
    return '$name is absent.';
  }

  @override
  String planningConflictMissingSkill(String name, String skill) {
    return '$name lacks the skill $skill.';
  }

  @override
  String get planningConflictCrossesDays => 'The job runs past midnight.';

  @override
  String get planningAbsenceVacation => 'Vacation';

  @override
  String get planningAbsenceSick => 'Sick';

  @override
  String get planningAbsenceTraining => 'Training';

  @override
  String get planningAbsenceOther => 'Other absence';

  @override
  String get planningAgendaEmpty => 'Nothing planned.';

  @override
  String get planningSettingsTitle => 'Planning settings';

  @override
  String get planningAbsences => 'Absences';

  @override
  String get planningHours => 'Working hours';

  @override
  String get planningSkills => 'Skills';

  @override
  String get planningGeneral => 'General';

  @override
  String get planningAddAbsence => 'Add absence';

  @override
  String get planningNoAbsences => 'No absences recorded.';

  @override
  String get planningTechnician => 'Technician';

  @override
  String get planningKind => 'Kind';

  @override
  String get planningDefaultHours => 'Company default';

  @override
  String get planningUsesDefault =>
      'No hours of their own: the company default applies.';

  @override
  String get planningAddBlock => 'Add block';

  @override
  String get planningAddSkill => 'Add skill';

  @override
  String get planningTechnicianSkills => 'Skills per technician';

  @override
  String planningSkillLevel(int n) {
    return 'Level $n';
  }

  @override
  String get planningTravelBuffer => 'Travel time between jobs (minutes)';

  @override
  String get planningTravelBufferHelp =>
      'Kept free between two jobs of a technician on the same day.';

  @override
  String get planningDefaultJobMinutes => 'Default job length (minutes)';

  @override
  String get planningTimezone => 'Time zone';

  @override
  String get adminTitle => 'Administration';

  @override
  String get adminUsers => 'Users';

  @override
  String get adminModules => 'Modules';

  @override
  String get newUser => 'New user';

  @override
  String get editUser => 'Edit user';

  @override
  String get userDisabledModules => 'Disabled modules';

  @override
  String get userNotSignedIn => 'Not signed in yet';

  @override
  String get userResendInvitation => 'Send invitation again';

  @override
  String get userInvitationSent => 'Invitation sent';

  @override
  String get userCreated => 'User added';

  @override
  String get userFilterAll => 'All members';

  @override
  String get userFilterActive => 'Active members';

  @override
  String get userFilterInactive => 'Deactivated members';

  @override
  String get userActiveHelp =>
      'A deactivated member can no longer sign in to this company.';

  @override
  String get userCannotDeactivateSelf => 'You cannot deactivate yourself.';

  @override
  String get userCannotDropOwnAdmin => 'You cannot remove your own admin role.';

  @override
  String userRolePermissions(int count) {
    return '$count permissions';
  }

  @override
  String get userModulesHelp =>
      'Switch modules off for this person. Modules the company has switched off cannot be turned back on here.';

  @override
  String get userModuleCompanyOff => 'Switched off for the whole company';

  @override
  String moduleRequires(String modules) {
    return 'Needs $modules';
  }

  @override
  String get modulesIntro =>
      'Switch off the modules this company does not use. People no longer see them and the server refuses their requests.';

  @override
  String get modulesSaved => 'Modules saved';

  @override
  String moduleAlsoRequires(String modules) {
    return 'Also needs $modules';
  }

  @override
  String moduleAlsoSwitchedOff(String modules) {
    return 'Also switches off: $modules';
  }

  @override
  String moduleAlsoSwitchedOn(String modules) {
    return 'Also switches on: $modules';
  }

  @override
  String moduleExpand(String module) {
    return 'Expand $module';
  }

  @override
  String moduleCollapse(String module) {
    return 'Collapse $module';
  }

  @override
  String get moduleOn => 'On';

  @override
  String get moduleOff => 'Off';

  @override
  String moduleLevel(int level) {
    return 'Level $level';
  }

  @override
  String get userRoleAdmin => 'Administrator';

  @override
  String get userRoleSalesManager => 'Sales manager';

  @override
  String get userRoleSales => 'Sales';

  @override
  String get userRoleSupport => 'Support';

  @override
  String get userRoleProduction => 'Production';

  @override
  String get userRoleWarehouse => 'Warehouse';

  @override
  String get userRoleProductManager => 'Product manager';

  @override
  String get userRoleWorkshop => 'Workshop';

  @override
  String get userRoleTechnician => 'Technician';

  @override
  String get userRoleDispatcher => 'Dispatcher';

  @override
  String get userRoleLogistics => 'Logistics';

  @override
  String get userRoleViewer => 'Viewer';

  @override
  String get moduleCustomers => 'Customers';

  @override
  String get moduleProducts => 'Products';

  @override
  String get moduleSales => 'Sales';

  @override
  String get moduleEngineering => 'Engineering';

  @override
  String get moduleInventory => 'Inventory';

  @override
  String get moduleHelpdesk => 'Helpdesk';

  @override
  String get moduleKb => 'Knowledge base';

  @override
  String get moduleRepairs => 'Repairs';

  @override
  String get moduleField => 'Field service';

  @override
  String get purpose => 'Purpose';

  @override
  String get purposeInstallation => 'Installation';

  @override
  String get purposeStock => 'Stock';

  @override
  String get deliveryCountry => 'Delivery country';

  @override
  String deliveryCountryDefault(String country) {
    return 'Default: $country';
  }

  @override
  String get deliveryCountryInvalid =>
      'Enter a two-letter country code, for example BE.';

  @override
  String get shippingNotRequired => 'not required';

  @override
  String get shippingPending => 'pending';

  @override
  String get shippingQuoted => 'quoted';

  @override
  String get shippingRequested => 'requested';

  @override
  String get shippingPendingBanner =>
      'Waiting for a shipping quote from logistics. The quotation cannot be sent until the cost has been entered.';

  @override
  String get shippingQuotedBanner =>
      'The shipping cost has been quoted and is on the quotation as a shipping line.';

  @override
  String get shippingLineNote => 'Added by logistics';

  @override
  String get sendAnyway => 'Send anyway';

  @override
  String sendAnywayHelp(String message) {
    return '$message\n\nAs logistics you may send the quotation without the shipping cost. Send it anyway?';
  }

  @override
  String get shippingRequests => 'Shipping requests';

  @override
  String get shippingQueue => 'Open and requested';

  @override
  String get markAsRequested => 'Mark as requested';

  @override
  String get enterQuote => 'Enter quote';

  @override
  String get carrier => 'Carrier';

  @override
  String get amount => 'Amount';

  @override
  String get currency => 'Currency';

  @override
  String get quotedAmount => 'Quoted amount';

  @override
  String get requestedAt => 'Requested';

  @override
  String get amountRequired => 'Enter a valid amount.';

  @override
  String get carrierRequired => 'Enter the carrier.';

  @override
  String get packagingCategory => 'Packaging category';

  @override
  String get packagingCategories => 'Packaging categories';

  @override
  String get newPackagingCategory => 'New packaging category';

  @override
  String get requiresShippingQuote => 'Requires a shipping quote';

  @override
  String get lengthMm => 'Length (mm)';

  @override
  String get widthMm => 'Width (mm)';

  @override
  String get heightMm => 'Height (mm)';

  @override
  String get weightG => 'Weight (g)';

  @override
  String get dimensions => 'Dimensions';

  @override
  String dimensionsValue(int length, int width, int height) {
    return '$length x $width x $height mm';
  }

  @override
  String get weight => 'Weight';

  @override
  String weightValue(int grams) {
    return '$grams g';
  }

  @override
  String get positiveWholeNumbers =>
      'Dimensions and weight must be positive whole numbers, or empty.';

  @override
  String get powerTab => 'Power';

  @override
  String get powerNotElectrical =>
      'No supplies are listed, so this is not an electrical product and is never checked against a power grid.';

  @override
  String get powerAddSupply => 'Add supply';

  @override
  String get currentType => 'Current';

  @override
  String get currentAc => 'AC';

  @override
  String get currentDc => 'DC';

  @override
  String get voltageV => 'Voltage (V)';

  @override
  String get phases => 'Phases';

  @override
  String get frequencyHz => 'Frequency (Hz)';

  @override
  String get frequencyBoth => '50 and 60 Hz';

  @override
  String get tolerancePct => 'Tolerance (%)';

  @override
  String get powerVoltageInvalid =>
      'Enter the voltage as a positive whole number.';

  @override
  String get powerToleranceInvalid =>
      'The tolerance must be a whole number from 0 to 50.';

  @override
  String get powerSupplyDuplicate => 'The same supply is listed twice.';

  @override
  String get powerCheckTitle => 'Grid compatibility check';

  @override
  String get powerCheckHelp =>
      'Checks the saved supplies against the power grids of a country.';

  @override
  String get powerGrid => 'Power grid';

  @override
  String get powerAnyGrid => 'Any grid in this country';

  @override
  String get powerCheck => 'Check';

  @override
  String powerResultCompatible(String country) {
    return 'Compatible with the power grid of $country.';
  }

  @override
  String powerResultIncompatible(
    String country,
    String supported,
    String available,
  ) {
    return 'Does not fit the grid of $country. Supported: $supported. Available there: $available.';
  }

  @override
  String get powerResultExternal =>
      'Runs on DC only and needs an external power supply; it is not checked against the grid.';

  @override
  String get powerResultNotApplicable =>
      'Not an electrical product; there is nothing to check.';

  @override
  String powerResultUnknown(String country) {
    return 'There is no grid data for $country, so compatibility cannot be checked.';
  }

  @override
  String get powerStatusCompatible => 'Compatible';

  @override
  String get powerStatusIncompatible => 'Incompatible';

  @override
  String get powerStatusExternal => 'Needs external supply';

  @override
  String get powerStatusNotApplicable => 'Not applicable';

  @override
  String get powerStatusUnknown => 'Unknown grid';

  @override
  String get relatedTab => 'Related';

  @override
  String get relationRules => 'Rules';

  @override
  String get relationSuggestions => 'Suggestions';

  @override
  String get relationNoRules => 'No rules apply to this product.';

  @override
  String get relationNoSuggestions => 'No suggestions yet.';

  @override
  String get relationKindCompatible => 'Compatible';

  @override
  String get relationKindIncompatible => 'Incompatible';

  @override
  String get relationKindSuggested => 'Suggested';

  @override
  String get relationAddRule => 'Add rule';

  @override
  String get relationEdit => 'Edit relation';

  @override
  String get relationsTitle => 'Product relations';

  @override
  String get newRelation => 'New relation';

  @override
  String get relationKindLabel => 'Kind';

  @override
  String get relationSideA => 'First side';

  @override
  String get relationSideB => 'Second side';

  @override
  String get relationBidirectional => 'Applies in both directions';

  @override
  String get relationStrength => 'Strength (1-100)';

  @override
  String get relationStrengthHelp => 'Only used by suggested rules.';

  @override
  String get relationNeedSides => 'Choose a product or a family on both sides.';

  @override
  String get relationStrengthInvalid =>
      'The strength must be a whole number from 1 to 100.';

  @override
  String get relationsEmpty => 'No relations.';

  @override
  String relationFamilyValue(String code) {
    return 'Family $code';
  }

  @override
  String get suggestionReasonRule => 'Rule';

  @override
  String get suggestionReasonOften => 'Often bought together';

  @override
  String suggestionStrength(int n) {
    return 'Strength $n';
  }

  @override
  String suggestionConfidence(int pct) {
    return 'Confidence $pct %';
  }

  @override
  String suggestionBecause(String code) {
    return 'Because of $code';
  }

  @override
  String get powerGridsTitle => 'Power grids';

  @override
  String get newPowerGrid => 'New power grid';

  @override
  String get powerGridInvalid =>
      'Enter a two-letter country code, a voltage, 1 or 3 phases and 50 or 60 Hz.';

  @override
  String get warningKindPowerGrid => 'Power grid';

  @override
  String get warningKindIncompatible => 'Incompatible products';

  @override
  String hintsPowerIncompatible(String code) {
    return '$code does not fit the power grid at the delivery site.';
  }

  @override
  String hintsSupported(String value) {
    return 'Supported: $value';
  }

  @override
  String hintsAvailable(String value) {
    return 'Available: $value';
  }

  @override
  String hintsPowerExternal(String code) {
    return '$code runs on DC and needs an external power supply.';
  }

  @override
  String hintsPowerUnknown(String country, String code) {
    return 'No grid data for $country, so $code could not be checked. Add the country\'s grid under Power grids on the Products page.';
  }

  @override
  String hintsIncompatibleProducts(String a, String b) {
    return '$a and $b are not compatible.';
  }

  @override
  String get suggestionsTitle => 'Suggested additions';

  @override
  String get hintsTitle => 'Warnings and suggestions';

  @override
  String revisionShippingExisting(String amount) {
    return 'Existing shipping charge: $amount';
  }

  @override
  String get revisionShippingReset =>
      'With current prices, this shipping charge will be reset. A new shipping quote from logistics is needed before the revised quotation can be sent.';

  @override
  String revisionShippingKept(String amount) {
    return 'With agreed prices, the quoted shipping is carried over to the revised quotation (current charge: $amount).';
  }

  @override
  String get packagesReceiving => 'Receiving';

  @override
  String get packagesIntake => 'Repair intake';

  @override
  String get registerParcel => 'Register parcel';

  @override
  String get registeredParcels => 'Registered parcels';

  @override
  String get noParcels => 'No parcels.';

  @override
  String get sender => 'Sender';

  @override
  String get trackingNumber => 'Tracking number';

  @override
  String get parcelCount => 'Number of parcels';

  @override
  String get packageCondition => 'Condition of the box';

  @override
  String get conditionIntact => 'Intact';

  @override
  String get conditionDamaged => 'Damaged';

  @override
  String get conditionOpened => 'Opened';

  @override
  String get conditionWet => 'Wet';

  @override
  String get conditionNote => 'Note on the condition';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String parcelRegistered(String number) {
    return 'Parcel $number registered';
  }

  @override
  String get pkgStatusRegistered => 'Registered';

  @override
  String get pkgStatusOpened => 'Opened';

  @override
  String get pkgStatusLinked => 'Linked to a repair';

  @override
  String get pkgStatusClosed => 'Closed';

  @override
  String get packageKindRepair => 'Repair';

  @override
  String get packageKindOther => 'Other (no repair)';

  @override
  String get packageKindReturn => 'Return to sender';

  @override
  String get toOpen => 'To open';

  @override
  String get toProcess => 'To process';

  @override
  String get toRoute => 'To route';

  @override
  String get nothingHere => 'Nothing to do here.';

  @override
  String get openParcel => 'Open parcel';

  @override
  String get parcelContents => 'What is in the parcel?';

  @override
  String get closeParcel => 'Close parcel';

  @override
  String get noteRequired => 'A note is required.';

  @override
  String get linkToRepair => 'Match with a repair';

  @override
  String get repairSuggestions => 'Suggested repairs';

  @override
  String get noSuggestions => 'No announced repair matches.';

  @override
  String suggestedCustomer(String name) {
    return 'Suggested customer: $name';
  }

  @override
  String suggestionScore(String score) {
    return 'Score $score';
  }

  @override
  String get reasonSerial => 'Same serial number';

  @override
  String get reasonCustomer => 'Same customer';

  @override
  String get reasonReference => 'Same reference';

  @override
  String get reasonTicket => 'Same ticket';

  @override
  String get reasonProduct => 'Similar product';

  @override
  String get reasonRecent => 'Announced recently';

  @override
  String get confirmLinkTitle => 'Confirm match';

  @override
  String confirmLinkBody(String parcel, String repair) {
    return 'Parcel $parcel contains repair $repair. An announced repair will be marked as received.';
  }

  @override
  String get customerMismatchWarning =>
      'The customer of the parcel is not the customer of the repair.';

  @override
  String get confirmCustomerMismatch =>
      'Yes, it was sent by someone else (for example a colleague)';

  @override
  String get confirmLink => 'Confirm and link';

  @override
  String get linkConflict =>
      'The repair has changed in the meantime. The list was refreshed; check it and try again.';

  @override
  String get createNewRepair => 'Create new repair';

  @override
  String get parcelsSection => 'Parcels';

  @override
  String get noParcelsLinked => 'No parcel linked.';

  @override
  String get unlinkParcel => 'Unlink parcel';

  @override
  String get parcelsToLink => 'Parcels waiting for this repair';

  @override
  String get linkParcel => 'Link parcel';

  @override
  String get parcelLinked => 'Parcel linked';

  @override
  String get parcelUnlinked => 'Parcel unlinked';

  @override
  String get customerUnknown => 'Customer not known';

  @override
  String get findingsSection => 'Findings';

  @override
  String get findingsLabel => 'What was found';

  @override
  String get diagnosisLabel => 'Diagnosis';

  @override
  String get saveFindings => 'Save findings';

  @override
  String get warrantySection => 'Warranty';

  @override
  String get warrantyVoid => 'Void (misuse)';

  @override
  String get warrantyAutomatic => 'Automatic result';

  @override
  String warrantyComparedWith(String date) {
    return 'Compared with the arrival date $date';
  }

  @override
  String get warrantyProvisional =>
      'Not received yet: compared with today, so provisional.';

  @override
  String serialUnitLabel(String unit) {
    return 'Serial unit: $unit';
  }

  @override
  String get noSerialUnit => 'No serial unit linked';

  @override
  String get linkSerialUnit => 'Link serial unit';

  @override
  String get unlinkSerialUnit => 'Unlink serial unit';

  @override
  String get serialUnitSeveral =>
      'Several serial units match. Pick the right one.';

  @override
  String get serialUnitNoResults => 'No serial units found';

  @override
  String get recheckWarranty => 'Check warranty again';

  @override
  String get markWarrantyVoid => 'Mark warranty void (misuse)';

  @override
  String get removeWarrantyOverride => 'Remove override';

  @override
  String get warrantyVoidTitle => 'Mark warranty void';

  @override
  String get warrantyRemoveTitle => 'Remove the void override';

  @override
  String get warrantyReasonLabel => 'Reason (required)';

  @override
  String warrantyOverriddenBy(String name, String date, String reason) {
    return 'Overridden to void by $name on $date: $reason';
  }

  @override
  String get eventFindings => 'Findings updated';

  @override
  String get eventSerialUnit => 'Serial unit';

  @override
  String get eventWarrantyAuto => 'Automatic warranty';

  @override
  String get eventWarrantyManual => 'Warranty set by hand';

  @override
  String get eventWarrantyVoid => 'Warranty void';

  @override
  String get eventWarrantyVoidRemoved => 'Warranty override removed';

  @override
  String get csvMenu => 'CSV export and import';

  @override
  String get csvExport => 'Export CSV';

  @override
  String get csvImport => 'Import CSV';

  @override
  String csvExported(String name) {
    return 'Saved $name';
  }

  @override
  String csvExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String csvImportTitle(String entity) {
    return 'Import CSV: $entity';
  }

  @override
  String get csvImportHelp =>
      'Rows are matched on the code: an existing code is updated, a new code is created. Columns that are missing from the file are left untouched, and nothing is ever deleted. It is all or nothing: if any row has an error, nothing is imported. Semicolon or comma separated, UTF-8.';

  @override
  String get csvChooseFile => 'Choose CSV file';

  @override
  String get csvChooseOther => 'Choose another file';

  @override
  String get csvChecking => 'Checking the file...';

  @override
  String get csvImporting => 'Importing...';

  @override
  String get csvPreview => 'Preview: nothing has been imported yet';

  @override
  String get csvDone => 'Import complete';

  @override
  String get csvToCreate => 'To create';

  @override
  String get csvToUpdate => 'To update';

  @override
  String get csvUnchanged => 'Unchanged';

  @override
  String get csvCreated => 'Created';

  @override
  String get csvUpdated => 'Updated';

  @override
  String get csvImportAction => 'Import';

  @override
  String get csvEmptyFile => 'The file is empty.';

  @override
  String get csvNotUtf8 =>
      'The file is not UTF-8 text. Save it as CSV (UTF-8) and try again.';

  @override
  String get csvReadFailed => 'The file could not be read.';

  @override
  String csvErrorsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems found',
      one: '1 problem found',
    );
    return '$_temp0. Nothing has been imported.';
  }

  @override
  String csvErrorRow(int row) {
    return 'Row $row';
  }

  @override
  String csvErrorRowColumn(int row, String column) {
    return 'Row $row, column $column';
  }

  @override
  String csvAndMore(int count) {
    return 'and $count more';
  }

  @override
  String profileTooltip(String name) {
    return 'Profile: $name';
  }

  @override
  String get tabTicket => 'Ticket';

  @override
  String get tabQuotation => 'Quotation';

  @override
  String get tabNewQuotation => 'New quotation';

  @override
  String get tabOrder => 'Order';

  @override
  String get tabRepair => 'Repair';

  @override
  String get tabJob => 'Job';

  @override
  String get tabProduct => 'Product';

  @override
  String get tabOpportunity => 'Opportunity';

  @override
  String get tabStock => 'Stock';

  @override
  String get tabArticle => 'Article';

  @override
  String get tabContract => 'Contract';

  @override
  String get tabCount => 'Count';

  @override
  String get workspaceOverview => 'Overview';

  @override
  String get openTabs => 'Open tabs';

  @override
  String get closeTab => 'Close tab';

  @override
  String get openInNewTab => 'Open in new tab';

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get unsavedChangesBody =>
      'This tab has unsaved changes. Close it and discard them?';

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get remarkProduction => 'Production remark';

  @override
  String get remarkProductionHelp => 'Internal, never shown to the customer';

  @override
  String get remarkCustomer => 'Customer remark';

  @override
  String get remarkCustomerHelp =>
      'Printed on the quotation and the order confirmation';

  @override
  String get remarkHistory => 'Earlier remarks';

  @override
  String get remarkHistoryThisCustomer => 'This customer';

  @override
  String get remarkHistoryThisLanguage => 'This language';

  @override
  String get remarkHistoryAll => 'All';

  @override
  String get remarkHistoryEmpty => 'No earlier remarks for this product.';

  @override
  String remarkHistoryUsed(int count, String quotation) {
    return 'Used $count times, last on $quotation';
  }

  @override
  String get defaultProductionRemark => 'Default production remark';

  @override
  String get optionsTab => 'Options';

  @override
  String get optionsIntro =>
      'Products offered together with this one on a quotation. A required option is added automatically.';

  @override
  String get optionsNone => 'This product has no options.';

  @override
  String get optionAdd => 'Add option';

  @override
  String get optionRequired => 'Required';

  @override
  String get optionQuantity => 'Quantity per unit';

  @override
  String get optionRemove => 'Remove option';

  @override
  String get optionsSaved => 'Options saved.';

  @override
  String get optionsInvalidQuantity =>
      'Enter a quantity greater than 0 for every option.';

  @override
  String optionsChooseTitle(String product) {
    return 'Options for $product';
  }

  @override
  String get optionsChooseHelp =>
      'Required options are added automatically. Tick the optional ones to add.';

  @override
  String get optionsAddSelected => 'Add';

  @override
  String get optionsSkip => 'Without optional options';

  @override
  String get optionLine => 'Option of the line above';

  @override
  String get configurator => 'Configurator';

  @override
  String get configurators => 'Configurators';

  @override
  String get configure => 'Configure';

  @override
  String get newConfiguration => 'New configuration';

  @override
  String get savedConfigurations => 'Saved configurations';

  @override
  String cfgAddRow(String item) {
    return 'Add $item';
  }

  @override
  String cfgAddRowToGroup(String group) {
    return 'Add a row to $group';
  }

  @override
  String get cfgCalculated => 'Calculated';

  @override
  String get cfgChangeCustomer => 'Other customer';

  @override
  String get cfgCreateQuotation => 'Create quotation';

  @override
  String get cfgUpdateQuotation => 'Update quotation';

  @override
  String get cfgDeleteConfirm =>
      'Delete this configuration? Quotations made from it stay.';

  @override
  String get cfgDeleteRow => 'Delete row';

  @override
  String get cfgDuplicateRow => 'Duplicate row';

  @override
  String get cfgDiscard => 'Discard';

  @override
  String get cfgDiscardChanges => 'Discard the unsaved changes?';

  @override
  String cfgEach(String value) {
    return 'For each: $value';
  }

  @override
  String get cfgErrors => 'Errors';

  @override
  String get cfgWarnings => 'Warnings';

  @override
  String get cfgInfo => 'Information';

  @override
  String cfgEvalFailed(String message) {
    return 'Could not recalculate: $message';
  }

  @override
  String get cfgInput => 'Input';

  @override
  String get cfgIssues => 'Issues';

  @override
  String get cfgLines => 'Lines';

  @override
  String get cfgWhy => 'Why?';

  @override
  String get cfgInvalidNumber => 'Not a valid number';

  @override
  String get cfgNewerRevision =>
      'A newer revision of this configurator is available.';

  @override
  String get cfgUpgrade => 'Upgrade';

  @override
  String get cfgNoConfigurations => 'No saved configurations yet.';

  @override
  String get cfgNoModels => 'No configurator is active yet.';

  @override
  String get cfgNoCustomer => 'No customer';

  @override
  String get cfgNoIssues => 'No issues.';

  @override
  String get cfgNoLines => 'The configuration produces no lines yet.';

  @override
  String get cfgNotInCatalogue => 'Not in the product catalogue';

  @override
  String get cfgPinned => 'Your own value (pinned)';

  @override
  String get cfgPricesNeedCustomer => 'Choose a customer to see prices.';

  @override
  String get cfgQuoteBlocked => 'Fix the errors before making a quotation.';

  @override
  String get cfgQuoteNeedsCustomer =>
      'Choose a customer before making a quotation.';

  @override
  String cfgQuoteCreated(String number) {
    return 'Quotation $number created.';
  }

  @override
  String cfgQuoteUpdated(String number) {
    return 'Quotation $number updated.';
  }

  @override
  String cfgQuoteRevised(String number) {
    return 'Quotation $number: a new revision was created.';
  }

  @override
  String cfgResetToCalculated(String value) {
    return 'Reset to calculated ($value)';
  }

  @override
  String cfgStale(String value) {
    return 'The calculation now gives $value';
  }

  @override
  String cfgRevision(int revision) {
    return 'revision $revision';
  }

  @override
  String cfgRule(String rule) {
    return 'Rule: $rule';
  }

  @override
  String get cfgSaved => 'Saved.';

  @override
  String get cfgSelectLine => 'Select a line to see where it comes from.';

  @override
  String get cfgSetForAll => 'Set for all rows…';

  @override
  String cfgSetForAllTitle(String column) {
    return '$column for all rows';
  }

  @override
  String get cfgStart => 'Start';

  @override
  String get cfgUnsaved => 'Unsaved changes';

  @override
  String cfgNewerRevisionAvailable(int revision) {
    return 'revision $revision available';
  }

  @override
  String get cfgbActivate => 'Activate';

  @override
  String get cfgbActivateConfirm =>
      'Activate this draft? Sales will use it for new configurations; the current active revision becomes obsolete.';

  @override
  String get cfgbActivated => 'Activated.';

  @override
  String cfgbActivatedOn(String date) {
    return 'activated $date';
  }

  @override
  String get cfgbActivateModel => 'Make available';

  @override
  String cfgbActivateRefused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
    );
    return 'Not activated: $_temp0 to solve.';
  }

  @override
  String cfgbActiveRevision(int revision) {
    return 'active: revision $revision';
  }

  @override
  String get cfgbAddChild => 'Add option line';

  @override
  String get cfgbAddColumn => 'Add column';

  @override
  String get cfgbAddComputed => 'Add computed value';

  @override
  String get cfgbAddField => 'Add field';

  @override
  String get cfgbAddItemTable => 'Add item table';

  @override
  String get cfgbAddOption => 'Add option';

  @override
  String get cfgbAddRow => 'Add row';

  @override
  String get cfgbAddRule => 'Add output rule';

  @override
  String get cfgbAddSection => 'Add section';

  @override
  String get cfgbAddTable => 'Add table';

  @override
  String get cfgbAddValidation => 'Add check';

  @override
  String get cfgbApply => 'Apply';

  @override
  String cfgbChildRuleTitle(String id) {
    return 'Option line $id';
  }

  @override
  String get cfgbCode => 'Product code (formula)';

  @override
  String get cfgbCodeExpr => 'Formula';

  @override
  String get cfgbCodeHelp => 'e.g. \'BELT-M\' or motor_code';

  @override
  String get cfgbCodeTemplate => 'Product code (template)';

  @override
  String get cfgbCodeTemplateHelp =>
      'Text with formulas in curly brackets, e.g. DRV- then motor_size in brackets';

  @override
  String get cfgbColumn => 'Column';

  @override
  String get cfgbColumnName => 'Column';

  @override
  String get cfgbCommentTemplate => 'Comment (template)';

  @override
  String cfgbComputedOf(String scope) {
    return 'Computed values: $scope';
  }

  @override
  String cfgbComputedTitle(String name) {
    return 'Computed value $name';
  }

  @override
  String get cfgbConditions => 'Conditions';

  @override
  String get cfgbCreate => 'Create';

  @override
  String get cfgbCsvExport => 'Export CSV';

  @override
  String get cfgbCsvImport => 'Import CSV';

  @override
  String cfgbCsvImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows imported.',
      one: '1 row imported.',
    );
    return '$_temp0';
  }

  @override
  String get cfgbCsvProblems => 'The CSV file was not imported';

  @override
  String get cfgbDeactivateModel => 'Withdraw';

  @override
  String get cfgbDefault => 'Default';

  @override
  String get cfgbDefaultExpr => 'Default (formula)';

  @override
  String get cfgbDefaultExprHelp => 'Instead of a fixed default';

  @override
  String get cfgbDescriptionTemplate => 'Description (template)';

  @override
  String get cfgbDesignTitle => 'Design configurators';

  @override
  String get cfgbDimCurrent => 'Current';

  @override
  String get cfgbDimension => 'Dimension';

  @override
  String get cfgbDimLength => 'Length';

  @override
  String get cfgbDimMass => 'Mass';

  @override
  String get cfgbDimPower => 'Power';

  @override
  String get cfgbDimSpeed => 'Speed';

  @override
  String get cfgbDimVoltage => 'Voltage';

  @override
  String get cfgbDiscard => 'Discard';

  @override
  String get cfgbDisplayUnits => 'Display units:';

  @override
  String cfgbDraftRevision(int revision) {
    return 'draft: revision $revision';
  }

  @override
  String get cfgbEditDraft => 'Edit draft';

  @override
  String get cfgbEnabledIf => 'Enabled when';

  @override
  String cfgbExported(String name) {
    return 'Saved $name.';
  }

  @override
  String get cfgbExportJson => 'Export JSON';

  @override
  String get cfgbExpr => 'Formula';

  @override
  String get cfgbFamily => 'Product family (code)';

  @override
  String cfgbFieldsOf(String scope) {
    return 'Fields: $scope';
  }

  @override
  String cfgbFieldTitle(String name) {
    return 'Field $name';
  }

  @override
  String get cfgbForEach => 'For each';

  @override
  String get cfgbForEachHelp =>
      'A list: one line per element, with each and each_index';

  @override
  String cfgbFormulaType(String type) {
    return 'Result: $type';
  }

  @override
  String get cfgbGroupField => 'Group by field';

  @override
  String get cfgbGroupHelp =>
      'A group is one section of rows (e.g. a hall): one per distinct value of an item table\'s group field. Group fields with the name of a project field override it within the group.';

  @override
  String get cfgbGroupLabel => 'Name of a group';

  @override
  String get cfgbHelp => 'Help text';

  @override
  String get cfgbId => 'Id';

  @override
  String get cfgbImported => 'Imported into the editor; save to keep it.';

  @override
  String cfgbImportFailed(String message) {
    return 'Not imported: $message';
  }

  @override
  String get cfgbImportJson => 'Import JSON';

  @override
  String get cfgbImportNotExport => 'This file is not a configurator export.';

  @override
  String cfgbImportReplace(String name) {
    return 'Replace the whole definition of this draft by $name?';
  }

  @override
  String get cfgbInactive => 'not available to sales';

  @override
  String get cfgbItemLabel => 'Item label (template)';

  @override
  String get cfgbItemLabelHelp =>
      'Names one row in comments and messages; formulas in curly brackets, e.g. group_name and index';

  @override
  String get cfgbItemTable => 'Item table';

  @override
  String get cfgbKeys => 'Key columns:';

  @override
  String get cfgbKindExact => 'Exact';

  @override
  String get cfgbKindRange => 'Range';

  @override
  String get cfgbLabel => 'Label';

  @override
  String get cfgbLayout => 'Layout';

  @override
  String get cfgbLayoutSections => 'Form sections';

  @override
  String get cfgbLayoutSectionsHelp =>
      'Fields name a section in their layout; the form shows them under its heading.';

  @override
  String get cfgbMax => 'Maximum';

  @override
  String get cfgbMaxLength => 'Maximum length';

  @override
  String get cfgbMaxRows => 'Maximum rows';

  @override
  String get cfgbMergeIdentical => 'Merge identical lines';

  @override
  String get cfgbMergeIdenticalHelp =>
      'Lines with the same code become one; the comment lists the items';

  @override
  String get cfgbMessage => 'Message (template)';

  @override
  String get cfgbMin => 'Minimum';

  @override
  String get cfgbMinRows => 'Minimum rows';

  @override
  String get cfgbMoveDown => 'Move down';

  @override
  String get cfgbMoveUp => 'Move up';

  @override
  String get cfgbNewDraft => 'New draft from the active revision';

  @override
  String get cfgbNewDraftFromThis => 'New draft from this revision';

  @override
  String get cfgbNewModel => 'New configurator';

  @override
  String get cfgbNoProblems => 'No problems';

  @override
  String get cfgbOnMissing => 'When no row fits';

  @override
  String get cfgbOnMissingClamp => 'Next higher row';

  @override
  String get cfgbOnMissingHelp =>
      'Next higher row: a value below or between the ranges takes the row with the next higher range, a value above all ranges the last row; an offset past either end stops at the first or last row.';

  @override
  String get cfgbOnMissingError => 'Error';

  @override
  String get cfgbOnMissingNull => 'No value';

  @override
  String get cfgbOptionsFamily => 'Product family';

  @override
  String get cfgbOptionsFrom => 'Allowed alternatives (formula)';

  @override
  String get cfgbOptionsFromHelp =>
      'A list the user may choose from instead of the calculated value';

  @override
  String get cfgbOptionsStatic => 'Fixed list';

  @override
  String get cfgbOptionsTable => 'Table column';

  @override
  String get cfgbOrder => 'Order';

  @override
  String get cfgbOutputRules => 'Output rules';

  @override
  String get cfgbOverridable => 'The user may override it';

  @override
  String get cfgbOverridableHelp =>
      'Shown as calculated, pinned or pinned but stale';

  @override
  String get cfgbPattern => 'Pattern (regular expression)';

  @override
  String get cfgbPercentBase => 'Percentage of';

  @override
  String get cfgbPercentBaseList => 'the parent\'s list price';

  @override
  String get cfgbPercentBaseNet => 'the parent\'s net price';

  @override
  String get cfgbPercentOfParent => 'Percent of parent (formula)';

  @override
  String get cfgbPercentOfParentHelp =>
      'Prices the line as this percentage of the parent line, e.g. 20';

  @override
  String cfgbProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
    );
    return '$_temp0';
  }

  @override
  String get cfgbProductFilter => 'Product filter (formula on p)';

  @override
  String get cfgbProductFilterHelp => 'e.g. p.attr(\'kw\') >= 1';

  @override
  String get cfgbQuantity => 'Quantity (formula)';

  @override
  String get cfgbQuantityHelp =>
      'Defaults to 1; zero or less leaves the line out';

  @override
  String get cfgbRangeKey => 'Range key';

  @override
  String get cfgbRangeKeyHelp => 'The lookup key carrying the value';

  @override
  String get cfgbRangeMax => 'Maximum column';

  @override
  String get cfgbRangeMin => 'Minimum column';

  @override
  String get cfgbRawJson => 'Definition as JSON';

  @override
  String get cfgbRemoveColumn => 'Remove column';

  @override
  String get cfgbRemoveItemTable => 'Remove item table';

  @override
  String get cfgbRemoveRow => 'Remove row';

  @override
  String get cfgbReplace => 'Replace';

  @override
  String get cfgbRequired => 'Required';

  @override
  String get cfgbRevisions => 'Revisions';

  @override
  String cfgbRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return '$_temp0';
  }

  @override
  String cfgbRuleTitle(String id) {
    return 'Output rule $id';
  }

  @override
  String get cfgbSavedValid => 'Saved. The draft can be activated.';

  @override
  String cfgbSavedWithProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
    );
    return 'Saved with $_temp0.';
  }

  @override
  String get cfgbScope => 'Scope';

  @override
  String get cfgbScopeGroup => 'Group';

  @override
  String get cfgbScopeItem => 'Item (row)';

  @override
  String cfgbScopeItems(String table) {
    return 'Items: $table';
  }

  @override
  String get cfgbScopeProject => 'Project';

  @override
  String get cfgbScopes => 'Scopes';

  @override
  String get cfgbSection => 'Section';

  @override
  String get cfgbSectionTemplate => 'Section (template)';

  @override
  String get cfgbSectionTemplateHelp =>
      'Defaults to the group name for group and item rules';

  @override
  String get cfgbSelectComputed => 'Choose a computed value or add one.';

  @override
  String get cfgbSelectField => 'Choose a field or add one.';

  @override
  String get cfgbSelectRule => 'Choose an output rule or add one.';

  @override
  String get cfgbSelectTable => 'Choose a table or add one.';

  @override
  String get cfgbSelectValidation => 'Choose a check or add one.';

  @override
  String get cfgbSeverity => 'Severity';

  @override
  String get cfgbSeverityError => 'Error';

  @override
  String get cfgbSeverityInfo => 'Information';

  @override
  String get cfgbSeverityWarning => 'Warning';

  @override
  String get cfgbShow => 'Shown to the user';

  @override
  String get cfgbShownAt => 'Shown at field';

  @override
  String get cfgbStatusActive => 'active';

  @override
  String get cfgbStatusDraft => 'draft';

  @override
  String get cfgbStatusObsolete => 'obsolete';

  @override
  String get cfgbStep => 'Step';

  @override
  String get cfgbTabComputed => 'Computed values';

  @override
  String get cfgbTabFields => 'Fields & layout';

  @override
  String get cfgbTabGeneral => 'General';

  @override
  String get cfgbTable => 'Table';

  @override
  String get cfgbTableKind => 'Kind';

  @override
  String get cfgbTables => 'Lookup tables';

  @override
  String cfgbTableTitle(String name) {
    return 'Table $name';
  }

  @override
  String get cfgbTabOutputs => 'Output rules';

  @override
  String get cfgbTabTables => 'Tables';

  @override
  String get cfgbTabTest => 'Test';

  @override
  String get cfgbTabTransfer => 'Import/export';

  @override
  String get cfgbTabValidations => 'Checks';

  @override
  String get cfgbTestHelp =>
      'Try the saved draft as sales will see it. Nothing is saved; select a line to see why it is there.';

  @override
  String get cfgbTestNeedsValid =>
      'The saved draft has problems; the test may fail until they are solved.';

  @override
  String get cfgbTestReset => 'Start again';

  @override
  String get cfgbTestUnsaved =>
      'The test uses the saved draft; save to include your latest changes.';

  @override
  String get cfgbTranslations => 'Translations';

  @override
  String get cfgbTypeBoolean => 'Yes/no';

  @override
  String get cfgbTypeChoice => 'Choice';

  @override
  String get cfgbTypeInteger => 'Whole number';

  @override
  String get cfgbTypeNumber => 'Number';

  @override
  String get cfgbTypeProduct => 'Product';

  @override
  String get cfgbTypeText => 'Text';

  @override
  String get cfgbUnsavedText => 'The draft has changes that are not saved.';

  @override
  String get cfgbUnsavedTitle => 'Unsaved changes';

  @override
  String get cfgbValidations => 'Checks';

  @override
  String cfgbValidationTitle(String id) {
    return 'Check $id';
  }

  @override
  String get cfgbValidationWhenHelp => 'When true, the message is shown';

  @override
  String get cfgbValue => 'Value';

  @override
  String get cfgbVisibleIf => 'Visible when';

  @override
  String get cfgbWhen => 'When';

  @override
  String get cfgbWhenHelp => 'Lines are only made when this is true';

  @override
  String get cfgbWidth => 'Width';

  @override
  String get tabProductionOrder => 'Production order';

  @override
  String get tabDeliveryNote => 'Delivery note';

  @override
  String get vatRegime => 'VAT regime';

  @override
  String get vatRegimeDomestic => 'EU customer, VAT charged';

  @override
  String get vatRegimeIntraEu => 'EU business, VAT reverse-charged';

  @override
  String get vatRegimeOutsideEu => 'Outside the EU, no VAT';

  @override
  String get addSubItem => 'Add sub-item';

  @override
  String subItemsOptions(String product) {
    return 'Options of $product';
  }

  @override
  String get subItemsNoOptions => 'This product has no options defined.';

  @override
  String get subItemsOtherProducts => 'Other products';

  @override
  String get crTitle => 'Reports';

  @override
  String get crNew => 'New report';

  @override
  String get crEmpty =>
      'No reports yet. Build one to see your data grouped and summed.';

  @override
  String get crShared => 'Shared';

  @override
  String get crPrivate => 'Private';

  @override
  String get crShare => 'Share with everyone in the company';

  @override
  String crOwnedBy(String name) {
    return 'By $name';
  }

  @override
  String get crObject => 'Report on';

  @override
  String get crJoin => 'Add related data';

  @override
  String get crGroupBy => 'Group by';

  @override
  String get crAddGrouping => 'Add grouping';

  @override
  String get crColumns => 'Columns';

  @override
  String get crAddColumn => 'Add column';

  @override
  String get crField => 'Field';

  @override
  String get crSummary => 'Summary';

  @override
  String get crSummaryNone => 'Show value';

  @override
  String get crSumCount => 'Count';

  @override
  String get crSumSum => 'Sum';

  @override
  String get crSumAvg => 'Average';

  @override
  String get crSumMin => 'Minimum';

  @override
  String get crSumMax => 'Maximum';

  @override
  String get crFilters => 'Filters';

  @override
  String get crAddFilter => 'Add filter';

  @override
  String get crMatchAll => 'All filters must match';

  @override
  String get crMatchAny => 'At least one filter must match';

  @override
  String get crOpEq => 'equals';

  @override
  String get crOpNe => 'does not equal';

  @override
  String get crOpGt => 'greater than';

  @override
  String get crOpGte => 'at least';

  @override
  String get crOpLt => 'less than';

  @override
  String get crOpLte => 'at most';

  @override
  String get crOpContains => 'contains';

  @override
  String get crOpStartsWith => 'starts with';

  @override
  String get crOpIn => 'is one of';

  @override
  String get crOpIsNull => 'is empty';

  @override
  String get crOpNotNull => 'is not empty';

  @override
  String get crValue => 'Value';

  @override
  String get crValueListHint => 'Separate values with commas';

  @override
  String get crBucketNone => 'Exact value';

  @override
  String get crBucketDay => 'By day';

  @override
  String get crBucketMonth => 'By month';

  @override
  String get crBucketYear => 'By year';

  @override
  String get crSort => 'Sort';

  @override
  String get crAddSort => 'Add sort';

  @override
  String get crDescending => 'Descending';

  @override
  String get crChart => 'Chart';

  @override
  String get crChartNone => 'No chart';

  @override
  String get crChartBar => 'Bar';

  @override
  String get crChartLine => 'Line';

  @override
  String get crChartPie => 'Pie';

  @override
  String get crChartX => 'Categories';

  @override
  String get crChartY => 'Values';

  @override
  String crRows(int count) {
    return '$count rows';
  }

  @override
  String crRowsShown(int shown, int total) {
    return '$shown of $total rows shown';
  }

  @override
  String crChartShareShown(int count) {
    return 'Shares are of the $count groups shown.';
  }

  @override
  String get crSaved => 'Report saved';

  @override
  String get crDeleted => 'Report deleted';

  @override
  String get crDelete => 'Delete';

  @override
  String get crDeleteConfirm => 'Delete this report?';

  @override
  String get crExportCsv => 'Export CSV';

  @override
  String get crExportPdf => 'Export PDF';

  @override
  String get crNeedName => 'Give the report a name.';

  @override
  String get crNeedColumn => 'Add at least one column.';

  @override
  String get crLoadMore => 'Show more rows';

  @override
  String get crNoRows => 'No rows match this report.';

  @override
  String get crRun => 'Run';

  @override
  String get crDateMode => 'Date';

  @override
  String get crDateFixed => 'Fixed date';

  @override
  String get crDateRelative => 'Relative to today';

  @override
  String get crRelativePeriod => 'Period';

  @override
  String get crRelativeDays => 'Number of days';

  @override
  String get crRelativeDaysInvalid =>
      'Enter a whole number of days from 1 to 3660.';

  @override
  String get crRelToday => 'Today';

  @override
  String get crRelYesterday => 'Yesterday';

  @override
  String get crRelThisWeek => 'This week';

  @override
  String get crRelLastWeek => 'Last week';

  @override
  String get crRelThisMonth => 'This month';

  @override
  String get crRelLastMonth => 'Last month';

  @override
  String get crRelThisQuarter => 'This quarter';

  @override
  String get crRelLastQuarter => 'Last quarter';

  @override
  String get crRelThisYear => 'This year';

  @override
  String get crRelLastYear => 'Last year';

  @override
  String get crRelLastNDays => 'Last N days';

  @override
  String get crRelNextNDays => 'Next N days';

  @override
  String get envLive => 'Live';

  @override
  String get envTest => 'Test';

  @override
  String get envTutorial => 'Tutorial';

  @override
  String envBannerSemantics(String name, String kind) {
    return 'Environment $name, $kind';
  }

  @override
  String get envSwitcherTitle => 'Environments';

  @override
  String envSwitchMenu(String name) {
    return 'Environment: $name';
  }

  @override
  String get envSwitchTooltip => 'Switch environment';

  @override
  String get envActive => 'Active';

  @override
  String get envAdd => 'Add environment';

  @override
  String get envName => 'Name';

  @override
  String get envServerUrl => 'Server address';

  @override
  String get envCheck => 'Check server';

  @override
  String envDetected(String kind, String db) {
    return 'Server says: $kind environment, database $db';
  }

  @override
  String get envInvalidUrl =>
      'Enter a full address such as https://erp.example.com';

  @override
  String get envAlreadyListed => 'This server is already in the list.';

  @override
  String envUnreachable(String error) {
    return 'Could not read the environment from this server: $error';
  }

  @override
  String get envRemove => 'Remove';

  @override
  String get envRemoveTitle => 'Remove environment?';

  @override
  String envRemoveBody(String name) {
    return '$name is removed from this device, with its saved sign-in. Nothing changes on the server.';
  }

  @override
  String get envCannotRemoveActive => 'Switch to another environment first';

  @override
  String envUnsavedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open tabs have unsaved changes',
      one: '1 open tab has unsaved changes',
    );
    return '$_temp0. Switching environment closes all tabs and discards them.';
  }

  @override
  String get envDiscardAndSwitch => 'Discard and switch';

  @override
  String get adminPriceZones => 'Price zones';

  @override
  String get newPriceZone => 'New price zone';

  @override
  String get editPriceZone => 'Edit price zone';

  @override
  String get sortOrder => 'Sort order';

  @override
  String get noPriceZones => 'No price zones yet.';

  @override
  String get priceZoneDeleted => 'Price zone deleted';

  @override
  String get delete => 'Delete';

  @override
  String deletePriceZoneConfirm(String code) {
    return 'Delete price zone $code? This is refused when prices or customers use it.';
  }

  @override
  String get sortOrderInvalid => 'Sort order must be a whole number.';

  @override
  String get envNotSaved =>
      'Done, but the list of environments could not be saved on this device.';

  @override
  String get tutTitle => 'Tutorial';

  @override
  String get tutBack => 'Back';

  @override
  String get tutNext => 'Next';

  @override
  String get tutSkipStep => 'Skip step';

  @override
  String get tutPause => 'Pause';

  @override
  String get tutResume => 'Resume';

  @override
  String get tutPaused => 'Tutorial paused';

  @override
  String get tutTakeMe => 'Take me there';

  @override
  String tutStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get tutOfferTitle => 'Welcome to TradoCraft';

  @override
  String get tutOfferBody =>
      'This is a tutorial environment. Want a guided tour that teaches you the app step by step, on practice data?';

  @override
  String get tutOfferStart => 'Start the tutorial';

  @override
  String get tutOfferLater => 'Not now';

  @override
  String get tutLiveTitle => 'The tutorial does not run on live data';

  @override
  String get tutLiveBody =>
      'The tutorial creates records, so it only runs in a test or tutorial environment. Switch to one, or add one.';

  @override
  String get tutSwitchEnv => 'Switch environment';

  @override
  String get tutAddEnv => 'Add an environment';

  @override
  String get tutMapIntro =>
      'Work through the chapters in order. You can pause, replay or skip a chapter at any time.';

  @override
  String get tutStatusDone => 'Done';

  @override
  String get tutStatusCurrent => 'Up next';

  @override
  String get tutStatusLocked => 'Locked';

  @override
  String get tutStatusSkipped => 'Skipped';

  @override
  String get tutStatusPaused => 'In progress';

  @override
  String get tutStart => 'Start';

  @override
  String get tutReplay => 'Replay';

  @override
  String get tutSkipChapter => 'Skip chapter';

  @override
  String get tutWelcomeTitle => 'Welcome';

  @override
  String get tutWelcomeSummary =>
      'Find your way around: the environment banner, the tabs and the tutorial controls.';

  @override
  String get tutProductTitle => 'Your first product';

  @override
  String get tutProductSummary =>
      'Hat: product manager. Create three components, a finished product and its bill of materials.';

  @override
  String get tutWelcomeBannerTitle => 'The strip at the top';

  @override
  String get tutWelcomeBannerBody =>
      'This strip always shows which environment you are in: its name and its kind. Amber means test, blue means tutorial and red means live data. The tutorial only runs in test and tutorial environments, so nothing you do here touches real data.';

  @override
  String get tutWelcomeTabsTitle => 'Tabs and sections';

  @override
  String get tutWelcomeTabsBody =>
      'The sections are on the left (or in the bottom bar on a phone). Opening a record, such as a product or a quotation, adds a tab to the workspace, so you can keep several records open and come back to them.';

  @override
  String get tutWelcomeControlsTitle => 'This card';

  @override
  String get tutWelcomeControlsBody =>
      'I am your narrator. Next moves on when a step is only an explanation. Steps that ask you to do something finish by themselves as soon as you have done it. Back and Skip step let you move around, and Pause hides me until you press Resume.';

  @override
  String get tutWelcomeMenuTitle => 'Where to find me';

  @override
  String get tutWelcomeMenuBody =>
      'Open the account menu to find the Tutorial entry. It opens the chapter map, where you can resume, replay or skip a chapter at any time.';

  @override
  String get tutWelcomeProductsTitle => 'Let\'s start';

  @override
  String get tutWelcomeProductsBody =>
      'Open the Products section. The next chapter starts there.';

  @override
  String get tutProductOpenTitle => 'Products';

  @override
  String get tutProductOpenBody =>
      'Today you are the product manager. Everything the company sells or builds is a product. Open the Products section.';

  @override
  String get tutProductMotorTitle => 'Component: Motor';

  @override
  String get tutProductMotorBody =>
      'Create the first component. Press New product, enter code TUT-MOTOR and name Motor, keep the type Purchased, and save.';

  @override
  String get tutProductMotorHint =>
      'The TUT- prefix marks tutorial data, so you can recognise it later.';

  @override
  String get tutProductFrameTitle => 'Component: Frame';

  @override
  String get tutProductFrameBody =>
      'Create a second component the same way: code TUT-FRAME, name Frame, type Purchased.';

  @override
  String get tutProductControllerTitle => 'Component: Controller';

  @override
  String get tutProductControllerBody =>
      'And a third one: code TUT-CTRL, name Controller, type Purchased.';

  @override
  String get tutProductCartTitle => 'The finished product';

  @override
  String get tutProductCartBody =>
      'Now the product you build from those parts. Create code TUT-CART, name Cart, and choose the type Manufactured: only manufactured products have a bill of materials.';

  @override
  String get tutProductOpenCartTitle => 'Open the cart';

  @override
  String get tutProductOpenCartBody =>
      'Open the new Cart product from the list to see its tabs.';

  @override
  String get tutProductBomTabTitle => 'Bill of materials';

  @override
  String get tutProductBomTabBody =>
      'Choose the Bill of materials tab. It lists the components needed to build one unit. A revision is a draft you edit, or the active one that production uses. Press Next when you are there.';

  @override
  String get tutProductRevisionTitle => 'A first revision';

  @override
  String get tutProductRevisionBody => 'Press New revision to start a draft.';

  @override
  String get tutProductLinesTitle => 'Add the components';

  @override
  String get tutProductLinesBody =>
      'Search each component and add it: Motor, Frame and Controller. Then press Save draft.';

  @override
  String get tutProductLinesHint =>
      'Type TUT in the search box to find the three components.';

  @override
  String get tutProductActivateTitle => 'Activate it';

  @override
  String get tutProductActivateBody =>
      'Press Activate. From now on production and quotations use this revision; later changes go through a new revision.';

  @override
  String get tutProductDoneTitle => 'Well done';

  @override
  String get tutProductDoneBody =>
      'You have a finished product with a bill of materials of three components. Later chapters build on it.';

  @override
  String get purchasing => 'Purchasing';

  @override
  String get tabSupplier => 'Supplier';

  @override
  String get purchSuppliers => 'Suppliers';

  @override
  String get purchNewSupplier => 'New supplier';

  @override
  String get purchPaymentTerms => 'Payment terms';

  @override
  String purchDays(int count) {
    return '$count days';
  }

  @override
  String get purchActiveOnly => 'Active only';

  @override
  String get purchNameRequired => 'The name is required.';

  @override
  String get purchCountryInvalid => 'The country must be a 2-letter code.';

  @override
  String get purchCurrencyInvalid => 'The currency must be a 3-letter code.';

  @override
  String get purchTermsInvalid =>
      'Payment terms must be a whole number of days.';

  @override
  String get purchInactive => 'Inactive';

  @override
  String get purchPriceList => 'Price list';

  @override
  String get purchAddProduct => 'Add product';

  @override
  String get purchEditPrice => 'Edit price';

  @override
  String get purchNoPrices => 'No products on this price list yet.';

  @override
  String get purchPickProduct => 'Choose a product.';

  @override
  String get purchPriceInvalid => 'Enter a valid unit price.';

  @override
  String get purchMoqInvalid => 'Enter a valid minimum order quantity.';

  @override
  String get purchLeadInvalid => 'Lead time must be a whole number of days.';

  @override
  String get purchSupplierArticleCode => 'Supplier article code';

  @override
  String get purchSupplierArticleName => 'Supplier article name';

  @override
  String get purchMoq => 'Min. order qty';

  @override
  String get purchLeadTimeDays => 'Lead time (days)';

  @override
  String get purchPreferred => 'Preferred supplier';

  @override
  String purchRemoveProductConfirm(String code) {
    return 'Remove $code from this price list?';
  }

  @override
  String purchMoqValue(String qty) {
    return 'MOQ $qty';
  }

  @override
  String purchLeadValue(int days) {
    return 'lead time $days d';
  }

  @override
  String get purchNoSuppliers => 'No suppliers found.';

  @override
  String get purchOrders => 'Purchase orders';

  @override
  String get purchNewOrder => 'New purchase order';

  @override
  String get purchNoOrders => 'No purchase orders found.';

  @override
  String get purchOrderNumber => 'Number';

  @override
  String get purchSupplier => 'Supplier';

  @override
  String get purchAllSuppliers => 'All suppliers';

  @override
  String get purchOrderDate => 'Order date';

  @override
  String get purchExpectedDate => 'Expected delivery';

  @override
  String get purchStatusDraft => 'draft';

  @override
  String get purchStatusApproved => 'approved';

  @override
  String get purchStatusSent => 'sent';

  @override
  String get purchStatusPartial => 'partially received';

  @override
  String get purchStatusReceived => 'received';

  @override
  String get purchStatusCancelled => 'cancelled';

  @override
  String get purchLines => 'Lines';

  @override
  String get purchAddLine => 'Add line';

  @override
  String get purchPickSupplier => 'Choose a supplier.';

  @override
  String get purchLineQtyInvalid =>
      'Quantity must be greater than zero, with at most 4 decimals.';

  @override
  String get purchLinePriceInvalid =>
      'Unit price must be zero or more, with at most 4 decimals.';

  @override
  String get purchNeedLine => 'Add at least one line.';

  @override
  String get purchApprove => 'Approve';

  @override
  String get purchCancelOrder => 'Cancel order';

  @override
  String purchCancelOrderConfirm(String number) {
    return 'Cancel purchase order $number? This cannot be undone.';
  }

  @override
  String get purchKeepOrder => 'Keep order';

  @override
  String get purchQtyReceived => 'Received';

  @override
  String get purchLineTotal => 'Line total';

  @override
  String get purchSubtotal => 'Subtotal';

  @override
  String get purchTax => 'Tax';

  @override
  String get tabPurchaseOrder => 'Purchase order';

  @override
  String get purchReceiveGoods => 'Receive goods';

  @override
  String purchReceiveTitle(String number) {
    return 'Receive goods for $number';
  }

  @override
  String get purchReceiveDestination => 'Destination location';

  @override
  String get purchReceiveQty => 'Quantity to receive';

  @override
  String purchReceiveRemaining(String qty) {
    return 'Remaining: $qty';
  }

  @override
  String get purchReceiveSerialsHelp => 'One serial number per line';

  @override
  String get purchDeliveryNote => 'Supplier delivery note';

  @override
  String purchReceiveQtyInvalid(String product, String max) {
    return '$product: enter a quantity between 0 and $max.';
  }

  @override
  String purchReceiveLotNeeded(String product) {
    return '$product: enter a lot number.';
  }

  @override
  String purchReceiveSerialWhole(String product) {
    return '$product: the quantity must be a whole number.';
  }

  @override
  String purchReceiveSerialCount(String product, int count) {
    return '$product: enter exactly $count different serial numbers.';
  }

  @override
  String get purchReceiveNothing => 'Enter a quantity for at least one line.';

  @override
  String get purchReceiveLocationNeeded => 'Choose a destination location.';

  @override
  String purchReceiptBooked(String number) {
    return 'Goods receipt $number booked.';
  }

  @override
  String get purchOpenReceipt => 'Open receipt';

  @override
  String get purchReceipts => 'Goods receipts';

  @override
  String get purchReceivedDate => 'Received';

  @override
  String get purchOpenOrder => 'Purchase order';

  @override
  String get tabGoodsReceipt => 'Goods receipt';

  @override
  String get setupTitle => 'Set up a new company';

  @override
  String get setupOffer => 'Set up a new company';

  @override
  String get setupOfferHint => 'This server has no company yet.';

  @override
  String setupServer(String url) {
    return 'Server: $url';
  }

  @override
  String setupStepOf(int n, int total) {
    return 'Step $n of $total';
  }

  @override
  String get setupStepCompany => 'Company';

  @override
  String get setupStepRegion => 'Country, currency and language';

  @override
  String get setupStepAdmin => 'Administrator';

  @override
  String get setupStepToken => 'Setup token';

  @override
  String get setupStepReview => 'Review';

  @override
  String get setupCompanyName => 'Company name';

  @override
  String get setupLegalName => 'Legal name (optional)';

  @override
  String get setupVatNumber => 'VAT number (optional)';

  @override
  String get setupCountry => 'Country code (2 letters, e.g. BE)';

  @override
  String get setupCurrency => 'Currency (3 letters, e.g. EUR)';

  @override
  String get setupLanguage => 'Default language';

  @override
  String get setupAdminEmail => 'Administrator e-mail';

  @override
  String get setupAdminName => 'Administrator name';

  @override
  String get setupToken => 'Setup token';

  @override
  String get setupTokenHelp => 'The value of BOOTSTRAP_TOKEN on the server.';

  @override
  String get setupErrName => 'Enter the company name.';

  @override
  String get setupErrVat => 'A VAT number has 4 to 20 letters and digits.';

  @override
  String get setupErrCountry => 'Enter a two-letter country code.';

  @override
  String get setupErrCurrency => 'Enter a three-letter currency code.';

  @override
  String get setupErrEmail => 'Enter a valid e-mail address.';

  @override
  String get setupErrAdminName => 'Enter the administrator\'s name.';

  @override
  String get setupErrToken => 'Enter the setup token.';

  @override
  String get setupNext => 'Next';

  @override
  String get setupBack => 'Back';

  @override
  String get setupCreate => 'Create company';

  @override
  String get setupReviewHint =>
      'Check the details. A company can be created only once on this server.';

  @override
  String get setupErr403 => 'The setup token is missing or wrong.';

  @override
  String get setupErr404 =>
      'Setting up is disabled on this server. Set BOOTSTRAP_TOKEN on the server and restart it.';

  @override
  String get setupErr409 => 'This server already has a company.';

  @override
  String setupDone(String name) {
    return 'Company $name created.';
  }

  @override
  String setupDoneDev(String email) {
    return 'Signing in as $email.';
  }

  @override
  String setupDoneOidc(String email) {
    return 'Sign in through your identity provider with $email: that account is the administrator.';
  }

  @override
  String get setupToLogin => 'Go to sign in';

  @override
  String get setupAddOfferTitle => 'Set up this server?';

  @override
  String get setupAddOfferBody =>
      'This server has no company yet. Set one up now?';

  @override
  String get setupLater => 'Later';

  @override
  String get finMatchColumn => 'Match';

  @override
  String get finance => 'Finance';

  @override
  String get finSupplierInvoices => 'Supplier invoices';

  @override
  String get finSettings => 'Settings';

  @override
  String get tabSupplierInvoice => 'Supplier invoice';

  @override
  String get finNewInvoice => 'New supplier invoice';

  @override
  String get finNoInvoices => 'No supplier invoices found.';

  @override
  String get finInvoiceNumber => 'Invoice number';

  @override
  String get finInternalNumber => 'Internal number';

  @override
  String get finInvoiceDate => 'Invoice date';

  @override
  String get finDueDate => 'Due date';

  @override
  String get finStatusDraft => 'draft';

  @override
  String get finStatusMatched => 'matched';

  @override
  String get finStatusDisputed => 'disputed';

  @override
  String get finStatusApproved => 'approved';

  @override
  String get finStatusPaid => 'paid';

  @override
  String get finMatchOk => 'ok';

  @override
  String get finMatchNotReceived => 'not received';

  @override
  String get finMatchOverInvoiced => 'over invoiced';

  @override
  String get finMatchPriceVariance => 'price variance';

  @override
  String get finMatchNoPoLine => 'no order line';

  @override
  String get finOrderOptional => 'Purchase order (optional)';

  @override
  String get finNoOrder => 'No purchase order';

  @override
  String get finOrderPrefillHint =>
      'The lines are filled from the goods received and not yet invoiced.';

  @override
  String get finNumberRequired =>
      'The invoice number is required (at most 64 characters).';

  @override
  String get finLineDescriptionRequired =>
      'A free-text line needs a description.';

  @override
  String get finVatInvalid =>
      'VAT rate must be between 0 and 100 with at most 2 decimals.';

  @override
  String get finOrdered => 'Ordered';

  @override
  String get finInvoiced => 'Invoiced';

  @override
  String get finOrderPrice => 'Order price';

  @override
  String get finInvoicePrice => 'Invoice price';

  @override
  String get finVariance => 'Variance';

  @override
  String get finMatches => 'The invoice matches the order and the receipts.';

  @override
  String get finNotMatches =>
      'The invoice does not match the order and the receipts.';

  @override
  String finTolerances(String qty, String price) {
    return 'Tolerances: quantity $qty %, price $price %';
  }

  @override
  String get finSubmitMatch => 'Check match';

  @override
  String get finApprove => 'Approve';

  @override
  String get finOverrideTitle => 'Approve despite mismatch';

  @override
  String get finOverrideHelp =>
      'The invoice does not match. Give the reason for approving it anyway; it is stored with the approval.';

  @override
  String get finOverrideReason => 'Override reason';

  @override
  String get finReasonRequired => 'A reason is required.';

  @override
  String get finDispute => 'Dispute';

  @override
  String get finDisputeReason => 'Dispute reason';

  @override
  String get finReopen => 'Reopen';

  @override
  String get finMarkPaid => 'Mark as paid';

  @override
  String get finPaymentDate => 'Payment date';

  @override
  String get finPaymentReference => 'Payment reference';

  @override
  String get finDeleteDraft => 'Delete draft';

  @override
  String finDeleteConfirm(String number) {
    return 'Delete invoice $number? This cannot be undone.';
  }

  @override
  String get finNetTotal => 'Net';

  @override
  String get finGrossTotal => 'Total incl. VAT';

  @override
  String get finDisputeReasonShown => 'Dispute reason';

  @override
  String get finOverrideShown => 'Override reason';

  @override
  String get finPaidOn => 'Paid on';

  @override
  String get finPurchaseOrder => 'Purchase order';

  @override
  String get finQuantityTolerance => 'Quantity tolerance (%)';

  @override
  String get finPriceTolerance => 'Price tolerance (%)';

  @override
  String get finToleranceInvalid => 'Enter a percentage between 0 and 100.';

  @override
  String get finSettingsSaved => 'Settings saved.';

  @override
  String get finSettingsHelp =>
      'Largest accepted difference between the order and the invoice before a line counts as a mismatch.';

  @override
  String get finCreateInvoice => 'Create supplier invoice';

  @override
  String get userRoleFinance => 'Finance';

  @override
  String get moduleFinance => 'Finance';

  @override
  String get productionDivisionMembers => 'Members';

  @override
  String get productionDivisionNoMembers => 'No members';

  @override
  String get productionScopeMine => 'My divisions';

  @override
  String get productionScopeAll => 'All divisions';

  @override
  String get productionScopeEmpty =>
      'No orders in your divisions. Orders without a division are included.';

  @override
  String get productionShowAllDivisions => 'Show all divisions';

  @override
  String get productionYourDivisions => 'Your divisions';

  @override
  String get setupErrInsecure =>
      'The setup token is not sent over an unencrypted connection to another computer. Use an https:// address (plain http is only allowed for localhost).';

  @override
  String get setupUnavailable =>
      'Setting up is not available on this server: it already has a company, or setting up is disabled.';

  @override
  String get setupErrRedirect =>
      'The server redirected the request, so the setup token was not sent on. Check the server address (use the final https:// address).';

  @override
  String get tutSuppliersTitle => 'Suppliers';

  @override
  String get tutSuppliersSummary =>
      'Hat: purchaser. Create two suppliers and give them a price list for your components.';

  @override
  String get tutSuppliersNeedsTitle => 'Chapter 1 first';

  @override
  String get tutSuppliersNeedsBody =>
      'This chapter needs the four products from chapter 1 (TUT-MOTOR, TUT-FRAME, TUT-CTRL and TUT-CART) and could not find them. Go back to the chapter map and finish chapter 1 first, then come back here.';

  @override
  String get tutSuppliersOpenTitle => 'Put on the purchaser hat';

  @override
  String get tutSuppliersOpenBody =>
      'Your components have to come from somewhere. Open Purchasing in the menu: the Suppliers list is the first segment.';

  @override
  String get tutSuppliersSupplierATitle => 'The first supplier';

  @override
  String get tutSuppliersSupplierABody =>
      'Create a supplier with code TUT-SUP-A and name Voltaic Drives Ltd. Code and name are the only required fields; payment terms, tax id and contact details can follow later.';

  @override
  String get tutSuppliersSupplierBTitle => 'A second supplier';

  @override
  String get tutSuppliersSupplierBBody =>
      'A purchaser likes to compare. Create a second supplier with code TUT-SUP-B and name Ironbridge Frames.';

  @override
  String get tutSuppliersOpenATitle => 'Open the first supplier';

  @override
  String get tutSuppliersOpenABody =>
      'Open Voltaic Drives Ltd from the list. Its price list is at the bottom of the supplier screen.';

  @override
  String get tutSuppliersPriceMotorTitle => 'A price for the motor';

  @override
  String get tutSuppliersPriceMotorBody =>
      'Add TUT-MOTOR to the price list: unit price 120, lead time 14 days, minimum order quantity 5. Purchase orders use these values to pre-fill their lines.';

  @override
  String get tutSuppliersPriceMotorHint =>
      'Pick the product with the search box in the dialog; type TUT-MOTOR.';

  @override
  String get tutSuppliersPriceFrameTitle => 'A price for the frame';

  @override
  String get tutSuppliersPriceFrameBody =>
      'Same again for TUT-FRAME: unit price 45, lead time 10 days, minimum order quantity 5.';

  @override
  String get tutSuppliersPriceControllerTitle => 'A price for the controller';

  @override
  String get tutSuppliersPriceControllerBody =>
      'And TUT-CTRL: unit price 30, lead time 7 days, minimum order quantity 5. This supplier now covers all three components.';

  @override
  String get tutSuppliersOpenBTitle => 'Open the second supplier';

  @override
  String get tutSuppliersOpenBBody =>
      'Go back to the list and open Ironbridge Frames.';

  @override
  String get tutSuppliersPriceMotorBTitle => 'A competing price';

  @override
  String get tutSuppliersPriceMotorBBody =>
      'Give this supplier a price for TUT-MOTOR too: unit price 135, lead time 5 days, minimum order quantity 1. It is dearer but faster; that is the kind of choice a price list helps with.';

  @override
  String get tutSuppliersDoneTitle => 'What you learned';

  @override
  String get tutSuppliersDoneBody =>
      'A supplier is a record with payment terms and contacts, and its price list links it to products with a price, a lead time and a minimum order quantity. Next: ordering the goods.';

  @override
  String get tutBuyingTitle => 'Buying and receiving';

  @override
  String get tutBuyingSummary =>
      'Hats: purchaser and goods-in. Order the components, send the order and receive the goods in two deliveries.';

  @override
  String get tutBuyingNeedsTitle => 'Chapters 1 and 2 first';

  @override
  String get tutBuyingNeedsBody =>
      'This chapter needs the products of chapter 1 and the supplier Voltaic Drives Ltd with its price list from chapter 2, and could not find the products. Finish those chapters first.';

  @override
  String get tutBuyingOpenTitle => 'The orders list';

  @override
  String get tutBuyingOpenBody =>
      'Open Purchasing. Next to Suppliers there is a segment for purchase orders; open it.';

  @override
  String get tutBuyingOrderTitle => 'Order the components';

  @override
  String get tutBuyingOrderBody =>
      'Create a purchase order for Voltaic Drives Ltd with three lines: TUT-MOTOR, TUT-FRAME and TUT-CTRL, 30 pieces each. The prices come from the price list.';

  @override
  String get tutBuyingOrderHint =>
      'Choose the supplier first: the line prices fill in once its price list has loaded. Use Add line for the second and third component.';

  @override
  String get tutBuyingOpenOrderTitle => 'The order screen';

  @override
  String get tutBuyingOpenOrderBody =>
      'Open the order you just made. A purchase order is a draft first; the buttons at the top follow its life: approve, send, receive.';

  @override
  String get tutBuyingApproveTitle => 'Approve the order';

  @override
  String get tutBuyingApproveBody =>
      'Approving is a separate permission, so a purchaser can prepare orders that a manager releases. As admin you wear both hats: press Approve.';

  @override
  String get tutBuyingSendTitle => 'Send it to the supplier';

  @override
  String get tutBuyingSendBody =>
      'Press Send. The order is marked as sent and the supplier gets it. In test and tutorial environments outgoing mail is only written to files on the server, nothing leaves the building.';

  @override
  String get tutBuyingReceivePartTitle => 'The first delivery arrives';

  @override
  String get tutBuyingReceivePartBody =>
      'Put on the goods-in hat. Press Receive goods, choose the warehouse location MAIN and book 10 pieces of each component, fewer than ordered. The order becomes partially received.';

  @override
  String get tutBuyingReceivePartHint =>
      'Change the quantity of each line in the dialog; the remaining quantity is shown next to it. A delivery note number is optional.';

  @override
  String get tutBuyingReceiveRestTitle => 'The rest arrives';

  @override
  String get tutBuyingReceiveRestBody =>
      'Receive the remaining 20 pieces of each component the same way. When everything is in, the order is fully received; each delivery keeps its own goods receipt.';

  @override
  String get tutBuyingStockTitle => 'Look at the stock';

  @override
  String get tutBuyingStockBody =>
      'Open Stock. The 30 motors, frames and controllers are on hand in warehouse MAIN. Every receipt created a stock movement, so the quantity can always be traced back.';

  @override
  String get tutBuyingDoneTitle => 'What you learned';

  @override
  String get tutBuyingDoneBody =>
      'A purchase order goes draft, approved, sent, received. Goods can arrive in several deliveries and every delivery adds to stock. The supplier\'s invoice comes next.';

  @override
  String get tutInvoicesTitle => 'Checking the invoices';

  @override
  String get tutInvoicesSummary =>
      'Hat: accountant. Register supplier invoices, read the three-way match, approve, dispute and pay.';

  @override
  String get tutInvoicesNeedsTitle => 'Chapter 3 first';

  @override
  String get tutInvoicesNeedsBody =>
      'This chapter needs the purchase order from chapter 3, fully received, and it is not (yet). Finish chapter 3 first.';

  @override
  String get tutInvoicesOpenOrderTitle => 'Back to the order';

  @override
  String get tutInvoicesOpenOrderBody =>
      'The supplier\'s invoice arrives. Open the purchase order from chapter 3 again: once goods are received it offers a shortcut to register the invoice.';

  @override
  String get tutInvoicesCreateTitle => 'Register the invoice';

  @override
  String get tutInvoicesCreateBody =>
      'Press Create supplier invoice. Type the supplier\'s own invoice number, for example TUT-INV-001, and save. The lines are filled in from what was ordered and received, so there is nothing to type.';

  @override
  String get tutInvoicesCreateHint =>
      'The invoice date and due date default to today and to the payment terms of the supplier.';

  @override
  String get tutInvoicesMatchTitle => 'The three-way match';

  @override
  String get tutInvoicesMatchBody =>
      'The banner compares three documents: what was ordered, what was received and what is invoiced, line by line. Green means they agree within the tolerances; the tolerances are shown in the banner. Press Next when you have looked.';

  @override
  String get tutInvoicesApproveTitle => 'Approve the invoice';

  @override
  String get tutInvoicesApproveBody =>
      'The match is green, so press Approve. An approved invoice is ready for payment.';

  @override
  String get tutInvoicesSecondTitle => 'A suspicious invoice';

  @override
  String get tutInvoicesSecondBody =>
      'Now a second invoice arrives from Voltaic Drives Ltd, this time without a purchase order: in Finance, create a supplier invoice for that supplier, number TUT-INV-002, leave the order empty and add one line with description Motors, quantity 10, unit price 150.';

  @override
  String get tutInvoicesSecondHint =>
      'The real motor price is 120 and this line has no order line to compare with. The app cannot change prices of an order-based invoice, so a free-text invoice is how a mismatch shows up here.';

  @override
  String get tutInvoicesMismatchTitle => 'The match fails';

  @override
  String get tutInvoicesMismatchBody =>
      'The banner is orange: a free-text line has nothing it can be matched against, so it cannot be checked against an order or a receipt. The line shows why. Press Next when you have looked.';

  @override
  String get tutInvoicesDisputeTitle => 'Dispute the invoice';

  @override
  String get tutInvoicesDisputeBody =>
      'Press Dispute and give a reason, for example price does not match the agreement. A disputed invoice cannot be paid until it is reopened. (An approver can also approve a failed match with an override reason, which is kept on the invoice.)';

  @override
  String get tutInvoicesTolerancesTitle => 'The tolerances';

  @override
  String get tutInvoicesTolerancesBody =>
      'How far an invoice may differ is a setting: open the Settings segment of Finance to see the quantity and price tolerances in percent. Look, then press Next; changing them is up to you.';

  @override
  String get tutInvoicesPayTitle => 'Pay the good invoice';

  @override
  String get tutInvoicesPayBody =>
      'Open the first supplier invoice you registered (the one that matched and was approved) and press Mark as paid. Enter a payment reference such as TUT-PAY-001. The app records the payment; the bank transfer itself happens elsewhere.';

  @override
  String get tutInvoicesDoneTitle => 'What you learned';

  @override
  String get tutInvoicesDoneBody =>
      'The three-way match compares order, receipt and invoice before money moves. Matching invoices are approved and paid, doubtful ones are disputed. Next: building the carts yourself.';

  @override
  String get tutManufacturingTitle => 'Manufacturing';

  @override
  String get tutManufacturingSummary =>
      'Hats: production manager and production worker. Set up a division, then build five carts from the components.';

  @override
  String get tutManufacturingNeedsTitle => 'Chapters 1 to 3 first';

  @override
  String get tutManufacturingNeedsBody =>
      'This chapter needs the cart with its bill of materials (chapter 1) and components in stock (chapter 3), and could not find the products. Finish those chapters first.';

  @override
  String get tutManufacturingOpenDivisionsTitle => 'Divisions';

  @override
  String get tutManufacturingOpenDivisionsBody =>
      'Production work is organised in divisions, for example an assembly line. Only an administrator defines them. Open Production and use the gear button at the top right to reach the divisions.';

  @override
  String get tutManufacturingDivisionTitle => 'Create a division';

  @override
  String get tutManufacturingDivisionBody =>
      'Add a division with code TUT-ASM and name Tutorial assembly, and tick yourself in the member list: members are the workers of the division.';

  @override
  String get tutManufacturingDivisionHint =>
      'The dialog lists the users of the company; tick the chip with your own name.';

  @override
  String get tutManufacturingQueueTitle => 'The production queue';

  @override
  String get tutManufacturingQueueBody =>
      'Go back to Production. In the queue header choose My divisions: it shows the orders of your divisions plus orders without a division, so nothing unassigned is hidden. You are a member of a division, so this is the default for you; choose All divisions to see everything.';

  @override
  String get tutManufacturingReleaseTitle => 'Release a production order';

  @override
  String get tutManufacturingReleaseBody =>
      'Press Build for stock, choose TUT-CART and quantity 5, and release. The bill of materials is frozen and the components are reserved. Normally production starts from a sales order line; you will see that in chapter 9.';

  @override
  String get tutManufacturingReleaseHint =>
      'Only manufactured products with an active bill of materials can be released.';

  @override
  String get tutManufacturingAssignTitle => 'Give it to the division';

  @override
  String get tutManufacturingAssignBody =>
      'The new order is open. Choose the division Tutorial assembly in the Division field and press Save, so that the order shows up in the queue of that division.';

  @override
  String get tutManufacturingStartTitle => 'Start the work';

  @override
  String get tutManufacturingStartBody =>
      'Put on the worker hat and press Start. The order moves from released to in progress.';

  @override
  String get tutManufacturingCompleteTitle => 'Complete the order';

  @override
  String get tutManufacturingCompleteBody =>
      'Press Complete. The dialog shows the output quantity (5) and the components consumed. Confirm: the components leave the stock and five finished carts enter it.';

  @override
  String get tutManufacturingCompleteHint =>
      'Leave the planned values as they are; the dialog lets you record scrap or extra consumption when reality differs.';

  @override
  String get tutManufacturingStockTitle => 'Check the stock';

  @override
  String get tutManufacturingStockBody =>
      'Open Stock: TUT-CART now has 5 on hand, and each component is down by 5 (25 left of each). Production is what links purchasing to selling.';

  @override
  String get tutManufacturingDoneTitle => 'What you learned';

  @override
  String get tutManufacturingDoneBody =>
      'Divisions group production workers; a production order freezes the bill of materials, reserves components, is started and completed, and turns components into finished goods. Next: prices.';

  @override
  String get tutPricesTitle => 'Prices and zones';

  @override
  String get tutPricesSummary =>
      'Hat: sales manager. Create a price zone and give the cart a price in two zones.';

  @override
  String get tutPricesNeedsTitle => 'Chapter 1 first';

  @override
  String get tutPricesNeedsBody =>
      'This chapter needs the cart from chapter 1 and could not find it. Finish chapter 1 first.';

  @override
  String get tutPricesOpenAdminTitle => 'Open the admin area';

  @override
  String get tutPricesOpenAdminBody =>
      'A price depends on the customer\'s zone: a country or market with its own price list. Zones are managed under Admin. Open Admin and choose the Price zones segment; the company already has zones Z1 to Z5.';

  @override
  String get tutPricesZoneTitle => 'Create a zone';

  @override
  String get tutPricesZoneBody =>
      'Add a price zone with code TUT-EXPORT and name Export zone. Customers are placed in a zone later, when you create one.';

  @override
  String get tutPricesZoneHint =>
      'Choose the Price zones segment at the top of the Admin page first.';

  @override
  String get tutPricesOpenCartTitle => 'Open the cart';

  @override
  String get tutPricesOpenCartBody =>
      'Open the product TUT-CART from the Products list. Its first tab, Prices, holds the prices per zone.';

  @override
  String get tutPricesPriceExportTitle => 'A price in the new zone';

  @override
  String get tutPricesPriceExportBody =>
      'Press New price, choose zone TUT-EXPORT, enter unit price 1450 (excluding VAT) and save.';

  @override
  String get tutPricesPriceExportHint =>
      'The valid-from date defaults to today; a later date schedules a price change.';

  @override
  String get tutPricesPriceHomeTitle => 'A price in another zone';

  @override
  String get tutPricesPriceHomeBody =>
      'Add a second price for the cart in one of the existing zones, for example Z1 at 1200. The same product can now cost different amounts depending on the customer\'s zone.';

  @override
  String get tutPricesDoneTitle => 'What you learned';

  @override
  String get tutPricesDoneBody =>
      'A price zone groups customers that get the same price list, and a product has one price per zone and date. Quotations pick the price of the customer\'s zone. Next: a new customer writes in.';

  @override
  String get tutCustomerTitle => 'A new customer writes in';

  @override
  String get tutCustomerSummary =>
      'Hats: sales and helpdesk. A customer e-mail becomes a ticket; the sender is new, so you ask for company details and create the customer.';

  @override
  String get tutCustomerNeedsTitle => 'Chapter 6 first';

  @override
  String get tutCustomerNeedsBody =>
      'This chapter needs the price zone TUT-EXPORT from chapter 6 (the new customer gets it) and could not find it. Finish the earlier chapters first.';

  @override
  String get tutCustomerMail1Title => 'An e-mail arrives';

  @override
  String get tutCustomerMail1Body =>
      'Someone you do not know asks for a quotation for your cart. A real mailbox would deliver the message by itself; here the button below plays the customer and hands a ready-made e-mail (from Maya Okafor, example.test) to the helpdesk, exactly as the mail importer does.';

  @override
  String get tutCustomerMail1Action => 'Simulate customer e-mail';

  @override
  String get tutCustomerOpenHelpdeskTitle => 'The ticket';

  @override
  String get tutCustomerOpenHelpdeskBody =>
      'Every incoming message becomes a ticket. Open Helpdesk: the ticket from Maya Okafor is in the list.';

  @override
  String get tutCustomerOpenTicketTitle => 'Open the ticket';

  @override
  String get tutCustomerOpenTicketBody =>
      'Open the ticket. The conversation is on the left; on the right are its properties. No customer is linked yet, because nobody with this address exists in the system.';

  @override
  String get tutCustomerReplyTitle => 'Ask for company details';

  @override
  String get tutCustomerReplyBody =>
      'Reply to Maya: thank her and ask for the company name, VAT number and address, then press Send. The reply is queued for the mail worker. In test and tutorial environments outgoing mail is only written to files on the server, so Maya never receives it.';

  @override
  String get tutCustomerReplyHint =>
      'Make sure the Reply tab (not Internal note) is selected above the message box.';

  @override
  String get tutCustomerMail2Title => 'The customer answers';

  @override
  String get tutCustomerMail2Body =>
      'Use the button to play Maya\'s answer. It is a reply to her first message, so it lands in the same ticket as a new message, with her company name, VAT number and address.';

  @override
  String get tutCustomerMail2Action => 'Simulate customer e-mail';

  @override
  String get tutCustomerReadDetailsTitle => 'Read the details';

  @override
  String get tutCustomerReadDetailsBody =>
      'Go back to the ticket (reopen it if it does not show the new message yet) and read Maya\'s answer: company Brightwheel Logistics BV, VAT number BE0123456749, Voorbeeldlaan 12, 9000 Gent, Belgium. Press Next when you have it.';

  @override
  String get tutCustomerCreateCustomerTitle => 'Create the customer';

  @override
  String get tutCustomerCreateCustomerBody =>
      'In the ticket properties press New customer. Fill in name Brightwheel Logistics BV, a code such as TUT-CUST, VAT number, the address, and choose the price zone TUT-EXPORT. The ticket is linked to the new customer when you save.';

  @override
  String get tutCustomerCreateCustomerHint =>
      'Street Voorbeeldlaan 12, postal code 9000, city Gent, country BE. Language and payment terms can stay as they are.';

  @override
  String get tutCustomerLinkedTitle => 'The ticket knows its customer';

  @override
  String get tutCustomerLinkedBody =>
      'The ticket now shows the customer, and new buttons appear: create a lead or start a quotation straight from the ticket. The next chapter makes the quotation. Press Next.';

  @override
  String get tutCustomerDoneTitle => 'What you learned';

  @override
  String get tutCustomerDoneBody =>
      'Incoming mail becomes tickets, a reply asks the customer for what is missing, and a customer can be created from the ticket so that everything stays linked. Next: the quotation.';

  @override
  String get tutQuotationTitle => 'The quotation';

  @override
  String get tutQuotationSummary =>
      'Hat: salesperson. Quote 8 carts to the new customer, get an answer from production on timing and send it.';

  @override
  String get tutQuotationNeedsTitle => 'Chapter 7 first';

  @override
  String get tutQuotationNeedsBody =>
      'This chapter needs the customer Brightwheel Logistics BV from chapter 7 and could not find it. Finish chapter 7 first.';

  @override
  String get tutQuotationOpenQuotationsTitle => 'Quotations';

  @override
  String get tutQuotationOpenQuotationsBody =>
      'Open Quotations in the menu. This list holds every quotation with its number, customer and status.';

  @override
  String get tutQuotationCreateTitle => 'Write the quotation';

  @override
  String get tutQuotationCreateBody =>
      'Press New quotation, choose Brightwheel Logistics BV, add TUT-CART with quantity 8 and save the draft. The unit price comes from the customer\'s price zone, TUT-EXPORT, so it is the 1450 you entered in chapter 6.';

  @override
  String get tutQuotationCreateHint =>
      'Use the product search in the lines section; type TUT-CART. If the customer is not preselected, search for Brightwheel.';

  @override
  String get tutQuotationLeadTitle => 'How long will it take?';

  @override
  String get tutQuotationLeadBody =>
      'The customer asked for a delivery time. Honestly: the app does not calculate lead times automatically yet, and a quotation has no delivery date field. So ask production (put on that hat, look at the production queue and the components in stock) and write the answer into the quotation\'s notes, for example: Delivery about 3 weeks after order. Save the draft.';

  @override
  String get tutQuotationLeadHint =>
      'On an order you can send production a question as a ticket (you will see that in chapter 9); quotations do not have that button yet.';

  @override
  String get tutQuotationSendTitle => 'Send the quotation';

  @override
  String get tutQuotationSendBody =>
      'Press Mark as sent. From now on the quotation is frozen: it can only be accepted, rejected or revised. (Mail is not sent from this button; you would send the PDF yourself or reply in the ticket.)';

  @override
  String get tutQuotationPdfTitle => 'The PDF';

  @override
  String get tutQuotationPdfBody =>
      'The PDF button shows the quotation as the customer would see it. It is made on the server with a typesetting tool; on a server without it you get an error message, which does not affect anything else. Look if you like, then press Next.';

  @override
  String get tutQuotationPdfHint =>
      'Nothing breaks if the PDF fails: the quotation is already sent.';

  @override
  String get tutQuotationDoneTitle => 'What you learned';

  @override
  String get tutQuotationDoneBody =>
      'A quotation takes the price of the customer\'s zone, carries notes and freezes when it is sent. Delivery times are still your judgement call, together with production. Next: the customer wants a change.';

  @override
  String get tutChangeTitle => 'Change, order, production';

  @override
  String get tutChangeSummary =>
      'Hats: sales and production. Revise the quotation, turn it into an order, build the carts and a few extra for stock.';

  @override
  String get tutChangeNeedsTitle => 'Chapter 8 first';

  @override
  String get tutChangeNeedsBody =>
      'This chapter needs the sent quotation from chapter 8 and could not find it. Finish chapter 8 first.';

  @override
  String get tutChangeMail3Title => 'The customer answers again';

  @override
  String get tutChangeMail3Body =>
      'Maya is happy with the quotation but wants 10 carts instead of 8. Use the button to play her e-mail; it joins the same ticket.';

  @override
  String get tutChangeMail3Action => 'Simulate customer e-mail';

  @override
  String get tutChangeOpenQuoteTitle => 'Open the sent quotation';

  @override
  String get tutChangeOpenQuoteBody =>
      'A sent quotation is frozen, so a change means a new revision. Open the quotation from chapter 8.';

  @override
  String get tutChangeReviseTitle => 'Make a revision';

  @override
  String get tutChangeReviseBody =>
      'Press New revision and choose Keep agreed prices. The old revision is marked superseded and a new draft with the same number opens.';

  @override
  String get tutChangeReviseHint =>
      'Update to current prices would reprice at today\'s price list; here the customer keeps the agreed price.';

  @override
  String get tutChangeEditTitle => 'Change the quantity';

  @override
  String get tutChangeEditBody =>
      'Set the quantity of TUT-CART to 10 and save the draft.';

  @override
  String get tutChangeEditHint =>
      'The notes of the first revision were copied; adjust them if the delivery time changes.';

  @override
  String get tutChangeSendTitle => 'Send the revision';

  @override
  String get tutChangeSendBody => 'Mark the new revision as sent, as before.';

  @override
  String get tutChangeAcceptTitle => 'The customer accepts';

  @override
  String get tutChangeAcceptBody =>
      'Maya agrees with the new revision: press Accepted to record it.';

  @override
  String get tutChangeConvertTitle => 'Turn it into a sales order';

  @override
  String get tutChangeConvertBody =>
      'Press Convert to order. A draft sales order is created from the accepted revision and opens.';

  @override
  String get tutChangeConvertHint =>
      'The dialog asks for the customer\'s own reference; type for instance TUT-PO-1 or leave it empty.';

  @override
  String get tutChangeOpenOrderTitle => 'The sales order';

  @override
  String get tutChangeOpenOrderBody =>
      'If the order did not open by itself, open it from Orders. It has the 10 carts, the price and the customer reference. Orders go from draft to sent to confirmed.';

  @override
  String get tutChangeSendOrderTitle => 'Send the order confirmation';

  @override
  String get tutChangeSendOrderBody =>
      'Press Send order confirmation. The order becomes sent: the customer can now confirm it.';

  @override
  String get tutChangeSendOrderHint =>
      'Making the confirmation document needs the server\'s typesetting tool; if it is missing the server refuses this step and a server with the tool is needed to continue.';

  @override
  String get tutChangeConfirmTitle => 'Confirm on the customer\'s behalf';

  @override
  String get tutChangeConfirmBody =>
      'Maya already said yes by e-mail, so press Confirm on behalf and add a note such as confirmed by e-mail. The order is now confirmed and can go to production.';

  @override
  String get tutChangeReleaseTitle => 'To release';

  @override
  String get tutChangeReleaseBody =>
      'Put on the production hat. Open Production > To release: the confirmed order line with 10 carts is waiting. Press Release to production to create the production order for exactly that line.';

  @override
  String get tutChangeStartTitle => 'Start production';

  @override
  String get tutChangeStartBody => 'Press Start on the new production order.';

  @override
  String get tutChangeCompleteTitle => 'Complete production';

  @override
  String get tutChangeCompleteBody =>
      'Press Complete and confirm the 10 carts. The components are consumed and the carts go to the order.';

  @override
  String get tutChangeReadyTitle => 'Ready for shipping';

  @override
  String get tutChangeReadyBody =>
      'Open the order again: with all its lines produced it is ready for shipping. Delivery (picking, shipping, invoicing the customer) is outside this tutorial. Press Next.';

  @override
  String get tutChangeStockTitle => 'A few extra for stock';

  @override
  String get tutChangeStockBody =>
      'Production is often ahead of orders. Open Production, press Build for stock and release 4 more carts of TUT-CART. Without an order they simply land in stock when completed.';

  @override
  String get tutChangeStockHint =>
      'You can start and complete that order as in chapter 5, or leave it released.';

  @override
  String get tutChangeDoneTitle => 'Well done: the whole story';

  @override
  String get tutChangeDoneBody =>
      'You went from suppliers to purchasing, invoices, production, prices, a ticket, a new customer, a revised quotation, an order and production for the order and for stock. Where next: deliveries and shipping, repairs, field service and the reports each have their own menu entry. Any chapter can be replayed from the chapter map; steps that are already done are skipped.';

  @override
  String get tutInvoicesOpenSecondTitle => 'Open the suspicious invoice';

  @override
  String get tutInvoicesOpenSecondBody =>
      'Open invoice TUT-INV-002, the one you just registered, from the list in Finance.';

  @override
  String tutActionFailed(String reason) {
    return 'Could not send the simulated e-mail: $reason. Try again.';
  }

  @override
  String get tutActionForbidden =>
      'You are not allowed to import e-mail into the helpdesk (it needs the helpdesk write permission). Ask an administrator, or sign in as one, and try again.';
}
