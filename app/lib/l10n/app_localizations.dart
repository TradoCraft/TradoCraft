import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('nl'),
  ];

  /// No description provided for @accepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get accepted;

  /// No description provided for @accessToken.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get accessToken;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @actionAddTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get actionAddTag;

  /// No description provided for @actionSetCategory.
  ///
  /// In en, this message translates to:
  /// **'Set category'**
  String get actionSetCategory;

  /// No description provided for @actionSetInternal.
  ///
  /// In en, this message translates to:
  /// **'Mark as internal'**
  String get actionSetInternal;

  /// No description provided for @actionSetOwner.
  ///
  /// In en, this message translates to:
  /// **'Set owner'**
  String get actionSetOwner;

  /// No description provided for @actionSetPriority.
  ///
  /// In en, this message translates to:
  /// **'Set priority'**
  String get actionSetPriority;

  /// No description provided for @actionSetTeam.
  ///
  /// In en, this message translates to:
  /// **'Set team'**
  String get actionSetTeam;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @activeSince.
  ///
  /// In en, this message translates to:
  /// **'Active since {date}. Changes go through a new revision.'**
  String activeSince(String date);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add action'**
  String get addAction;

  /// No description provided for @addClosure.
  ///
  /// In en, this message translates to:
  /// **'Add closure'**
  String get addClosure;

  /// No description provided for @addComponent.
  ///
  /// In en, this message translates to:
  /// **'Add component'**
  String get addComponent;

  /// No description provided for @addComponentBySerial.
  ///
  /// In en, this message translates to:
  /// **'Add component by serial number (in stock)'**
  String get addComponentBySerial;

  /// No description provided for @addEquipment.
  ///
  /// In en, this message translates to:
  /// **'Add equipment'**
  String get addEquipment;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get addNote;

  /// No description provided for @addNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add an internal note'**
  String get addNoteHint;

  /// No description provided for @addPart.
  ///
  /// In en, this message translates to:
  /// **'Add part'**
  String get addPart;

  /// No description provided for @addPhone.
  ///
  /// In en, this message translates to:
  /// **'Add phone number'**
  String get addPhone;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProduct;

  /// No description provided for @addRebate.
  ///
  /// In en, this message translates to:
  /// **'Add rebate'**
  String get addRebate;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @addedBy.
  ///
  /// In en, this message translates to:
  /// **'added {date} by {name}'**
  String addedBy(String date, String name);

  /// No description provided for @addressForm.
  ///
  /// In en, this message translates to:
  /// **'Form of address'**
  String get addressForm;

  /// No description provided for @addressFormal.
  ///
  /// In en, this message translates to:
  /// **'Formal (Dear Mr. Smith)'**
  String get addressFormal;

  /// No description provided for @addressInformal.
  ///
  /// In en, this message translates to:
  /// **'Informal (Hi Sam)'**
  String get addressInformal;

  /// No description provided for @addVisit.
  ///
  /// In en, this message translates to:
  /// **'Add visit'**
  String get addVisit;

  /// No description provided for @agreed.
  ///
  /// In en, this message translates to:
  /// **'Agreed'**
  String get agreed;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get allCategories;

  /// No description provided for @allOwners.
  ///
  /// In en, this message translates to:
  /// **'All owners'**
  String get allOwners;

  /// No description provided for @allProducts.
  ///
  /// In en, this message translates to:
  /// **'All products'**
  String get allProducts;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get allStatuses;

  /// No description provided for @allTags.
  ///
  /// In en, this message translates to:
  /// **'All tags'**
  String get allTags;

  /// No description provided for @allTeams.
  ///
  /// In en, this message translates to:
  /// **'All teams'**
  String get allTeams;

  /// No description provided for @always.
  ///
  /// In en, this message translates to:
  /// **'always'**
  String get always;

  /// No description provided for @andMore.
  ///
  /// In en, this message translates to:
  /// **'… and {count} more'**
  String andMore(int count);

  /// No description provided for @announceRepair.
  ///
  /// In en, this message translates to:
  /// **'Announce a repair'**
  String get announceRepair;

  /// No description provided for @announcedNotReceived.
  ///
  /// In en, this message translates to:
  /// **'Announced, not received yet'**
  String get announcedNotReceived;

  /// No description provided for @answerFallback.
  ///
  /// In en, this message translates to:
  /// **'No {ticketLanguage} text yet: the {usedLanguage} text was used. Translate it before sending.'**
  String answerFallback(String ticketLanguage, String usedLanguage);

  /// No description provided for @anyValue.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get anyValue;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appLanguage;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TradoCraft'**
  String get appTitle;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @assignTo.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get assignTo;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @attachmentsHelp.
  ///
  /// In en, this message translates to:
  /// **'Images (JPEG, PNG, WebP) and PDF, up to 12 MB'**
  String get attachmentsHelp;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @automationHelp.
  ///
  /// In en, this message translates to:
  /// **'Rules run in this order when a ticket is created, changed or answered by the customer. A rule applies when all its conditions match. Rules can change tickets and send e-mail.'**
  String get automationHelp;

  /// No description provided for @automationRules.
  ///
  /// In en, this message translates to:
  /// **'Automation rules'**
  String get automationRules;

  /// No description provided for @autoRenew.
  ///
  /// In en, this message translates to:
  /// **'Renew automatically'**
  String get autoRenew;

  /// No description provided for @backIntoWork.
  ///
  /// In en, this message translates to:
  /// **'Back into work'**
  String get backIntoWork;

  /// No description provided for @backToCurrentRevision.
  ///
  /// In en, this message translates to:
  /// **'Back to current revision'**
  String get backToCurrentRevision;

  /// No description provided for @backlogByOwner.
  ///
  /// In en, this message translates to:
  /// **'Open tickets by owner'**
  String get backlogByOwner;

  /// No description provided for @backlogByPriority.
  ///
  /// In en, this message translates to:
  /// **'Open tickets by priority'**
  String get backlogByPriority;

  /// No description provided for @backlogByStatus.
  ///
  /// In en, this message translates to:
  /// **'Open tickets by status'**
  String get backlogByStatus;

  /// No description provided for @backlogByTeam.
  ///
  /// In en, this message translates to:
  /// **'Open tickets by team'**
  String get backlogByTeam;

  /// No description provided for @basisBusiness.
  ///
  /// In en, this message translates to:
  /// **'business hours'**
  String get basisBusiness;

  /// No description provided for @basisElapsed.
  ///
  /// In en, this message translates to:
  /// **'elapsed time'**
  String get basisElapsed;

  /// No description provided for @billOfMaterials.
  ///
  /// In en, this message translates to:
  /// **'Bill of materials'**
  String get billOfMaterials;

  /// No description provided for @billable.
  ///
  /// In en, this message translates to:
  /// **'Billable'**
  String get billable;

  /// No description provided for @bomActive.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get bomActive;

  /// No description provided for @bomObsolete.
  ///
  /// In en, this message translates to:
  /// **'obsolete'**
  String get bomObsolete;

  /// No description provided for @bomRev.
  ///
  /// In en, this message translates to:
  /// **'BOM rev.'**
  String get bomRev;

  /// No description provided for @bomRevision.
  ///
  /// In en, this message translates to:
  /// **'BOM revision'**
  String get bomRevision;

  /// No description provided for @breached.
  ///
  /// In en, this message translates to:
  /// **'Breached'**
  String get breached;

  /// No description provided for @breachesByTeam.
  ///
  /// In en, this message translates to:
  /// **'SLA breaches by team'**
  String get breachesByTeam;

  /// No description provided for @builtInto.
  ///
  /// In en, this message translates to:
  /// **'Built into'**
  String get builtInto;

  /// No description provided for @bulkKeepsQuotes.
  ///
  /// In en, this message translates to:
  /// **'Quotations before this date keep using the current prices'**
  String get bulkKeepsQuotes;

  /// No description provided for @bulkPriceChange.
  ///
  /// In en, this message translates to:
  /// **'Bulk price change'**
  String get bulkPriceChange;

  /// No description provided for @businessHours.
  ///
  /// In en, this message translates to:
  /// **'Business hours'**
  String get businessHours;

  /// No description provided for @businessHoursEnabled.
  ///
  /// In en, this message translates to:
  /// **'Count business hours only'**
  String get businessHoursEnabled;

  /// No description provided for @businessHoursHelp.
  ///
  /// In en, this message translates to:
  /// **'Service level times count only the hours below, on days that are not holidays. Switched off, they run around the clock.'**
  String get businessHoursHelp;

  /// No description provided for @businessHoursInvalidTime.
  ///
  /// In en, this message translates to:
  /// **'Enter times as HH:MM.'**
  String get businessHoursInvalidTime;

  /// No description provided for @businessHoursRecompute.
  ///
  /// In en, this message translates to:
  /// **'Saving recalculates the due times of all open tickets.'**
  String get businessHoursRecompute;

  /// No description provided for @businessHoursSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved. Open tickets were recalculated.'**
  String get businessHoursSaved;

  /// No description provided for @byStage.
  ///
  /// In en, this message translates to:
  /// **'by stage'**
  String get byStage;

  /// No description provided for @callIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get callIncoming;

  /// No description provided for @callLogged.
  ///
  /// In en, this message translates to:
  /// **'Call logged'**
  String get callLogged;

  /// No description provided for @callMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes)'**
  String get callMinutes;

  /// No description provided for @callOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing call'**
  String get callOutgoing;

  /// No description provided for @callSummary.
  ///
  /// In en, this message translates to:
  /// **'What was discussed'**
  String get callSummary;

  /// No description provided for @callWith.
  ///
  /// In en, this message translates to:
  /// **'Call with {name}'**
  String callWith(String name);

  /// No description provided for @canStillKeep.
  ///
  /// In en, this message translates to:
  /// **'You can still keep the agreed prices.'**
  String get canStillKeep;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelJob.
  ///
  /// In en, this message translates to:
  /// **'Cancel job'**
  String get cancelJob;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @cancelReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason for cancelling'**
  String get cancelReasonLabel;

  /// No description provided for @cancelRepair.
  ///
  /// In en, this message translates to:
  /// **'Cancel repair'**
  String get cancelRepair;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get cancelled;

  /// No description provided for @cancelledReason.
  ///
  /// In en, this message translates to:
  /// **'Cancelled: {reason}'**
  String cancelledReason(String reason);

  /// No description provided for @cannotConfirmNewer.
  ///
  /// In en, this message translates to:
  /// **'A newer revision of this order is being prepared. You can confirm it once it has been sent to you.'**
  String get cannotConfirmNewer;

  /// No description provided for @cannotConfirmOther.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be confirmed.'**
  String get cannotConfirmOther;

  /// No description provided for @captureSignature.
  ///
  /// In en, this message translates to:
  /// **'Capture signature'**
  String get captureSignature;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @categoryComplaint.
  ///
  /// In en, this message translates to:
  /// **'complaint'**
  String get categoryComplaint;

  /// No description provided for @categoryLead.
  ///
  /// In en, this message translates to:
  /// **'lead (new business)'**
  String get categoryLead;

  /// No description provided for @categoryOrderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'order confirmation'**
  String get categoryOrderConfirmation;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'other'**
  String get categoryOther;

  /// No description provided for @categoryProductionQuestion.
  ///
  /// In en, this message translates to:
  /// **'production question'**
  String get categoryProductionQuestion;

  /// No description provided for @categoryQuestion.
  ///
  /// In en, this message translates to:
  /// **'question'**
  String get categoryQuestion;

  /// No description provided for @categoryQuoteChange.
  ///
  /// In en, this message translates to:
  /// **'quote change'**
  String get categoryQuoteChange;

  /// No description provided for @categoryService.
  ///
  /// In en, this message translates to:
  /// **'service / repair'**
  String get categoryService;

  /// No description provided for @cc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get cc;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @changePriority.
  ///
  /// In en, this message translates to:
  /// **'Change priority'**
  String get changePriority;

  /// No description provided for @channel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// No description provided for @channelEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get channelEmail;

  /// No description provided for @channelInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal question'**
  String get channelInternal;

  /// No description provided for @channelManual.
  ///
  /// In en, this message translates to:
  /// **'Entered by hand'**
  String get channelManual;

  /// No description provided for @channelPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get channelPhone;

  /// No description provided for @channelPortal.
  ///
  /// In en, this message translates to:
  /// **'Portal'**
  String get channelPortal;

  /// No description provided for @checklistOnePerLine.
  ///
  /// In en, this message translates to:
  /// **'Checklist (one task per line)'**
  String get checklistOnePerLine;

  /// No description provided for @chooseCustomerAndLine.
  ///
  /// In en, this message translates to:
  /// **'Choose a customer and add at least one valid line.'**
  String get chooseCustomerAndLine;

  /// No description provided for @choosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get choosePhoto;

  /// No description provided for @chooseRebateTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose a product or family and enter a percentage.'**
  String get chooseRebateTarget;

  /// No description provided for @chooseZonePrice.
  ///
  /// In en, this message translates to:
  /// **'Choose a zone and enter a price.'**
  String get chooseZonePrice;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @closedLabel.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get closedLabel;

  /// No description provided for @closes.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get closes;

  /// No description provided for @closureKindCollectiveLeave.
  ///
  /// In en, this message translates to:
  /// **'Collective leave'**
  String get closureKindCollectiveLeave;

  /// No description provided for @closureKindHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get closureKindHoliday;

  /// No description provided for @closureKindInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get closureKindInventory;

  /// No description provided for @closureKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get closureKindLabel;

  /// No description provided for @closureKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get closureKindOther;

  /// No description provided for @closureKindWorks.
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get closureKindWorks;

  /// No description provided for @closurePolicyBlock.
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get closurePolicyBlock;

  /// No description provided for @closurePolicyBlockHelp.
  ///
  /// In en, this message translates to:
  /// **'A delivery cannot be planned on a closed day; another date has to be chosen.'**
  String get closurePolicyBlockHelp;

  /// No description provided for @closurePolicyOverride.
  ///
  /// In en, this message translates to:
  /// **'Needs a reason and the right to override'**
  String get closurePolicyOverride;

  /// No description provided for @closurePolicyOverrideHelp.
  ///
  /// In en, this message translates to:
  /// **'Only users who may override can plan on a closed day, and they must give a reason.'**
  String get closurePolicyOverrideHelp;

  /// No description provided for @closurePolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'When a delivery is planned on a day the customer is closed'**
  String get closurePolicyTitle;

  /// No description provided for @closurePolicyWarn.
  ///
  /// In en, this message translates to:
  /// **'Warn only'**
  String get closurePolicyWarn;

  /// No description provided for @closurePolicyWarnHelp.
  ///
  /// In en, this message translates to:
  /// **'The date is saved and the closure is shown as a warning.'**
  String get closurePolicyWarnHelp;

  /// No description provided for @closures.
  ///
  /// In en, this message translates to:
  /// **'Closed days'**
  String get closures;

  /// No description provided for @closuresShowPast.
  ///
  /// In en, this message translates to:
  /// **'Show past closures'**
  String get closuresShowPast;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @codeNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Code and name are required.'**
  String get codeNameRequired;

  /// No description provided for @poLineVatInvalid.
  ///
  /// In en, this message translates to:
  /// **'VAT rate must be between 0 and 100.'**
  String get poLineVatInvalid;

  /// No description provided for @codeNameVatRequired.
  ///
  /// In en, this message translates to:
  /// **'Code, name and VAT rate are required.'**
  String get codeNameVatRequired;

  /// No description provided for @completeJob.
  ///
  /// In en, this message translates to:
  /// **'Complete job'**
  String get completeJob;

  /// No description provided for @completionNotes.
  ///
  /// In en, this message translates to:
  /// **'What was done (and anything left open)'**
  String get completionNotes;

  /// No description provided for @component.
  ///
  /// In en, this message translates to:
  /// **'Component'**
  String get component;

  /// No description provided for @componentHistory.
  ///
  /// In en, this message translates to:
  /// **'Component history'**
  String get componentHistory;

  /// No description provided for @componentSince.
  ///
  /// In en, this message translates to:
  /// **'{product} · since {date}'**
  String componentSince(String product, String date);

  /// No description provided for @componentsAsBuilt.
  ///
  /// In en, this message translates to:
  /// **'Components (as built)'**
  String get componentsAsBuilt;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'confirm'**
  String get confirm;

  /// No description provided for @confirmOnBehalf.
  ///
  /// In en, this message translates to:
  /// **'Confirm on behalf of customer'**
  String get confirmOnBehalf;

  /// No description provided for @confirmOnBehalfHelp.
  ///
  /// In en, this message translates to:
  /// **'Record that the customer has confirmed this revision, for example by phone or e-mail.'**
  String get confirmOnBehalfHelp;

  /// No description provided for @confirmOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm order'**
  String get confirmOrder;

  /// No description provided for @confirmOrderHelp.
  ///
  /// In en, this message translates to:
  /// **'By confirming you accept this order as shown.'**
  String get confirmOrderHelp;

  /// No description provided for @confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// No description provided for @confirmationDate.
  ///
  /// In en, this message translates to:
  /// **'Confirmed on'**
  String get confirmationDate;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'confirmed'**
  String get confirmed;

  /// No description provided for @confirmedRevision.
  ///
  /// In en, this message translates to:
  /// **'Confirmed revision'**
  String get confirmedRevision;

  /// No description provided for @confirmedVia.
  ///
  /// In en, this message translates to:
  /// **'Confirmed via'**
  String get confirmedVia;

  /// No description provided for @confirmedViaPortal.
  ///
  /// In en, this message translates to:
  /// **'customer portal'**
  String get confirmedViaPortal;

  /// No description provided for @confirmedViaStaff.
  ///
  /// In en, this message translates to:
  /// **'staff, on behalf of the customer'**
  String get confirmedViaStaff;

  /// No description provided for @conflictsOnDate.
  ///
  /// In en, this message translates to:
  /// **'{count} already have a price on this date'**
  String conflictsOnDate(int count);

  /// No description provided for @contactName.
  ///
  /// In en, this message translates to:
  /// **'Contact name'**
  String get contactName;

  /// No description provided for @contactPerson.
  ///
  /// In en, this message translates to:
  /// **'Contact person'**
  String get contactPerson;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @contractEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get contractEnded;

  /// No description provided for @contractJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs of this contract'**
  String get contractJobs;

  /// No description provided for @contractLabel.
  ///
  /// In en, this message translates to:
  /// **'Contract {number}'**
  String contractLabel(String number);

  /// No description provided for @contractOpenJobs.
  ///
  /// In en, this message translates to:
  /// **'{count} open jobs'**
  String contractOpenJobs(String count);

  /// No description provided for @contracts.
  ///
  /// In en, this message translates to:
  /// **'Contracts'**
  String get contracts;

  /// No description provided for @contractSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get contractSuspended;

  /// No description provided for @convertHelp.
  ///
  /// In en, this message translates to:
  /// **'Does the customer want changes? Make a new revision of the quotation first, link it here, then convert.'**
  String get convertHelp;

  /// No description provided for @convertToOrder.
  ///
  /// In en, this message translates to:
  /// **'Convert to order'**
  String get convertToOrder;

  /// No description provided for @countAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add stock not listed'**
  String get countAddLine;

  /// No description provided for @countCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel count'**
  String get countCancel;

  /// No description provided for @countCounted.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get countCounted;

  /// No description provided for @countDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get countDifference;

  /// No description provided for @countExpected.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get countExpected;

  /// No description provided for @countInvalidQuantity.
  ///
  /// In en, this message translates to:
  /// **'A counted quantity is not a number.'**
  String get countInvalidQuantity;

  /// No description provided for @countMovedDuring.
  ///
  /// In en, this message translates to:
  /// **'{count} line(s) had stock movements during the count; the counted quantity replaced them.'**
  String countMovedDuring(int count);

  /// No description provided for @countNew.
  ///
  /// In en, this message translates to:
  /// **'New count'**
  String get countNew;

  /// No description provided for @countOf.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total}'**
  String countOf(int count, int total);

  /// No description provided for @countOneProduct.
  ///
  /// In en, this message translates to:
  /// **'Only one product (optional)'**
  String get countOneProduct;

  /// No description provided for @countOverwriteWarning.
  ///
  /// In en, this message translates to:
  /// **'Movements made while you count are overwritten: when the count is posted, the counted quantity becomes the stock.'**
  String get countOverwriteWarning;

  /// No description provided for @countPost.
  ///
  /// In en, this message translates to:
  /// **'Post count'**
  String get countPost;

  /// No description provided for @countPostConfirm.
  ///
  /// In en, this message translates to:
  /// **'The differences are posted as stock adjustments. Lines without a counted quantity are left alone.'**
  String get countPostConfirm;

  /// No description provided for @countProgress.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get countProgress;

  /// No description provided for @countStart.
  ///
  /// In en, this message translates to:
  /// **'Start count'**
  String get countStart;

  /// No description provided for @countStatusCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting'**
  String get countStatusCounting;

  /// No description provided for @countStatusPosted.
  ///
  /// In en, this message translates to:
  /// **'Posted'**
  String get countStatusPosted;

  /// No description provided for @countStockAtPost.
  ///
  /// In en, this message translates to:
  /// **'Stock when posted: {quantity}'**
  String countStockAtPost(String quantity);

  /// No description provided for @countWarehouseRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a warehouse.'**
  String get countWarehouseRequired;

  /// No description provided for @countWholeWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Whole warehouse'**
  String get countWholeWarehouse;

  /// No description provided for @countedBy.
  ///
  /// In en, this message translates to:
  /// **'Started by'**
  String get countedBy;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createLead.
  ///
  /// In en, this message translates to:
  /// **'Create lead'**
  String get createLead;

  /// No description provided for @createRepair.
  ///
  /// In en, this message translates to:
  /// **'Create repair'**
  String get createRepair;

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'created'**
  String get created;

  /// No description provided for @csatAlready.
  ///
  /// In en, this message translates to:
  /// **'This survey was already answered.'**
  String get csatAlready;

  /// No description provided for @csatAverage.
  ///
  /// In en, this message translates to:
  /// **'Customer satisfaction'**
  String get csatAverage;

  /// No description provided for @csatBad.
  ///
  /// In en, this message translates to:
  /// **'Not satisfied'**
  String get csatBad;

  /// No description provided for @csatComment.
  ///
  /// In en, this message translates to:
  /// **'Comment (optional)'**
  String get csatComment;

  /// No description provided for @csatEnabled.
  ///
  /// In en, this message translates to:
  /// **'Send a satisfaction survey when a ticket is closed'**
  String get csatEnabled;

  /// No description provided for @csatExpired.
  ///
  /// In en, this message translates to:
  /// **'This survey link has expired.'**
  String get csatExpired;

  /// No description provided for @csatGood.
  ///
  /// In en, this message translates to:
  /// **'Satisfied'**
  String get csatGood;

  /// No description provided for @csatNone.
  ///
  /// In en, this message translates to:
  /// **'No rating yet'**
  String get csatNone;

  /// No description provided for @csatQuestion.
  ///
  /// In en, this message translates to:
  /// **'How satisfied are you with the handling of ticket {number}?'**
  String csatQuestion(String number);

  /// No description provided for @csatResponses.
  ///
  /// In en, this message translates to:
  /// **'{count} responses'**
  String csatResponses(int count);

  /// No description provided for @csatThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get csatThanks;

  /// No description provided for @csatTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer satisfaction'**
  String get csatTitle;

  /// No description provided for @csvCopied.
  ///
  /// In en, this message translates to:
  /// **'CSV copied to the clipboard'**
  String get csvCopied;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

  /// No description provided for @customerDeclinedToSign.
  ///
  /// In en, this message translates to:
  /// **'The customer declined to sign'**
  String get customerDeclinedToSign;

  /// No description provided for @customerEquipment.
  ///
  /// In en, this message translates to:
  /// **'Customer equipment'**
  String get customerEquipment;

  /// No description provided for @customerLanguage.
  ///
  /// In en, this message translates to:
  /// **'Customer language'**
  String get customerLanguage;

  /// No description provided for @customerMainNumber.
  ///
  /// In en, this message translates to:
  /// **'Main number of {name}'**
  String customerMainNumber(String name);

  /// No description provided for @customerNamed.
  ///
  /// In en, this message translates to:
  /// **'Customer: {name}'**
  String customerNamed(String name);

  /// No description provided for @customerOptional.
  ///
  /// In en, this message translates to:
  /// **'Customer (optional)'**
  String get customerOptional;

  /// No description provided for @customerReference.
  ///
  /// In en, this message translates to:
  /// **'Customer reference'**
  String get customerReference;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @customerSignature.
  ///
  /// In en, this message translates to:
  /// **'Customer signature'**
  String get customerSignature;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @declinedToSignWithReason.
  ///
  /// In en, this message translates to:
  /// **'Declined to sign: {reason}'**
  String declinedToSignWithReason(String reason);

  /// No description provided for @defaultTeam.
  ///
  /// In en, this message translates to:
  /// **'Default team for new tickets'**
  String get defaultTeam;

  /// No description provided for @deleteRuleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this rule? Tickets that it changed keep their changes.'**
  String get deleteRuleConfirm;

  /// No description provided for @deliveries.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get deliveries;

  /// No description provided for @deliveryBlocked.
  ///
  /// In en, this message translates to:
  /// **'Deliveries on a closed day are not allowed. Choose another date.'**
  String get deliveryBlocked;

  /// No description provided for @deliveryCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel delivery'**
  String get deliveryCancel;

  /// No description provided for @deliveryCancelReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for cancelling'**
  String get deliveryCancelReason;

  /// No description provided for @deliveryChooseSerial.
  ///
  /// In en, this message translates to:
  /// **'Choose serial number'**
  String get deliveryChooseSerial;

  /// No description provided for @deliveryClosedWarning.
  ///
  /// In en, this message translates to:
  /// **'The customer is closed from {from} to {to}. Next open day: {next}.'**
  String deliveryClosedWarning(String from, String to, String next);

  /// No description provided for @deliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'not sent'**
  String get deliveryFailed;

  /// No description provided for @deliveryLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get deliveryLocation;

  /// No description provided for @deliveryLot.
  ///
  /// In en, this message translates to:
  /// **'Lot'**
  String get deliveryLot;

  /// No description provided for @deliveryNew.
  ///
  /// In en, this message translates to:
  /// **'New delivery'**
  String get deliveryNew;

  /// No description provided for @deliveryNoDate.
  ///
  /// In en, this message translates to:
  /// **'no date'**
  String get deliveryNoDate;

  /// No description provided for @deliveryNoLines.
  ///
  /// In en, this message translates to:
  /// **'Nothing to deliver yet: reserve stock for the order first.'**
  String get deliveryNoLines;

  /// No description provided for @deliveryOnClosure.
  ///
  /// In en, this message translates to:
  /// **'on a closure'**
  String get deliveryOnClosure;

  /// No description provided for @deliveryOverrideNeedsRight.
  ///
  /// In en, this message translates to:
  /// **'Delivering on a closed day needs a reason and the right to override.'**
  String get deliveryOverrideNeedsRight;

  /// No description provided for @deliveryOverrideReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for delivering on a closed day'**
  String get deliveryOverrideReason;

  /// No description provided for @deliveryPicking.
  ///
  /// In en, this message translates to:
  /// **'Picking list'**
  String get deliveryPicking;

  /// No description provided for @deliveryPlannedDate.
  ///
  /// In en, this message translates to:
  /// **'Planned date'**
  String get deliveryPlannedDate;

  /// No description provided for @deliveryQueued.
  ///
  /// In en, this message translates to:
  /// **'waiting to send'**
  String get deliveryQueued;

  /// No description provided for @deliverySent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get deliverySent;

  /// No description provided for @deliverySerial.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get deliverySerial;

  /// No description provided for @deliverySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery settings'**
  String get deliverySettingsTitle;

  /// No description provided for @deliveryShip.
  ///
  /// In en, this message translates to:
  /// **'Ship'**
  String get deliveryShip;

  /// No description provided for @deliveryShipTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get deliveryShipTo;

  /// No description provided for @deliveryShippedSnack.
  ///
  /// In en, this message translates to:
  /// **'Delivery shipped'**
  String get deliveryShippedSnack;

  /// No description provided for @deliveryStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'planned'**
  String get deliveryStatusPlanned;

  /// No description provided for @deliveryStatusShipped.
  ///
  /// In en, this message translates to:
  /// **'shipped'**
  String get deliveryStatusShipped;

  /// No description provided for @deliveryUseDay.
  ///
  /// In en, this message translates to:
  /// **'Use {date}'**
  String deliveryUseDay(String date);

  /// No description provided for @department.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get department;

  /// No description provided for @departmentCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get departmentCode;

  /// No description provided for @departmentMembers.
  ///
  /// In en, this message translates to:
  /// **'Colleagues in this department'**
  String get departmentMembers;

  /// No description provided for @departments.
  ///
  /// In en, this message translates to:
  /// **'Departments'**
  String get departments;

  /// No description provided for @departmentsHelp.
  ///
  /// In en, this message translates to:
  /// **'Repairs are routed to these departments. Only colleagues who belong to a department can work on its repairs.'**
  String get departmentsHelp;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @devModeHelp.
  ///
  /// In en, this message translates to:
  /// **'Server must run with AUTH_MODE=dev'**
  String get devModeHelp;

  /// No description provided for @developmentUser.
  ///
  /// In en, this message translates to:
  /// **'Development user'**
  String get developmentUser;

  /// No description provided for @deviceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get deviceLanguage;

  /// No description provided for @difference.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get difference;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @dismissRequest.
  ///
  /// In en, this message translates to:
  /// **'Dismiss request'**
  String get dismissRequest;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSaved;

  /// No description provided for @dryRun.
  ///
  /// In en, this message translates to:
  /// **'Try on a ticket'**
  String get dryRun;

  /// No description provided for @dryRunHelp.
  ///
  /// In en, this message translates to:
  /// **'Shows which rules would apply to a ticket and what they would change. Nothing is changed.'**
  String get dryRunHelp;

  /// No description provided for @dryRunRun.
  ///
  /// In en, this message translates to:
  /// **'Run test'**
  String get dryRunRun;

  /// No description provided for @drawSignatureFirst.
  ///
  /// In en, this message translates to:
  /// **'Draw a signature first'**
  String get drawSignatureFirst;

  /// No description provided for @dueOnDate.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String dueOnDate(String date);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editClosure.
  ///
  /// In en, this message translates to:
  /// **'Edit closure'**
  String get editClosure;

  /// No description provided for @editContact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get editContact;

  /// No description provided for @editDepartment.
  ///
  /// In en, this message translates to:
  /// **'Edit department'**
  String get editDepartment;

  /// No description provided for @editJob.
  ///
  /// In en, this message translates to:
  /// **'Edit job'**
  String get editJob;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get email;

  /// No description provided for @emailAddresses.
  ///
  /// In en, this message translates to:
  /// **'E-mail addresses (the first is primary)'**
  String get emailAddresses;

  /// No description provided for @endContract.
  ///
  /// In en, this message translates to:
  /// **'End contract'**
  String get endContract;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDate;

  /// No description provided for @enterChange.
  ///
  /// In en, this message translates to:
  /// **'Enter the change, e.g. 4.5 for +4.5 %.'**
  String get enterChange;

  /// No description provided for @enterValidNumbersLine.
  ///
  /// In en, this message translates to:
  /// **'Line {line}: enter valid numbers.'**
  String enterValidNumbersLine(int line);

  /// No description provided for @equipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get equipment;

  /// No description provided for @estimatedMinutes.
  ///
  /// In en, this message translates to:
  /// **'Estimated minutes'**
  String get estimatedMinutes;

  /// No description provided for @expectedClose.
  ///
  /// In en, this message translates to:
  /// **'Expected close'**
  String get expectedClose;

  /// No description provided for @expectedCloseDate.
  ///
  /// In en, this message translates to:
  /// **'Expected close {date}'**
  String expectedCloseDate(String date);

  /// No description provided for @expectedValue.
  ///
  /// In en, this message translates to:
  /// **'Expected value'**
  String get expectedValue;

  /// No description provided for @expectedValueEur.
  ///
  /// In en, this message translates to:
  /// **'Expected value (€)'**
  String get expectedValueEur;

  /// No description provided for @expectedValueOptional.
  ///
  /// In en, this message translates to:
  /// **'Expected value (optional)'**
  String get expectedValueOptional;

  /// No description provided for @explode.
  ///
  /// In en, this message translates to:
  /// **'Explode'**
  String get explode;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Copy as CSV'**
  String get exportCsv;

  /// No description provided for @families.
  ///
  /// In en, this message translates to:
  /// **'Families'**
  String get families;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get family;

  /// No description provided for @familyNamed.
  ///
  /// In en, this message translates to:
  /// **'Family {code}'**
  String familyNamed(String code);

  /// No description provided for @faultDescription.
  ///
  /// In en, this message translates to:
  /// **'What is wrong'**
  String get faultDescription;

  /// No description provided for @firstDueDate.
  ///
  /// In en, this message translates to:
  /// **'First due date'**
  String get firstDueDate;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @firstResponseMinutes.
  ///
  /// In en, this message translates to:
  /// **'First response (min)'**
  String get firstResponseMinutes;

  /// No description provided for @firstResponseTime.
  ///
  /// In en, this message translates to:
  /// **'First response'**
  String get firstResponseTime;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @fromYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get fromYou;

  /// No description provided for @generalRebateInfo.
  ///
  /// In en, this message translates to:
  /// **'General rebate on all products: {percent} % (net-priced products are never discounted).'**
  String generalRebateInfo(String percent);

  /// No description provided for @generalRebatePercent.
  ///
  /// In en, this message translates to:
  /// **'General rebate %'**
  String get generalRebatePercent;

  /// No description provided for @greetingPreview.
  ///
  /// In en, this message translates to:
  /// **'Greeting: {greeting}'**
  String greetingPreview(String greeting);

  /// No description provided for @helpdesk.
  ///
  /// In en, this message translates to:
  /// **'Helpdesk'**
  String get helpdesk;

  /// No description provided for @helpdeskReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get helpdeskReports;

  /// No description provided for @helpdeskSettings.
  ///
  /// In en, this message translates to:
  /// **'Helpdesk settings'**
  String get helpdeskSettings;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @holidayDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get holidayDate;

  /// No description provided for @holidayInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a date (YYYY-MM-DD) and a name.'**
  String get holidayInvalid;

  /// No description provided for @holidays.
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get holidays;

  /// No description provided for @holidaysHelp.
  ///
  /// In en, this message translates to:
  /// **'Days on which the helpdesk is closed.'**
  String get holidaysHelp;

  /// No description provided for @calendarFor.
  ///
  /// In en, this message translates to:
  /// **'Calendar for'**
  String get calendarFor;

  /// No description provided for @calendarCompanyWide.
  ///
  /// In en, this message translates to:
  /// **'Whole company'**
  String get calendarCompanyWide;

  /// No description provided for @calendarInherited.
  ///
  /// In en, this message translates to:
  /// **'This team has no calendar of its own and uses the company calendar. Saving creates one for the team.'**
  String get calendarInherited;

  /// No description provided for @calendarHolidaysInherited.
  ///
  /// In en, this message translates to:
  /// **'The company holidays apply to this team as well. Holidays added here are the team\'s own.'**
  String get calendarHolidaysInherited;

  /// No description provided for @calendarUseCompany.
  ///
  /// In en, this message translates to:
  /// **'Use the company calendar'**
  String get calendarUseCompany;

  /// No description provided for @calendarRemoved.
  ///
  /// In en, this message translates to:
  /// **'The team uses the company calendar again.'**
  String get calendarRemoved;

  /// No description provided for @basisMixed.
  ///
  /// In en, this message translates to:
  /// **'business hours or elapsed time, per team'**
  String get basisMixed;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'inactive'**
  String get inactive;

  /// No description provided for @inactiveContact.
  ///
  /// In en, this message translates to:
  /// **'No longer active (left the company)'**
  String get inactiveContact;

  /// No description provided for @priceOnRequestLine.
  ///
  /// In en, this message translates to:
  /// **'{description} (price on request, to enter)'**
  String priceOnRequestLine(String description);

  /// No description provided for @priceOnRequestToEnter.
  ///
  /// In en, this message translates to:
  /// **'{count} price-on-request line(s) without a price: enter the agreed price in the list price field before the quotation can be sent.'**
  String priceOnRequestToEnter(int count);

  /// No description provided for @insertPreparedAnswer.
  ///
  /// In en, this message translates to:
  /// **'Insert prepared answer'**
  String get insertPreparedAnswer;

  /// No description provided for @instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get instructions;

  /// No description provided for @internalNote.
  ///
  /// In en, this message translates to:
  /// **'Internal note'**
  String get internalNote;

  /// No description provided for @internalQuestionHelp.
  ///
  /// In en, this message translates to:
  /// **'Internal question. Ask the customer in {language} with a reply, then post the answer for your colleague as an internal note.'**
  String internalQuestionHelp(String language);

  /// No description provided for @internalTicket.
  ///
  /// In en, this message translates to:
  /// **'Internal ticket'**
  String get internalTicket;

  /// No description provided for @internalTicketHelp.
  ///
  /// In en, this message translates to:
  /// **'A question between colleagues; nothing is sent to the customer.'**
  String get internalTicketHelp;

  /// No description provided for @interval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get interval;

  /// No description provided for @jobCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get jobCancelled;

  /// No description provided for @jobCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get jobCompleted;

  /// No description provided for @jobCount.
  ///
  /// In en, this message translates to:
  /// **'{count} jobs'**
  String jobCount(String count);

  /// No description provided for @jobCreatedOnDate.
  ///
  /// In en, this message translates to:
  /// **'job created on {date}'**
  String jobCreatedOnDate(String date);

  /// No description provided for @jobInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get jobInProgress;

  /// No description provided for @jobKindInspection.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get jobKindInspection;

  /// No description provided for @jobKindInstallation.
  ///
  /// In en, this message translates to:
  /// **'Installation'**
  String get jobKindInstallation;

  /// No description provided for @jobKindMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get jobKindMaintenance;

  /// No description provided for @jobKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get jobKindOther;

  /// No description provided for @jobKindRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get jobKindRepair;

  /// No description provided for @jobName.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get jobName;

  /// No description provided for @jobPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get jobPlanned;

  /// No description provided for @jobTitle.
  ///
  /// In en, this message translates to:
  /// **'Job title'**
  String get jobTitle;

  /// No description provided for @jobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get jobs;

  /// No description provided for @keepAgreedPrices.
  ///
  /// In en, this message translates to:
  /// **'Keep agreed prices'**
  String get keepAgreedPrices;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSameAsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Same as company ({language})'**
  String languageSameAsCustomer(String language);

  /// No description provided for @lastDays.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String lastDays(int days);

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @leadCreated.
  ///
  /// In en, this message translates to:
  /// **'Lead created'**
  String get leadCreated;

  /// No description provided for @leadDays.
  ///
  /// In en, this message translates to:
  /// **'Create the job (days before)'**
  String get leadDays;

  /// No description provided for @lineDiscount.
  ///
  /// In en, this message translates to:
  /// **'Extra disc. ±'**
  String get lineDiscount;

  /// No description provided for @listPrice.
  ///
  /// In en, this message translates to:
  /// **'List price'**
  String get listPrice;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @logCall.
  ///
  /// In en, this message translates to:
  /// **'Log call'**
  String get logCall;

  /// No description provided for @logTime.
  ///
  /// In en, this message translates to:
  /// **'Log time'**
  String get logTime;

  /// No description provided for @logWork.
  ///
  /// In en, this message translates to:
  /// **'Log work'**
  String get logWork;

  /// No description provided for @loginLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'This login link has expired or was already used. Request a new one.'**
  String get loginLinkInvalid;

  /// No description provided for @loginLinkSent.
  ///
  /// In en, this message translates to:
  /// **'If this address may use the portal, a login link is on its way. Check your inbox.'**
  String get loginLinkSent;

  /// No description provided for @lookUp.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get lookUp;

  /// No description provided for @lost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get lost;

  /// No description provided for @lostReason.
  ///
  /// In en, this message translates to:
  /// **'Lost reason'**
  String get lostReason;

  /// No description provided for @markAsLost.
  ///
  /// In en, this message translates to:
  /// **'Mark as lost'**
  String get markAsLost;

  /// No description provided for @markAsSent.
  ///
  /// In en, this message translates to:
  /// **'Mark as sent'**
  String get markAsSent;

  /// No description provided for @markCompleted.
  ///
  /// In en, this message translates to:
  /// **'Mark as completed'**
  String get markCompleted;

  /// No description provided for @markReceived.
  ///
  /// In en, this message translates to:
  /// **'Mark as received'**
  String get markReceived;

  /// No description provided for @markShipped.
  ///
  /// In en, this message translates to:
  /// **'Mark as shipped back'**
  String get markShipped;

  /// No description provided for @markWaitingCustomer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for customer'**
  String get markWaitingCustomer;

  /// No description provided for @markWaitingParts.
  ///
  /// In en, this message translates to:
  /// **'Waiting for parts'**
  String get markWaitingParts;

  /// No description provided for @materialRequirements.
  ///
  /// In en, this message translates to:
  /// **'Material requirements (active revision)'**
  String get materialRequirements;

  /// No description provided for @mergeAction.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get mergeAction;

  /// No description provided for @mergeHelp.
  ///
  /// In en, this message translates to:
  /// **'All messages, files, tags and time entries move to the chosen ticket of the same customer. This ticket is closed. This cannot be undone.'**
  String get mergeHelp;

  /// No description provided for @mergeNoCandidates.
  ///
  /// In en, this message translates to:
  /// **'No other open ticket of this customer.'**
  String get mergeNoCandidates;

  /// No description provided for @mergeTicket.
  ///
  /// In en, this message translates to:
  /// **'Merge into another ticket…'**
  String get mergeTicket;

  /// No description provided for @mergedInto.
  ///
  /// In en, this message translates to:
  /// **'Merged into {number}'**
  String mergedInto(String number);

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @messageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get messageSent;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(String minutes);

  /// No description provided for @moduleDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get moduleDelivery;

  /// No description provided for @moduleProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get moduleProduction;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @months.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get months;

  /// No description provided for @myJobs.
  ///
  /// In en, this message translates to:
  /// **'My jobs'**
  String get myJobs;

  /// No description provided for @myOrders.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get myOrders;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My details'**
  String get myProfile;

  /// No description provided for @myRepairs.
  ///
  /// In en, this message translates to:
  /// **'My repairs'**
  String get myRepairs;

  /// No description provided for @myTickets.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get myTickets;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @netPrice.
  ///
  /// In en, this message translates to:
  /// **'Net price'**
  String get netPrice;

  /// No description provided for @newAnswer.
  ///
  /// In en, this message translates to:
  /// **'New answer'**
  String get newAnswer;

  /// No description provided for @newContact.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get newContact;

  /// No description provided for @newContract.
  ///
  /// In en, this message translates to:
  /// **'New contract'**
  String get newContract;

  /// No description provided for @newCustomer.
  ///
  /// In en, this message translates to:
  /// **'New customer'**
  String get newCustomer;

  /// No description provided for @newDepartment.
  ///
  /// In en, this message translates to:
  /// **'New department'**
  String get newDepartment;

  /// No description provided for @newFamily.
  ///
  /// In en, this message translates to:
  /// **'New family'**
  String get newFamily;

  /// No description provided for @newItem.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newItem;

  /// No description provided for @newJob.
  ///
  /// In en, this message translates to:
  /// **'New job'**
  String get newJob;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @newOpportunity.
  ///
  /// In en, this message translates to:
  /// **'New opportunity'**
  String get newOpportunity;

  /// No description provided for @correctPrice.
  ///
  /// In en, this message translates to:
  /// **'Correct planned price'**
  String get correctPrice;

  /// No description provided for @newPrice.
  ///
  /// In en, this message translates to:
  /// **'New price'**
  String get newPrice;

  /// No description provided for @newPricesValidFrom.
  ///
  /// In en, this message translates to:
  /// **'New prices valid from {date}'**
  String newPricesValidFrom(String date);

  /// No description provided for @newPriority.
  ///
  /// In en, this message translates to:
  /// **'New priority'**
  String get newPriority;

  /// No description provided for @newProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get newProduct;

  /// No description provided for @newQuotation.
  ///
  /// In en, this message translates to:
  /// **'New quotation'**
  String get newQuotation;

  /// No description provided for @newRepair.
  ///
  /// In en, this message translates to:
  /// **'New repair'**
  String get newRepair;

  /// No description provided for @newRevision.
  ///
  /// In en, this message translates to:
  /// **'New revision'**
  String get newRevision;

  /// No description provided for @newRevisionOf.
  ///
  /// In en, this message translates to:
  /// **'New revision of {number}'**
  String newRevisionOf(String number);

  /// No description provided for @newRule.
  ///
  /// In en, this message translates to:
  /// **'New rule'**
  String get newRule;

  /// No description provided for @newTeam.
  ///
  /// In en, this message translates to:
  /// **'New team'**
  String get newTeam;

  /// No description provided for @newTicket.
  ///
  /// In en, this message translates to:
  /// **'New ticket'**
  String get newTicket;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @noAccess.
  ///
  /// In en, this message translates to:
  /// **'Your account has no access to any section yet. Ask an administrator.'**
  String get noAccess;

  /// No description provided for @noActiveBom.
  ///
  /// In en, this message translates to:
  /// **'No active bill of materials.'**
  String get noActiveBom;

  /// No description provided for @noBom.
  ///
  /// In en, this message translates to:
  /// **'No bill of materials yet.'**
  String get noBom;

  /// No description provided for @noClosures.
  ///
  /// In en, this message translates to:
  /// **'No closures recorded.'**
  String get noClosures;

  /// No description provided for @noContactLinked.
  ///
  /// In en, this message translates to:
  /// **'No contact person linked'**
  String get noContactLinked;

  /// No description provided for @noContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet.'**
  String get noContacts;

  /// No description provided for @noContracts.
  ///
  /// In en, this message translates to:
  /// **'No contracts'**
  String get noContracts;

  /// No description provided for @noCustomerEquipment.
  ///
  /// In en, this message translates to:
  /// **'This customer has no installed units'**
  String get noCustomerEquipment;

  /// No description provided for @noCustomerLinked.
  ///
  /// In en, this message translates to:
  /// **'No customer linked'**
  String get noCustomerLinked;

  /// No description provided for @noEquipment.
  ///
  /// In en, this message translates to:
  /// **'No equipment linked'**
  String get noEquipment;

  /// No description provided for @noExpectedClose.
  ///
  /// In en, this message translates to:
  /// **'No expected close date'**
  String get noExpectedClose;

  /// No description provided for @noJobsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No jobs assigned to you.'**
  String get noJobsAssigned;

  /// No description provided for @noLines.
  ///
  /// In en, this message translates to:
  /// **'No lines yet.'**
  String get noLines;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'You have no orders yet.'**
  String get noOrdersYet;

  /// No description provided for @noParts.
  ///
  /// In en, this message translates to:
  /// **'No parts recorded'**
  String get noParts;

  /// No description provided for @noPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change these settings.'**
  String get noPermission;

  /// No description provided for @noPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet.'**
  String get noPhotos;

  /// No description provided for @noPrices.
  ///
  /// In en, this message translates to:
  /// **'No prices yet.'**
  String get noPrices;

  /// No description provided for @noPriorityChanges.
  ///
  /// In en, this message translates to:
  /// **'No priority changes yet.'**
  String get noPriorityChanges;

  /// No description provided for @noPriorityRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests.'**
  String get noPriorityRequests;

  /// No description provided for @noQuotations.
  ///
  /// In en, this message translates to:
  /// **'No quotations yet.'**
  String get noQuotations;

  /// No description provided for @noRebates.
  ///
  /// In en, this message translates to:
  /// **'No product or family rebates.'**
  String get noRebates;

  /// No description provided for @noRepairs.
  ///
  /// In en, this message translates to:
  /// **'No repairs.'**
  String get noRepairs;

  /// No description provided for @noRepairsYet.
  ///
  /// In en, this message translates to:
  /// **'You have no repairs yet.'**
  String get noRepairsYet;

  /// No description provided for @noRules.
  ///
  /// In en, this message translates to:
  /// **'No rules yet.'**
  String get noRules;

  /// No description provided for @noSerialComponents.
  ///
  /// In en, this message translates to:
  /// **'No serialised components.'**
  String get noSerialComponents;

  /// No description provided for @noSignature.
  ///
  /// In en, this message translates to:
  /// **'Not signed yet'**
  String get noSignature;

  /// No description provided for @noTeam.
  ///
  /// In en, this message translates to:
  /// **'No team'**
  String get noTeam;

  /// No description provided for @noTechnicians.
  ///
  /// In en, this message translates to:
  /// **'Nobody assigned'**
  String get noTechnicians;

  /// No description provided for @noTicketsYet.
  ///
  /// In en, this message translates to:
  /// **'You have no tickets yet.'**
  String get noTicketsYet;

  /// No description provided for @noTimeEntries.
  ///
  /// In en, this message translates to:
  /// **'No time logged yet.'**
  String get noTimeEntries;

  /// No description provided for @nobodyFound.
  ///
  /// In en, this message translates to:
  /// **'Nobody found with this number.'**
  String get nobodyFound;

  /// No description provided for @nonBillable.
  ///
  /// In en, this message translates to:
  /// **'Not billable'**
  String get nonBillable;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @notClosed.
  ///
  /// In en, this message translates to:
  /// **'Not closed'**
  String get notClosed;

  /// No description provided for @notRouted.
  ///
  /// In en, this message translates to:
  /// **'Not routed yet'**
  String get notRouted;

  /// No description provided for @notScheduled.
  ///
  /// In en, this message translates to:
  /// **'Not scheduled'**
  String get notScheduled;

  /// No description provided for @noteAdded.
  ///
  /// In en, this message translates to:
  /// **'Note added'**
  String get noteAdded;

  /// No description provided for @noteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @noUpcomingVisits.
  ///
  /// In en, this message translates to:
  /// **'No visits due'**
  String get noUpcomingVisits;

  /// No description provided for @number.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get number;

  /// No description provided for @numberRequired.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get numberRequired;

  /// No description provided for @obsoleteRevision.
  ///
  /// In en, this message translates to:
  /// **'Obsolete revision (read-only).'**
  String get obsoleteRevision;

  /// No description provided for @oidcAccessToken.
  ///
  /// In en, this message translates to:
  /// **'OIDC access token'**
  String get oidcAccessToken;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @onSiteContact.
  ///
  /// In en, this message translates to:
  /// **'Person on site'**
  String get onSiteContact;

  /// No description provided for @openEnded.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get openEnded;

  /// No description provided for @openJobsOnly.
  ///
  /// In en, this message translates to:
  /// **'Active only'**
  String get openJobsOnly;

  /// No description provided for @openOnly.
  ///
  /// In en, this message translates to:
  /// **'Open only'**
  String get openOnly;

  /// No description provided for @openOpportunity.
  ///
  /// In en, this message translates to:
  /// **'Open opportunity'**
  String get openOpportunity;

  /// No description provided for @openPriorityRequests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open priority request} other{{count} open priority requests}}'**
  String openPriorityRequests(int count);

  /// No description provided for @openRepairsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} open'**
  String openRepairsCount(String count);

  /// No description provided for @opens.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get opens;

  /// No description provided for @opportunities.
  ///
  /// In en, this message translates to:
  /// **'Opportunities'**
  String get opportunities;

  /// No description provided for @opportunity.
  ///
  /// In en, this message translates to:
  /// **'Opportunity'**
  String get opportunity;

  /// No description provided for @opportunityOptional.
  ///
  /// In en, this message translates to:
  /// **'Opportunity (optional)'**
  String get opportunityOptional;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @orderAlreadyConfirmed.
  ///
  /// In en, this message translates to:
  /// **'This order was confirmed on {date}.'**
  String orderAlreadyConfirmed(String date);

  /// No description provided for @orderAwaitingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'awaiting your confirmation'**
  String get orderAwaitingConfirmation;

  /// No description provided for @orderConfirmationQueued.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation queued for sending.'**
  String get orderConfirmationQueued;

  /// No description provided for @orderConfirmedSnack.
  ///
  /// In en, this message translates to:
  /// **'Order confirmed.'**
  String get orderConfirmedSnack;

  /// No description provided for @orderConfirmedThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you, your order is confirmed.'**
  String get orderConfirmedThanks;

  /// No description provided for @orderCreated.
  ///
  /// In en, this message translates to:
  /// **'Order created'**
  String get orderCreated;

  /// No description provided for @orderSaved.
  ///
  /// In en, this message translates to:
  /// **'Order saved.'**
  String get orderSaved;

  /// No description provided for @orderStatusInPlanning.
  ///
  /// In en, this message translates to:
  /// **'in planning'**
  String get orderStatusInPlanning;

  /// No description provided for @orderStatusInProduction.
  ///
  /// In en, this message translates to:
  /// **'in production'**
  String get orderStatusInProduction;

  /// No description provided for @orderStatusPartiallyShipped.
  ///
  /// In en, this message translates to:
  /// **'partially shipped'**
  String get orderStatusPartiallyShipped;

  /// No description provided for @orderStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'planned'**
  String get orderStatusPlanned;

  /// No description provided for @orderStatusReadyForShipping.
  ///
  /// In en, this message translates to:
  /// **'ready for shipping'**
  String get orderStatusReadyForShipping;

  /// No description provided for @orderStatusShipped.
  ///
  /// In en, this message translates to:
  /// **'shipped'**
  String get orderStatusShipped;

  /// No description provided for @orderStockRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get orderStockRelease;

  /// No description provided for @orderStockReserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get orderStockReserve;

  /// No description provided for @orderStockReserveHint.
  ///
  /// In en, this message translates to:
  /// **'Stock can be reserved once the customer has confirmed the order.'**
  String get orderStockReserveHint;

  /// No description provided for @orderStockThisLine.
  ///
  /// In en, this message translates to:
  /// **'{quantity} reserved for this line'**
  String orderStockThisLine(String quantity);

  /// No description provided for @orderStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock availability'**
  String get orderStockTitle;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @ownerEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get ownerEmpty;

  /// No description provided for @ownerSet.
  ///
  /// In en, this message translates to:
  /// **'Somebody'**
  String get ownerSet;

  /// No description provided for @p90.
  ///
  /// In en, this message translates to:
  /// **'90% within'**
  String get p90;

  /// No description provided for @partFreeTextHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a product or type a description'**
  String get partFreeTextHint;

  /// No description provided for @partsUsed.
  ///
  /// In en, this message translates to:
  /// **'Parts used'**
  String get partsUsed;

  /// No description provided for @paymentDays.
  ///
  /// In en, this message translates to:
  /// **'Payment days'**
  String get paymentDays;

  /// No description provided for @pdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get pdf;

  /// No description provided for @perDay.
  ///
  /// In en, this message translates to:
  /// **'Per day'**
  String get perDay;

  /// No description provided for @perWeek.
  ///
  /// In en, this message translates to:
  /// **'Per week'**
  String get perWeek;

  /// No description provided for @personTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get personTitle;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @phoneCall.
  ///
  /// In en, this message translates to:
  /// **'Phone call'**
  String get phoneCall;

  /// No description provided for @phoneDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get phoneDirect;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'With country code, e.g. +32 475 12 34 56'**
  String get phoneHint;

  /// No description provided for @phoneMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get phoneMobile;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phoneNumbers.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers'**
  String get phoneNumbers;

  /// No description provided for @phoneOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get phoneOther;

  /// No description provided for @phoneWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get phoneWork;

  /// No description provided for @photoBy.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String photoBy(String name);

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @photosAdded.
  ///
  /// In en, this message translates to:
  /// **'Photos added'**
  String get photosAdded;

  /// No description provided for @placeholdersHelp.
  ///
  /// In en, this message translates to:
  /// **'Placeholders (click to insert in the current language):'**
  String get placeholdersHelp;

  /// No description provided for @portalAccess.
  ///
  /// In en, this message translates to:
  /// **'Customer portal access'**
  String get portalAccess;

  /// No description provided for @portalScope.
  ///
  /// In en, this message translates to:
  /// **'Sees in the portal'**
  String get portalScope;

  /// No description provided for @portalScopeCustomer.
  ///
  /// In en, this message translates to:
  /// **'All tickets of the company'**
  String get portalScopeCustomer;

  /// No description provided for @portalScopeOwn.
  ///
  /// In en, this message translates to:
  /// **'Own tickets only'**
  String get portalScopeOwn;

  /// No description provided for @portalSignInIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter your e-mail address. We will send you a link to sign in, no password needed.'**
  String get portalSignInIntro;

  /// No description provided for @portalTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer portal'**
  String get portalTitle;

  /// No description provided for @postalCode.
  ///
  /// In en, this message translates to:
  /// **'Postal code'**
  String get postalCode;

  /// No description provided for @preparedAnswers.
  ///
  /// In en, this message translates to:
  /// **'Prepared answers'**
  String get preparedAnswers;

  /// No description provided for @preparedAnswersHelp.
  ///
  /// In en, this message translates to:
  /// **'Reusable answers to recurring questions, one text per language. Placeholders such as «quotation.number» are filled in for the ticket; the text can still be edited before sending.'**
  String get preparedAnswersHelp;

  /// No description provided for @answerKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get answerKind;

  /// No description provided for @answerKindName.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, reply{Reply} internal_note{Internal note} handover{Hand-over} notice{Notice} other{{kind}}}'**
  String answerKindName(String kind);

  /// No description provided for @answerTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get answerTeam;

  /// No description provided for @answerAllTeams.
  ///
  /// In en, this message translates to:
  /// **'All teams'**
  String get answerAllTeams;

  /// No description provided for @answerKeywords.
  ///
  /// In en, this message translates to:
  /// **'Keywords (comma separated)'**
  String get answerKeywords;

  /// No description provided for @answerKeywordsHelp.
  ///
  /// In en, this message translates to:
  /// **'Tickets whose subject contains a keyword get this answer suggested first.'**
  String get answerKeywordsHelp;

  /// No description provided for @answerShortcutHint.
  ///
  /// In en, this message translates to:
  /// **'Type /code to insert an answer'**
  String get answerShortcutHint;

  /// No description provided for @ticketLanguageSource.
  ///
  /// In en, this message translates to:
  /// **'{source, select, record{Taken from the contact or customer} detected{Detected from the message} agent{Set by an agent} other{{source}}}'**
  String ticketLanguageSource(String source);

  /// No description provided for @ticketLanguage.
  ///
  /// In en, this message translates to:
  /// **'Ticket language'**
  String get ticketLanguage;

  /// No description provided for @mailTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template (optional)'**
  String get mailTemplate;

  /// No description provided for @mailTemplateNone.
  ///
  /// In en, this message translates to:
  /// **'Write the text here'**
  String get mailTemplateNone;

  /// No description provided for @ticketLanguageCondition.
  ///
  /// In en, this message translates to:
  /// **'Ticket language'**
  String get ticketLanguageCondition;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @priceListOf.
  ///
  /// In en, this message translates to:
  /// **'Price list of {date}'**
  String priceListOf(String date);

  /// No description provided for @priceListValidOn.
  ///
  /// In en, this message translates to:
  /// **'Price list valid on'**
  String get priceListValidOn;

  /// No description provided for @priceZone.
  ///
  /// In en, this message translates to:
  /// **'Price zone'**
  String get priceZone;

  /// No description provided for @pricedOnPriceListOf.
  ///
  /// In en, this message translates to:
  /// **'Priced on the price list of {date}'**
  String pricedOnPriceListOf(String date);

  /// No description provided for @prices.
  ///
  /// In en, this message translates to:
  /// **'Prices'**
  String get prices;

  /// No description provided for @pricesCreated.
  ///
  /// In en, this message translates to:
  /// **'{count} prices created, valid from {date}'**
  String pricesCreated(int count, String date);

  /// No description provided for @pricesWillChange.
  ///
  /// In en, this message translates to:
  /// **'{count} prices will change'**
  String pricesWillChange(int count);

  /// No description provided for @pricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get pricing;

  /// No description provided for @pricingIndicative.
  ///
  /// In en, this message translates to:
  /// **'indicative'**
  String get pricingIndicative;

  /// No description provided for @productIncludedInTurnover.
  ///
  /// In en, this message translates to:
  /// **'Counts toward rebate turnover'**
  String get productIncludedInTurnover;

  /// No description provided for @productTurnoverUnclassified.
  ///
  /// In en, this message translates to:
  /// **'Unclassified'**
  String get productTurnoverUnclassified;

  /// No description provided for @pricingIndicativeHelp.
  ///
  /// In en, this message translates to:
  /// **'Indicative price (printed as indicative; rebates apply)'**
  String get pricingIndicativeHelp;

  /// No description provided for @pricingNet.
  ///
  /// In en, this message translates to:
  /// **'net'**
  String get pricingNet;

  /// No description provided for @pricingNetHelp.
  ///
  /// In en, this message translates to:
  /// **'Not discountable (no rebate, no line discount)'**
  String get pricingNetHelp;

  /// No description provided for @pricingOnRequestHelp.
  ///
  /// In en, this message translates to:
  /// **'Price on request (enter the price on each quotation)'**
  String get pricingOnRequestHelp;

  /// No description provided for @pricingOnRequest.
  ///
  /// In en, this message translates to:
  /// **'price on request'**
  String get pricingOnRequest;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @priorityChangeLine.
  ///
  /// In en, this message translates to:
  /// **'{date}: {from} → {to} by {name}'**
  String priorityChangeLine(String date, String from, String to, String name);

  /// No description provided for @priorityChangedSnack.
  ///
  /// In en, this message translates to:
  /// **'Priority changed.'**
  String get priorityChangedSnack;

  /// No description provided for @priorityExpedite.
  ///
  /// In en, this message translates to:
  /// **'expedite'**
  String get priorityExpedite;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get priorityHigh;

  /// No description provided for @priorityHistory.
  ///
  /// In en, this message translates to:
  /// **'Priority history'**
  String get priorityHistory;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get priorityLow;

  /// No description provided for @priorityNormal.
  ///
  /// In en, this message translates to:
  /// **'normal'**
  String get priorityNormal;

  /// No description provided for @priorityRequestHelp.
  ///
  /// In en, this message translates to:
  /// **'Our team decides whether and how the priority is changed.'**
  String get priorityRequestHelp;

  /// No description provided for @priorityRequestLine.
  ///
  /// In en, this message translates to:
  /// **'{name} asks for priority: {priority}'**
  String priorityRequestLine(String name, String priority);

  /// No description provided for @priorityRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Your request has been sent.'**
  String get priorityRequestSent;

  /// No description provided for @priorityRequests.
  ///
  /// In en, this message translates to:
  /// **'Customer priority requests'**
  String get priorityRequests;

  /// No description provided for @priorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'urgent'**
  String get priorityUrgent;

  /// No description provided for @probability.
  ///
  /// In en, this message translates to:
  /// **'Probability'**
  String get probability;

  /// No description provided for @probabilityPercent.
  ///
  /// In en, this message translates to:
  /// **'Probability %'**
  String get probabilityPercent;

  /// No description provided for @probabilityShort.
  ///
  /// In en, this message translates to:
  /// **'Prob.'**
  String get probabilityShort;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @productCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products'**
  String productCount(int count);

  /// No description provided for @productDescription.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productDescription;

  /// No description provided for @productFamilies.
  ///
  /// In en, this message translates to:
  /// **'Product families'**
  String get productFamilies;

  /// No description provided for @productFamily.
  ///
  /// In en, this message translates to:
  /// **'Product family'**
  String get productFamily;

  /// No description provided for @productRebates.
  ///
  /// In en, this message translates to:
  /// **'Product rebates'**
  String get productRebates;

  /// No description provided for @productTypeConfigurable.
  ///
  /// In en, this message translates to:
  /// **'configurable'**
  String get productTypeConfigurable;

  /// No description provided for @productTypeManufactured.
  ///
  /// In en, this message translates to:
  /// **'manufactured'**
  String get productTypeManufactured;

  /// No description provided for @productTypePurchased.
  ///
  /// In en, this message translates to:
  /// **'purchased'**
  String get productTypePurchased;

  /// No description provided for @productTypeService.
  ///
  /// In en, this message translates to:
  /// **'service'**
  String get productTypeService;

  /// No description provided for @production.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get production;

  /// No description provided for @productionBomRevision.
  ///
  /// In en, this message translates to:
  /// **'BOM revision {revision}'**
  String productionBomRevision(String revision);

  /// No description provided for @productionBuildComponent.
  ///
  /// In en, this message translates to:
  /// **'Build it'**
  String get productionBuildComponent;

  /// No description provided for @productionBuildForStock.
  ///
  /// In en, this message translates to:
  /// **'Build for stock'**
  String get productionBuildForStock;

  /// No description provided for @productionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel production order'**
  String get productionCancel;

  /// No description provided for @productionCancelReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for cancelling'**
  String get productionCancelReason;

  /// No description provided for @productionChooseSerials.
  ///
  /// In en, this message translates to:
  /// **'Choose serial numbers'**
  String get productionChooseSerials;

  /// No description provided for @productionComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get productionComplete;

  /// No description provided for @productionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Production order completed'**
  String get productionCompleted;

  /// No description provided for @productionComponents.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get productionComponents;

  /// No description provided for @productionConsumed.
  ///
  /// In en, this message translates to:
  /// **'Consumed'**
  String get productionConsumed;

  /// No description provided for @productionDivision.
  ///
  /// In en, this message translates to:
  /// **'Division'**
  String get productionDivision;

  /// No description provided for @productionDivisionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add division'**
  String get productionDivisionAdd;

  /// No description provided for @productionDivisionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit division'**
  String get productionDivisionEdit;

  /// No description provided for @productionDivisions.
  ///
  /// In en, this message translates to:
  /// **'Divisions'**
  String get productionDivisions;

  /// No description provided for @productionExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get productionExpiry;

  /// No description provided for @productionExtraFrom.
  ///
  /// In en, this message translates to:
  /// **'Extra stock taken from'**
  String get productionExtraFrom;

  /// No description provided for @productionLocation.
  ///
  /// In en, this message translates to:
  /// **'Put into'**
  String get productionLocation;

  /// No description provided for @productionLot.
  ///
  /// In en, this message translates to:
  /// **'Lot number'**
  String get productionLot;

  /// No description provided for @productionNoDivision.
  ///
  /// In en, this message translates to:
  /// **'no division'**
  String get productionNoDivision;

  /// No description provided for @productionNothingToRelease.
  ///
  /// In en, this message translates to:
  /// **'Nothing to release: every manufactured line is covered by production orders.'**
  String get productionNothingToRelease;

  /// No description provided for @productionOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'The sales order was cancelled. Cancel this production order to free its components.'**
  String get productionOrderCancelled;

  /// No description provided for @productionOrdersOfOrder.
  ///
  /// In en, this message translates to:
  /// **'Production orders'**
  String get productionOrdersOfOrder;

  /// No description provided for @productionOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get productionOutput;

  /// No description provided for @productionPlannedReady.
  ///
  /// In en, this message translates to:
  /// **'Planned ready'**
  String get productionPlannedReady;

  /// No description provided for @productionPromised.
  ///
  /// In en, this message translates to:
  /// **'Promised'**
  String get productionPromised;

  /// No description provided for @productionQuantityBuilt.
  ///
  /// In en, this message translates to:
  /// **'Quantity built'**
  String get productionQuantityBuilt;

  /// No description provided for @productionRelease.
  ///
  /// In en, this message translates to:
  /// **'Release to production'**
  String get productionRelease;

  /// No description provided for @productionReleased.
  ///
  /// In en, this message translates to:
  /// **'Released to production'**
  String get productionReleased;

  /// No description provided for @productionRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get productionRequired;

  /// No description provided for @productionReserveAgain.
  ///
  /// In en, this message translates to:
  /// **'Reserve again'**
  String get productionReserveAgain;

  /// No description provided for @productionReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get productionReserved;

  /// No description provided for @productionScrap.
  ///
  /// In en, this message translates to:
  /// **'Scrap'**
  String get productionScrap;

  /// No description provided for @productionSerials.
  ///
  /// In en, this message translates to:
  /// **'Serial numbers, one per line'**
  String get productionSerials;

  /// No description provided for @productionSerialsNeeded.
  ///
  /// In en, this message translates to:
  /// **'Choose {count} serial numbers'**
  String productionSerialsNeeded(String count);

  /// No description provided for @productionShort.
  ///
  /// In en, this message translates to:
  /// **'short of stock'**
  String get productionShort;

  /// No description provided for @productionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get productionStart;

  /// No description provided for @productionStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get productionStatusCompleted;

  /// No description provided for @productionStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get productionStatusInProgress;

  /// No description provided for @productionStatusReleased.
  ///
  /// In en, this message translates to:
  /// **'released'**
  String get productionStatusReleased;

  /// No description provided for @productionToRelease.
  ///
  /// In en, this message translates to:
  /// **'To release'**
  String get productionToRelease;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @profileHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the language and the way we address you in our e-mails and in this portal.'**
  String get profileHelp;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @question.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get question;

  /// No description provided for @questionToSales.
  ///
  /// In en, this message translates to:
  /// **'Question to sales'**
  String get questionToSales;

  /// No description provided for @questionToSalesHelp.
  ///
  /// In en, this message translates to:
  /// **'{salesperson} gets this question and asks the customer in their language.'**
  String questionToSalesHelp(String salesperson);

  /// No description provided for @quotation.
  ///
  /// In en, this message translates to:
  /// **'Quotation'**
  String get quotation;

  /// No description provided for @quotations.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get quotations;

  /// No description provided for @raisedBy.
  ///
  /// In en, this message translates to:
  /// **'Raised by {name}'**
  String raisedBy(String name);

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required.'**
  String get reasonRequired;

  /// No description provided for @rebate.
  ///
  /// In en, this message translates to:
  /// **'Std. rebate'**
  String get rebate;

  /// No description provided for @rebateFor.
  ///
  /// In en, this message translates to:
  /// **'{target}: {percent} %'**
  String rebateFor(String target, String percent);

  /// No description provided for @rebatePercent.
  ///
  /// In en, this message translates to:
  /// **'Rebate %'**
  String get rebatePercent;

  /// No description provided for @rebateSourceFamily.
  ///
  /// In en, this message translates to:
  /// **'family'**
  String get rebateSourceFamily;

  /// No description provided for @rebateSourceGeneral.
  ///
  /// In en, this message translates to:
  /// **'general'**
  String get rebateSourceGeneral;

  /// No description provided for @rebateSourceProduct.
  ///
  /// In en, this message translates to:
  /// **'product'**
  String get rebateSourceProduct;

  /// No description provided for @rebatesOf.
  ///
  /// In en, this message translates to:
  /// **'Rebates · {customer}'**
  String rebatesOf(String customer);

  /// No description provided for @recurrenceMonthList.
  ///
  /// In en, this message translates to:
  /// **'In chosen months'**
  String get recurrenceMonthList;

  /// No description provided for @recurrenceMonths.
  ///
  /// In en, this message translates to:
  /// **'Every N months'**
  String get recurrenceMonths;

  /// No description provided for @recurrenceWeeks.
  ///
  /// In en, this message translates to:
  /// **'Every N weeks'**
  String get recurrenceWeeks;

  /// No description provided for @registerProduct.
  ///
  /// In en, this message translates to:
  /// **'Register {product}'**
  String registerProduct(String product);

  /// No description provided for @registerUnit.
  ///
  /// In en, this message translates to:
  /// **'Register unit'**
  String get registerUnit;

  /// No description provided for @registered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get registered;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removeAndScrap.
  ///
  /// In en, this message translates to:
  /// **'Remove and scrap'**
  String get removeAndScrap;

  /// No description provided for @removeBackToStock.
  ///
  /// In en, this message translates to:
  /// **'Remove, back to stock'**
  String get removeBackToStock;

  /// No description provided for @removeLine.
  ///
  /// In en, this message translates to:
  /// **'Remove line'**
  String get removeLine;

  /// No description provided for @removedBy.
  ///
  /// In en, this message translates to:
  /// **'removed {date} by {name}'**
  String removedBy(String date, String name);

  /// No description provided for @reopenJob.
  ///
  /// In en, this message translates to:
  /// **'Reopen job'**
  String get reopenJob;

  /// No description provided for @repairAnnouncedByTicket.
  ///
  /// In en, this message translates to:
  /// **'The customer announced it (the product has not arrived yet)'**
  String get repairAnnouncedByTicket;

  /// No description provided for @repairAnnouncedOk.
  ///
  /// In en, this message translates to:
  /// **'Repair announced. Write the number on the parcel and send the product to us.'**
  String get repairAnnouncedOk;

  /// No description provided for @repairPhotosHelp.
  ///
  /// In en, this message translates to:
  /// **'Photos of the product and the fault help us a lot.'**
  String get repairPhotosHelp;

  /// No description provided for @repairPortalAnnounced.
  ///
  /// In en, this message translates to:
  /// **'Announced, not received yet'**
  String get repairPortalAnnounced;

  /// No description provided for @repairPortalInRepair.
  ///
  /// In en, this message translates to:
  /// **'In repair'**
  String get repairPortalInRepair;

  /// No description provided for @repairPortalReady.
  ///
  /// In en, this message translates to:
  /// **'Repaired, ready to ship'**
  String get repairPortalReady;

  /// No description provided for @repairPortalWaitingCustomer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your answer'**
  String get repairPortalWaitingCustomer;

  /// No description provided for @repairStatusAnnounced.
  ///
  /// In en, this message translates to:
  /// **'Announced'**
  String get repairStatusAnnounced;

  /// No description provided for @repairStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get repairStatusCancelled;

  /// No description provided for @repairStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get repairStatusCompleted;

  /// No description provided for @repairStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get repairStatusInProgress;

  /// No description provided for @repairStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get repairStatusReceived;

  /// No description provided for @repairStatusRouted.
  ///
  /// In en, this message translates to:
  /// **'In department queue'**
  String get repairStatusRouted;

  /// No description provided for @repairStatusShipped.
  ///
  /// In en, this message translates to:
  /// **'Shipped back'**
  String get repairStatusShipped;

  /// No description provided for @repairStatusWaitingCustomer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for customer'**
  String get repairStatusWaitingCustomer;

  /// No description provided for @repairStatusWaitingParts.
  ///
  /// In en, this message translates to:
  /// **'Waiting for parts'**
  String get repairStatusWaitingParts;

  /// No description provided for @repairs.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get repairs;

  /// No description provided for @replaceSignature.
  ///
  /// In en, this message translates to:
  /// **'Replace signature'**
  String get replaceSignature;

  /// No description provided for @replyQueued.
  ///
  /// In en, this message translates to:
  /// **'Reply queued for sending'**
  String get replyQueued;

  /// No description provided for @replyToCustomer.
  ///
  /// In en, this message translates to:
  /// **'Reply to customer'**
  String get replyToCustomer;

  /// No description provided for @reportQueued.
  ///
  /// In en, this message translates to:
  /// **'The report will be sent'**
  String get reportQueued;

  /// No description provided for @reportSend.
  ///
  /// In en, this message translates to:
  /// **'Send report by e-mail'**
  String get reportSend;

  /// No description provided for @reportSentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {to} on {date}'**
  String reportSentTo(String to, String date);

  /// No description provided for @reportView.
  ///
  /// In en, this message translates to:
  /// **'View report (PDF)'**
  String get reportView;

  /// No description provided for @repricingFailed.
  ///
  /// In en, this message translates to:
  /// **'Today\'s prices could not be calculated: {error}'**
  String repricingFailed(String error);

  /// No description provided for @requestDismissedSnack.
  ///
  /// In en, this message translates to:
  /// **'Request dismissed.'**
  String get requestDismissedSnack;

  /// No description provided for @requestLessUrgent.
  ///
  /// In en, this message translates to:
  /// **'Less urgent'**
  String get requestLessUrgent;

  /// No description provided for @requestMoreUrgent.
  ///
  /// In en, this message translates to:
  /// **'More urgent (expedite)'**
  String get requestMoreUrgent;

  /// No description provided for @requestPriorityChange.
  ///
  /// In en, this message translates to:
  /// **'Request priority change'**
  String get requestPriorityChange;

  /// No description provided for @requestStatusApplied.
  ///
  /// In en, this message translates to:
  /// **'applied'**
  String get requestStatusApplied;

  /// No description provided for @requestStatusDismissed.
  ///
  /// In en, this message translates to:
  /// **'dismissed'**
  String get requestStatusDismissed;

  /// No description provided for @requestStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get requestStatusOpen;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @resolutionHours.
  ///
  /// In en, this message translates to:
  /// **'Resolution within (hours)'**
  String get resolutionHours;

  /// No description provided for @resolutionMinutes.
  ///
  /// In en, this message translates to:
  /// **'Resolution (min)'**
  String get resolutionMinutes;

  /// No description provided for @resolutionTime.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolutionTime;

  /// No description provided for @responseTimes.
  ///
  /// In en, this message translates to:
  /// **'Response and resolution times'**
  String get responseTimes;

  /// No description provided for @responseHours.
  ///
  /// In en, this message translates to:
  /// **'Response within (hours)'**
  String get responseHours;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @revisionActivated.
  ///
  /// In en, this message translates to:
  /// **'Revision activated'**
  String get revisionActivated;

  /// No description provided for @revisionItem.
  ///
  /// In en, this message translates to:
  /// **'Revision {revision} · {status} · {lines} lines'**
  String revisionItem(int revision, String status, int lines);

  /// No description provided for @revisionNotes.
  ///
  /// In en, this message translates to:
  /// **'Revision notes'**
  String get revisionNotes;

  /// No description provided for @revisionNumber.
  ///
  /// In en, this message translates to:
  /// **'Revision {revision}'**
  String revisionNumber(int revision);

  /// No description provided for @revisionPriceLists.
  ///
  /// In en, this message translates to:
  /// **'Agreed prices: price list of {agreed}. Current prices: price list of {current}.'**
  String revisionPriceLists(String agreed, String current);

  /// No description provided for @revisionViewNotice.
  ///
  /// In en, this message translates to:
  /// **'You are viewing revision {revision} (read-only). The current revision is {current}.'**
  String revisionViewNotice(int revision, int current);

  /// No description provided for @revisions.
  ///
  /// In en, this message translates to:
  /// **'Revisions'**
  String get revisions;

  /// No description provided for @roleInvoicing.
  ///
  /// In en, this message translates to:
  /// **'Invoicing'**
  String get roleInvoicing;

  /// No description provided for @roleManagement.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get roleManagement;

  /// No description provided for @roleOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get roleOther;

  /// No description provided for @rolePurchasing.
  ///
  /// In en, this message translates to:
  /// **'Purchasing'**
  String get rolePurchasing;

  /// No description provided for @roleQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get roleQuality;

  /// No description provided for @roleSalesContact.
  ///
  /// In en, this message translates to:
  /// **'Sales contact'**
  String get roleSalesContact;

  /// No description provided for @roleTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get roleTechnical;

  /// No description provided for @roles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get roles;

  /// No description provided for @roundTo.
  ///
  /// In en, this message translates to:
  /// **'Round to'**
  String get roundTo;

  /// No description provided for @routeNote.
  ///
  /// In en, this message translates to:
  /// **'Note for the department'**
  String get routeNote;

  /// No description provided for @routeRepair.
  ///
  /// In en, this message translates to:
  /// **'Route to department'**
  String get routeRepair;

  /// No description provided for @ruleActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get ruleActions;

  /// No description provided for @ruleConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions (all must match)'**
  String get ruleConditions;

  /// No description provided for @ruleConditionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Pick any number of values per line; a ticket needs one of them. Empty lines are ignored.'**
  String get ruleConditionsHelp;

  /// No description provided for @ruleNameRequired.
  ///
  /// In en, this message translates to:
  /// **'A rule needs a name.'**
  String get ruleNameRequired;

  /// No description provided for @ruleResultAfterStop.
  ///
  /// In en, this message translates to:
  /// **'skipped (stopped)'**
  String get ruleResultAfterStop;

  /// No description provided for @ruleResultInactive.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get ruleResultInactive;

  /// No description provided for @ruleResultMatched.
  ///
  /// In en, this message translates to:
  /// **'applies'**
  String get ruleResultMatched;

  /// No description provided for @ruleResultNoMatch.
  ///
  /// In en, this message translates to:
  /// **'no match'**
  String get ruleResultNoMatch;

  /// No description provided for @ruleResultOtherTrigger.
  ///
  /// In en, this message translates to:
  /// **'other event'**
  String get ruleResultOtherTrigger;

  /// No description provided for @ruleTrigger.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get ruleTrigger;

  /// No description provided for @ruleTriggerCreated.
  ///
  /// In en, this message translates to:
  /// **'A ticket is created'**
  String get ruleTriggerCreated;

  /// No description provided for @ruleTriggerCustomerReplied.
  ///
  /// In en, this message translates to:
  /// **'The customer replies'**
  String get ruleTriggerCustomerReplied;

  /// No description provided for @ruleTriggerUpdated.
  ///
  /// In en, this message translates to:
  /// **'A ticket is updated by staff'**
  String get ruleTriggerUpdated;

  /// No description provided for @salesperson.
  ///
  /// In en, this message translates to:
  /// **'Salesperson'**
  String get salesperson;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @savedNumber.
  ///
  /// In en, this message translates to:
  /// **'Saved {number}'**
  String savedNumber(String number);

  /// No description provided for @scheduledEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get scheduledEnd;

  /// No description provided for @scheduledStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get scheduledStart;

  /// No description provided for @scrapPercent.
  ///
  /// In en, this message translates to:
  /// **'Scrap %'**
  String get scrapPercent;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendBackToTriage.
  ///
  /// In en, this message translates to:
  /// **'Send back to triage'**
  String get sendBackToTriage;

  /// No description provided for @sendLoginLink.
  ///
  /// In en, this message translates to:
  /// **'Send login link'**
  String get sendLoginLink;

  /// No description provided for @sendOrderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Send order confirmation'**
  String get sendOrderConfirmation;

  /// No description provided for @sendOrderConfirmationHelp.
  ///
  /// In en, this message translates to:
  /// **'The order confirmation is e-mailed to the customer as a PDF. The revision can no longer be edited afterwards.'**
  String get sendOrderConfirmationHelp;

  /// No description provided for @senderDomain.
  ///
  /// In en, this message translates to:
  /// **'Sender domain'**
  String get senderDomain;

  /// No description provided for @serial.
  ///
  /// In en, this message translates to:
  /// **'serial'**
  String get serial;

  /// No description provided for @serialBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'built in'**
  String get serialBuiltIn;

  /// No description provided for @serialDelivered.
  ///
  /// In en, this message translates to:
  /// **'delivered'**
  String get serialDelivered;

  /// No description provided for @serialInStock.
  ///
  /// In en, this message translates to:
  /// **'in stock'**
  String get serialInStock;

  /// No description provided for @serialInstalled.
  ///
  /// In en, this message translates to:
  /// **'installed'**
  String get serialInstalled;

  /// No description provided for @serialNumber.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get serialNumber;

  /// No description provided for @serialNumbers.
  ///
  /// In en, this message translates to:
  /// **'Serial numbers'**
  String get serialNumbers;

  /// No description provided for @serialNumbersHelp.
  ///
  /// In en, this message translates to:
  /// **'Every unit gets its own serial number and history'**
  String get serialNumbersHelp;

  /// No description provided for @serialScrapped.
  ///
  /// In en, this message translates to:
  /// **'scrapped'**
  String get serialScrapped;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serviceReport.
  ///
  /// In en, this message translates to:
  /// **'Service report'**
  String get serviceReport;

  /// No description provided for @setWarranty.
  ///
  /// In en, this message translates to:
  /// **'Set warranty'**
  String get setWarranty;

  /// No description provided for @showInactive.
  ///
  /// In en, this message translates to:
  /// **'Show inactive'**
  String get showInactive;

  /// No description provided for @signedByOn.
  ///
  /// In en, this message translates to:
  /// **'Signed by {name} on {date}'**
  String signedByOn(String name, String date);

  /// No description provided for @signerName.
  ///
  /// In en, this message translates to:
  /// **'Name of the signer'**
  String get signerName;

  /// No description provided for @signHere.
  ///
  /// In en, this message translates to:
  /// **'Sign here'**
  String get signHere;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String signedInAs(String name);

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @singleProduct.
  ///
  /// In en, this message translates to:
  /// **'Single product'**
  String get singleProduct;

  /// No description provided for @siteAddress.
  ///
  /// In en, this message translates to:
  /// **'Where to go'**
  String get siteAddress;

  /// No description provided for @siteName.
  ///
  /// In en, this message translates to:
  /// **'Site name'**
  String get siteName;

  /// No description provided for @skippedWithoutPrice.
  ///
  /// In en, this message translates to:
  /// **'{count} product/zone combinations have no price and are skipped'**
  String skippedWithoutPrice(int count);

  /// No description provided for @sla.
  ///
  /// In en, this message translates to:
  /// **'SLA'**
  String get sla;

  /// No description provided for @slaAndSatisfaction.
  ///
  /// In en, this message translates to:
  /// **'SLA and satisfaction'**
  String get slaAndSatisfaction;

  /// No description provided for @slaAtRisk.
  ///
  /// In en, this message translates to:
  /// **'At risk'**
  String get slaAtRisk;

  /// No description provided for @slaBreached.
  ///
  /// In en, this message translates to:
  /// **'Breached'**
  String get slaBreached;

  /// No description provided for @slaCompliance.
  ///
  /// In en, this message translates to:
  /// **'SLA compliance'**
  String get slaCompliance;

  /// No description provided for @slaComplianceDetail.
  ///
  /// In en, this message translates to:
  /// **'{breached} of {total} breached'**
  String slaComplianceDetail(int breached, int total);

  /// No description provided for @slaDue.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String slaDue(String date);

  /// No description provided for @slaFilterAny.
  ///
  /// In en, this message translates to:
  /// **'Any SLA state'**
  String get slaFilterAny;

  /// No description provided for @slaFirstResponse.
  ///
  /// In en, this message translates to:
  /// **'First response'**
  String get slaFirstResponse;

  /// No description provided for @slaLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String slaLeft(String time);

  /// No description provided for @slaMet.
  ///
  /// In en, this message translates to:
  /// **'Met'**
  String get slaMet;

  /// No description provided for @slaNone.
  ///
  /// In en, this message translates to:
  /// **'No SLA'**
  String get slaNone;

  /// No description provided for @slaOnTime.
  ///
  /// In en, this message translates to:
  /// **'On time'**
  String get slaOnTime;

  /// No description provided for @slaOverdue.
  ///
  /// In en, this message translates to:
  /// **'{time} overdue'**
  String slaOverdue(String time);

  /// No description provided for @slaPaused.
  ///
  /// In en, this message translates to:
  /// **'Clock stopped: waiting for the customer'**
  String get slaPaused;

  /// No description provided for @slaPolicies.
  ///
  /// In en, this message translates to:
  /// **'Service levels (SLA)'**
  String get slaPolicies;

  /// No description provided for @slaPoliciesHelp.
  ///
  /// In en, this message translates to:
  /// **'Plain elapsed time, business hours are not taken into account. The clock stops while a ticket waits for the customer.'**
  String get slaPoliciesHelp;

  /// No description provided for @slaResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get slaResolution;

  /// No description provided for @splitAction.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get splitAction;

  /// No description provided for @splitFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s)'**
  String splitFiles(int count);

  /// No description provided for @splitHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the messages that move to a new ticket for the same customer. Their files move with them. This cannot be undone (tickets can be merged again).'**
  String get splitHelp;

  /// No description provided for @splitKeepOne.
  ///
  /// In en, this message translates to:
  /// **'At least one message must stay in this ticket.'**
  String get splitKeepOne;

  /// No description provided for @splitSubjectOptional.
  ///
  /// In en, this message translates to:
  /// **'Subject of the new ticket (optional)'**
  String get splitSubjectOptional;

  /// No description provided for @splitTicket.
  ///
  /// In en, this message translates to:
  /// **'Split ticket…'**
  String get splitTicket;

  /// No description provided for @stage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get stage;

  /// No description provided for @stageLead.
  ///
  /// In en, this message translates to:
  /// **'lead'**
  String get stageLead;

  /// No description provided for @stageLost.
  ///
  /// In en, this message translates to:
  /// **'lost'**
  String get stageLost;

  /// No description provided for @stageNegotiation.
  ///
  /// In en, this message translates to:
  /// **'negotiation'**
  String get stageNegotiation;

  /// No description provided for @stageProposal.
  ///
  /// In en, this message translates to:
  /// **'proposal'**
  String get stageProposal;

  /// No description provided for @stageQualified.
  ///
  /// In en, this message translates to:
  /// **'qualified'**
  String get stageQualified;

  /// No description provided for @stageWon.
  ///
  /// In en, this message translates to:
  /// **'won'**
  String get stageWon;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @startJob.
  ///
  /// In en, this message translates to:
  /// **'Start job'**
  String get startJob;

  /// No description provided for @startWork.
  ///
  /// In en, this message translates to:
  /// **'Start work'**
  String get startWork;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @statusAccepted.
  ///
  /// In en, this message translates to:
  /// **'accepted'**
  String get statusAccepted;

  /// No description provided for @statusAfterwards.
  ///
  /// In en, this message translates to:
  /// **'Status afterwards'**
  String get statusAfterwards;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get statusDraft;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'rejected'**
  String get statusRejected;

  /// No description provided for @statusSent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get statusSent;

  /// No description provided for @statusSuperseded.
  ///
  /// In en, this message translates to:
  /// **'superseded'**
  String get statusSuperseded;

  /// No description provided for @stopOnMatch.
  ///
  /// In en, this message translates to:
  /// **'Stop after this rule'**
  String get stopOnMatch;

  /// No description provided for @stopOnMatchHelp.
  ///
  /// In en, this message translates to:
  /// **'When it matches, the rules after it are skipped.'**
  String get stopOnMatchHelp;

  /// No description provided for @stockAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get stockAdjust;

  /// No description provided for @stockAdjustReason.
  ///
  /// In en, this message translates to:
  /// **'Why is the stock corrected?'**
  String get stockAdjustReason;

  /// No description provided for @stockAdjustRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a location, enter a quantity and give a reason.'**
  String get stockAdjustRequired;

  /// No description provided for @stockAllWarehouses.
  ///
  /// In en, this message translates to:
  /// **'All warehouses'**
  String get stockAllWarehouses;

  /// No description provided for @stockAssignedTo.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get stockAssignedTo;

  /// No description provided for @stockAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get stockAvailable;

  /// No description provided for @stockBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get stockBarcode;

  /// No description provided for @stockBelowReorder.
  ///
  /// In en, this message translates to:
  /// **'Below reorder level'**
  String get stockBelowReorder;

  /// No description provided for @stockChangeBy.
  ///
  /// In en, this message translates to:
  /// **'Change by (+/−)'**
  String get stockChangeBy;

  /// No description provided for @stockCounts.
  ///
  /// In en, this message translates to:
  /// **'Stock counts'**
  String get stockCounts;

  /// No description provided for @stockExpiredQty.
  ///
  /// In en, this message translates to:
  /// **'{quantity} expired'**
  String stockExpiredQty(String quantity);

  /// No description provided for @stockExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get stockExpiry;

  /// No description provided for @stockFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get stockFrom;

  /// No description provided for @stockInVans.
  ///
  /// In en, this message translates to:
  /// **'In vans'**
  String get stockInVans;

  /// No description provided for @stockInvalidNumbers.
  ///
  /// In en, this message translates to:
  /// **'Cost, reorder levels and lead time must be numbers.'**
  String get stockInvalidNumbers;

  /// No description provided for @stockIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get stockIssue;

  /// No description provided for @stockKindVan.
  ///
  /// In en, this message translates to:
  /// **'Service van'**
  String get stockKindVan;

  /// No description provided for @stockKindWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get stockKindWarehouse;

  /// No description provided for @stockLeadTime.
  ///
  /// In en, this message translates to:
  /// **'Lead time (days)'**
  String get stockLeadTime;

  /// No description provided for @stockLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get stockLocation;

  /// No description provided for @stockLocations.
  ///
  /// In en, this message translates to:
  /// **'Stock by location'**
  String get stockLocations;

  /// No description provided for @stockLot.
  ///
  /// In en, this message translates to:
  /// **'Lot'**
  String get stockLot;

  /// No description provided for @stockLotNumber.
  ///
  /// In en, this message translates to:
  /// **'Lot number'**
  String get stockLotNumber;

  /// No description provided for @stockLotTrackingHelp.
  ///
  /// In en, this message translates to:
  /// **'Lots / batches'**
  String get stockLotTrackingHelp;

  /// No description provided for @stockMoves.
  ///
  /// In en, this message translates to:
  /// **'Movements'**
  String get stockMoves;

  /// No description provided for @stockNewLocation.
  ///
  /// In en, this message translates to:
  /// **'New location'**
  String get stockNewLocation;

  /// No description provided for @stockNewLot.
  ///
  /// In en, this message translates to:
  /// **'New lot'**
  String get stockNewLot;

  /// No description provided for @stockNewQuantity.
  ///
  /// In en, this message translates to:
  /// **'New quantity'**
  String get stockNewQuantity;

  /// No description provided for @stockNewVan.
  ///
  /// In en, this message translates to:
  /// **'New service van'**
  String get stockNewVan;

  /// No description provided for @stockNewWarehouse.
  ///
  /// In en, this message translates to:
  /// **'New warehouse'**
  String get stockNewWarehouse;

  /// No description provided for @stockNoMoves.
  ///
  /// In en, this message translates to:
  /// **'No movements yet'**
  String get stockNoMoves;

  /// No description provided for @stockNoLocationsHint.
  ///
  /// In en, this message translates to:
  /// **'No locations yet. An administrator creates a warehouse and a location under Stock > Warehouses.'**
  String get stockNoLocationsHint;

  /// No description provided for @stockNoWarehouses.
  ///
  /// In en, this message translates to:
  /// **'No warehouses yet. An administrator creates them here.'**
  String get stockNoWarehouses;

  /// No description provided for @stockNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get stockNote;

  /// No description provided for @stockNothingInStock.
  ///
  /// In en, this message translates to:
  /// **'Nothing in stock'**
  String get stockNothingInStock;

  /// No description provided for @stockOnHand.
  ///
  /// In en, this message translates to:
  /// **'On hand'**
  String get stockOnHand;

  /// No description provided for @stockOnlyInStock.
  ///
  /// In en, this message translates to:
  /// **'Only in stock'**
  String get stockOnlyInStock;

  /// No description provided for @stockProductQuantityRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a product and enter a quantity.'**
  String get stockProductQuantityRequired;

  /// No description provided for @stockReasonConsumption.
  ///
  /// In en, this message translates to:
  /// **'Consumption'**
  String get stockReasonConsumption;

  /// No description provided for @stockReasonCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get stockReasonCorrection;

  /// No description provided for @stockReasonCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get stockReasonCount;

  /// No description provided for @stockReasonManualReceipt.
  ///
  /// In en, this message translates to:
  /// **'Manual receipt'**
  String get stockReasonManualReceipt;

  /// No description provided for @stockReasonProductionOutput.
  ///
  /// In en, this message translates to:
  /// **'Production output'**
  String get stockReasonProductionOutput;

  /// No description provided for @stockReasonPurchaseReceipt.
  ///
  /// In en, this message translates to:
  /// **'Purchase receipt'**
  String get stockReasonPurchaseReceipt;

  /// No description provided for @stockReasonRepairUse.
  ///
  /// In en, this message translates to:
  /// **'Used in repair'**
  String get stockReasonRepairUse;

  /// No description provided for @stockReasonReturn.
  ///
  /// In en, this message translates to:
  /// **'Customer return'**
  String get stockReasonReturn;

  /// No description provided for @stockReasonReversal.
  ///
  /// In en, this message translates to:
  /// **'Reversal'**
  String get stockReasonReversal;

  /// No description provided for @stockReasonScrap.
  ///
  /// In en, this message translates to:
  /// **'Scrap'**
  String get stockReasonScrap;

  /// No description provided for @stockReasonShipment.
  ///
  /// In en, this message translates to:
  /// **'Shipment'**
  String get stockReasonShipment;

  /// No description provided for @stockReasonVanReplenishment.
  ///
  /// In en, this message translates to:
  /// **'Van replenishment'**
  String get stockReasonVanReplenishment;

  /// No description provided for @stockReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get stockReceive;

  /// No description provided for @stockReorderMax.
  ///
  /// In en, this message translates to:
  /// **'Reorder maximum'**
  String get stockReorderMax;

  /// No description provided for @stockReorderMin.
  ///
  /// In en, this message translates to:
  /// **'Reorder minimum'**
  String get stockReorderMin;

  /// No description provided for @stockReservations.
  ///
  /// In en, this message translates to:
  /// **'Reserved for orders'**
  String get stockReservations;

  /// No description provided for @stockReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get stockReserved;

  /// No description provided for @stockReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get stockReverse;

  /// No description provided for @stockReverseAnyway.
  ///
  /// In en, this message translates to:
  /// **'Reverse anyway'**
  String get stockReverseAnyway;

  /// No description provided for @stockReverseTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse this movement'**
  String get stockReverseTitle;

  /// No description provided for @stockReversed.
  ///
  /// In en, this message translates to:
  /// **'reversed'**
  String get stockReversed;

  /// No description provided for @stockShortBy.
  ///
  /// In en, this message translates to:
  /// **'Short by {quantity}'**
  String stockShortBy(String quantity);

  /// No description provided for @stockStandardCost.
  ///
  /// In en, this message translates to:
  /// **'Standard cost'**
  String get stockStandardCost;

  /// No description provided for @stockStateAvailable.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get stockStateAvailable;

  /// No description provided for @stockStateNotStocked.
  ///
  /// In en, this message translates to:
  /// **'Not stocked'**
  String get stockStateNotStocked;

  /// No description provided for @stockStatePartial.
  ///
  /// In en, this message translates to:
  /// **'Partly in stock'**
  String get stockStatePartial;

  /// No description provided for @stockStateReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get stockStateReserved;

  /// No description provided for @stockStateShort.
  ///
  /// In en, this message translates to:
  /// **'Not in stock'**
  String get stockStateShort;

  /// No description provided for @stockTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stockTitle;

  /// No description provided for @stockTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get stockTo;

  /// No description provided for @stockTrackingLot.
  ///
  /// In en, this message translates to:
  /// **'lot'**
  String get stockTrackingLot;

  /// No description provided for @stockTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get stockTransfer;

  /// No description provided for @stockWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get stockWarehouse;

  /// No description provided for @stockWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Warehouses'**
  String get stockWarehouses;

  /// No description provided for @street.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get street;

  /// No description provided for @streetAddress.
  ///
  /// In en, this message translates to:
  /// **'Street and number'**
  String get streetAddress;

  /// No description provided for @structureRevision.
  ///
  /// In en, this message translates to:
  /// **'Structure (revision {revision})'**
  String structureRevision(int revision);

  /// No description provided for @subassembly.
  ///
  /// In en, this message translates to:
  /// **'subassembly'**
  String get subassembly;

  /// No description provided for @subject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subject;

  /// No description provided for @subjectContains.
  ///
  /// In en, this message translates to:
  /// **'Subject contains'**
  String get subjectContains;

  /// No description provided for @subjectOptional.
  ///
  /// In en, this message translates to:
  /// **'Subject (optional)'**
  String get subjectOptional;

  /// No description provided for @suggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested: {value}'**
  String suggested(String value);

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @suspendContract.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get suspendContract;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @tasksProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String tasksProgress(String done, String total);

  /// No description provided for @team.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get team;

  /// No description provided for @teamLead.
  ///
  /// In en, this message translates to:
  /// **'Lead'**
  String get teamLead;

  /// No description provided for @teamMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get teamMembers;

  /// No description provided for @teamName.
  ///
  /// In en, this message translates to:
  /// **'Team name'**
  String get teamName;

  /// No description provided for @teams.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get teams;

  /// No description provided for @technicians.
  ///
  /// In en, this message translates to:
  /// **'Technicians'**
  String get technicians;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @ticket.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get ticket;

  /// No description provided for @ticketClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get ticketClosed;

  /// No description provided for @ticketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket details'**
  String get ticketDetails;

  /// No description provided for @ticketInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get ticketInProgress;

  /// No description provided for @ticketMerged.
  ///
  /// In en, this message translates to:
  /// **'Tickets merged'**
  String get ticketMerged;

  /// No description provided for @ticketOpened.
  ///
  /// In en, this message translates to:
  /// **'Ticket opened'**
  String get ticketOpened;

  /// No description provided for @ticketSplit.
  ///
  /// In en, this message translates to:
  /// **'Created ticket {number}'**
  String ticketSplit(String number);

  /// No description provided for @ticketStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get ticketStatusClosed;

  /// No description provided for @ticketStatusNew.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get ticketStatusNew;

  /// No description provided for @ticketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get ticketStatusOpen;

  /// No description provided for @ticketStatusPendingCustomer.
  ///
  /// In en, this message translates to:
  /// **'waiting for customer'**
  String get ticketStatusPendingCustomer;

  /// No description provided for @ticketStatusPendingInternal.
  ///
  /// In en, this message translates to:
  /// **'waiting for colleague'**
  String get ticketStatusPendingInternal;

  /// No description provided for @ticketVolume.
  ///
  /// In en, this message translates to:
  /// **'Tickets created and closed'**
  String get ticketVolume;

  /// No description provided for @ticketWaitingForYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your reply'**
  String get ticketWaitingForYou;

  /// No description provided for @tickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get tickets;

  /// No description provided for @timeLogged.
  ///
  /// In en, this message translates to:
  /// **'Time logged'**
  String get timeLogged;

  /// No description provided for @timeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get timeNote;

  /// No description provided for @timeTotal.
  ///
  /// In en, this message translates to:
  /// **'Total {total}, billable {billable}'**
  String timeTotal(String total, String billable);

  /// No description provided for @timeTotals.
  ///
  /// In en, this message translates to:
  /// **'Work {work} · Travel {travel}'**
  String timeTotals(String work, String travel);

  /// No description provided for @timeTracking.
  ///
  /// In en, this message translates to:
  /// **'Time tracking'**
  String get timeTracking;

  /// No description provided for @timeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get timeZone;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @titleCustomerValueRequired.
  ///
  /// In en, this message translates to:
  /// **'Title, customer and a valid value are required.'**
  String get titleCustomerValueRequired;

  /// No description provided for @titleMr.
  ///
  /// In en, this message translates to:
  /// **'Mr.'**
  String get titleMr;

  /// No description provided for @titleMs.
  ///
  /// In en, this message translates to:
  /// **'Ms.'**
  String get titleMs;

  /// No description provided for @titleNone.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get titleNone;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @topCategories.
  ///
  /// In en, this message translates to:
  /// **'Top categories'**
  String get topCategories;

  /// No description provided for @topTags.
  ///
  /// In en, this message translates to:
  /// **'Top tags'**
  String get topTags;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @productsTotalChange.
  ///
  /// In en, this message translates to:
  /// **'Products excl. shipping and VAT: {from} → {to} ({difference})'**
  String productsTotalChange(String from, String to, String difference);

  /// No description provided for @totalExclVat.
  ///
  /// In en, this message translates to:
  /// **'Total excl. VAT'**
  String get totalExclVat;

  /// No description provided for @totalInclVat.
  ///
  /// In en, this message translates to:
  /// **'Total incl. VAT'**
  String get totalInclVat;

  /// No description provided for @totalsToBuyOrMake.
  ///
  /// In en, this message translates to:
  /// **'Totals to buy or make'**
  String get totalsToBuyOrMake;

  /// No description provided for @tracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// No description provided for @twoLetters.
  ///
  /// In en, this message translates to:
  /// **'2 letters'**
  String get twoLetters;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @unassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassigned;

  /// No description provided for @unchanged.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get unchanged;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @unitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get unitPrice;

  /// No description provided for @unitPriceExclVat.
  ///
  /// In en, this message translates to:
  /// **'Unit price (excl. VAT)'**
  String get unitPriceExclVat;

  /// No description provided for @unknownCaller.
  ///
  /// In en, this message translates to:
  /// **'Unknown caller'**
  String get unknownCaller;

  /// No description provided for @until.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get until;

  /// No description provided for @upcomingVisits.
  ///
  /// In en, this message translates to:
  /// **'Upcoming visits'**
  String get upcomingVisits;

  /// No description provided for @updateToCurrentPrices.
  ///
  /// In en, this message translates to:
  /// **'Update to current prices'**
  String get updateToCurrentPrices;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploadingFile;

  /// No description provided for @uploadingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploadingPhotos;

  /// No description provided for @useAnotherPriceListDate.
  ///
  /// In en, this message translates to:
  /// **'Use another price list date'**
  String get useAnotherPriceListDate;

  /// No description provided for @validFrom.
  ///
  /// In en, this message translates to:
  /// **'Valid from'**
  String get validFrom;

  /// No description provided for @validFromDate.
  ///
  /// In en, this message translates to:
  /// **'Valid from {date}'**
  String validFromDate(String date);

  /// No description provided for @validUntil.
  ///
  /// In en, this message translates to:
  /// **'valid until {date}'**
  String validUntil(String date);

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @vat.
  ///
  /// In en, this message translates to:
  /// **'VAT'**
  String get vat;

  /// No description provided for @vatNumber.
  ///
  /// In en, this message translates to:
  /// **'VAT number'**
  String get vatNumber;

  /// No description provided for @vatOn.
  ///
  /// In en, this message translates to:
  /// **'VAT {rate} % on {base}'**
  String vatOn(String rate, String base);

  /// No description provided for @vatPercent.
  ///
  /// In en, this message translates to:
  /// **'VAT %'**
  String get vatPercent;

  /// No description provided for @viaPortal.
  ///
  /// In en, this message translates to:
  /// **'Via the customer portal'**
  String get viaPortal;

  /// No description provided for @visitTemplates.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get visitTemplates;

  /// No description provided for @visitTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Every visit needs a title'**
  String get visitTitleRequired;

  /// No description provided for @warranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get warranty;

  /// No description provided for @warrantyExpired.
  ///
  /// In en, this message translates to:
  /// **'Warranty expired'**
  String get warrantyExpired;

  /// No description provided for @warrantyIn.
  ///
  /// In en, this message translates to:
  /// **'In warranty'**
  String get warrantyIn;

  /// No description provided for @warrantyOut.
  ///
  /// In en, this message translates to:
  /// **'Out of warranty'**
  String get warrantyOut;

  /// No description provided for @warrantyUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get warrantyUnknown;

  /// No description provided for @weekdayFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get weekdayFriday;

  /// No description provided for @weekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get weekdayMonday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get weekdaySaturday;

  /// No description provided for @weekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get weekdaySunday;

  /// No description provided for @weekdayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get weekdayThursday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get weekdayWednesday;

  /// No description provided for @warrantyUntilDate.
  ///
  /// In en, this message translates to:
  /// **'until {date}'**
  String warrantyUntilDate(String date);

  /// No description provided for @warrantyUntilLabel.
  ///
  /// In en, this message translates to:
  /// **'Warranty until'**
  String get warrantyUntilLabel;

  /// No description provided for @weighted.
  ///
  /// In en, this message translates to:
  /// **'weighted {amount}'**
  String weighted(String amount);

  /// No description provided for @whatWasAsked.
  ///
  /// In en, this message translates to:
  /// **'What was asked?'**
  String get whatWasAsked;

  /// No description provided for @whoIsCalling.
  ///
  /// In en, this message translates to:
  /// **'Who is calling?'**
  String get whoIsCalling;

  /// No description provided for @won.
  ///
  /// In en, this message translates to:
  /// **'Won'**
  String get won;

  /// No description provided for @workFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get workFrom;

  /// No description provided for @workKindTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get workKindTravel;

  /// No description provided for @workKindWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get workKindWork;

  /// No description provided for @workLogs.
  ///
  /// In en, this message translates to:
  /// **'Time registered'**
  String get workLogs;

  /// No description provided for @workUntil.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get workUntil;

  /// No description provided for @writeIn.
  ///
  /// In en, this message translates to:
  /// **'Write in {language}'**
  String writeIn(String language);

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @yourMessage.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get yourMessage;

  /// No description provided for @yourReference.
  ///
  /// In en, this message translates to:
  /// **'Your reference (RMA or order)'**
  String get yourReference;

  /// No description provided for @zone.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get zone;

  /// No description provided for @zoneAndRebate.
  ///
  /// In en, this message translates to:
  /// **'Zone {zone} · general rebate {percent} %'**
  String zoneAndRebate(String zone, String percent);

  /// No description provided for @zonesNoneAll.
  ///
  /// In en, this message translates to:
  /// **'Zones (none selected = all)'**
  String get zonesNoneAll;

  /// No description provided for @kbTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base'**
  String get kbTitle;

  /// No description provided for @kbNewArticle.
  ///
  /// In en, this message translates to:
  /// **'New article'**
  String get kbNewArticle;

  /// No description provided for @kbSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search articles'**
  String get kbSearchHint;

  /// No description provided for @kbAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get kbAllCategories;

  /// No description provided for @kbAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get kbAllStatuses;

  /// No description provided for @kbAllAudiences.
  ///
  /// In en, this message translates to:
  /// **'All audiences'**
  String get kbAllAudiences;

  /// No description provided for @kbManageCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get kbManageCategories;

  /// No description provided for @kbStatusPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get kbStatusPublished;

  /// No description provided for @kbStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get kbStatusArchived;

  /// No description provided for @kbAudience.
  ///
  /// In en, this message translates to:
  /// **'Audience'**
  String get kbAudience;

  /// No description provided for @kbAudienceInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal (staff only)'**
  String get kbAudienceInternal;

  /// No description provided for @kbAudiencePortal.
  ///
  /// In en, this message translates to:
  /// **'Customer portal'**
  String get kbAudiencePortal;

  /// No description provided for @kbAudiencePublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get kbAudiencePublic;

  /// No description provided for @kbArticleTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get kbArticleTitle;

  /// No description provided for @kbSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get kbSummary;

  /// No description provided for @kbBody.
  ///
  /// In en, this message translates to:
  /// **'Text (Markdown)'**
  String get kbBody;

  /// No description provided for @kbPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get kbPreview;

  /// No description provided for @kbWriteTab.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get kbWriteTab;

  /// No description provided for @kbMarkdownHelp.
  ///
  /// In en, this message translates to:
  /// **'Use # for headings, **bold**, *italic*, - for lists, [text](https://…) for links and ![description](image:ID) for pictures.'**
  String get kbMarkdownHelp;

  /// No description provided for @kbTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get kbTagsLabel;

  /// No description provided for @kbRelated.
  ///
  /// In en, this message translates to:
  /// **'Related articles'**
  String get kbRelated;

  /// No description provided for @kbAddRelated.
  ///
  /// In en, this message translates to:
  /// **'Add related article'**
  String get kbAddRelated;

  /// No description provided for @kbImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get kbImages;

  /// No description provided for @kbUploadImage.
  ///
  /// In en, this message translates to:
  /// **'Upload image'**
  String get kbUploadImage;

  /// No description provided for @kbInsertImage.
  ///
  /// In en, this message translates to:
  /// **'Insert in text'**
  String get kbInsertImage;

  /// No description provided for @kbPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get kbPublish;

  /// No description provided for @kbUnpublish.
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get kbUnpublish;

  /// No description provided for @kbArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get kbArchive;

  /// No description provided for @kbHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get kbHistory;

  /// No description provided for @kbVersionLine.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · {name} · {date}'**
  String kbVersionLine(int version, String name, String date);

  /// No description provided for @kbRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get kbRestore;

  /// No description provided for @kbRestoredFrom.
  ///
  /// In en, this message translates to:
  /// **'restored from version {version}'**
  String kbRestoredFrom(int version);

  /// No description provided for @kbFeedback.
  ///
  /// In en, this message translates to:
  /// **'{yes} found this helpful, {no} did not'**
  String kbFeedback(int yes, int no);

  /// No description provided for @kbViews.
  ///
  /// In en, this message translates to:
  /// **'{count} views'**
  String kbViews(int count);

  /// No description provided for @kbNoArticles.
  ///
  /// In en, this message translates to:
  /// **'No articles found.'**
  String get kbNoArticles;

  /// No description provided for @kbNoCategory.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get kbNoCategory;

  /// No description provided for @kbMainCategory.
  ///
  /// In en, this message translates to:
  /// **'Main category'**
  String get kbMainCategory;

  /// No description provided for @kbSortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort order'**
  String get kbSortOrder;

  /// No description provided for @kbNewCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get kbNewCategory;

  /// No description provided for @kbCategoryNames.
  ///
  /// In en, this message translates to:
  /// **'Name per language'**
  String get kbCategoryNames;

  /// No description provided for @kbDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get kbDelete;

  /// No description provided for @kbSuggestedArticles.
  ///
  /// In en, this message translates to:
  /// **'Suggested articles'**
  String get kbSuggestedArticles;

  /// No description provided for @kbNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No matching articles.'**
  String get kbNoSuggestions;

  /// No description provided for @kbInsertText.
  ///
  /// In en, this message translates to:
  /// **'Insert text'**
  String get kbInsertText;

  /// No description provided for @kbInsertLink.
  ///
  /// In en, this message translates to:
  /// **'Insert link'**
  String get kbInsertLink;

  /// No description provided for @kbInsertArticle.
  ///
  /// In en, this message translates to:
  /// **'Insert article'**
  String get kbInsertArticle;

  /// No description provided for @kbNoPortalLink.
  ///
  /// In en, this message translates to:
  /// **'This article is internal: only its text can be inserted.'**
  String get kbNoPortalLink;

  /// No description provided for @kbHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get kbHelp;

  /// No description provided for @kbHelpHeading.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get kbHelpHeading;

  /// No description provided for @kbHelpSearch.
  ///
  /// In en, this message translates to:
  /// **'Search the help articles'**
  String get kbHelpSearch;

  /// No description provided for @kbHelpEmpty.
  ///
  /// In en, this message translates to:
  /// **'No articles found. You can open a ticket instead.'**
  String get kbHelpEmpty;

  /// No description provided for @kbWasHelpful.
  ///
  /// In en, this message translates to:
  /// **'Was this article helpful?'**
  String get kbWasHelpful;

  /// No description provided for @kbYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get kbYes;

  /// No description provided for @kbNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get kbNo;

  /// No description provided for @kbThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback.'**
  String get kbThanks;

  /// No description provided for @kbStillNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Still need help? Open a ticket.'**
  String get kbStillNeedHelp;

  /// No description provided for @kbRelatedReading.
  ///
  /// In en, this message translates to:
  /// **'Related articles'**
  String get kbRelatedReading;

  /// No description provided for @kbDeflectionTitle.
  ///
  /// In en, this message translates to:
  /// **'These articles may already answer your question'**
  String get kbDeflectionTitle;

  /// No description provided for @kbShownIn.
  ///
  /// In en, this message translates to:
  /// **'Not available in your language; shown in {language}.'**
  String kbShownIn(String language);

  /// No description provided for @kbUpdatedOn.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String kbUpdatedOn(String date);

  /// No description provided for @offlineWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change waiting to sync} other{{count} changes waiting to sync}}'**
  String offlineWaiting(int count);

  /// No description provided for @offlineFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 needs your attention} other{{count} need your attention}}'**
  String offlineFailedCount(int count);

  /// No description provided for @offlineQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Changes waiting to sync'**
  String get offlineQueueTitle;

  /// No description provided for @offlineSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get offlineSyncNow;

  /// No description provided for @offlineRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get offlineRetry;

  /// No description provided for @offlineDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get offlineDiscard;

  /// No description provided for @offlineDiscardQuestion.
  ///
  /// In en, this message translates to:
  /// **'Discard this change? It will not be sent to the server.'**
  String get offlineDiscardQuestion;

  /// No description provided for @offlineAllSynced.
  ///
  /// In en, this message translates to:
  /// **'Everything is synced.'**
  String get offlineAllSynced;

  /// No description provided for @offlineAttempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts: {count}'**
  String offlineAttempts(int count);

  /// No description provided for @offlineLastError.
  ///
  /// In en, this message translates to:
  /// **'Last error: {message}'**
  String offlineLastError(String message);

  /// No description provided for @offlineRejected.
  ///
  /// In en, this message translates to:
  /// **'The server refused this change. The job may have been reassigned, cancelled or changed in the meantime.'**
  String get offlineRejected;

  /// No description provided for @offlineDataFrom.
  ///
  /// In en, this message translates to:
  /// **'Offline: data from {time}'**
  String offlineDataFrom(String time);

  /// No description provided for @offlinePendingSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get offlinePendingSync;

  /// No description provided for @offlineQueuedMessage.
  ///
  /// In en, this message translates to:
  /// **'No connection: saved on this device, it will be sent when you are back online.'**
  String get offlineQueuedMessage;

  /// No description provided for @offlinePhotosWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo waiting to upload} other{{count} photos waiting to upload}}'**
  String offlinePhotosWaiting(int count);

  /// No description provided for @offlineTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large to keep offline. Connect to send it.'**
  String get offlineTooLarge;

  /// No description provided for @offlineReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get offlineReload;

  /// No description provided for @offlineOpStart.
  ///
  /// In en, this message translates to:
  /// **'Start job'**
  String get offlineOpStart;

  /// No description provided for @offlineOpTaskDone.
  ///
  /// In en, this message translates to:
  /// **'Task ticked'**
  String get offlineOpTaskDone;

  /// No description provided for @offlineOpTaskUndone.
  ///
  /// In en, this message translates to:
  /// **'Task unticked'**
  String get offlineOpTaskUndone;

  /// No description provided for @offlineOpTaskAdd.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get offlineOpTaskAdd;

  /// No description provided for @offlineOpWorkLog.
  ///
  /// In en, this message translates to:
  /// **'Time entry'**
  String get offlineOpWorkLog;

  /// No description provided for @offlineOpPart.
  ///
  /// In en, this message translates to:
  /// **'Part used'**
  String get offlineOpPart;

  /// No description provided for @offlineOpComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete job'**
  String get offlineOpComplete;

  /// No description provided for @offlineOpDecline.
  ///
  /// In en, this message translates to:
  /// **'Customer declined to sign'**
  String get offlineOpDecline;

  /// No description provided for @offlineOpSignature.
  ///
  /// In en, this message translates to:
  /// **'Customer signature'**
  String get offlineOpSignature;

  /// No description provided for @offlineOpPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get offlineOpPhoto;

  /// No description provided for @collabEscalate.
  ///
  /// In en, this message translates to:
  /// **'Escalate'**
  String get collabEscalate;

  /// No description provided for @collabEscalateTitle.
  ///
  /// In en, this message translates to:
  /// **'Escalate ticket'**
  String get collabEscalateTitle;

  /// No description provided for @collabDelegate.
  ///
  /// In en, this message translates to:
  /// **'Hand over'**
  String get collabDelegate;

  /// No description provided for @collabDelegateTitle.
  ///
  /// In en, this message translates to:
  /// **'Hand over ticket'**
  String get collabDelegateTitle;

  /// No description provided for @collabEscalateTo.
  ///
  /// In en, this message translates to:
  /// **'Escalate to'**
  String get collabEscalateTo;

  /// No description provided for @collabNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Leads of the ticket\'s team'**
  String get collabNoTarget;

  /// No description provided for @collabPerson.
  ///
  /// In en, this message translates to:
  /// **'Colleague'**
  String get collabPerson;

  /// No description provided for @collabTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get collabTeam;

  /// No description provided for @collabHandOverTo.
  ///
  /// In en, this message translates to:
  /// **'New owner'**
  String get collabHandOverTo;

  /// No description provided for @collabReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get collabReasonRequired;

  /// No description provided for @collabRaisePriority.
  ///
  /// In en, this message translates to:
  /// **'Raise priority one step'**
  String get collabRaisePriority;

  /// No description provided for @collabCommentOptional.
  ///
  /// In en, this message translates to:
  /// **'Comment for the new owner (optional)'**
  String get collabCommentOptional;

  /// No description provided for @collabInternalHint.
  ///
  /// In en, this message translates to:
  /// **'Internal: never sent to the customer.'**
  String get collabInternalHint;

  /// No description provided for @collabEscalated.
  ///
  /// In en, this message translates to:
  /// **'Ticket escalated'**
  String get collabEscalated;

  /// No description provided for @collabHandedOver.
  ///
  /// In en, this message translates to:
  /// **'Ticket handed over'**
  String get collabHandedOver;

  /// No description provided for @collabEscalatedBadge.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get collabEscalatedBadge;

  /// No description provided for @collabEscalatedBy.
  ///
  /// In en, this message translates to:
  /// **'Escalated by {name}'**
  String collabEscalatedBy(String name);

  /// No description provided for @collabWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get collabWatch;

  /// No description provided for @collabUnwatch.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get collabUnwatch;

  /// No description provided for @collabWatchers.
  ///
  /// In en, this message translates to:
  /// **'Watchers'**
  String get collabWatchers;

  /// No description provided for @collabNoWatchers.
  ///
  /// In en, this message translates to:
  /// **'Nobody follows this ticket'**
  String get collabNoWatchers;

  /// No description provided for @collabAddWatcher.
  ///
  /// In en, this message translates to:
  /// **'Add watcher'**
  String get collabAddWatcher;

  /// No description provided for @collabActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get collabActivity;

  /// No description provided for @collabNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get collabNoActivity;

  /// No description provided for @collabSeenBy.
  ///
  /// In en, this message translates to:
  /// **'Seen by {readers}'**
  String collabSeenBy(String readers);

  /// No description provided for @collabFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get collabFilterUnread;

  /// No description provided for @collabFilterWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get collabFilterWatching;

  /// No description provided for @collabFilterEscalated.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get collabFilterEscalated;

  /// No description provided for @collabUnreadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get collabUnreadTooltip;

  /// No description provided for @collabReplying.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{names} is replying} other{{names} are replying}} — coordinate before sending'**
  String collabReplying(int count, String names);

  /// No description provided for @collabViewing.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{names} is viewing this ticket} other{{names} are viewing this ticket}}'**
  String collabViewing(int count, String names);

  /// No description provided for @collabConfirmSend.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{names} is replying to this ticket right now.} other{{names} are replying to this ticket right now.}} Send anyway?'**
  String collabConfirmSend(int count, String names);

  /// No description provided for @collabSendAnyway.
  ///
  /// In en, this message translates to:
  /// **'Send anyway'**
  String get collabSendAnyway;

  /// No description provided for @collabSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get collabSystem;

  /// No description provided for @collabEventCreated.
  ///
  /// In en, this message translates to:
  /// **'{actor} created the ticket'**
  String collabEventCreated(String actor);

  /// No description provided for @collabEventAssignedOwner.
  ///
  /// In en, this message translates to:
  /// **'{actor} assigned the ticket to {owner}'**
  String collabEventAssignedOwner(String actor, String owner);

  /// No description provided for @collabEventOwnerCleared.
  ///
  /// In en, this message translates to:
  /// **'{actor} removed the owner'**
  String collabEventOwnerCleared(String actor);

  /// No description provided for @collabEventTeam.
  ///
  /// In en, this message translates to:
  /// **'{actor} moved the ticket to team {team}'**
  String collabEventTeam(String actor, String team);

  /// No description provided for @collabEventTeamCleared.
  ///
  /// In en, this message translates to:
  /// **'{actor} removed the team'**
  String collabEventTeamCleared(String actor);

  /// No description provided for @collabEventDelegated.
  ///
  /// In en, this message translates to:
  /// **'{actor} handed the ticket over to {owner}'**
  String collabEventDelegated(String actor, String owner);

  /// No description provided for @collabEventEscalated.
  ///
  /// In en, this message translates to:
  /// **'{actor} escalated the ticket'**
  String collabEventEscalated(String actor);

  /// No description provided for @collabEventStatus.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the status from {before} to {after}'**
  String collabEventStatus(String actor, String before, String after);

  /// No description provided for @collabEventPriority.
  ///
  /// In en, this message translates to:
  /// **'{actor} changed the priority from {before} to {after}'**
  String collabEventPriority(String actor, String before, String after);

  /// No description provided for @collabEventMergedInto.
  ///
  /// In en, this message translates to:
  /// **'{actor} merged this ticket into {number}'**
  String collabEventMergedInto(String actor, String number);

  /// No description provided for @collabEventMergedFrom.
  ///
  /// In en, this message translates to:
  /// **'{actor} merged {number} into this ticket'**
  String collabEventMergedFrom(String actor, String number);

  /// No description provided for @collabEventTagAdded.
  ///
  /// In en, this message translates to:
  /// **'{actor} added the tag {tag}'**
  String collabEventTagAdded(String actor, String tag);

  /// No description provided for @collabEventTagRemoved.
  ///
  /// In en, this message translates to:
  /// **'{actor} removed the tag {tag}'**
  String collabEventTagRemoved(String actor, String tag);

  /// No description provided for @collabMsgCustomer.
  ///
  /// In en, this message translates to:
  /// **'{actor} (customer) wrote'**
  String collabMsgCustomer(String actor);

  /// No description provided for @collabMsgReply.
  ///
  /// In en, this message translates to:
  /// **'{actor} replied to the customer'**
  String collabMsgReply(String actor);

  /// No description provided for @collabMsgNote.
  ///
  /// In en, this message translates to:
  /// **'{actor} added an internal note'**
  String collabMsgNote(String actor);

  /// No description provided for @collabMsgCall.
  ///
  /// In en, this message translates to:
  /// **'{actor} logged a call'**
  String collabMsgCall(String actor);

  /// No description provided for @planningTitle.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get planningTitle;

  /// No description provided for @planningDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get planningDay;

  /// No description provided for @planningWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get planningWeek;

  /// No description provided for @planningToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get planningToday;

  /// No description provided for @planningPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get planningPrevious;

  /// No description provided for @planningNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get planningNext;

  /// No description provided for @planningBacklog.
  ///
  /// In en, this message translates to:
  /// **'To plan'**
  String get planningBacklog;

  /// No description provided for @planningBacklogEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing left to plan.'**
  String get planningBacklogEmpty;

  /// No description provided for @planningSkillFilter.
  ///
  /// In en, this message translates to:
  /// **'Skill'**
  String get planningSkillFilter;

  /// No description provided for @planningAllSkills.
  ///
  /// In en, this message translates to:
  /// **'All skills'**
  String get planningAllSkills;

  /// No description provided for @planningNoTechnicians.
  ///
  /// In en, this message translates to:
  /// **'No technicians to show. Give users the technician role.'**
  String get planningNoTechnicians;

  /// No description provided for @planningPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planningPlan;

  /// No description provided for @planningScheduleJob.
  ///
  /// In en, this message translates to:
  /// **'Schedule {number}'**
  String planningScheduleJob(String number);

  /// No description provided for @planningSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get planningSuggestions;

  /// No description provided for @planningShowSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Show suggestions'**
  String get planningShowSuggestions;

  /// No description provided for @planningNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No free slot found in the next two weeks.'**
  String get planningNoSuggestions;

  /// No description provided for @planningMissingSkills.
  ///
  /// In en, this message translates to:
  /// **'{count} skill(s) missing'**
  String planningMissingSkills(int count);

  /// No description provided for @planningRequiredSkills.
  ///
  /// In en, this message translates to:
  /// **'Required skills'**
  String get planningRequiredSkills;

  /// No description provided for @planningChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get planningChecking;

  /// No description provided for @planningNoConflicts.
  ///
  /// In en, this message translates to:
  /// **'No conflicts.'**
  String get planningNoConflicts;

  /// No description provided for @planningConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule with conflicts?'**
  String get planningConfirmTitle;

  /// No description provided for @planningConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This placement has errors:'**
  String get planningConfirmBody;

  /// No description provided for @planningScheduleAnyway.
  ///
  /// In en, this message translates to:
  /// **'Schedule anyway'**
  String get planningScheduleAnyway;

  /// No description provided for @planningScheduled.
  ///
  /// In en, this message translates to:
  /// **'Job scheduled.'**
  String get planningScheduled;

  /// No description provided for @planningConflictDoubleBooked.
  ///
  /// In en, this message translates to:
  /// **'{name} has another job at that time (travel time included).'**
  String planningConflictDoubleBooked(String name);

  /// No description provided for @planningConflictOutsideHours.
  ///
  /// In en, this message translates to:
  /// **'{name} is outside working hours.'**
  String planningConflictOutsideHours(String name);

  /// No description provided for @planningConflictOnAbsence.
  ///
  /// In en, this message translates to:
  /// **'{name} is absent.'**
  String planningConflictOnAbsence(String name);

  /// No description provided for @planningConflictMissingSkill.
  ///
  /// In en, this message translates to:
  /// **'{name} lacks the skill {skill}.'**
  String planningConflictMissingSkill(String name, String skill);

  /// No description provided for @planningConflictCrossesDays.
  ///
  /// In en, this message translates to:
  /// **'The job runs past midnight.'**
  String get planningConflictCrossesDays;

  /// No description provided for @planningAbsenceVacation.
  ///
  /// In en, this message translates to:
  /// **'Vacation'**
  String get planningAbsenceVacation;

  /// No description provided for @planningAbsenceSick.
  ///
  /// In en, this message translates to:
  /// **'Sick'**
  String get planningAbsenceSick;

  /// No description provided for @planningAbsenceTraining.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get planningAbsenceTraining;

  /// No description provided for @planningAbsenceOther.
  ///
  /// In en, this message translates to:
  /// **'Other absence'**
  String get planningAbsenceOther;

  /// No description provided for @planningAgendaEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned.'**
  String get planningAgendaEmpty;

  /// No description provided for @planningSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Planning settings'**
  String get planningSettingsTitle;

  /// No description provided for @planningAbsences.
  ///
  /// In en, this message translates to:
  /// **'Absences'**
  String get planningAbsences;

  /// No description provided for @planningHours.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get planningHours;

  /// No description provided for @planningSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get planningSkills;

  /// No description provided for @planningGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get planningGeneral;

  /// No description provided for @planningAddAbsence.
  ///
  /// In en, this message translates to:
  /// **'Add absence'**
  String get planningAddAbsence;

  /// No description provided for @planningNoAbsences.
  ///
  /// In en, this message translates to:
  /// **'No absences recorded.'**
  String get planningNoAbsences;

  /// No description provided for @planningTechnician.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get planningTechnician;

  /// No description provided for @planningKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get planningKind;

  /// No description provided for @planningDefaultHours.
  ///
  /// In en, this message translates to:
  /// **'Company default'**
  String get planningDefaultHours;

  /// No description provided for @planningUsesDefault.
  ///
  /// In en, this message translates to:
  /// **'No hours of their own: the company default applies.'**
  String get planningUsesDefault;

  /// No description provided for @planningAddBlock.
  ///
  /// In en, this message translates to:
  /// **'Add block'**
  String get planningAddBlock;

  /// No description provided for @planningAddSkill.
  ///
  /// In en, this message translates to:
  /// **'Add skill'**
  String get planningAddSkill;

  /// No description provided for @planningTechnicianSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills per technician'**
  String get planningTechnicianSkills;

  /// No description provided for @planningSkillLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {n}'**
  String planningSkillLevel(int n);

  /// No description provided for @planningTravelBuffer.
  ///
  /// In en, this message translates to:
  /// **'Travel time between jobs (minutes)'**
  String get planningTravelBuffer;

  /// No description provided for @planningTravelBufferHelp.
  ///
  /// In en, this message translates to:
  /// **'Kept free between two jobs of a technician on the same day.'**
  String get planningTravelBufferHelp;

  /// No description provided for @planningDefaultJobMinutes.
  ///
  /// In en, this message translates to:
  /// **'Default job length (minutes)'**
  String get planningDefaultJobMinutes;

  /// No description provided for @planningTimezone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get planningTimezone;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get adminTitle;

  /// No description provided for @adminUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsers;

  /// No description provided for @adminModules.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get adminModules;

  /// No description provided for @newUser.
  ///
  /// In en, this message translates to:
  /// **'New user'**
  String get newUser;

  /// No description provided for @editUser.
  ///
  /// In en, this message translates to:
  /// **'Edit user'**
  String get editUser;

  /// No description provided for @userDisabledModules.
  ///
  /// In en, this message translates to:
  /// **'Disabled modules'**
  String get userDisabledModules;

  /// No description provided for @userNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in yet'**
  String get userNotSignedIn;

  /// No description provided for @userResendInvitation.
  ///
  /// In en, this message translates to:
  /// **'Send invitation again'**
  String get userResendInvitation;

  /// No description provided for @userInvitationSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent'**
  String get userInvitationSent;

  /// No description provided for @userCreated.
  ///
  /// In en, this message translates to:
  /// **'User added'**
  String get userCreated;

  /// No description provided for @userFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All members'**
  String get userFilterAll;

  /// No description provided for @userFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active members'**
  String get userFilterActive;

  /// No description provided for @userFilterInactive.
  ///
  /// In en, this message translates to:
  /// **'Deactivated members'**
  String get userFilterInactive;

  /// No description provided for @userActiveHelp.
  ///
  /// In en, this message translates to:
  /// **'A deactivated member can no longer sign in to this company.'**
  String get userActiveHelp;

  /// No description provided for @userCannotDeactivateSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot deactivate yourself.'**
  String get userCannotDeactivateSelf;

  /// No description provided for @userCannotDropOwnAdmin.
  ///
  /// In en, this message translates to:
  /// **'You cannot remove your own admin role.'**
  String get userCannotDropOwnAdmin;

  /// No description provided for @userRolePermissions.
  ///
  /// In en, this message translates to:
  /// **'{count} permissions'**
  String userRolePermissions(int count);

  /// No description provided for @userModulesHelp.
  ///
  /// In en, this message translates to:
  /// **'Switch modules off for this person. Modules the company has switched off cannot be turned back on here.'**
  String get userModulesHelp;

  /// No description provided for @userModuleCompanyOff.
  ///
  /// In en, this message translates to:
  /// **'Switched off for the whole company'**
  String get userModuleCompanyOff;

  /// No description provided for @moduleRequires.
  ///
  /// In en, this message translates to:
  /// **'Needs {modules}'**
  String moduleRequires(String modules);

  /// No description provided for @modulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Switch off the modules this company does not use. People no longer see them and the server refuses their requests.'**
  String get modulesIntro;

  /// No description provided for @modulesSaved.
  ///
  /// In en, this message translates to:
  /// **'Modules saved'**
  String get modulesSaved;

  /// No description provided for @moduleAlsoRequires.
  ///
  /// In en, this message translates to:
  /// **'Also needs {modules}'**
  String moduleAlsoRequires(String modules);

  /// No description provided for @moduleAlsoSwitchedOff.
  ///
  /// In en, this message translates to:
  /// **'Also switches off: {modules}'**
  String moduleAlsoSwitchedOff(String modules);

  /// No description provided for @moduleAlsoSwitchedOn.
  ///
  /// In en, this message translates to:
  /// **'Also switches on: {modules}'**
  String moduleAlsoSwitchedOn(String modules);

  /// No description provided for @moduleExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand {module}'**
  String moduleExpand(String module);

  /// No description provided for @moduleCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse {module}'**
  String moduleCollapse(String module);

  /// No description provided for @moduleOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get moduleOn;

  /// No description provided for @moduleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get moduleOff;

  /// No description provided for @moduleLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String moduleLevel(int level);

  /// No description provided for @userRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get userRoleAdmin;

  /// No description provided for @userRoleSalesManager.
  ///
  /// In en, this message translates to:
  /// **'Sales manager'**
  String get userRoleSalesManager;

  /// No description provided for @userRoleSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get userRoleSales;

  /// No description provided for @userRoleSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get userRoleSupport;

  /// No description provided for @userRoleProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get userRoleProduction;

  /// No description provided for @userRoleWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get userRoleWarehouse;

  /// No description provided for @userRoleProductManager.
  ///
  /// In en, this message translates to:
  /// **'Product manager'**
  String get userRoleProductManager;

  /// No description provided for @userRoleWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Workshop'**
  String get userRoleWorkshop;

  /// No description provided for @userRoleTechnician.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get userRoleTechnician;

  /// No description provided for @userRoleDispatcher.
  ///
  /// In en, this message translates to:
  /// **'Dispatcher'**
  String get userRoleDispatcher;

  /// No description provided for @userRoleLogistics.
  ///
  /// In en, this message translates to:
  /// **'Logistics'**
  String get userRoleLogistics;

  /// No description provided for @userRoleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get userRoleViewer;

  /// No description provided for @moduleCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get moduleCustomers;

  /// No description provided for @moduleProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get moduleProducts;

  /// No description provided for @moduleSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get moduleSales;

  /// No description provided for @moduleEngineering.
  ///
  /// In en, this message translates to:
  /// **'Engineering'**
  String get moduleEngineering;

  /// No description provided for @moduleInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get moduleInventory;

  /// No description provided for @moduleHelpdesk.
  ///
  /// In en, this message translates to:
  /// **'Helpdesk'**
  String get moduleHelpdesk;

  /// No description provided for @moduleKb.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base'**
  String get moduleKb;

  /// No description provided for @moduleRepairs.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get moduleRepairs;

  /// No description provided for @moduleField.
  ///
  /// In en, this message translates to:
  /// **'Field service'**
  String get moduleField;

  /// No description provided for @purpose.
  ///
  /// In en, this message translates to:
  /// **'Purpose'**
  String get purpose;

  /// No description provided for @purposeInstallation.
  ///
  /// In en, this message translates to:
  /// **'Installation'**
  String get purposeInstallation;

  /// No description provided for @purposeStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get purposeStock;

  /// No description provided for @deliveryCountry.
  ///
  /// In en, this message translates to:
  /// **'Delivery country'**
  String get deliveryCountry;

  /// No description provided for @deliveryCountryDefault.
  ///
  /// In en, this message translates to:
  /// **'Default: {country}'**
  String deliveryCountryDefault(String country);

  /// No description provided for @deliveryCountryInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a two-letter country code, for example BE.'**
  String get deliveryCountryInvalid;

  /// No description provided for @shippingNotRequired.
  ///
  /// In en, this message translates to:
  /// **'not required'**
  String get shippingNotRequired;

  /// No description provided for @shippingPending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get shippingPending;

  /// No description provided for @shippingQuoted.
  ///
  /// In en, this message translates to:
  /// **'quoted'**
  String get shippingQuoted;

  /// No description provided for @shippingRequested.
  ///
  /// In en, this message translates to:
  /// **'requested'**
  String get shippingRequested;

  /// No description provided for @shippingPendingBanner.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a shipping quote from logistics. The quotation cannot be sent until the cost has been entered.'**
  String get shippingPendingBanner;

  /// No description provided for @shippingQuotedBanner.
  ///
  /// In en, this message translates to:
  /// **'The shipping cost has been quoted and is on the quotation as a shipping line.'**
  String get shippingQuotedBanner;

  /// No description provided for @shippingLineNote.
  ///
  /// In en, this message translates to:
  /// **'Added by logistics'**
  String get shippingLineNote;

  /// No description provided for @sendAnyway.
  ///
  /// In en, this message translates to:
  /// **'Send anyway'**
  String get sendAnyway;

  /// No description provided for @sendAnywayHelp.
  ///
  /// In en, this message translates to:
  /// **'{message}\n\nAs logistics you may send the quotation without the shipping cost. Send it anyway?'**
  String sendAnywayHelp(String message);

  /// No description provided for @shippingRequests.
  ///
  /// In en, this message translates to:
  /// **'Shipping requests'**
  String get shippingRequests;

  /// No description provided for @shippingQueue.
  ///
  /// In en, this message translates to:
  /// **'Open and requested'**
  String get shippingQueue;

  /// No description provided for @markAsRequested.
  ///
  /// In en, this message translates to:
  /// **'Mark as requested'**
  String get markAsRequested;

  /// No description provided for @enterQuote.
  ///
  /// In en, this message translates to:
  /// **'Enter quote'**
  String get enterQuote;

  /// No description provided for @carrier.
  ///
  /// In en, this message translates to:
  /// **'Carrier'**
  String get carrier;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @quotedAmount.
  ///
  /// In en, this message translates to:
  /// **'Quoted amount'**
  String get quotedAmount;

  /// No description provided for @requestedAt.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requestedAt;

  /// No description provided for @amountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get amountRequired;

  /// No description provided for @carrierRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the carrier.'**
  String get carrierRequired;

  /// No description provided for @packagingCategory.
  ///
  /// In en, this message translates to:
  /// **'Packaging category'**
  String get packagingCategory;

  /// No description provided for @packagingCategories.
  ///
  /// In en, this message translates to:
  /// **'Packaging categories'**
  String get packagingCategories;

  /// No description provided for @newPackagingCategory.
  ///
  /// In en, this message translates to:
  /// **'New packaging category'**
  String get newPackagingCategory;

  /// No description provided for @requiresShippingQuote.
  ///
  /// In en, this message translates to:
  /// **'Requires a shipping quote'**
  String get requiresShippingQuote;

  /// No description provided for @lengthMm.
  ///
  /// In en, this message translates to:
  /// **'Length (mm)'**
  String get lengthMm;

  /// No description provided for @widthMm.
  ///
  /// In en, this message translates to:
  /// **'Width (mm)'**
  String get widthMm;

  /// No description provided for @heightMm.
  ///
  /// In en, this message translates to:
  /// **'Height (mm)'**
  String get heightMm;

  /// No description provided for @weightG.
  ///
  /// In en, this message translates to:
  /// **'Weight (g)'**
  String get weightG;

  /// No description provided for @dimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get dimensions;

  /// No description provided for @dimensionsValue.
  ///
  /// In en, this message translates to:
  /// **'{length} x {width} x {height} mm'**
  String dimensionsValue(int length, int width, int height);

  /// No description provided for @weight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weight;

  /// No description provided for @weightValue.
  ///
  /// In en, this message translates to:
  /// **'{grams} g'**
  String weightValue(int grams);

  /// No description provided for @positiveWholeNumbers.
  ///
  /// In en, this message translates to:
  /// **'Dimensions and weight must be positive whole numbers, or empty.'**
  String get positiveWholeNumbers;

  /// No description provided for @powerTab.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get powerTab;

  /// No description provided for @powerNotElectrical.
  ///
  /// In en, this message translates to:
  /// **'No supplies are listed, so this is not an electrical product and is never checked against a power grid.'**
  String get powerNotElectrical;

  /// No description provided for @powerAddSupply.
  ///
  /// In en, this message translates to:
  /// **'Add supply'**
  String get powerAddSupply;

  /// No description provided for @currentType.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentType;

  /// No description provided for @currentAc.
  ///
  /// In en, this message translates to:
  /// **'AC'**
  String get currentAc;

  /// No description provided for @currentDc.
  ///
  /// In en, this message translates to:
  /// **'DC'**
  String get currentDc;

  /// No description provided for @voltageV.
  ///
  /// In en, this message translates to:
  /// **'Voltage (V)'**
  String get voltageV;

  /// No description provided for @phases.
  ///
  /// In en, this message translates to:
  /// **'Phases'**
  String get phases;

  /// No description provided for @frequencyHz.
  ///
  /// In en, this message translates to:
  /// **'Frequency (Hz)'**
  String get frequencyHz;

  /// No description provided for @frequencyBoth.
  ///
  /// In en, this message translates to:
  /// **'50 and 60 Hz'**
  String get frequencyBoth;

  /// No description provided for @tolerancePct.
  ///
  /// In en, this message translates to:
  /// **'Tolerance (%)'**
  String get tolerancePct;

  /// No description provided for @powerVoltageInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the voltage as a positive whole number.'**
  String get powerVoltageInvalid;

  /// No description provided for @powerToleranceInvalid.
  ///
  /// In en, this message translates to:
  /// **'The tolerance must be a whole number from 0 to 50.'**
  String get powerToleranceInvalid;

  /// No description provided for @powerSupplyDuplicate.
  ///
  /// In en, this message translates to:
  /// **'The same supply is listed twice.'**
  String get powerSupplyDuplicate;

  /// No description provided for @powerCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Grid compatibility check'**
  String get powerCheckTitle;

  /// No description provided for @powerCheckHelp.
  ///
  /// In en, this message translates to:
  /// **'Checks the saved supplies against the power grids of a country.'**
  String get powerCheckHelp;

  /// No description provided for @powerGrid.
  ///
  /// In en, this message translates to:
  /// **'Power grid'**
  String get powerGrid;

  /// No description provided for @powerAnyGrid.
  ///
  /// In en, this message translates to:
  /// **'Any grid in this country'**
  String get powerAnyGrid;

  /// No description provided for @powerCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get powerCheck;

  /// No description provided for @powerResultCompatible.
  ///
  /// In en, this message translates to:
  /// **'Compatible with the power grid of {country}.'**
  String powerResultCompatible(String country);

  /// No description provided for @powerResultIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Does not fit the grid of {country}. Supported: {supported}. Available there: {available}.'**
  String powerResultIncompatible(
    String country,
    String supported,
    String available,
  );

  /// No description provided for @powerResultExternal.
  ///
  /// In en, this message translates to:
  /// **'Runs on DC only and needs an external power supply; it is not checked against the grid.'**
  String get powerResultExternal;

  /// No description provided for @powerResultNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not an electrical product; there is nothing to check.'**
  String get powerResultNotApplicable;

  /// No description provided for @powerResultUnknown.
  ///
  /// In en, this message translates to:
  /// **'There is no grid data for {country}, so compatibility cannot be checked.'**
  String powerResultUnknown(String country);

  /// No description provided for @powerStatusCompatible.
  ///
  /// In en, this message translates to:
  /// **'Compatible'**
  String get powerStatusCompatible;

  /// No description provided for @powerStatusIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Incompatible'**
  String get powerStatusIncompatible;

  /// No description provided for @powerStatusExternal.
  ///
  /// In en, this message translates to:
  /// **'Needs external supply'**
  String get powerStatusExternal;

  /// No description provided for @powerStatusNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not applicable'**
  String get powerStatusNotApplicable;

  /// No description provided for @powerStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown grid'**
  String get powerStatusUnknown;

  /// No description provided for @relatedTab.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get relatedTab;

  /// No description provided for @relationRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get relationRules;

  /// No description provided for @relationSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get relationSuggestions;

  /// No description provided for @relationNoRules.
  ///
  /// In en, this message translates to:
  /// **'No rules apply to this product.'**
  String get relationNoRules;

  /// No description provided for @relationNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No suggestions yet.'**
  String get relationNoSuggestions;

  /// No description provided for @relationKindCompatible.
  ///
  /// In en, this message translates to:
  /// **'Compatible'**
  String get relationKindCompatible;

  /// No description provided for @relationKindIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Incompatible'**
  String get relationKindIncompatible;

  /// No description provided for @relationKindSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get relationKindSuggested;

  /// No description provided for @relationAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get relationAddRule;

  /// No description provided for @relationEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit relation'**
  String get relationEdit;

  /// No description provided for @relationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Product relations'**
  String get relationsTitle;

  /// No description provided for @newRelation.
  ///
  /// In en, this message translates to:
  /// **'New relation'**
  String get newRelation;

  /// No description provided for @relationKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get relationKindLabel;

  /// No description provided for @relationSideA.
  ///
  /// In en, this message translates to:
  /// **'First side'**
  String get relationSideA;

  /// No description provided for @relationSideB.
  ///
  /// In en, this message translates to:
  /// **'Second side'**
  String get relationSideB;

  /// No description provided for @relationBidirectional.
  ///
  /// In en, this message translates to:
  /// **'Applies in both directions'**
  String get relationBidirectional;

  /// No description provided for @relationStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength (1-100)'**
  String get relationStrength;

  /// No description provided for @relationStrengthHelp.
  ///
  /// In en, this message translates to:
  /// **'Only used by suggested rules.'**
  String get relationStrengthHelp;

  /// No description provided for @relationNeedSides.
  ///
  /// In en, this message translates to:
  /// **'Choose a product or a family on both sides.'**
  String get relationNeedSides;

  /// No description provided for @relationStrengthInvalid.
  ///
  /// In en, this message translates to:
  /// **'The strength must be a whole number from 1 to 100.'**
  String get relationStrengthInvalid;

  /// No description provided for @relationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No relations.'**
  String get relationsEmpty;

  /// No description provided for @relationFamilyValue.
  ///
  /// In en, this message translates to:
  /// **'Family {code}'**
  String relationFamilyValue(String code);

  /// No description provided for @suggestionReasonRule.
  ///
  /// In en, this message translates to:
  /// **'Rule'**
  String get suggestionReasonRule;

  /// No description provided for @suggestionReasonOften.
  ///
  /// In en, this message translates to:
  /// **'Often bought together'**
  String get suggestionReasonOften;

  /// No description provided for @suggestionStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength {n}'**
  String suggestionStrength(int n);

  /// No description provided for @suggestionConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence {pct} %'**
  String suggestionConfidence(int pct);

  /// No description provided for @suggestionBecause.
  ///
  /// In en, this message translates to:
  /// **'Because of {code}'**
  String suggestionBecause(String code);

  /// No description provided for @powerGridsTitle.
  ///
  /// In en, this message translates to:
  /// **'Power grids'**
  String get powerGridsTitle;

  /// No description provided for @newPowerGrid.
  ///
  /// In en, this message translates to:
  /// **'New power grid'**
  String get newPowerGrid;

  /// No description provided for @powerGridInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a two-letter country code, a voltage, 1 or 3 phases and 50 or 60 Hz.'**
  String get powerGridInvalid;

  /// No description provided for @warningKindPowerGrid.
  ///
  /// In en, this message translates to:
  /// **'Power grid'**
  String get warningKindPowerGrid;

  /// No description provided for @warningKindIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Incompatible products'**
  String get warningKindIncompatible;

  /// No description provided for @hintsPowerIncompatible.
  ///
  /// In en, this message translates to:
  /// **'{code} does not fit the power grid at the delivery site.'**
  String hintsPowerIncompatible(String code);

  /// No description provided for @hintsSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported: {value}'**
  String hintsSupported(String value);

  /// No description provided for @hintsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available: {value}'**
  String hintsAvailable(String value);

  /// No description provided for @hintsPowerExternal.
  ///
  /// In en, this message translates to:
  /// **'{code} runs on DC and needs an external power supply.'**
  String hintsPowerExternal(String code);

  /// No description provided for @hintsPowerUnknown.
  ///
  /// In en, this message translates to:
  /// **'No grid data for {country}, so {code} could not be checked. Add the country\'s grid under Power grids on the Products page.'**
  String hintsPowerUnknown(String country, String code);

  /// No description provided for @hintsIncompatibleProducts.
  ///
  /// In en, this message translates to:
  /// **'{a} and {b} are not compatible.'**
  String hintsIncompatibleProducts(String a, String b);

  /// No description provided for @suggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested additions'**
  String get suggestionsTitle;

  /// No description provided for @hintsTitle.
  ///
  /// In en, this message translates to:
  /// **'Warnings and suggestions'**
  String get hintsTitle;

  /// No description provided for @revisionShippingExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing shipping charge: {amount}'**
  String revisionShippingExisting(String amount);

  /// No description provided for @revisionShippingReset.
  ///
  /// In en, this message translates to:
  /// **'With current prices, this shipping charge will be reset. A new shipping quote from logistics is needed before the revised quotation can be sent.'**
  String get revisionShippingReset;

  /// No description provided for @revisionShippingKept.
  ///
  /// In en, this message translates to:
  /// **'With agreed prices, the quoted shipping is carried over to the revised quotation (current charge: {amount}).'**
  String revisionShippingKept(String amount);

  /// No description provided for @packagesReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get packagesReceiving;

  /// No description provided for @packagesIntake.
  ///
  /// In en, this message translates to:
  /// **'Repair intake'**
  String get packagesIntake;

  /// No description provided for @registerParcel.
  ///
  /// In en, this message translates to:
  /// **'Register parcel'**
  String get registerParcel;

  /// No description provided for @registeredParcels.
  ///
  /// In en, this message translates to:
  /// **'Registered parcels'**
  String get registeredParcels;

  /// No description provided for @noParcels.
  ///
  /// In en, this message translates to:
  /// **'No parcels.'**
  String get noParcels;

  /// No description provided for @sender.
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get sender;

  /// No description provided for @trackingNumber.
  ///
  /// In en, this message translates to:
  /// **'Tracking number'**
  String get trackingNumber;

  /// No description provided for @parcelCount.
  ///
  /// In en, this message translates to:
  /// **'Number of parcels'**
  String get parcelCount;

  /// No description provided for @packageCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition of the box'**
  String get packageCondition;

  /// No description provided for @conditionIntact.
  ///
  /// In en, this message translates to:
  /// **'Intact'**
  String get conditionIntact;

  /// No description provided for @conditionDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get conditionDamaged;

  /// No description provided for @conditionOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get conditionOpened;

  /// No description provided for @conditionWet.
  ///
  /// In en, this message translates to:
  /// **'Wet'**
  String get conditionWet;

  /// No description provided for @conditionNote.
  ///
  /// In en, this message translates to:
  /// **'Note on the condition'**
  String get conditionNote;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @parcelRegistered.
  ///
  /// In en, this message translates to:
  /// **'Parcel {number} registered'**
  String parcelRegistered(String number);

  /// No description provided for @pkgStatusRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get pkgStatusRegistered;

  /// No description provided for @pkgStatusOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get pkgStatusOpened;

  /// No description provided for @pkgStatusLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked to a repair'**
  String get pkgStatusLinked;

  /// No description provided for @pkgStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get pkgStatusClosed;

  /// No description provided for @packageKindRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get packageKindRepair;

  /// No description provided for @packageKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other (no repair)'**
  String get packageKindOther;

  /// No description provided for @packageKindReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to sender'**
  String get packageKindReturn;

  /// No description provided for @toOpen.
  ///
  /// In en, this message translates to:
  /// **'To open'**
  String get toOpen;

  /// No description provided for @toProcess.
  ///
  /// In en, this message translates to:
  /// **'To process'**
  String get toProcess;

  /// No description provided for @toRoute.
  ///
  /// In en, this message translates to:
  /// **'To route'**
  String get toRoute;

  /// No description provided for @nothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do here.'**
  String get nothingHere;

  /// No description provided for @openParcel.
  ///
  /// In en, this message translates to:
  /// **'Open parcel'**
  String get openParcel;

  /// No description provided for @parcelContents.
  ///
  /// In en, this message translates to:
  /// **'What is in the parcel?'**
  String get parcelContents;

  /// No description provided for @closeParcel.
  ///
  /// In en, this message translates to:
  /// **'Close parcel'**
  String get closeParcel;

  /// No description provided for @noteRequired.
  ///
  /// In en, this message translates to:
  /// **'A note is required.'**
  String get noteRequired;

  /// No description provided for @linkToRepair.
  ///
  /// In en, this message translates to:
  /// **'Match with a repair'**
  String get linkToRepair;

  /// No description provided for @repairSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggested repairs'**
  String get repairSuggestions;

  /// No description provided for @noSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No announced repair matches.'**
  String get noSuggestions;

  /// No description provided for @suggestedCustomer.
  ///
  /// In en, this message translates to:
  /// **'Suggested customer: {name}'**
  String suggestedCustomer(String name);

  /// No description provided for @suggestionScore.
  ///
  /// In en, this message translates to:
  /// **'Score {score}'**
  String suggestionScore(String score);

  /// No description provided for @reasonSerial.
  ///
  /// In en, this message translates to:
  /// **'Same serial number'**
  String get reasonSerial;

  /// No description provided for @reasonCustomer.
  ///
  /// In en, this message translates to:
  /// **'Same customer'**
  String get reasonCustomer;

  /// No description provided for @reasonReference.
  ///
  /// In en, this message translates to:
  /// **'Same reference'**
  String get reasonReference;

  /// No description provided for @reasonTicket.
  ///
  /// In en, this message translates to:
  /// **'Same ticket'**
  String get reasonTicket;

  /// No description provided for @reasonProduct.
  ///
  /// In en, this message translates to:
  /// **'Similar product'**
  String get reasonProduct;

  /// No description provided for @reasonRecent.
  ///
  /// In en, this message translates to:
  /// **'Announced recently'**
  String get reasonRecent;

  /// No description provided for @confirmLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm match'**
  String get confirmLinkTitle;

  /// No description provided for @confirmLinkBody.
  ///
  /// In en, this message translates to:
  /// **'Parcel {parcel} contains repair {repair}. An announced repair will be marked as received.'**
  String confirmLinkBody(String parcel, String repair);

  /// No description provided for @customerMismatchWarning.
  ///
  /// In en, this message translates to:
  /// **'The customer of the parcel is not the customer of the repair.'**
  String get customerMismatchWarning;

  /// No description provided for @confirmCustomerMismatch.
  ///
  /// In en, this message translates to:
  /// **'Yes, it was sent by someone else (for example a colleague)'**
  String get confirmCustomerMismatch;

  /// No description provided for @confirmLink.
  ///
  /// In en, this message translates to:
  /// **'Confirm and link'**
  String get confirmLink;

  /// No description provided for @linkConflict.
  ///
  /// In en, this message translates to:
  /// **'The repair has changed in the meantime. The list was refreshed; check it and try again.'**
  String get linkConflict;

  /// No description provided for @createNewRepair.
  ///
  /// In en, this message translates to:
  /// **'Create new repair'**
  String get createNewRepair;

  /// No description provided for @parcelsSection.
  ///
  /// In en, this message translates to:
  /// **'Parcels'**
  String get parcelsSection;

  /// No description provided for @noParcelsLinked.
  ///
  /// In en, this message translates to:
  /// **'No parcel linked.'**
  String get noParcelsLinked;

  /// No description provided for @unlinkParcel.
  ///
  /// In en, this message translates to:
  /// **'Unlink parcel'**
  String get unlinkParcel;

  /// No description provided for @parcelsToLink.
  ///
  /// In en, this message translates to:
  /// **'Parcels waiting for this repair'**
  String get parcelsToLink;

  /// No description provided for @linkParcel.
  ///
  /// In en, this message translates to:
  /// **'Link parcel'**
  String get linkParcel;

  /// No description provided for @parcelLinked.
  ///
  /// In en, this message translates to:
  /// **'Parcel linked'**
  String get parcelLinked;

  /// No description provided for @parcelUnlinked.
  ///
  /// In en, this message translates to:
  /// **'Parcel unlinked'**
  String get parcelUnlinked;

  /// No description provided for @customerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Customer not known'**
  String get customerUnknown;

  /// No description provided for @findingsSection.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get findingsSection;

  /// No description provided for @findingsLabel.
  ///
  /// In en, this message translates to:
  /// **'What was found'**
  String get findingsLabel;

  /// No description provided for @diagnosisLabel.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis'**
  String get diagnosisLabel;

  /// No description provided for @saveFindings.
  ///
  /// In en, this message translates to:
  /// **'Save findings'**
  String get saveFindings;

  /// No description provided for @warrantySection.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get warrantySection;

  /// No description provided for @warrantyVoid.
  ///
  /// In en, this message translates to:
  /// **'Void (misuse)'**
  String get warrantyVoid;

  /// No description provided for @warrantyAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic result'**
  String get warrantyAutomatic;

  /// No description provided for @warrantyComparedWith.
  ///
  /// In en, this message translates to:
  /// **'Compared with the arrival date {date}'**
  String warrantyComparedWith(String date);

  /// No description provided for @warrantyProvisional.
  ///
  /// In en, this message translates to:
  /// **'Not received yet: compared with today, so provisional.'**
  String get warrantyProvisional;

  /// No description provided for @serialUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Serial unit: {unit}'**
  String serialUnitLabel(String unit);

  /// No description provided for @noSerialUnit.
  ///
  /// In en, this message translates to:
  /// **'No serial unit linked'**
  String get noSerialUnit;

  /// No description provided for @linkSerialUnit.
  ///
  /// In en, this message translates to:
  /// **'Link serial unit'**
  String get linkSerialUnit;

  /// No description provided for @unlinkSerialUnit.
  ///
  /// In en, this message translates to:
  /// **'Unlink serial unit'**
  String get unlinkSerialUnit;

  /// No description provided for @serialUnitSeveral.
  ///
  /// In en, this message translates to:
  /// **'Several serial units match. Pick the right one.'**
  String get serialUnitSeveral;

  /// No description provided for @serialUnitNoResults.
  ///
  /// In en, this message translates to:
  /// **'No serial units found'**
  String get serialUnitNoResults;

  /// No description provided for @recheckWarranty.
  ///
  /// In en, this message translates to:
  /// **'Check warranty again'**
  String get recheckWarranty;

  /// No description provided for @markWarrantyVoid.
  ///
  /// In en, this message translates to:
  /// **'Mark warranty void (misuse)'**
  String get markWarrantyVoid;

  /// No description provided for @removeWarrantyOverride.
  ///
  /// In en, this message translates to:
  /// **'Remove override'**
  String get removeWarrantyOverride;

  /// No description provided for @warrantyVoidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark warranty void'**
  String get warrantyVoidTitle;

  /// No description provided for @warrantyRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the void override'**
  String get warrantyRemoveTitle;

  /// No description provided for @warrantyReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get warrantyReasonLabel;

  /// No description provided for @warrantyOverriddenBy.
  ///
  /// In en, this message translates to:
  /// **'Overridden to void by {name} on {date}: {reason}'**
  String warrantyOverriddenBy(String name, String date, String reason);

  /// No description provided for @eventFindings.
  ///
  /// In en, this message translates to:
  /// **'Findings updated'**
  String get eventFindings;

  /// No description provided for @eventSerialUnit.
  ///
  /// In en, this message translates to:
  /// **'Serial unit'**
  String get eventSerialUnit;

  /// No description provided for @eventWarrantyAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic warranty'**
  String get eventWarrantyAuto;

  /// No description provided for @eventWarrantyManual.
  ///
  /// In en, this message translates to:
  /// **'Warranty set by hand'**
  String get eventWarrantyManual;

  /// No description provided for @eventWarrantyVoid.
  ///
  /// In en, this message translates to:
  /// **'Warranty void'**
  String get eventWarrantyVoid;

  /// No description provided for @eventWarrantyVoidRemoved.
  ///
  /// In en, this message translates to:
  /// **'Warranty override removed'**
  String get eventWarrantyVoidRemoved;

  /// No description provided for @csvMenu.
  ///
  /// In en, this message translates to:
  /// **'Import and export'**
  String get csvMenu;

  /// No description provided for @csvImport.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get csvImport;

  /// No description provided for @csvExported.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String csvExported(String name);

  /// No description provided for @csvExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String csvExportFailed(String error);

  /// No description provided for @csvImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import: {entity}'**
  String csvImportTitle(String entity);

  /// No description provided for @csvImportHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a CSV, Excel (XLSX) or OpenDocument (ODS) file. Rows are matched on the code: an existing code is updated, a new code is created. Columns that are missing from the file are left untouched, and nothing is ever deleted. It is all or nothing: if any row has an error, nothing is imported. CSV: semicolon or comma separated, UTF-8. Spreadsheets: the first sheet is read; to pick another sheet or map differently named columns, use Administration, Import.'**
  String get csvImportHelp;

  /// No description provided for @csvChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get csvChooseFile;

  /// No description provided for @csvChooseOther.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get csvChooseOther;

  /// No description provided for @csvChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the file...'**
  String get csvChecking;

  /// No description provided for @csvImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get csvImporting;

  /// No description provided for @csvPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview: nothing has been imported yet'**
  String get csvPreview;

  /// No description provided for @csvDone.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get csvDone;

  /// No description provided for @csvToCreate.
  ///
  /// In en, this message translates to:
  /// **'To create'**
  String get csvToCreate;

  /// No description provided for @csvToUpdate.
  ///
  /// In en, this message translates to:
  /// **'To update'**
  String get csvToUpdate;

  /// No description provided for @csvUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get csvUnchanged;

  /// No description provided for @csvCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get csvCreated;

  /// No description provided for @csvUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get csvUpdated;

  /// No description provided for @csvImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get csvImportAction;

  /// No description provided for @csvEmptyFile.
  ///
  /// In en, this message translates to:
  /// **'The file is empty.'**
  String get csvEmptyFile;

  /// No description provided for @csvReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read.'**
  String get csvReadFailed;

  /// No description provided for @csvErrorsFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 problem found} other{{count} problems found}}. Nothing has been imported.'**
  String csvErrorsFound(int count);

  /// No description provided for @csvErrorRow.
  ///
  /// In en, this message translates to:
  /// **'Row {row}'**
  String csvErrorRow(int row);

  /// No description provided for @csvErrorRowColumn.
  ///
  /// In en, this message translates to:
  /// **'Row {row}, column {column}'**
  String csvErrorRowColumn(int row, String column);

  /// No description provided for @csvAndMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String csvAndMore(int count);

  /// No description provided for @profileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Profile: {name}'**
  String profileTooltip(String name);

  /// No description provided for @tabTicket.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get tabTicket;

  /// No description provided for @tabQuotation.
  ///
  /// In en, this message translates to:
  /// **'Quotation'**
  String get tabQuotation;

  /// No description provided for @tabNewQuotation.
  ///
  /// In en, this message translates to:
  /// **'New quotation'**
  String get tabNewQuotation;

  /// No description provided for @tabOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get tabOrder;

  /// No description provided for @tabRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get tabRepair;

  /// No description provided for @tabJob.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get tabJob;

  /// No description provided for @tabProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get tabProduct;

  /// No description provided for @tabOpportunity.
  ///
  /// In en, this message translates to:
  /// **'Opportunity'**
  String get tabOpportunity;

  /// No description provided for @tabStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get tabStock;

  /// No description provided for @tabArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get tabArticle;

  /// No description provided for @tabContract.
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get tabContract;

  /// No description provided for @tabCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get tabCount;

  /// No description provided for @workspaceOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get workspaceOverview;

  /// No description provided for @openTabs.
  ///
  /// In en, this message translates to:
  /// **'Open tabs'**
  String get openTabs;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTab;

  /// No description provided for @openInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get openInNewTab;

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesBody.
  ///
  /// In en, this message translates to:
  /// **'This tab has unsaved changes. Close it and discard them?'**
  String get unsavedChangesBody;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// No description provided for @remarkProduction.
  ///
  /// In en, this message translates to:
  /// **'Production remark'**
  String get remarkProduction;

  /// No description provided for @remarkProductionHelp.
  ///
  /// In en, this message translates to:
  /// **'Internal, never shown to the customer'**
  String get remarkProductionHelp;

  /// No description provided for @remarkCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer remark'**
  String get remarkCustomer;

  /// No description provided for @remarkCustomerHelp.
  ///
  /// In en, this message translates to:
  /// **'Printed on the quotation and the order confirmation'**
  String get remarkCustomerHelp;

  /// No description provided for @remarkHistory.
  ///
  /// In en, this message translates to:
  /// **'Earlier remarks'**
  String get remarkHistory;

  /// No description provided for @remarkHistoryThisCustomer.
  ///
  /// In en, this message translates to:
  /// **'This customer'**
  String get remarkHistoryThisCustomer;

  /// No description provided for @remarkHistoryThisLanguage.
  ///
  /// In en, this message translates to:
  /// **'This language'**
  String get remarkHistoryThisLanguage;

  /// No description provided for @remarkHistoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get remarkHistoryAll;

  /// No description provided for @remarkHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No earlier remarks for this product.'**
  String get remarkHistoryEmpty;

  /// No description provided for @remarkHistoryUsed.
  ///
  /// In en, this message translates to:
  /// **'Used {count} times, last on {quotation}'**
  String remarkHistoryUsed(int count, String quotation);

  /// No description provided for @defaultProductionRemark.
  ///
  /// In en, this message translates to:
  /// **'Default production remark'**
  String get defaultProductionRemark;

  /// No description provided for @optionsTab.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get optionsTab;

  /// No description provided for @optionsIntro.
  ///
  /// In en, this message translates to:
  /// **'Products offered together with this one on a quotation. A required option is added automatically.'**
  String get optionsIntro;

  /// No description provided for @optionsNone.
  ///
  /// In en, this message translates to:
  /// **'This product has no options.'**
  String get optionsNone;

  /// No description provided for @optionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get optionAdd;

  /// No description provided for @optionRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get optionRequired;

  /// No description provided for @optionQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity per unit'**
  String get optionQuantity;

  /// No description provided for @optionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get optionRemove;

  /// No description provided for @optionsSaved.
  ///
  /// In en, this message translates to:
  /// **'Options saved.'**
  String get optionsSaved;

  /// No description provided for @optionsInvalidQuantity.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity greater than 0 for every option.'**
  String get optionsInvalidQuantity;

  /// No description provided for @optionsChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Options for {product}'**
  String optionsChooseTitle(String product);

  /// No description provided for @optionsChooseHelp.
  ///
  /// In en, this message translates to:
  /// **'Required options are added automatically. Tick the optional ones to add.'**
  String get optionsChooseHelp;

  /// No description provided for @optionsAddSelected.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get optionsAddSelected;

  /// No description provided for @optionsSkip.
  ///
  /// In en, this message translates to:
  /// **'Without optional options'**
  String get optionsSkip;

  /// No description provided for @optionLine.
  ///
  /// In en, this message translates to:
  /// **'Option of the line above'**
  String get optionLine;

  /// No description provided for @configurator.
  ///
  /// In en, this message translates to:
  /// **'Configurator'**
  String get configurator;

  /// No description provided for @configurators.
  ///
  /// In en, this message translates to:
  /// **'Configurators'**
  String get configurators;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @newConfiguration.
  ///
  /// In en, this message translates to:
  /// **'New configuration'**
  String get newConfiguration;

  /// No description provided for @savedConfigurations.
  ///
  /// In en, this message translates to:
  /// **'Saved configurations'**
  String get savedConfigurations;

  /// No description provided for @cfgAddRow.
  ///
  /// In en, this message translates to:
  /// **'Add {item}'**
  String cfgAddRow(String item);

  /// No description provided for @cfgAddRowToGroup.
  ///
  /// In en, this message translates to:
  /// **'Add a row to {group}'**
  String cfgAddRowToGroup(String group);

  /// No description provided for @cfgCalculated.
  ///
  /// In en, this message translates to:
  /// **'Calculated'**
  String get cfgCalculated;

  /// No description provided for @cfgChangeCustomer.
  ///
  /// In en, this message translates to:
  /// **'Other customer'**
  String get cfgChangeCustomer;

  /// No description provided for @cfgCreateQuotation.
  ///
  /// In en, this message translates to:
  /// **'Create quotation'**
  String get cfgCreateQuotation;

  /// No description provided for @cfgUpdateQuotation.
  ///
  /// In en, this message translates to:
  /// **'Update quotation'**
  String get cfgUpdateQuotation;

  /// No description provided for @cfgDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this configuration? Quotations made from it stay.'**
  String get cfgDeleteConfirm;

  /// No description provided for @cfgDeleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete row'**
  String get cfgDeleteRow;

  /// No description provided for @cfgDuplicateRow.
  ///
  /// In en, this message translates to:
  /// **'Duplicate row'**
  String get cfgDuplicateRow;

  /// No description provided for @cfgDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get cfgDiscard;

  /// No description provided for @cfgDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard the unsaved changes?'**
  String get cfgDiscardChanges;

  /// No description provided for @cfgEach.
  ///
  /// In en, this message translates to:
  /// **'For each: {value}'**
  String cfgEach(String value);

  /// No description provided for @cfgErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get cfgErrors;

  /// No description provided for @cfgWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get cfgWarnings;

  /// No description provided for @cfgInfo.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get cfgInfo;

  /// No description provided for @cfgEvalFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not recalculate: {message}'**
  String cfgEvalFailed(String message);

  /// No description provided for @cfgInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get cfgInput;

  /// No description provided for @cfgIssues.
  ///
  /// In en, this message translates to:
  /// **'Issues'**
  String get cfgIssues;

  /// No description provided for @cfgLines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get cfgLines;

  /// No description provided for @cfgWhy.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get cfgWhy;

  /// No description provided for @cfgInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Not a valid number'**
  String get cfgInvalidNumber;

  /// No description provided for @cfgNewerRevision.
  ///
  /// In en, this message translates to:
  /// **'A newer revision of this configurator is available.'**
  String get cfgNewerRevision;

  /// No description provided for @cfgUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get cfgUpgrade;

  /// No description provided for @cfgNoConfigurations.
  ///
  /// In en, this message translates to:
  /// **'No saved configurations yet.'**
  String get cfgNoConfigurations;

  /// No description provided for @cfgNoModels.
  ///
  /// In en, this message translates to:
  /// **'No configurator is active yet.'**
  String get cfgNoModels;

  /// No description provided for @cfgNoCustomer.
  ///
  /// In en, this message translates to:
  /// **'No customer'**
  String get cfgNoCustomer;

  /// No description provided for @cfgNoIssues.
  ///
  /// In en, this message translates to:
  /// **'No issues.'**
  String get cfgNoIssues;

  /// No description provided for @cfgNoLines.
  ///
  /// In en, this message translates to:
  /// **'The configuration produces no lines yet.'**
  String get cfgNoLines;

  /// No description provided for @cfgNotInCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Not in the product catalogue'**
  String get cfgNotInCatalogue;

  /// No description provided for @cfgPinned.
  ///
  /// In en, this message translates to:
  /// **'Your own value (pinned)'**
  String get cfgPinned;

  /// No description provided for @cfgPricesNeedCustomer.
  ///
  /// In en, this message translates to:
  /// **'Choose a customer to see prices.'**
  String get cfgPricesNeedCustomer;

  /// No description provided for @cfgQuoteBlocked.
  ///
  /// In en, this message translates to:
  /// **'Fix the errors before making a quotation.'**
  String get cfgQuoteBlocked;

  /// No description provided for @cfgQuoteNeedsCustomer.
  ///
  /// In en, this message translates to:
  /// **'Choose a customer before making a quotation.'**
  String get cfgQuoteNeedsCustomer;

  /// No description provided for @cfgQuoteCreated.
  ///
  /// In en, this message translates to:
  /// **'Quotation {number} created.'**
  String cfgQuoteCreated(String number);

  /// No description provided for @cfgQuoteUpdated.
  ///
  /// In en, this message translates to:
  /// **'Quotation {number} updated.'**
  String cfgQuoteUpdated(String number);

  /// No description provided for @cfgQuoteRevised.
  ///
  /// In en, this message translates to:
  /// **'Quotation {number}: a new revision was created.'**
  String cfgQuoteRevised(String number);

  /// No description provided for @cfgResetToCalculated.
  ///
  /// In en, this message translates to:
  /// **'Reset to calculated ({value})'**
  String cfgResetToCalculated(String value);

  /// No description provided for @cfgStale.
  ///
  /// In en, this message translates to:
  /// **'The calculation now gives {value}'**
  String cfgStale(String value);

  /// No description provided for @cfgRevision.
  ///
  /// In en, this message translates to:
  /// **'revision {revision}'**
  String cfgRevision(int revision);

  /// No description provided for @cfgRule.
  ///
  /// In en, this message translates to:
  /// **'Rule: {rule}'**
  String cfgRule(String rule);

  /// No description provided for @cfgSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get cfgSaved;

  /// No description provided for @cfgSelectLine.
  ///
  /// In en, this message translates to:
  /// **'Select a line to see where it comes from.'**
  String get cfgSelectLine;

  /// No description provided for @cfgSetForAll.
  ///
  /// In en, this message translates to:
  /// **'Set for all rows…'**
  String get cfgSetForAll;

  /// No description provided for @cfgSetForAllTitle.
  ///
  /// In en, this message translates to:
  /// **'{column} for all rows'**
  String cfgSetForAllTitle(String column);

  /// No description provided for @cfgStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get cfgStart;

  /// No description provided for @cfgUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get cfgUnsaved;

  /// No description provided for @cfgNewerRevisionAvailable.
  ///
  /// In en, this message translates to:
  /// **'revision {revision} available'**
  String cfgNewerRevisionAvailable(int revision);

  /// No description provided for @cfgbActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get cfgbActivate;

  /// No description provided for @cfgbActivateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Activate this draft? Sales will use it for new configurations; the current active revision becomes obsolete.'**
  String get cfgbActivateConfirm;

  /// No description provided for @cfgbActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated.'**
  String get cfgbActivated;

  /// No description provided for @cfgbActivatedOn.
  ///
  /// In en, this message translates to:
  /// **'activated {date}'**
  String cfgbActivatedOn(String date);

  /// No description provided for @cfgbActivateModel.
  ///
  /// In en, this message translates to:
  /// **'Make available'**
  String get cfgbActivateModel;

  /// No description provided for @cfgbActivateRefused.
  ///
  /// In en, this message translates to:
  /// **'Not activated: {count, plural, =1{1 problem} other{{count} problems}} to solve.'**
  String cfgbActivateRefused(int count);

  /// No description provided for @cfgbActiveRevision.
  ///
  /// In en, this message translates to:
  /// **'active: revision {revision}'**
  String cfgbActiveRevision(int revision);

  /// No description provided for @cfgbAddChild.
  ///
  /// In en, this message translates to:
  /// **'Add option line'**
  String get cfgbAddChild;

  /// No description provided for @cfgbAddColumn.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get cfgbAddColumn;

  /// No description provided for @cfgbAddComputed.
  ///
  /// In en, this message translates to:
  /// **'Add computed value'**
  String get cfgbAddComputed;

  /// No description provided for @cfgbAddField.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get cfgbAddField;

  /// No description provided for @cfgbAddItemTable.
  ///
  /// In en, this message translates to:
  /// **'Add item table'**
  String get cfgbAddItemTable;

  /// No description provided for @cfgbAddOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get cfgbAddOption;

  /// No description provided for @cfgbAddRow.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get cfgbAddRow;

  /// No description provided for @cfgbAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add output rule'**
  String get cfgbAddRule;

  /// No description provided for @cfgbAddSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get cfgbAddSection;

  /// No description provided for @cfgbAddTable.
  ///
  /// In en, this message translates to:
  /// **'Add table'**
  String get cfgbAddTable;

  /// No description provided for @cfgbAddValidation.
  ///
  /// In en, this message translates to:
  /// **'Add check'**
  String get cfgbAddValidation;

  /// No description provided for @cfgbApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get cfgbApply;

  /// No description provided for @cfgbChildRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Option line {id}'**
  String cfgbChildRuleTitle(String id);

  /// No description provided for @cfgbCode.
  ///
  /// In en, this message translates to:
  /// **'Product code (formula)'**
  String get cfgbCode;

  /// No description provided for @cfgbCodeExpr.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get cfgbCodeExpr;

  /// No description provided for @cfgbCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'e.g. \'BELT-M\' or motor_code'**
  String get cfgbCodeHelp;

  /// No description provided for @cfgbCodeTemplate.
  ///
  /// In en, this message translates to:
  /// **'Product code (template)'**
  String get cfgbCodeTemplate;

  /// No description provided for @cfgbCodeTemplateHelp.
  ///
  /// In en, this message translates to:
  /// **'Text with formulas in curly brackets, e.g. DRV- then motor_size in brackets'**
  String get cfgbCodeTemplateHelp;

  /// No description provided for @cfgbColumn.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get cfgbColumn;

  /// No description provided for @cfgbColumnName.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get cfgbColumnName;

  /// No description provided for @cfgbCommentTemplate.
  ///
  /// In en, this message translates to:
  /// **'Comment (template)'**
  String get cfgbCommentTemplate;

  /// No description provided for @cfgbComputedOf.
  ///
  /// In en, this message translates to:
  /// **'Computed values: {scope}'**
  String cfgbComputedOf(String scope);

  /// No description provided for @cfgbComputedTitle.
  ///
  /// In en, this message translates to:
  /// **'Computed value {name}'**
  String cfgbComputedTitle(String name);

  /// No description provided for @cfgbConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get cfgbConditions;

  /// No description provided for @cfgbCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get cfgbCreate;

  /// No description provided for @cfgbCsvExport.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get cfgbCsvExport;

  /// No description provided for @cfgbCsvImport.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get cfgbCsvImport;

  /// No description provided for @cfgbCsvImported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row imported.} other{{count} rows imported.}}'**
  String cfgbCsvImported(int count);

  /// No description provided for @cfgbCsvProblems.
  ///
  /// In en, this message translates to:
  /// **'The CSV file was not imported'**
  String get cfgbCsvProblems;

  /// No description provided for @cfgbDeactivateModel.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get cfgbDeactivateModel;

  /// No description provided for @cfgbDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get cfgbDefault;

  /// No description provided for @cfgbDefaultExpr.
  ///
  /// In en, this message translates to:
  /// **'Default (formula)'**
  String get cfgbDefaultExpr;

  /// No description provided for @cfgbDefaultExprHelp.
  ///
  /// In en, this message translates to:
  /// **'Instead of a fixed default'**
  String get cfgbDefaultExprHelp;

  /// No description provided for @cfgbDescriptionTemplate.
  ///
  /// In en, this message translates to:
  /// **'Description (template)'**
  String get cfgbDescriptionTemplate;

  /// No description provided for @cfgbDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'Design configurators'**
  String get cfgbDesignTitle;

  /// No description provided for @cfgbDimCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get cfgbDimCurrent;

  /// No description provided for @cfgbDimension.
  ///
  /// In en, this message translates to:
  /// **'Dimension'**
  String get cfgbDimension;

  /// No description provided for @cfgbDimLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get cfgbDimLength;

  /// No description provided for @cfgbDimMass.
  ///
  /// In en, this message translates to:
  /// **'Mass'**
  String get cfgbDimMass;

  /// No description provided for @cfgbDimPower.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get cfgbDimPower;

  /// No description provided for @cfgbDimSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get cfgbDimSpeed;

  /// No description provided for @cfgbDimVoltage.
  ///
  /// In en, this message translates to:
  /// **'Voltage'**
  String get cfgbDimVoltage;

  /// No description provided for @cfgbDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get cfgbDiscard;

  /// No description provided for @cfgbDisplayUnits.
  ///
  /// In en, this message translates to:
  /// **'Display units:'**
  String get cfgbDisplayUnits;

  /// No description provided for @cfgbDraftRevision.
  ///
  /// In en, this message translates to:
  /// **'draft: revision {revision}'**
  String cfgbDraftRevision(int revision);

  /// No description provided for @cfgbEditDraft.
  ///
  /// In en, this message translates to:
  /// **'Edit draft'**
  String get cfgbEditDraft;

  /// No description provided for @cfgbEnabledIf.
  ///
  /// In en, this message translates to:
  /// **'Enabled when'**
  String get cfgbEnabledIf;

  /// No description provided for @cfgbExported.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}.'**
  String cfgbExported(String name);

  /// No description provided for @cfgbExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get cfgbExportJson;

  /// No description provided for @cfgbExpr.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get cfgbExpr;

  /// No description provided for @cfgbFamily.
  ///
  /// In en, this message translates to:
  /// **'Product family (code)'**
  String get cfgbFamily;

  /// No description provided for @cfgbFieldsOf.
  ///
  /// In en, this message translates to:
  /// **'Fields: {scope}'**
  String cfgbFieldsOf(String scope);

  /// No description provided for @cfgbFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Field {name}'**
  String cfgbFieldTitle(String name);

  /// No description provided for @cfgbForEach.
  ///
  /// In en, this message translates to:
  /// **'For each'**
  String get cfgbForEach;

  /// No description provided for @cfgbForEachHelp.
  ///
  /// In en, this message translates to:
  /// **'A list: one line per element, with each and each_index'**
  String get cfgbForEachHelp;

  /// No description provided for @cfgbFormulaType.
  ///
  /// In en, this message translates to:
  /// **'Result: {type}'**
  String cfgbFormulaType(String type);

  /// No description provided for @cfgbGroupField.
  ///
  /// In en, this message translates to:
  /// **'Group by field'**
  String get cfgbGroupField;

  /// No description provided for @cfgbGroupHelp.
  ///
  /// In en, this message translates to:
  /// **'A group is one section of rows (e.g. a hall): one per distinct value of an item table\'s group field. Group fields with the name of a project field override it within the group.'**
  String get cfgbGroupHelp;

  /// No description provided for @cfgbGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Name of a group'**
  String get cfgbGroupLabel;

  /// No description provided for @cfgbHelp.
  ///
  /// In en, this message translates to:
  /// **'Help text'**
  String get cfgbHelp;

  /// No description provided for @cfgbId.
  ///
  /// In en, this message translates to:
  /// **'Id'**
  String get cfgbId;

  /// No description provided for @cfgbImported.
  ///
  /// In en, this message translates to:
  /// **'Imported into the editor; save to keep it.'**
  String get cfgbImported;

  /// No description provided for @cfgbImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Not imported: {message}'**
  String cfgbImportFailed(String message);

  /// No description provided for @cfgbImportJson.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get cfgbImportJson;

  /// No description provided for @cfgbImportNotExport.
  ///
  /// In en, this message translates to:
  /// **'This file is not a configurator export.'**
  String get cfgbImportNotExport;

  /// No description provided for @cfgbImportReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace the whole definition of this draft by {name}?'**
  String cfgbImportReplace(String name);

  /// No description provided for @cfgbInactive.
  ///
  /// In en, this message translates to:
  /// **'not available to sales'**
  String get cfgbInactive;

  /// No description provided for @cfgbItemLabel.
  ///
  /// In en, this message translates to:
  /// **'Item label (template)'**
  String get cfgbItemLabel;

  /// No description provided for @cfgbItemLabelHelp.
  ///
  /// In en, this message translates to:
  /// **'Names one row in comments and messages; formulas in curly brackets, e.g. group_name and index'**
  String get cfgbItemLabelHelp;

  /// No description provided for @cfgbItemTable.
  ///
  /// In en, this message translates to:
  /// **'Item table'**
  String get cfgbItemTable;

  /// No description provided for @cfgbKeys.
  ///
  /// In en, this message translates to:
  /// **'Key columns:'**
  String get cfgbKeys;

  /// No description provided for @cfgbKindExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get cfgbKindExact;

  /// No description provided for @cfgbKindRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get cfgbKindRange;

  /// No description provided for @cfgbLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get cfgbLabel;

  /// No description provided for @cfgbLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get cfgbLayout;

  /// No description provided for @cfgbLayoutSections.
  ///
  /// In en, this message translates to:
  /// **'Form sections'**
  String get cfgbLayoutSections;

  /// No description provided for @cfgbLayoutSectionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Fields name a section in their layout; the form shows them under its heading.'**
  String get cfgbLayoutSectionsHelp;

  /// No description provided for @cfgbMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get cfgbMax;

  /// No description provided for @cfgbMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Maximum length'**
  String get cfgbMaxLength;

  /// No description provided for @cfgbMaxRows.
  ///
  /// In en, this message translates to:
  /// **'Maximum rows'**
  String get cfgbMaxRows;

  /// No description provided for @cfgbMergeIdentical.
  ///
  /// In en, this message translates to:
  /// **'Merge identical lines'**
  String get cfgbMergeIdentical;

  /// No description provided for @cfgbMergeIdenticalHelp.
  ///
  /// In en, this message translates to:
  /// **'Lines with the same code become one; the comment lists the items'**
  String get cfgbMergeIdenticalHelp;

  /// No description provided for @cfgbMessage.
  ///
  /// In en, this message translates to:
  /// **'Message (template)'**
  String get cfgbMessage;

  /// No description provided for @cfgbMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get cfgbMin;

  /// No description provided for @cfgbMinRows.
  ///
  /// In en, this message translates to:
  /// **'Minimum rows'**
  String get cfgbMinRows;

  /// No description provided for @cfgbMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get cfgbMoveDown;

  /// No description provided for @cfgbMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get cfgbMoveUp;

  /// No description provided for @cfgbNewDraft.
  ///
  /// In en, this message translates to:
  /// **'New draft from the active revision'**
  String get cfgbNewDraft;

  /// No description provided for @cfgbNewDraftFromThis.
  ///
  /// In en, this message translates to:
  /// **'New draft from this revision'**
  String get cfgbNewDraftFromThis;

  /// No description provided for @cfgbNewModel.
  ///
  /// In en, this message translates to:
  /// **'New configurator'**
  String get cfgbNewModel;

  /// No description provided for @cfgbNoProblems.
  ///
  /// In en, this message translates to:
  /// **'No problems'**
  String get cfgbNoProblems;

  /// No description provided for @cfgbOnMissing.
  ///
  /// In en, this message translates to:
  /// **'When no row fits'**
  String get cfgbOnMissing;

  /// No description provided for @cfgbOnMissingClamp.
  ///
  /// In en, this message translates to:
  /// **'Next higher row'**
  String get cfgbOnMissingClamp;

  /// No description provided for @cfgbOnMissingHelp.
  ///
  /// In en, this message translates to:
  /// **'Next higher row: a value below or between the ranges takes the row with the next higher range, a value above all ranges the last row; an offset past either end stops at the first or last row.'**
  String get cfgbOnMissingHelp;

  /// No description provided for @cfgbOnMissingError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get cfgbOnMissingError;

  /// No description provided for @cfgbOnMissingNull.
  ///
  /// In en, this message translates to:
  /// **'No value'**
  String get cfgbOnMissingNull;

  /// No description provided for @cfgbOptionsFamily.
  ///
  /// In en, this message translates to:
  /// **'Product family'**
  String get cfgbOptionsFamily;

  /// No description provided for @cfgbOptionsFrom.
  ///
  /// In en, this message translates to:
  /// **'Allowed alternatives (formula)'**
  String get cfgbOptionsFrom;

  /// No description provided for @cfgbOptionsFromHelp.
  ///
  /// In en, this message translates to:
  /// **'A list the user may choose from instead of the calculated value'**
  String get cfgbOptionsFromHelp;

  /// No description provided for @cfgbOptionsStatic.
  ///
  /// In en, this message translates to:
  /// **'Fixed list'**
  String get cfgbOptionsStatic;

  /// No description provided for @cfgbOptionsTable.
  ///
  /// In en, this message translates to:
  /// **'Table column'**
  String get cfgbOptionsTable;

  /// No description provided for @cfgbOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get cfgbOrder;

  /// No description provided for @cfgbOutputRules.
  ///
  /// In en, this message translates to:
  /// **'Output rules'**
  String get cfgbOutputRules;

  /// No description provided for @cfgbOverridable.
  ///
  /// In en, this message translates to:
  /// **'The user may override it'**
  String get cfgbOverridable;

  /// No description provided for @cfgbOverridableHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown as calculated, pinned or pinned but stale'**
  String get cfgbOverridableHelp;

  /// No description provided for @cfgbPattern.
  ///
  /// In en, this message translates to:
  /// **'Pattern (regular expression)'**
  String get cfgbPattern;

  /// No description provided for @cfgbPercentBase.
  ///
  /// In en, this message translates to:
  /// **'Percentage of'**
  String get cfgbPercentBase;

  /// No description provided for @cfgbPercentBaseList.
  ///
  /// In en, this message translates to:
  /// **'the parent\'s list price'**
  String get cfgbPercentBaseList;

  /// No description provided for @cfgbPercentBaseNet.
  ///
  /// In en, this message translates to:
  /// **'the parent\'s net price'**
  String get cfgbPercentBaseNet;

  /// No description provided for @cfgbPercentOfParent.
  ///
  /// In en, this message translates to:
  /// **'Percent of parent (formula)'**
  String get cfgbPercentOfParent;

  /// No description provided for @cfgbPercentOfParentHelp.
  ///
  /// In en, this message translates to:
  /// **'Prices the line as this percentage of the parent line, e.g. 20'**
  String get cfgbPercentOfParentHelp;

  /// No description provided for @cfgbProblems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 problem} other{{count} problems}}'**
  String cfgbProblems(int count);

  /// No description provided for @cfgbProductFilter.
  ///
  /// In en, this message translates to:
  /// **'Product filter (formula on p)'**
  String get cfgbProductFilter;

  /// No description provided for @cfgbProductFilterHelp.
  ///
  /// In en, this message translates to:
  /// **'e.g. p.attr(\'kw\') >= 1'**
  String get cfgbProductFilterHelp;

  /// No description provided for @cfgbQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity (formula)'**
  String get cfgbQuantity;

  /// No description provided for @cfgbQuantityHelp.
  ///
  /// In en, this message translates to:
  /// **'Defaults to 1; zero or less leaves the line out'**
  String get cfgbQuantityHelp;

  /// No description provided for @cfgbRangeKey.
  ///
  /// In en, this message translates to:
  /// **'Range key'**
  String get cfgbRangeKey;

  /// No description provided for @cfgbRangeKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'The lookup key carrying the value'**
  String get cfgbRangeKeyHelp;

  /// No description provided for @cfgbRangeMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum column'**
  String get cfgbRangeMax;

  /// No description provided for @cfgbRangeMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum column'**
  String get cfgbRangeMin;

  /// No description provided for @cfgbRawJson.
  ///
  /// In en, this message translates to:
  /// **'Definition as JSON'**
  String get cfgbRawJson;

  /// No description provided for @cfgbRemoveColumn.
  ///
  /// In en, this message translates to:
  /// **'Remove column'**
  String get cfgbRemoveColumn;

  /// No description provided for @cfgbRemoveItemTable.
  ///
  /// In en, this message translates to:
  /// **'Remove item table'**
  String get cfgbRemoveItemTable;

  /// No description provided for @cfgbRemoveRow.
  ///
  /// In en, this message translates to:
  /// **'Remove row'**
  String get cfgbRemoveRow;

  /// No description provided for @cfgbReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get cfgbReplace;

  /// No description provided for @cfgbRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get cfgbRequired;

  /// No description provided for @cfgbRevisions.
  ///
  /// In en, this message translates to:
  /// **'Revisions'**
  String get cfgbRevisions;

  /// No description provided for @cfgbRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row} other{{count} rows}}'**
  String cfgbRowCount(int count);

  /// No description provided for @cfgbRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Output rule {id}'**
  String cfgbRuleTitle(String id);

  /// No description provided for @cfgbSavedValid.
  ///
  /// In en, this message translates to:
  /// **'Saved. The draft can be activated.'**
  String get cfgbSavedValid;

  /// No description provided for @cfgbSavedWithProblems.
  ///
  /// In en, this message translates to:
  /// **'Saved with {count, plural, =1{1 problem} other{{count} problems}}.'**
  String cfgbSavedWithProblems(int count);

  /// No description provided for @cfgbScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get cfgbScope;

  /// No description provided for @cfgbScopeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get cfgbScopeGroup;

  /// No description provided for @cfgbScopeItem.
  ///
  /// In en, this message translates to:
  /// **'Item (row)'**
  String get cfgbScopeItem;

  /// No description provided for @cfgbScopeItems.
  ///
  /// In en, this message translates to:
  /// **'Items: {table}'**
  String cfgbScopeItems(String table);

  /// No description provided for @cfgbScopeProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get cfgbScopeProject;

  /// No description provided for @cfgbScopes.
  ///
  /// In en, this message translates to:
  /// **'Scopes'**
  String get cfgbScopes;

  /// No description provided for @cfgbSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get cfgbSection;

  /// No description provided for @cfgbSectionTemplate.
  ///
  /// In en, this message translates to:
  /// **'Section (template)'**
  String get cfgbSectionTemplate;

  /// No description provided for @cfgbSectionTemplateHelp.
  ///
  /// In en, this message translates to:
  /// **'Defaults to the group name for group and item rules'**
  String get cfgbSectionTemplateHelp;

  /// No description provided for @cfgbSelectComputed.
  ///
  /// In en, this message translates to:
  /// **'Choose a computed value or add one.'**
  String get cfgbSelectComputed;

  /// No description provided for @cfgbSelectField.
  ///
  /// In en, this message translates to:
  /// **'Choose a field or add one.'**
  String get cfgbSelectField;

  /// No description provided for @cfgbSelectRule.
  ///
  /// In en, this message translates to:
  /// **'Choose an output rule or add one.'**
  String get cfgbSelectRule;

  /// No description provided for @cfgbSelectTable.
  ///
  /// In en, this message translates to:
  /// **'Choose a table or add one.'**
  String get cfgbSelectTable;

  /// No description provided for @cfgbSelectValidation.
  ///
  /// In en, this message translates to:
  /// **'Choose a check or add one.'**
  String get cfgbSelectValidation;

  /// No description provided for @cfgbSeverity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get cfgbSeverity;

  /// No description provided for @cfgbSeverityError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get cfgbSeverityError;

  /// No description provided for @cfgbSeverityInfo.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get cfgbSeverityInfo;

  /// No description provided for @cfgbSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get cfgbSeverityWarning;

  /// No description provided for @cfgbShow.
  ///
  /// In en, this message translates to:
  /// **'Shown to the user'**
  String get cfgbShow;

  /// No description provided for @cfgbShownAt.
  ///
  /// In en, this message translates to:
  /// **'Shown at field'**
  String get cfgbShownAt;

  /// No description provided for @cfgbStatusActive.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get cfgbStatusActive;

  /// No description provided for @cfgbStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get cfgbStatusDraft;

  /// No description provided for @cfgbStatusObsolete.
  ///
  /// In en, this message translates to:
  /// **'obsolete'**
  String get cfgbStatusObsolete;

  /// No description provided for @cfgbStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get cfgbStep;

  /// No description provided for @cfgbTabComputed.
  ///
  /// In en, this message translates to:
  /// **'Computed values'**
  String get cfgbTabComputed;

  /// No description provided for @cfgbTabFields.
  ///
  /// In en, this message translates to:
  /// **'Fields & layout'**
  String get cfgbTabFields;

  /// No description provided for @cfgbTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get cfgbTabGeneral;

  /// No description provided for @cfgbTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get cfgbTable;

  /// No description provided for @cfgbTableKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get cfgbTableKind;

  /// No description provided for @cfgbTables.
  ///
  /// In en, this message translates to:
  /// **'Lookup tables'**
  String get cfgbTables;

  /// No description provided for @cfgbTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Table {name}'**
  String cfgbTableTitle(String name);

  /// No description provided for @cfgbTabOutputs.
  ///
  /// In en, this message translates to:
  /// **'Output rules'**
  String get cfgbTabOutputs;

  /// No description provided for @cfgbTabTables.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get cfgbTabTables;

  /// No description provided for @cfgbTabTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get cfgbTabTest;

  /// No description provided for @cfgbTabTransfer.
  ///
  /// In en, this message translates to:
  /// **'Import/export'**
  String get cfgbTabTransfer;

  /// No description provided for @cfgbTabValidations.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get cfgbTabValidations;

  /// No description provided for @cfgbTestHelp.
  ///
  /// In en, this message translates to:
  /// **'Try the saved draft as sales will see it. Nothing is saved; select a line to see why it is there.'**
  String get cfgbTestHelp;

  /// No description provided for @cfgbTestNeedsValid.
  ///
  /// In en, this message translates to:
  /// **'The saved draft has problems; the test may fail until they are solved.'**
  String get cfgbTestNeedsValid;

  /// No description provided for @cfgbTestReset.
  ///
  /// In en, this message translates to:
  /// **'Start again'**
  String get cfgbTestReset;

  /// No description provided for @cfgbTestUnsaved.
  ///
  /// In en, this message translates to:
  /// **'The test uses the saved draft; save to include your latest changes.'**
  String get cfgbTestUnsaved;

  /// No description provided for @cfgbTranslations.
  ///
  /// In en, this message translates to:
  /// **'Translations'**
  String get cfgbTranslations;

  /// No description provided for @cfgbTypeBoolean.
  ///
  /// In en, this message translates to:
  /// **'Yes/no'**
  String get cfgbTypeBoolean;

  /// No description provided for @cfgbTypeChoice.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get cfgbTypeChoice;

  /// No description provided for @cfgbTypeInteger.
  ///
  /// In en, this message translates to:
  /// **'Whole number'**
  String get cfgbTypeInteger;

  /// No description provided for @cfgbTypeNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get cfgbTypeNumber;

  /// No description provided for @cfgbTypeProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get cfgbTypeProduct;

  /// No description provided for @cfgbTypeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get cfgbTypeText;

  /// No description provided for @cfgbUnsavedText.
  ///
  /// In en, this message translates to:
  /// **'The draft has changes that are not saved.'**
  String get cfgbUnsavedText;

  /// No description provided for @cfgbUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get cfgbUnsavedTitle;

  /// No description provided for @cfgbValidations.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get cfgbValidations;

  /// No description provided for @cfgbValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Check {id}'**
  String cfgbValidationTitle(String id);

  /// No description provided for @cfgbValidationWhenHelp.
  ///
  /// In en, this message translates to:
  /// **'When true, the message is shown'**
  String get cfgbValidationWhenHelp;

  /// No description provided for @cfgbValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get cfgbValue;

  /// No description provided for @cfgbVisibleIf.
  ///
  /// In en, this message translates to:
  /// **'Visible when'**
  String get cfgbVisibleIf;

  /// No description provided for @cfgbWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get cfgbWhen;

  /// No description provided for @cfgbWhenHelp.
  ///
  /// In en, this message translates to:
  /// **'Lines are only made when this is true'**
  String get cfgbWhenHelp;

  /// No description provided for @cfgbWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get cfgbWidth;

  /// No description provided for @tabProductionOrder.
  ///
  /// In en, this message translates to:
  /// **'Production order'**
  String get tabProductionOrder;

  /// No description provided for @tabDeliveryNote.
  ///
  /// In en, this message translates to:
  /// **'Delivery note'**
  String get tabDeliveryNote;

  /// No description provided for @vatRegime.
  ///
  /// In en, this message translates to:
  /// **'VAT regime'**
  String get vatRegime;

  /// No description provided for @vatRegimeDomestic.
  ///
  /// In en, this message translates to:
  /// **'EU customer, VAT charged'**
  String get vatRegimeDomestic;

  /// No description provided for @vatRegimeIntraEu.
  ///
  /// In en, this message translates to:
  /// **'EU business, VAT reverse-charged'**
  String get vatRegimeIntraEu;

  /// No description provided for @vatRegimeOutsideEu.
  ///
  /// In en, this message translates to:
  /// **'Outside the EU, no VAT'**
  String get vatRegimeOutsideEu;

  /// No description provided for @addSubItem.
  ///
  /// In en, this message translates to:
  /// **'Add sub-item'**
  String get addSubItem;

  /// No description provided for @subItemsOptions.
  ///
  /// In en, this message translates to:
  /// **'Options of {product}'**
  String subItemsOptions(String product);

  /// No description provided for @subItemsNoOptions.
  ///
  /// In en, this message translates to:
  /// **'This product has no options defined.'**
  String get subItemsNoOptions;

  /// No description provided for @subItemsOtherProducts.
  ///
  /// In en, this message translates to:
  /// **'Other products'**
  String get subItemsOtherProducts;

  /// No description provided for @crTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get crTitle;

  /// No description provided for @crNew.
  ///
  /// In en, this message translates to:
  /// **'New report'**
  String get crNew;

  /// No description provided for @crEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports yet. Build one to see your data grouped and summed.'**
  String get crEmpty;

  /// No description provided for @crShared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get crShared;

  /// No description provided for @crPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get crPrivate;

  /// No description provided for @crShare.
  ///
  /// In en, this message translates to:
  /// **'Share with everyone in the company'**
  String get crShare;

  /// No description provided for @crOwnedBy.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String crOwnedBy(String name);

  /// No description provided for @crObject.
  ///
  /// In en, this message translates to:
  /// **'Report on'**
  String get crObject;

  /// No description provided for @crJoin.
  ///
  /// In en, this message translates to:
  /// **'Add related data'**
  String get crJoin;

  /// No description provided for @crGroupBy.
  ///
  /// In en, this message translates to:
  /// **'Group by'**
  String get crGroupBy;

  /// No description provided for @crAddGrouping.
  ///
  /// In en, this message translates to:
  /// **'Add grouping'**
  String get crAddGrouping;

  /// No description provided for @crColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get crColumns;

  /// No description provided for @crAddColumn.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get crAddColumn;

  /// No description provided for @crField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get crField;

  /// No description provided for @crSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get crSummary;

  /// No description provided for @crSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'Show value'**
  String get crSummaryNone;

  /// No description provided for @crSumCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get crSumCount;

  /// No description provided for @crSumSum.
  ///
  /// In en, this message translates to:
  /// **'Sum'**
  String get crSumSum;

  /// No description provided for @crSumAvg.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get crSumAvg;

  /// No description provided for @crSumMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get crSumMin;

  /// No description provided for @crSumMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get crSumMax;

  /// No description provided for @crFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get crFilters;

  /// No description provided for @crAddFilter.
  ///
  /// In en, this message translates to:
  /// **'Add filter'**
  String get crAddFilter;

  /// No description provided for @crMatchAll.
  ///
  /// In en, this message translates to:
  /// **'All filters must match'**
  String get crMatchAll;

  /// No description provided for @crMatchAny.
  ///
  /// In en, this message translates to:
  /// **'At least one filter must match'**
  String get crMatchAny;

  /// No description provided for @crOpEq.
  ///
  /// In en, this message translates to:
  /// **'equals'**
  String get crOpEq;

  /// No description provided for @crOpNe.
  ///
  /// In en, this message translates to:
  /// **'does not equal'**
  String get crOpNe;

  /// No description provided for @crOpGt.
  ///
  /// In en, this message translates to:
  /// **'greater than'**
  String get crOpGt;

  /// No description provided for @crOpGte.
  ///
  /// In en, this message translates to:
  /// **'at least'**
  String get crOpGte;

  /// No description provided for @crOpLt.
  ///
  /// In en, this message translates to:
  /// **'less than'**
  String get crOpLt;

  /// No description provided for @crOpLte.
  ///
  /// In en, this message translates to:
  /// **'at most'**
  String get crOpLte;

  /// No description provided for @crOpContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get crOpContains;

  /// No description provided for @crOpStartsWith.
  ///
  /// In en, this message translates to:
  /// **'starts with'**
  String get crOpStartsWith;

  /// No description provided for @crOpIn.
  ///
  /// In en, this message translates to:
  /// **'is one of'**
  String get crOpIn;

  /// No description provided for @crOpIsNull.
  ///
  /// In en, this message translates to:
  /// **'is empty'**
  String get crOpIsNull;

  /// No description provided for @crOpNotNull.
  ///
  /// In en, this message translates to:
  /// **'is not empty'**
  String get crOpNotNull;

  /// No description provided for @crValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get crValue;

  /// No description provided for @crValueListHint.
  ///
  /// In en, this message translates to:
  /// **'Separate values with commas'**
  String get crValueListHint;

  /// No description provided for @crBucketNone.
  ///
  /// In en, this message translates to:
  /// **'Exact value'**
  String get crBucketNone;

  /// No description provided for @crBucketDay.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get crBucketDay;

  /// No description provided for @crBucketMonth.
  ///
  /// In en, this message translates to:
  /// **'By month'**
  String get crBucketMonth;

  /// No description provided for @crBucketYear.
  ///
  /// In en, this message translates to:
  /// **'By year'**
  String get crBucketYear;

  /// No description provided for @crSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get crSort;

  /// No description provided for @crAddSort.
  ///
  /// In en, this message translates to:
  /// **'Add sort'**
  String get crAddSort;

  /// No description provided for @crDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get crDescending;

  /// No description provided for @crChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get crChart;

  /// No description provided for @crChartNone.
  ///
  /// In en, this message translates to:
  /// **'No chart'**
  String get crChartNone;

  /// No description provided for @crChartBar.
  ///
  /// In en, this message translates to:
  /// **'Bar'**
  String get crChartBar;

  /// No description provided for @crChartLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get crChartLine;

  /// No description provided for @crChartPie.
  ///
  /// In en, this message translates to:
  /// **'Pie'**
  String get crChartPie;

  /// No description provided for @crChartX.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get crChartX;

  /// No description provided for @crChartY.
  ///
  /// In en, this message translates to:
  /// **'Values'**
  String get crChartY;

  /// No description provided for @crRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String crRows(int count);

  /// No description provided for @crRowsShown.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {total} rows shown'**
  String crRowsShown(int shown, int total);

  /// No description provided for @crChartShareShown.
  ///
  /// In en, this message translates to:
  /// **'Shares are of the {count} groups shown.'**
  String crChartShareShown(int count);

  /// No description provided for @crSaved.
  ///
  /// In en, this message translates to:
  /// **'Report saved'**
  String get crSaved;

  /// No description provided for @crDeleted.
  ///
  /// In en, this message translates to:
  /// **'Report deleted'**
  String get crDeleted;

  /// No description provided for @crDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get crDelete;

  /// No description provided for @crDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this report?'**
  String get crDeleteConfirm;

  /// No description provided for @crExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get crExportCsv;

  /// No description provided for @crExportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get crExportPdf;

  /// No description provided for @crNeedName.
  ///
  /// In en, this message translates to:
  /// **'Give the report a name.'**
  String get crNeedName;

  /// No description provided for @crNeedColumn.
  ///
  /// In en, this message translates to:
  /// **'Add at least one column.'**
  String get crNeedColumn;

  /// No description provided for @crLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more rows'**
  String get crLoadMore;

  /// No description provided for @crNoRows.
  ///
  /// In en, this message translates to:
  /// **'No rows match this report.'**
  String get crNoRows;

  /// No description provided for @crRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get crRun;

  /// No description provided for @crDateMode.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get crDateMode;

  /// No description provided for @crDateFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed date'**
  String get crDateFixed;

  /// No description provided for @crDateRelative.
  ///
  /// In en, this message translates to:
  /// **'Relative to today'**
  String get crDateRelative;

  /// No description provided for @crRelativePeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get crRelativePeriod;

  /// No description provided for @crRelativeDays.
  ///
  /// In en, this message translates to:
  /// **'Number of days'**
  String get crRelativeDays;

  /// No description provided for @crRelativeDaysInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number of days from 1 to 3660.'**
  String get crRelativeDaysInvalid;

  /// No description provided for @crRelToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get crRelToday;

  /// No description provided for @crRelYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get crRelYesterday;

  /// No description provided for @crRelThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get crRelThisWeek;

  /// No description provided for @crRelLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get crRelLastWeek;

  /// No description provided for @crRelThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get crRelThisMonth;

  /// No description provided for @crRelLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get crRelLastMonth;

  /// No description provided for @crRelThisQuarter.
  ///
  /// In en, this message translates to:
  /// **'This quarter'**
  String get crRelThisQuarter;

  /// No description provided for @crRelLastQuarter.
  ///
  /// In en, this message translates to:
  /// **'Last quarter'**
  String get crRelLastQuarter;

  /// No description provided for @crRelThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get crRelThisYear;

  /// No description provided for @crRelLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get crRelLastYear;

  /// No description provided for @crRelLastNDays.
  ///
  /// In en, this message translates to:
  /// **'Last N days'**
  String get crRelLastNDays;

  /// No description provided for @crRelNextNDays.
  ///
  /// In en, this message translates to:
  /// **'Next N days'**
  String get crRelNextNDays;

  /// No description provided for @envLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get envLive;

  /// No description provided for @envTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get envTest;

  /// No description provided for @envTutorial.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get envTutorial;

  /// No description provided for @envBannerSemantics.
  ///
  /// In en, this message translates to:
  /// **'Environment {name}, {kind}'**
  String envBannerSemantics(String name, String kind);

  /// No description provided for @envSwitcherTitle.
  ///
  /// In en, this message translates to:
  /// **'Environments'**
  String get envSwitcherTitle;

  /// No description provided for @envSwitchMenu.
  ///
  /// In en, this message translates to:
  /// **'Environment: {name}'**
  String envSwitchMenu(String name);

  /// No description provided for @envSwitchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch environment'**
  String get envSwitchTooltip;

  /// No description provided for @envActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get envActive;

  /// No description provided for @envAdd.
  ///
  /// In en, this message translates to:
  /// **'Add environment'**
  String get envAdd;

  /// No description provided for @envName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get envName;

  /// No description provided for @envServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get envServerUrl;

  /// No description provided for @envCheck.
  ///
  /// In en, this message translates to:
  /// **'Check server'**
  String get envCheck;

  /// No description provided for @envDetected.
  ///
  /// In en, this message translates to:
  /// **'Server says: {kind} environment, database {db}'**
  String envDetected(String kind, String db);

  /// No description provided for @envInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a full address such as https://erp.example.com'**
  String get envInvalidUrl;

  /// No description provided for @envAlreadyListed.
  ///
  /// In en, this message translates to:
  /// **'This server is already in the list.'**
  String get envAlreadyListed;

  /// No description provided for @envUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the environment from this server: {error}'**
  String envUnreachable(String error);

  /// No description provided for @envRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get envRemove;

  /// No description provided for @envRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove environment?'**
  String get envRemoveTitle;

  /// No description provided for @envRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is removed from this device, with its saved sign-in. Nothing changes on the server.'**
  String envRemoveBody(String name);

  /// No description provided for @envCannotRemoveActive.
  ///
  /// In en, this message translates to:
  /// **'Switch to another environment first'**
  String get envCannotRemoveActive;

  /// No description provided for @envUnsavedBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open tab has unsaved changes} other{{count} open tabs have unsaved changes}}. Switching environment closes all tabs and discards them.'**
  String envUnsavedBody(int count);

  /// No description provided for @envDiscardAndSwitch.
  ///
  /// In en, this message translates to:
  /// **'Discard and switch'**
  String get envDiscardAndSwitch;

  /// No description provided for @adminPriceZones.
  ///
  /// In en, this message translates to:
  /// **'Price zones'**
  String get adminPriceZones;

  /// No description provided for @newPriceZone.
  ///
  /// In en, this message translates to:
  /// **'New price zone'**
  String get newPriceZone;

  /// No description provided for @editPriceZone.
  ///
  /// In en, this message translates to:
  /// **'Edit price zone'**
  String get editPriceZone;

  /// No description provided for @sortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort order'**
  String get sortOrder;

  /// No description provided for @noPriceZones.
  ///
  /// In en, this message translates to:
  /// **'No price zones yet.'**
  String get noPriceZones;

  /// No description provided for @priceZoneDeleted.
  ///
  /// In en, this message translates to:
  /// **'Price zone deleted'**
  String get priceZoneDeleted;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deletePriceZoneConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete price zone {code}? This is refused when prices or customers use it.'**
  String deletePriceZoneConfirm(String code);

  /// No description provided for @sortOrderInvalid.
  ///
  /// In en, this message translates to:
  /// **'Sort order must be a whole number.'**
  String get sortOrderInvalid;

  /// No description provided for @envNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Done, but the list of environments could not be saved on this device.'**
  String get envNotSaved;

  /// No description provided for @tutTitle.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get tutTitle;

  /// No description provided for @tutBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get tutBack;

  /// No description provided for @tutNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get tutNext;

  /// No description provided for @tutAssist.
  ///
  /// In en, this message translates to:
  /// **'Do this step for me'**
  String get tutAssist;

  /// No description provided for @tutAssistFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not finish this step: {reason}. Try again.'**
  String tutAssistFailed(String reason);

  /// No description provided for @tutSkipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip step'**
  String get tutSkipStep;

  /// No description provided for @tutPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get tutPause;

  /// No description provided for @tutResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get tutResume;

  /// No description provided for @tutPaused.
  ///
  /// In en, this message translates to:
  /// **'Tutorial paused'**
  String get tutPaused;

  /// No description provided for @tutMenuPath.
  ///
  /// In en, this message translates to:
  /// **'Menu path · {path}'**
  String tutMenuPath(String path);

  /// No description provided for @tutShortcut.
  ///
  /// In en, this message translates to:
  /// **'Tutorial shortcut · {path}'**
  String tutShortcut(String path);

  /// No description provided for @tutAssistManual.
  ///
  /// In en, this message translates to:
  /// **'How to do this step'**
  String get tutAssistManual;

  /// No description provided for @tutAssistConfirm.
  ///
  /// In en, this message translates to:
  /// **'The tutorial will apply these changes for you and verify the result.'**
  String get tutAssistConfirm;

  /// No description provided for @tutAssistRun.
  ///
  /// In en, this message translates to:
  /// **'Run this step'**
  String get tutAssistRun;

  /// No description provided for @tutAssistRunning.
  ///
  /// In en, this message translates to:
  /// **'Applying and checking this step…'**
  String get tutAssistRunning;

  /// No description provided for @tutShowControl.
  ///
  /// In en, this message translates to:
  /// **'Show control'**
  String get tutShowControl;

  /// No description provided for @tutShowInstructions.
  ///
  /// In en, this message translates to:
  /// **'Show instructions'**
  String get tutShowInstructions;

  /// No description provided for @tutControlUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The control is unavailable on this screen. Open the relevant section and try again.'**
  String get tutControlUnavailable;

  /// No description provided for @tutShortcutHelp.
  ///
  /// In en, this message translates to:
  /// **'Press {keys} to see the keyboard shortcuts available on the current screen.'**
  String tutShortcutHelp(String keys);

  /// No description provided for @tutTakeMe.
  ///
  /// In en, this message translates to:
  /// **'Take me there'**
  String get tutTakeMe;

  /// No description provided for @tutStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String tutStepOf(int current, int total);

  /// No description provided for @tutOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to TradoCraft'**
  String get tutOfferTitle;

  /// No description provided for @tutOfferBody.
  ///
  /// In en, this message translates to:
  /// **'This is a tutorial environment. Want a guided tour that teaches you the app step by step, on practice data?'**
  String get tutOfferBody;

  /// No description provided for @tutOfferStart.
  ///
  /// In en, this message translates to:
  /// **'Start the tutorial'**
  String get tutOfferStart;

  /// No description provided for @tutOfferLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get tutOfferLater;

  /// No description provided for @tutLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'The tutorial does not run on live data'**
  String get tutLiveTitle;

  /// No description provided for @tutLiveBody.
  ///
  /// In en, this message translates to:
  /// **'The tutorial creates records, so it only runs in a test or tutorial environment. Switch to one, or add one.'**
  String get tutLiveBody;

  /// No description provided for @tutSwitchEnv.
  ///
  /// In en, this message translates to:
  /// **'Switch environment'**
  String get tutSwitchEnv;

  /// No description provided for @tutAddEnv.
  ///
  /// In en, this message translates to:
  /// **'Add an environment'**
  String get tutAddEnv;

  /// No description provided for @tutMapIntro.
  ///
  /// In en, this message translates to:
  /// **'Work through the chapters in order. You can pause, replay or skip a chapter at any time.'**
  String get tutMapIntro;

  /// No description provided for @tutStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tutStatusDone;

  /// No description provided for @tutStatusCurrent.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get tutStatusCurrent;

  /// No description provided for @tutStatusLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get tutStatusLocked;

  /// No description provided for @tutStatusSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get tutStatusSkipped;

  /// No description provided for @tutStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get tutStatusPaused;

  /// No description provided for @tutStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get tutStart;

  /// No description provided for @tutReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get tutReplay;

  /// No description provided for @tutFinishedTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter {name} complete'**
  String tutFinishedTitle(String name);

  /// No description provided for @tutFinishedNext.
  ///
  /// In en, this message translates to:
  /// **'Well done. Next up: {name}. Start it now, or pick it later from the chapter map.'**
  String tutFinishedNext(String name);

  /// No description provided for @tutFinishedLast.
  ///
  /// In en, this message translates to:
  /// **'That was the last chapter. Well done. You can replay any chapter from the chapter map.'**
  String get tutFinishedLast;

  /// No description provided for @tutStartNext.
  ///
  /// In en, this message translates to:
  /// **'Start next chapter'**
  String get tutStartNext;

  /// No description provided for @tutBackToMap.
  ///
  /// In en, this message translates to:
  /// **'Back to chapter map'**
  String get tutBackToMap;

  /// No description provided for @tutSkipChapter.
  ///
  /// In en, this message translates to:
  /// **'Skip chapter'**
  String get tutSkipChapter;

  /// No description provided for @tutWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get tutWelcomeTitle;

  /// No description provided for @tutWelcomeSummary.
  ///
  /// In en, this message translates to:
  /// **'Find your way around: the environment banner, the tabs and the tutorial controls.'**
  String get tutWelcomeSummary;

  /// No description provided for @tutWelcomeBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'The strip at the top'**
  String get tutWelcomeBannerTitle;

  /// No description provided for @tutWelcomeBannerBody.
  ///
  /// In en, this message translates to:
  /// **'This strip always shows which environment you are in: its name and its kind. Amber means test, blue means tutorial and red means live data. The tutorial only runs in test and tutorial environments, so nothing you do here touches real data.'**
  String get tutWelcomeBannerBody;

  /// No description provided for @tutWelcomeTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tabs and sections'**
  String get tutWelcomeTabsTitle;

  /// No description provided for @tutWelcomeTabsBody.
  ///
  /// In en, this message translates to:
  /// **'Use Switch application to pick a category. Its modules appear on the left, or in the bottom bar on a phone. Opening a record, such as a product or quotation, adds a workspace tab so you can keep several records open.'**
  String get tutWelcomeTabsBody;

  /// No description provided for @tutWelcomeControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'This card'**
  String get tutWelcomeControlsTitle;

  /// No description provided for @tutWelcomeControlsBody.
  ///
  /// In en, this message translates to:
  /// **'I am your narrator. Next moves on when a step is only an explanation. Steps that ask you to do something finish by themselves as soon as you have done it. Back and Skip step let you move around, and Pause hides me until you press Resume.'**
  String get tutWelcomeControlsBody;

  /// No description provided for @tutWelcomeMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to find me'**
  String get tutWelcomeMenuTitle;

  /// No description provided for @tutWelcomeMenuBody.
  ///
  /// In en, this message translates to:
  /// **'Open the account menu to find the Tutorial entry. It opens the chapter map, where you can resume, replay or skip a chapter at any time.'**
  String get tutWelcomeMenuBody;

  /// No description provided for @tutWelcomeProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start'**
  String get tutWelcomeProductsTitle;

  /// No description provided for @tutWelcomeProductsBody.
  ///
  /// In en, this message translates to:
  /// **'Open the Products section. The next chapter starts there.'**
  String get tutWelcomeProductsBody;

  /// No description provided for @purchasing.
  ///
  /// In en, this message translates to:
  /// **'Purchasing'**
  String get purchasing;

  /// No description provided for @tabSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get tabSupplier;

  /// No description provided for @purchSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get purchSuppliers;

  /// No description provided for @purchNewSupplier.
  ///
  /// In en, this message translates to:
  /// **'New supplier'**
  String get purchNewSupplier;

  /// No description provided for @purchPaymentTerms.
  ///
  /// In en, this message translates to:
  /// **'Payment terms'**
  String get purchPaymentTerms;

  /// No description provided for @purchDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String purchDays(int count);

  /// No description provided for @purchActiveOnly.
  ///
  /// In en, this message translates to:
  /// **'Active only'**
  String get purchActiveOnly;

  /// No description provided for @purchNameRequired.
  ///
  /// In en, this message translates to:
  /// **'The name is required.'**
  String get purchNameRequired;

  /// No description provided for @purchCountryInvalid.
  ///
  /// In en, this message translates to:
  /// **'The country must be a 2-letter code.'**
  String get purchCountryInvalid;

  /// No description provided for @purchCurrencyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The currency must be a 3-letter code.'**
  String get purchCurrencyInvalid;

  /// No description provided for @purchTermsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Payment terms must be a whole number of days.'**
  String get purchTermsInvalid;

  /// No description provided for @purchInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get purchInactive;

  /// No description provided for @purchPriceList.
  ///
  /// In en, this message translates to:
  /// **'Price list'**
  String get purchPriceList;

  /// No description provided for @purchAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get purchAddProduct;

  /// No description provided for @purchEditPrice.
  ///
  /// In en, this message translates to:
  /// **'Edit price'**
  String get purchEditPrice;

  /// No description provided for @purchNoPrices.
  ///
  /// In en, this message translates to:
  /// **'No products on this price list yet.'**
  String get purchNoPrices;

  /// No description provided for @purchPickProduct.
  ///
  /// In en, this message translates to:
  /// **'Choose a product.'**
  String get purchPickProduct;

  /// No description provided for @purchPriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid unit price.'**
  String get purchPriceInvalid;

  /// No description provided for @purchMoqInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid minimum order quantity.'**
  String get purchMoqInvalid;

  /// No description provided for @purchLeadInvalid.
  ///
  /// In en, this message translates to:
  /// **'Lead time must be a whole number of days.'**
  String get purchLeadInvalid;

  /// No description provided for @purchSupplierArticleCode.
  ///
  /// In en, this message translates to:
  /// **'Supplier article code'**
  String get purchSupplierArticleCode;

  /// No description provided for @purchSupplierArticleName.
  ///
  /// In en, this message translates to:
  /// **'Supplier article name'**
  String get purchSupplierArticleName;

  /// No description provided for @purchMoq.
  ///
  /// In en, this message translates to:
  /// **'Min. order qty'**
  String get purchMoq;

  /// No description provided for @purchLeadTimeDays.
  ///
  /// In en, this message translates to:
  /// **'Lead time (days)'**
  String get purchLeadTimeDays;

  /// No description provided for @purchPreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred supplier'**
  String get purchPreferred;

  /// No description provided for @purchRemoveProductConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {code} from this price list?'**
  String purchRemoveProductConfirm(String code);

  /// No description provided for @purchMoqValue.
  ///
  /// In en, this message translates to:
  /// **'MOQ {qty}'**
  String purchMoqValue(String qty);

  /// No description provided for @purchLeadValue.
  ///
  /// In en, this message translates to:
  /// **'lead time {days} d'**
  String purchLeadValue(int days);

  /// No description provided for @purchNoSuppliers.
  ///
  /// In en, this message translates to:
  /// **'No suppliers found.'**
  String get purchNoSuppliers;

  /// No description provided for @purchOrders.
  ///
  /// In en, this message translates to:
  /// **'Purchase orders'**
  String get purchOrders;

  /// No description provided for @purchNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New purchase order'**
  String get purchNewOrder;

  /// No description provided for @purchNoOrders.
  ///
  /// In en, this message translates to:
  /// **'No purchase orders found.'**
  String get purchNoOrders;

  /// No description provided for @purchOrderNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get purchOrderNumber;

  /// No description provided for @purchSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get purchSupplier;

  /// No description provided for @purchAllSuppliers.
  ///
  /// In en, this message translates to:
  /// **'All suppliers'**
  String get purchAllSuppliers;

  /// No description provided for @purchOrderDate.
  ///
  /// In en, this message translates to:
  /// **'Order date'**
  String get purchOrderDate;

  /// No description provided for @purchExpectedDate.
  ///
  /// In en, this message translates to:
  /// **'Expected delivery'**
  String get purchExpectedDate;

  /// No description provided for @purchStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get purchStatusDraft;

  /// No description provided for @purchStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'approved'**
  String get purchStatusApproved;

  /// No description provided for @purchStatusSent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get purchStatusSent;

  /// No description provided for @purchStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'partially received'**
  String get purchStatusPartial;

  /// No description provided for @purchStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'received'**
  String get purchStatusReceived;

  /// No description provided for @purchStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get purchStatusCancelled;

  /// No description provided for @purchLines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get purchLines;

  /// No description provided for @purchAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get purchAddLine;

  /// No description provided for @purchGoodsPickSupplier.
  ///
  /// In en, this message translates to:
  /// **'Choose a supplier to see the goods it offers.'**
  String get purchGoodsPickSupplier;

  /// No description provided for @purchGoodsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This supplier has no products on its price list yet. Use \"Other products\" below to add products to this order, or add them to the price list later.'**
  String get purchGoodsEmpty;

  /// No description provided for @purchGoodsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No goods match the filter.'**
  String get purchGoodsNoMatch;

  /// No description provided for @purchGoodsFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter goods'**
  String get purchGoodsFilter;

  /// No description provided for @purchGoodsHeader.
  ///
  /// In en, this message translates to:
  /// **'Goods of this supplier: tick what you want to order'**
  String get purchGoodsHeader;

  /// No description provided for @purchGoodsBelowMoq.
  ///
  /// In en, this message translates to:
  /// **'Below the minimum order quantity ({qty})'**
  String purchGoodsBelowMoq(String qty);

  /// No description provided for @purchGoodsCleared.
  ///
  /// In en, this message translates to:
  /// **'The selected goods were cleared because the supplier changed.'**
  String get purchGoodsCleared;

  /// No description provided for @purchGoodsOther.
  ///
  /// In en, this message translates to:
  /// **'Other products (not on the price list)'**
  String get purchGoodsOther;

  /// No description provided for @purchGoodsSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} lines, total {total}'**
  String purchGoodsSummary(int count, String total);

  /// No description provided for @purchGoodsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The supplier\'s goods could not be loaded. You can still add products under \"Other products\", or retry.'**
  String get purchGoodsLoadFailed;

  /// No description provided for @purchGoodsMixedCurrencies.
  ///
  /// In en, this message translates to:
  /// **'{count} lines in mixed currencies ({currencies}): no single total'**
  String purchGoodsMixedCurrencies(int count, String currencies);

  /// No description provided for @purchPickSupplier.
  ///
  /// In en, this message translates to:
  /// **'Choose a supplier.'**
  String get purchPickSupplier;

  /// No description provided for @purchLineQtyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be greater than zero, with at most 4 decimals.'**
  String get purchLineQtyInvalid;

  /// No description provided for @purchLinePriceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Unit price must be zero or more, with at most 4 decimals.'**
  String get purchLinePriceInvalid;

  /// No description provided for @purchNeedLine.
  ///
  /// In en, this message translates to:
  /// **'Add at least one line.'**
  String get purchNeedLine;

  /// No description provided for @purchApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get purchApprove;

  /// No description provided for @purchCancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get purchCancelOrder;

  /// No description provided for @purchCancelOrderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel purchase order {number}? This cannot be undone.'**
  String purchCancelOrderConfirm(String number);

  /// No description provided for @purchKeepOrder.
  ///
  /// In en, this message translates to:
  /// **'Keep order'**
  String get purchKeepOrder;

  /// No description provided for @purchQtyReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get purchQtyReceived;

  /// No description provided for @purchLineTotal.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get purchLineTotal;

  /// No description provided for @purchSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get purchSubtotal;

  /// No description provided for @purchTax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get purchTax;

  /// No description provided for @tabPurchaseOrder.
  ///
  /// In en, this message translates to:
  /// **'Purchase order'**
  String get tabPurchaseOrder;

  /// No description provided for @purchReceiveGoods.
  ///
  /// In en, this message translates to:
  /// **'Receive goods'**
  String get purchReceiveGoods;

  /// No description provided for @purchReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive goods for {number}'**
  String purchReceiveTitle(String number);

  /// No description provided for @purchReceiveDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination location'**
  String get purchReceiveDestination;

  /// No description provided for @purchReceiveQty.
  ///
  /// In en, this message translates to:
  /// **'Quantity to receive'**
  String get purchReceiveQty;

  /// No description provided for @purchReceiveRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {qty}'**
  String purchReceiveRemaining(String qty);

  /// No description provided for @purchReceiveSerialsHelp.
  ///
  /// In en, this message translates to:
  /// **'One serial number per line'**
  String get purchReceiveSerialsHelp;

  /// No description provided for @purchDeliveryNote.
  ///
  /// In en, this message translates to:
  /// **'Supplier delivery note'**
  String get purchDeliveryNote;

  /// No description provided for @purchReceiveQtyInvalid.
  ///
  /// In en, this message translates to:
  /// **'{product}: enter a quantity between 0 and {max}.'**
  String purchReceiveQtyInvalid(String product, String max);

  /// No description provided for @purchReceiveLotNeeded.
  ///
  /// In en, this message translates to:
  /// **'{product}: enter a lot number.'**
  String purchReceiveLotNeeded(String product);

  /// No description provided for @purchReceiveSerialWhole.
  ///
  /// In en, this message translates to:
  /// **'{product}: the quantity must be a whole number.'**
  String purchReceiveSerialWhole(String product);

  /// No description provided for @purchReceiveSerialCount.
  ///
  /// In en, this message translates to:
  /// **'{product}: enter exactly {count} different serial numbers.'**
  String purchReceiveSerialCount(String product, int count);

  /// No description provided for @purchReceiveNothing.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity for at least one line.'**
  String get purchReceiveNothing;

  /// No description provided for @purchReceiveLocationNeeded.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination location.'**
  String get purchReceiveLocationNeeded;

  /// No description provided for @purchReceiptBooked.
  ///
  /// In en, this message translates to:
  /// **'Goods receipt {number} booked.'**
  String purchReceiptBooked(String number);

  /// No description provided for @purchOpenReceipt.
  ///
  /// In en, this message translates to:
  /// **'Open receipt'**
  String get purchOpenReceipt;

  /// No description provided for @purchReceipts.
  ///
  /// In en, this message translates to:
  /// **'Goods receipts'**
  String get purchReceipts;

  /// No description provided for @purchReceivedDate.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get purchReceivedDate;

  /// No description provided for @purchOpenOrder.
  ///
  /// In en, this message translates to:
  /// **'Purchase order'**
  String get purchOpenOrder;

  /// No description provided for @tabGoodsReceipt.
  ///
  /// In en, this message translates to:
  /// **'Goods receipt'**
  String get tabGoodsReceipt;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up a new company'**
  String get setupTitle;

  /// No description provided for @setupOffer.
  ///
  /// In en, this message translates to:
  /// **'Set up a new company'**
  String get setupOffer;

  /// No description provided for @setupOfferHint.
  ///
  /// In en, this message translates to:
  /// **'This server has no company yet.'**
  String get setupOfferHint;

  /// No description provided for @setupServer.
  ///
  /// In en, this message translates to:
  /// **'Server: {url}'**
  String setupServer(String url);

  /// No description provided for @setupStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {n} of {total}'**
  String setupStepOf(int n, int total);

  /// No description provided for @setupStepCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get setupStepCompany;

  /// No description provided for @setupStepRegion.
  ///
  /// In en, this message translates to:
  /// **'Country, currency and language'**
  String get setupStepRegion;

  /// No description provided for @setupStepAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get setupStepAdmin;

  /// No description provided for @setupStepToken.
  ///
  /// In en, this message translates to:
  /// **'Setup token'**
  String get setupStepToken;

  /// No description provided for @setupStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get setupStepReview;

  /// No description provided for @setupCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company name'**
  String get setupCompanyName;

  /// No description provided for @setupLegalName.
  ///
  /// In en, this message translates to:
  /// **'Legal name (optional)'**
  String get setupLegalName;

  /// No description provided for @setupVatNumber.
  ///
  /// In en, this message translates to:
  /// **'VAT number (optional)'**
  String get setupVatNumber;

  /// No description provided for @setupCountry.
  ///
  /// In en, this message translates to:
  /// **'Country code (2 letters, e.g. BE)'**
  String get setupCountry;

  /// No description provided for @setupCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency (3 letters, e.g. EUR)'**
  String get setupCurrency;

  /// No description provided for @setupLanguage.
  ///
  /// In en, this message translates to:
  /// **'Default language'**
  String get setupLanguage;

  /// No description provided for @setupAdminEmail.
  ///
  /// In en, this message translates to:
  /// **'Administrator e-mail'**
  String get setupAdminEmail;

  /// No description provided for @setupAdminName.
  ///
  /// In en, this message translates to:
  /// **'Administrator name'**
  String get setupAdminName;

  /// No description provided for @setupToken.
  ///
  /// In en, this message translates to:
  /// **'Setup token'**
  String get setupToken;

  /// No description provided for @setupTokenHelp.
  ///
  /// In en, this message translates to:
  /// **'The value of BOOTSTRAP_TOKEN on the server.'**
  String get setupTokenHelp;

  /// No description provided for @setupErrName.
  ///
  /// In en, this message translates to:
  /// **'Enter the company name.'**
  String get setupErrName;

  /// No description provided for @setupErrVat.
  ///
  /// In en, this message translates to:
  /// **'A VAT number has 4 to 20 letters and digits.'**
  String get setupErrVat;

  /// No description provided for @setupErrCountry.
  ///
  /// In en, this message translates to:
  /// **'Enter a two-letter country code.'**
  String get setupErrCountry;

  /// No description provided for @setupErrCurrency.
  ///
  /// In en, this message translates to:
  /// **'Enter a three-letter currency code.'**
  String get setupErrCurrency;

  /// No description provided for @setupErrEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid e-mail address.'**
  String get setupErrEmail;

  /// No description provided for @setupErrAdminName.
  ///
  /// In en, this message translates to:
  /// **'Enter the administrator\'s name.'**
  String get setupErrAdminName;

  /// No description provided for @setupErrToken.
  ///
  /// In en, this message translates to:
  /// **'Enter the setup token.'**
  String get setupErrToken;

  /// No description provided for @setupNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get setupNext;

  /// No description provided for @setupBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get setupBack;

  /// No description provided for @setupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create company'**
  String get setupCreate;

  /// No description provided for @setupReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Check the details. A company can be created only once on this server.'**
  String get setupReviewHint;

  /// No description provided for @setupErr403.
  ///
  /// In en, this message translates to:
  /// **'The setup token is missing or wrong.'**
  String get setupErr403;

  /// No description provided for @setupErr404.
  ///
  /// In en, this message translates to:
  /// **'Setting up is disabled on this server. Set BOOTSTRAP_TOKEN on the server and restart it.'**
  String get setupErr404;

  /// No description provided for @setupErr409.
  ///
  /// In en, this message translates to:
  /// **'This server already has a company.'**
  String get setupErr409;

  /// No description provided for @setupDone.
  ///
  /// In en, this message translates to:
  /// **'Company {name} created.'**
  String setupDone(String name);

  /// No description provided for @setupDoneDev.
  ///
  /// In en, this message translates to:
  /// **'Signing in as {email}.'**
  String setupDoneDev(String email);

  /// No description provided for @setupDoneOidc.
  ///
  /// In en, this message translates to:
  /// **'Sign in through your identity provider with {email}: that account is the administrator.'**
  String setupDoneOidc(String email);

  /// No description provided for @setupToLogin.
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get setupToLogin;

  /// No description provided for @setupAddOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up this server?'**
  String get setupAddOfferTitle;

  /// No description provided for @setupAddOfferBody.
  ///
  /// In en, this message translates to:
  /// **'This server has no company yet. Set one up now?'**
  String get setupAddOfferBody;

  /// No description provided for @setupLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get setupLater;

  /// No description provided for @finMatchColumn.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get finMatchColumn;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get finance;

  /// No description provided for @finSupplierInvoices.
  ///
  /// In en, this message translates to:
  /// **'Supplier invoices'**
  String get finSupplierInvoices;

  /// No description provided for @finSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get finSettings;

  /// No description provided for @tabSupplierInvoice.
  ///
  /// In en, this message translates to:
  /// **'Supplier invoice'**
  String get tabSupplierInvoice;

  /// No description provided for @finNewInvoice.
  ///
  /// In en, this message translates to:
  /// **'New supplier invoice'**
  String get finNewInvoice;

  /// No description provided for @finNoInvoices.
  ///
  /// In en, this message translates to:
  /// **'No supplier invoices found.'**
  String get finNoInvoices;

  /// No description provided for @finInvoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get finInvoiceNumber;

  /// No description provided for @finInternalNumber.
  ///
  /// In en, this message translates to:
  /// **'Internal number'**
  String get finInternalNumber;

  /// No description provided for @finInvoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice date'**
  String get finInvoiceDate;

  /// No description provided for @finDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get finDueDate;

  /// No description provided for @finStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'draft'**
  String get finStatusDraft;

  /// No description provided for @finStatusMatched.
  ///
  /// In en, this message translates to:
  /// **'matched'**
  String get finStatusMatched;

  /// No description provided for @finStatusDisputed.
  ///
  /// In en, this message translates to:
  /// **'disputed'**
  String get finStatusDisputed;

  /// No description provided for @finStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'approved'**
  String get finStatusApproved;

  /// No description provided for @finStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'paid'**
  String get finStatusPaid;

  /// No description provided for @finMatchOk.
  ///
  /// In en, this message translates to:
  /// **'ok'**
  String get finMatchOk;

  /// No description provided for @finMatchNotReceived.
  ///
  /// In en, this message translates to:
  /// **'not received'**
  String get finMatchNotReceived;

  /// No description provided for @finMatchOverInvoiced.
  ///
  /// In en, this message translates to:
  /// **'over invoiced'**
  String get finMatchOverInvoiced;

  /// No description provided for @finMatchPriceVariance.
  ///
  /// In en, this message translates to:
  /// **'price variance'**
  String get finMatchPriceVariance;

  /// No description provided for @finMatchNoPoLine.
  ///
  /// In en, this message translates to:
  /// **'no order line'**
  String get finMatchNoPoLine;

  /// No description provided for @finOrderOptional.
  ///
  /// In en, this message translates to:
  /// **'Purchase order (optional)'**
  String get finOrderOptional;

  /// No description provided for @finNoOrder.
  ///
  /// In en, this message translates to:
  /// **'No purchase order'**
  String get finNoOrder;

  /// No description provided for @finOrderPrefillHint.
  ///
  /// In en, this message translates to:
  /// **'The lines are filled from the goods received and not yet invoiced.'**
  String get finOrderPrefillHint;

  /// No description provided for @finNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'The invoice number is required (at most 64 characters).'**
  String get finNumberRequired;

  /// No description provided for @finLineDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'A free-text line needs a description.'**
  String get finLineDescriptionRequired;

  /// No description provided for @finVatInvalid.
  ///
  /// In en, this message translates to:
  /// **'VAT rate must be between 0 and 100 with at most 2 decimals.'**
  String get finVatInvalid;

  /// No description provided for @finOrdered.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get finOrdered;

  /// No description provided for @finInvoiced.
  ///
  /// In en, this message translates to:
  /// **'Invoiced'**
  String get finInvoiced;

  /// No description provided for @finOrderPrice.
  ///
  /// In en, this message translates to:
  /// **'Order price'**
  String get finOrderPrice;

  /// No description provided for @finInvoicePrice.
  ///
  /// In en, this message translates to:
  /// **'Invoice price'**
  String get finInvoicePrice;

  /// No description provided for @finVariance.
  ///
  /// In en, this message translates to:
  /// **'Variance'**
  String get finVariance;

  /// No description provided for @finMatches.
  ///
  /// In en, this message translates to:
  /// **'The invoice matches the order and the receipts.'**
  String get finMatches;

  /// No description provided for @finNotMatches.
  ///
  /// In en, this message translates to:
  /// **'The invoice does not match the order and the receipts.'**
  String get finNotMatches;

  /// No description provided for @finTolerances.
  ///
  /// In en, this message translates to:
  /// **'Tolerances: quantity {qty} %, price {price} %'**
  String finTolerances(String qty, String price);

  /// No description provided for @finSubmitMatch.
  ///
  /// In en, this message translates to:
  /// **'Check match'**
  String get finSubmitMatch;

  /// No description provided for @finApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get finApprove;

  /// No description provided for @finOverrideTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve despite mismatch'**
  String get finOverrideTitle;

  /// No description provided for @finOverrideHelp.
  ///
  /// In en, this message translates to:
  /// **'The invoice does not match. Give the reason for approving it anyway; it is stored with the approval.'**
  String get finOverrideHelp;

  /// No description provided for @finOverrideReason.
  ///
  /// In en, this message translates to:
  /// **'Override reason'**
  String get finOverrideReason;

  /// No description provided for @finReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required.'**
  String get finReasonRequired;

  /// No description provided for @finDispute.
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get finDispute;

  /// No description provided for @finDisputeReason.
  ///
  /// In en, this message translates to:
  /// **'Dispute reason'**
  String get finDisputeReason;

  /// No description provided for @finReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get finReopen;

  /// No description provided for @finMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get finMarkPaid;

  /// No description provided for @finPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get finPaymentDate;

  /// No description provided for @finPaymentReference.
  ///
  /// In en, this message translates to:
  /// **'Payment reference'**
  String get finPaymentReference;

  /// No description provided for @finDeleteDraft.
  ///
  /// In en, this message translates to:
  /// **'Delete draft'**
  String get finDeleteDraft;

  /// No description provided for @finDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete invoice {number}? This cannot be undone.'**
  String finDeleteConfirm(String number);

  /// No description provided for @finNetTotal.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get finNetTotal;

  /// No description provided for @finGrossTotal.
  ///
  /// In en, this message translates to:
  /// **'Total incl. VAT'**
  String get finGrossTotal;

  /// No description provided for @finDisputeReasonShown.
  ///
  /// In en, this message translates to:
  /// **'Dispute reason'**
  String get finDisputeReasonShown;

  /// No description provided for @finOverrideShown.
  ///
  /// In en, this message translates to:
  /// **'Override reason'**
  String get finOverrideShown;

  /// No description provided for @finPaidOn.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get finPaidOn;

  /// No description provided for @finPurchaseOrder.
  ///
  /// In en, this message translates to:
  /// **'Purchase order'**
  String get finPurchaseOrder;

  /// No description provided for @finQuantityTolerance.
  ///
  /// In en, this message translates to:
  /// **'Quantity tolerance (%)'**
  String get finQuantityTolerance;

  /// No description provided for @finPriceTolerance.
  ///
  /// In en, this message translates to:
  /// **'Price tolerance (%)'**
  String get finPriceTolerance;

  /// No description provided for @finToleranceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a percentage between 0 and 100.'**
  String get finToleranceInvalid;

  /// No description provided for @finSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved.'**
  String get finSettingsSaved;

  /// No description provided for @finSettingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Largest accepted difference between the order and the invoice before a line counts as a mismatch.'**
  String get finSettingsHelp;

  /// No description provided for @finCreateInvoice.
  ///
  /// In en, this message translates to:
  /// **'Create supplier invoice'**
  String get finCreateInvoice;

  /// No description provided for @userRoleFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get userRoleFinance;

  /// No description provided for @moduleFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get moduleFinance;

  /// No description provided for @productionDivisionMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get productionDivisionMembers;

  /// No description provided for @productionDivisionNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No members'**
  String get productionDivisionNoMembers;

  /// No description provided for @productionScopeMine.
  ///
  /// In en, this message translates to:
  /// **'My divisions'**
  String get productionScopeMine;

  /// No description provided for @productionScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All divisions'**
  String get productionScopeAll;

  /// No description provided for @productionScopeEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders in your divisions. Orders without a division are included.'**
  String get productionScopeEmpty;

  /// No description provided for @productionShowAllDivisions.
  ///
  /// In en, this message translates to:
  /// **'Show all divisions'**
  String get productionShowAllDivisions;

  /// No description provided for @productionYourDivisions.
  ///
  /// In en, this message translates to:
  /// **'Your divisions'**
  String get productionYourDivisions;

  /// No description provided for @setupErrInsecure.
  ///
  /// In en, this message translates to:
  /// **'The setup token is not sent over an unencrypted connection to another computer. Use an https:// address (plain http is only allowed for localhost).'**
  String get setupErrInsecure;

  /// No description provided for @setupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Setting up is not available on this server: it already has a company, or setting up is disabled.'**
  String get setupUnavailable;

  /// No description provided for @setupErrRedirect.
  ///
  /// In en, this message translates to:
  /// **'The server redirected the request, so the setup token was not sent on. Check the server address (use the final https:// address).'**
  String get setupErrRedirect;

  /// No description provided for @tutSuppliersTitle.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get tutSuppliersTitle;

  /// No description provided for @tutSuppliersSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: purchaser. Create two suppliers and give them a price list for your components.'**
  String get tutSuppliersSummary;

  /// No description provided for @tutSuppliersNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 1 first'**
  String get tutSuppliersNeedsTitle;

  /// No description provided for @tutSuppliersNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the four core products from Chapter 1 (Conveyor belts & motors: MOT-3P-055, VFD-3P-055, CONV-BELT-1M) and Chapter 2 (PLCs, parallel licensing & network: PLC-BASE), and could not find them. Go back to the chapter map and finish those chapters first, then come back here.'**
  String get tutSuppliersNeedsBody;

  /// No description provided for @tutSuppliersOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Put on the purchaser hat'**
  String get tutSuppliersOpenTitle;

  /// No description provided for @tutSuppliersOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Your components have to come from somewhere. Open Purchasing in the menu: the Suppliers list is the first segment.'**
  String get tutSuppliersOpenBody;

  /// No description provided for @tutSuppliersSupplierATitle.
  ///
  /// In en, this message translates to:
  /// **'The first supplier'**
  String get tutSuppliersSupplierATitle;

  /// No description provided for @tutSuppliersSupplierABody.
  ///
  /// In en, this message translates to:
  /// **'Create a supplier with code TUT-SUP-A and name Voltaic Drives Ltd. Code and name are the only required fields; payment terms, tax id and contact details can follow later.'**
  String get tutSuppliersSupplierABody;

  /// No description provided for @tutSuppliersSupplierBTitle.
  ///
  /// In en, this message translates to:
  /// **'A second supplier'**
  String get tutSuppliersSupplierBTitle;

  /// No description provided for @tutSuppliersSupplierBBody.
  ///
  /// In en, this message translates to:
  /// **'A purchaser likes to compare. Create a second supplier with code TUT-SUP-B and name Ironbridge Frames.'**
  String get tutSuppliersSupplierBBody;

  /// No description provided for @tutSuppliersOpenATitle.
  ///
  /// In en, this message translates to:
  /// **'Open the first supplier'**
  String get tutSuppliersOpenATitle;

  /// No description provided for @tutSuppliersOpenABody.
  ///
  /// In en, this message translates to:
  /// **'Open Voltaic Drives Ltd from the list. Its price list is at the bottom of the supplier screen.'**
  String get tutSuppliersOpenABody;

  /// No description provided for @tutSuppliersPriceMotorTitle.
  ///
  /// In en, this message translates to:
  /// **'A price for the motor'**
  String get tutSuppliersPriceMotorTitle;

  /// No description provided for @tutSuppliersPriceMotorBody.
  ///
  /// In en, this message translates to:
  /// **'Add MOT-3P-055 to the price list: unit price 120, lead time 14 days, minimum order quantity 5. Purchase orders use these values to pre-fill their lines.'**
  String get tutSuppliersPriceMotorBody;

  /// No description provided for @tutSuppliersPriceMotorHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the product with the search box in the dialog; type MOT-3P-055.'**
  String get tutSuppliersPriceMotorHint;

  /// No description provided for @tutSuppliersPriceFrameTitle.
  ///
  /// In en, this message translates to:
  /// **'A price for the VFD'**
  String get tutSuppliersPriceFrameTitle;

  /// No description provided for @tutSuppliersPriceFrameBody.
  ///
  /// In en, this message translates to:
  /// **'Same again for VFD-3P-055: unit price 45, lead time 10 days, minimum order quantity 5.'**
  String get tutSuppliersPriceFrameBody;

  /// No description provided for @tutSuppliersPriceControllerTitle.
  ///
  /// In en, this message translates to:
  /// **'A price for the controller'**
  String get tutSuppliersPriceControllerTitle;

  /// No description provided for @tutSuppliersPriceControllerBody.
  ///
  /// In en, this message translates to:
  /// **'And PLC-BASE: unit price 30, lead time 7 days, minimum order quantity 5. This supplier now covers all three components.'**
  String get tutSuppliersPriceControllerBody;

  /// No description provided for @tutSuppliersOpenBTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the second supplier'**
  String get tutSuppliersOpenBTitle;

  /// No description provided for @tutSuppliersOpenBBody.
  ///
  /// In en, this message translates to:
  /// **'Go back to the list and open Ironbridge Frames.'**
  String get tutSuppliersOpenBBody;

  /// No description provided for @tutSuppliersPriceMotorBTitle.
  ///
  /// In en, this message translates to:
  /// **'A competing price'**
  String get tutSuppliersPriceMotorBTitle;

  /// No description provided for @tutSuppliersPriceMotorBBody.
  ///
  /// In en, this message translates to:
  /// **'Give this supplier a price for MOT-3P-055 too: unit price 135, lead time 5 days, minimum order quantity 1. It is dearer but faster; that is the kind of choice a price list helps with.'**
  String get tutSuppliersPriceMotorBBody;

  /// No description provided for @tutSuppliersDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutSuppliersDoneTitle;

  /// No description provided for @tutSuppliersDoneBody.
  ///
  /// In en, this message translates to:
  /// **'A supplier is a record with payment terms and contacts, and its price list links it to products with a price, a lead time and a minimum order quantity. Next: ordering the goods.'**
  String get tutSuppliersDoneBody;

  /// No description provided for @tutBuyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Buying and receiving'**
  String get tutBuyingTitle;

  /// No description provided for @tutBuyingSummary.
  ///
  /// In en, this message translates to:
  /// **'Hats: purchaser and goods-in. Order the components, send the order and receive the goods in two deliveries.'**
  String get tutBuyingSummary;

  /// No description provided for @tutBuyingNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapters 1 and 2 first'**
  String get tutBuyingNeedsTitle;

  /// No description provided for @tutBuyingNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the products of Chapter 1 (Conveyor belts & motors) and the supplier Voltaic Drives Ltd with its price list from chapter 2, and could not find the products. Finish those chapters first.'**
  String get tutBuyingNeedsBody;

  /// No description provided for @tutBuyingOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'The orders list'**
  String get tutBuyingOpenTitle;

  /// No description provided for @tutBuyingOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Open Purchasing. Next to Suppliers there is a segment for purchase orders; open it.'**
  String get tutBuyingOpenBody;

  /// No description provided for @tutBuyingOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order the components'**
  String get tutBuyingOrderTitle;

  /// No description provided for @tutBuyingOrderBody.
  ///
  /// In en, this message translates to:
  /// **'Create a purchase order for Voltaic Drives Ltd. After choosing the supplier its goods are listed: tick MOT-3P-055, VFD-3P-055 and PLC-BASE and set the quantity to 30 for each, then save. The prices come from the price list.'**
  String get tutBuyingOrderBody;

  /// No description provided for @tutBuyingOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the supplier first. Ticking a box fills in the minimum order quantity (or 1); type 30 in the quantity box instead. Use the filter box to find a product quickly.'**
  String get tutBuyingOrderHint;

  /// No description provided for @tutBuyingOpenOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'The order screen'**
  String get tutBuyingOpenOrderTitle;

  /// No description provided for @tutBuyingOpenOrderBody.
  ///
  /// In en, this message translates to:
  /// **'Open the order you just made. A purchase order is a draft first; the buttons at the top follow its life: approve, send, receive.'**
  String get tutBuyingOpenOrderBody;

  /// No description provided for @tutBuyingApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve the order'**
  String get tutBuyingApproveTitle;

  /// No description provided for @tutBuyingApproveBody.
  ///
  /// In en, this message translates to:
  /// **'Approving is a separate permission, so a purchaser can prepare orders that a manager releases. As admin you wear both hats: press Approve.'**
  String get tutBuyingApproveBody;

  /// No description provided for @tutBuyingSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send it to the supplier'**
  String get tutBuyingSendTitle;

  /// No description provided for @tutBuyingSendBody.
  ///
  /// In en, this message translates to:
  /// **'Press Send. The order is marked as sent and the supplier gets it. In test and tutorial environments outgoing mail is only written to files on the server, nothing leaves the building.'**
  String get tutBuyingSendBody;

  /// No description provided for @tutBuyingOpenWarehousesTitle.
  ///
  /// In en, this message translates to:
  /// **'Where do the goods go?'**
  String get tutBuyingOpenWarehousesTitle;

  /// No description provided for @tutBuyingOpenWarehousesBody.
  ///
  /// In en, this message translates to:
  /// **'Goods need a place before they can be received. Open Stock and press Warehouses: this is where warehouses and their locations are kept.'**
  String get tutBuyingOpenWarehousesBody;

  /// No description provided for @tutBuyingWarehouseTitle.
  ///
  /// In en, this message translates to:
  /// **'Create the warehouse'**
  String get tutBuyingWarehouseTitle;

  /// No description provided for @tutBuyingWarehouseBody.
  ///
  /// In en, this message translates to:
  /// **'Press New warehouse, give it the code MAIN and the name Main warehouse, and save. A new warehouse comes with its location MAIN, which is where you receive the goods next. If saving is refused because the code MAIN is taken, an inactive warehouse holds it: switch it (and its location) back on in Stock > Warehouses, or give it another code with its edit button, then press Next.'**
  String get tutBuyingWarehouseBody;

  /// No description provided for @tutBuyingWarehouseHint.
  ///
  /// In en, this message translates to:
  /// **'Code and name are both required. If a warehouse with a location exists already, this step is skipped.'**
  String get tutBuyingWarehouseHint;

  /// No description provided for @tutBuyingReceivePartTitle.
  ///
  /// In en, this message translates to:
  /// **'The first delivery arrives'**
  String get tutBuyingReceivePartTitle;

  /// No description provided for @tutBuyingReceivePartBody.
  ///
  /// In en, this message translates to:
  /// **'Put on the goods-in hat. Press Receive goods, choose the warehouse location MAIN and book 10 pieces of each component, fewer than ordered. The order becomes partially received.'**
  String get tutBuyingReceivePartBody;

  /// No description provided for @tutBuyingReceivePartHint.
  ///
  /// In en, this message translates to:
  /// **'Change the quantity of each line in the dialog; the remaining quantity is shown next to it. A delivery note number is optional.'**
  String get tutBuyingReceivePartHint;

  /// No description provided for @tutBuyingReceiveRestTitle.
  ///
  /// In en, this message translates to:
  /// **'The rest arrives'**
  String get tutBuyingReceiveRestTitle;

  /// No description provided for @tutBuyingReceiveRestBody.
  ///
  /// In en, this message translates to:
  /// **'Receive the remaining 20 pieces of each component the same way. When everything is in, the order is fully received; each delivery keeps its own goods receipt.'**
  String get tutBuyingReceiveRestBody;

  /// No description provided for @tutBuyingStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Look at the stock'**
  String get tutBuyingStockTitle;

  /// No description provided for @tutBuyingStockBody.
  ///
  /// In en, this message translates to:
  /// **'Open Stock. The 30 motors, VFDs and PLCs are on hand in warehouse MAIN. Every receipt created a stock movement, so the quantity can always be traced back.'**
  String get tutBuyingStockBody;

  /// No description provided for @tutBuyingDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutBuyingDoneTitle;

  /// No description provided for @tutBuyingDoneBody.
  ///
  /// In en, this message translates to:
  /// **'A purchase order goes draft, approved, sent, received. Goods can arrive in several deliveries and every delivery adds to stock. The supplier\'s invoice comes next.'**
  String get tutBuyingDoneBody;

  /// No description provided for @tutInvoicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking the invoices'**
  String get tutInvoicesTitle;

  /// No description provided for @tutInvoicesSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: accountant. Register supplier invoices, read the three-way match, approve, dispute and pay.'**
  String get tutInvoicesSummary;

  /// No description provided for @tutInvoicesNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 3 first'**
  String get tutInvoicesNeedsTitle;

  /// No description provided for @tutInvoicesNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the purchase order from chapter 3, fully received, and it is not (yet). Finish chapter 3 first.'**
  String get tutInvoicesNeedsBody;

  /// No description provided for @tutInvoicesOpenOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Back to the order'**
  String get tutInvoicesOpenOrderTitle;

  /// No description provided for @tutInvoicesOpenOrderBody.
  ///
  /// In en, this message translates to:
  /// **'The supplier\'s invoice arrives. Open the purchase order from chapter 3 again: once goods are received it offers a shortcut to register the invoice.'**
  String get tutInvoicesOpenOrderBody;

  /// No description provided for @tutInvoicesCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Register the invoice'**
  String get tutInvoicesCreateTitle;

  /// No description provided for @tutInvoicesCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Press Create supplier invoice. Type the supplier\'s own invoice number, for example TUT-INV-001, and save. The lines are filled in from what was ordered and received, so there is nothing to type.'**
  String get tutInvoicesCreateBody;

  /// No description provided for @tutInvoicesCreateHint.
  ///
  /// In en, this message translates to:
  /// **'The invoice date and due date default to today and to the payment terms of the supplier.'**
  String get tutInvoicesCreateHint;

  /// No description provided for @tutInvoicesMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The three-way match'**
  String get tutInvoicesMatchTitle;

  /// No description provided for @tutInvoicesMatchBody.
  ///
  /// In en, this message translates to:
  /// **'The banner compares three documents: what was ordered, what was received and what is invoiced, line by line. Green means they agree within the tolerances; the tolerances are shown in the banner. Press Next when you have looked.'**
  String get tutInvoicesMatchBody;

  /// No description provided for @tutInvoicesApproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve the invoice'**
  String get tutInvoicesApproveTitle;

  /// No description provided for @tutInvoicesApproveBody.
  ///
  /// In en, this message translates to:
  /// **'The match is green, so press Approve. An approved invoice is ready for payment.'**
  String get tutInvoicesApproveBody;

  /// No description provided for @tutInvoicesSecondTitle.
  ///
  /// In en, this message translates to:
  /// **'A suspicious invoice'**
  String get tutInvoicesSecondTitle;

  /// No description provided for @tutInvoicesSecondBody.
  ///
  /// In en, this message translates to:
  /// **'Now a second invoice arrives from Voltaic Drives Ltd, this time without a purchase order: in Finance, create a supplier invoice for that supplier, number TUT-INV-002, leave the order empty and add one line with description Motors, quantity 10, unit price 150.'**
  String get tutInvoicesSecondBody;

  /// No description provided for @tutInvoicesSecondHint.
  ///
  /// In en, this message translates to:
  /// **'The real motor price is 120 and this line has no order line to compare with. The app cannot change prices of an order-based invoice, so a free-text invoice is how a mismatch shows up here.'**
  String get tutInvoicesSecondHint;

  /// No description provided for @tutInvoicesMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The match fails'**
  String get tutInvoicesMismatchTitle;

  /// No description provided for @tutInvoicesMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'The banner is orange: a free-text line has nothing it can be matched against, so it cannot be checked against an order or a receipt. The line shows why. Press Next when you have looked.'**
  String get tutInvoicesMismatchBody;

  /// No description provided for @tutInvoicesDisputeTitle.
  ///
  /// In en, this message translates to:
  /// **'Dispute the invoice'**
  String get tutInvoicesDisputeTitle;

  /// No description provided for @tutInvoicesDisputeBody.
  ///
  /// In en, this message translates to:
  /// **'Press Dispute and give a reason, for example price does not match the agreement. A disputed invoice cannot be paid until it is reopened. (An approver can also approve a failed match with an override reason, which is kept on the invoice.)'**
  String get tutInvoicesDisputeBody;

  /// No description provided for @tutInvoicesTolerancesTitle.
  ///
  /// In en, this message translates to:
  /// **'The tolerances'**
  String get tutInvoicesTolerancesTitle;

  /// No description provided for @tutInvoicesTolerancesBody.
  ///
  /// In en, this message translates to:
  /// **'How far an invoice may differ is a setting: open the Settings segment of Finance to see the quantity and price tolerances in percent. Look, then press Next; changing them is up to you.'**
  String get tutInvoicesTolerancesBody;

  /// No description provided for @tutInvoicesPayTitle.
  ///
  /// In en, this message translates to:
  /// **'Pay the good invoice'**
  String get tutInvoicesPayTitle;

  /// No description provided for @tutInvoicesPayBody.
  ///
  /// In en, this message translates to:
  /// **'Open the first supplier invoice you registered (the one that matched and was approved) and press Mark as paid. Enter a payment reference such as TUT-PAY-001. The app records the payment; the bank transfer itself happens elsewhere.'**
  String get tutInvoicesPayBody;

  /// No description provided for @tutInvoicesDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutInvoicesDoneTitle;

  /// No description provided for @tutInvoicesDoneBody.
  ///
  /// In en, this message translates to:
  /// **'The three-way match compares order, receipt and invoice before money moves. Matching invoices are approved and paid, doubtful ones are disputed. Next: building the conveyors yourself.'**
  String get tutInvoicesDoneBody;

  /// No description provided for @tutManufacturingTitle.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing'**
  String get tutManufacturingTitle;

  /// No description provided for @tutManufacturingSummary.
  ///
  /// In en, this message translates to:
  /// **'Hats: production manager and production worker. Set up a division, then build five conveyors from the components.'**
  String get tutManufacturingSummary;

  /// No description provided for @tutManufacturingNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapters 1 to 3 first'**
  String get tutManufacturingNeedsTitle;

  /// No description provided for @tutManufacturingNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the conveyor with its bill of materials (Chapter 1 (Conveyor belts & motors)) and components in stock (chapter 3), and could not find the products. Finish those chapters first.'**
  String get tutManufacturingNeedsBody;

  /// No description provided for @tutManufacturingOpenDivisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Divisions'**
  String get tutManufacturingOpenDivisionsTitle;

  /// No description provided for @tutManufacturingOpenDivisionsBody.
  ///
  /// In en, this message translates to:
  /// **'Production work is organised in divisions, for example an assembly line. Only an administrator defines them. Open Production and use the gear button at the top right to reach the divisions.'**
  String get tutManufacturingOpenDivisionsBody;

  /// No description provided for @tutManufacturingDivisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a division'**
  String get tutManufacturingDivisionTitle;

  /// No description provided for @tutManufacturingDivisionBody.
  ///
  /// In en, this message translates to:
  /// **'Add a division with code TUT-ASM and name Tutorial assembly, and tick yourself in the member list: members are the workers of the division.'**
  String get tutManufacturingDivisionBody;

  /// No description provided for @tutManufacturingDivisionHint.
  ///
  /// In en, this message translates to:
  /// **'The dialog lists the users of the company; tick the chip with your own name.'**
  String get tutManufacturingDivisionHint;

  /// No description provided for @tutManufacturingQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'The production queue'**
  String get tutManufacturingQueueTitle;

  /// No description provided for @tutManufacturingQueueBody.
  ///
  /// In en, this message translates to:
  /// **'Go back to Production. In the queue header choose My divisions: it shows the orders of your divisions plus orders without a division, so nothing unassigned is hidden. You are a member of a division, so this is the default for you; choose All divisions to see everything.'**
  String get tutManufacturingQueueBody;

  /// No description provided for @tutManufacturingReleaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Release a production order'**
  String get tutManufacturingReleaseTitle;

  /// No description provided for @tutManufacturingReleaseBody.
  ///
  /// In en, this message translates to:
  /// **'Press Build for stock, choose CONV-BELT-1M and quantity 5, and release. The bill of materials is frozen and the components are reserved. Normally production starts from a sales order line; you will see that in chapter 9.'**
  String get tutManufacturingReleaseBody;

  /// No description provided for @tutManufacturingReleaseHint.
  ///
  /// In en, this message translates to:
  /// **'Only manufactured products with an active bill of materials can be released.'**
  String get tutManufacturingReleaseHint;

  /// No description provided for @tutManufacturingAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'Give it to the division'**
  String get tutManufacturingAssignTitle;

  /// No description provided for @tutManufacturingAssignBody.
  ///
  /// In en, this message translates to:
  /// **'The new order is open. Choose the division Tutorial assembly in the Division field and press Save, so that the order shows up in the queue of that division.'**
  String get tutManufacturingAssignBody;

  /// No description provided for @tutManufacturingStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Start the work'**
  String get tutManufacturingStartTitle;

  /// No description provided for @tutManufacturingStartBody.
  ///
  /// In en, this message translates to:
  /// **'Put on the worker hat and press Start. The order moves from released to in progress.'**
  String get tutManufacturingStartBody;

  /// No description provided for @tutManufacturingWarehouseTitle.
  ///
  /// In en, this message translates to:
  /// **'A place for the conveyors'**
  String get tutManufacturingWarehouseTitle;

  /// No description provided for @tutManufacturingWarehouseBody.
  ///
  /// In en, this message translates to:
  /// **'The finished conveyors need a location to go into, and there is no warehouse yet (chapter 3 creates it). Open Stock, press Warehouses and create the warehouse MAIN with the name Main warehouse, then go back to the production order. If saving is refused because the code MAIN is taken, an inactive warehouse holds it: switch it (and its location) back on in Stock > Warehouses, or give it another code with its edit button, then press Next.'**
  String get tutManufacturingWarehouseBody;

  /// No description provided for @tutManufacturingWarehouseHint.
  ///
  /// In en, this message translates to:
  /// **'The location MAIN is created together with the warehouse. If a warehouse with a location exists already, this step is skipped.'**
  String get tutManufacturingWarehouseHint;

  /// No description provided for @tutManufacturingCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete the order'**
  String get tutManufacturingCompleteTitle;

  /// No description provided for @tutManufacturingCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Press Complete. The dialog shows the output quantity (5) and the components consumed. Choose the warehouse location MAIN in Put into, so the finished conveyors have a place to go, and confirm: the components leave the stock and five finished conveyors enter it.'**
  String get tutManufacturingCompleteBody;

  /// No description provided for @tutManufacturingCompleteHint.
  ///
  /// In en, this message translates to:
  /// **'Leave the planned values as they are; the dialog lets you record scrap or extra consumption when reality differs.'**
  String get tutManufacturingCompleteHint;

  /// No description provided for @tutManufacturingStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the stock'**
  String get tutManufacturingStockTitle;

  /// No description provided for @tutManufacturingStockBody.
  ///
  /// In en, this message translates to:
  /// **'Open Stock: CONV-BELT-1M now has 5 on hand, its BOM components (MOT-3P-055 and VFD-3P-055) are down by 5 (25 left of each), and PLC-BASE remains at 30. Production is what links purchasing to selling.'**
  String get tutManufacturingStockBody;

  /// No description provided for @tutManufacturingDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutManufacturingDoneTitle;

  /// No description provided for @tutManufacturingDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Divisions group production workers; a production order freezes the bill of materials, reserves components, is started and completed, and turns components into finished goods. Next: prices.'**
  String get tutManufacturingDoneBody;

  /// No description provided for @tutPricesTitle.
  ///
  /// In en, this message translates to:
  /// **'Prices and zones'**
  String get tutPricesTitle;

  /// No description provided for @tutPricesSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: sales manager. Create a price zone and give the conveyor a price in two zones.'**
  String get tutPricesSummary;

  /// No description provided for @tutPricesNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 1 first'**
  String get tutPricesNeedsTitle;

  /// No description provided for @tutPricesNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the conveyor from Chapter 1 (Conveyor belts & motors) and could not find it. Finish Chapter 1 (Conveyor belts & motors) first.'**
  String get tutPricesNeedsBody;

  /// No description provided for @tutPricesOpenAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the admin area'**
  String get tutPricesOpenAdminTitle;

  /// No description provided for @tutPricesOpenAdminBody.
  ///
  /// In en, this message translates to:
  /// **'A price depends on the customer\'s zone: a country or market with its own price list. Zones are managed under Admin. Open Admin and choose the Price zones segment; the company already has zones Z1 to Z5.'**
  String get tutPricesOpenAdminBody;

  /// No description provided for @tutPricesZoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a zone'**
  String get tutPricesZoneTitle;

  /// No description provided for @tutPricesZoneBody.
  ///
  /// In en, this message translates to:
  /// **'Add a price zone with code TUT-EXPORT and name Export zone. Customers are placed in a zone later, when you create one.'**
  String get tutPricesZoneBody;

  /// No description provided for @tutPricesZoneHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the Price zones segment at the top of the Admin page first.'**
  String get tutPricesZoneHint;

  /// No description provided for @tutPricesOpenCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the conveyor'**
  String get tutPricesOpenCartTitle;

  /// No description provided for @tutPricesOpenCartBody.
  ///
  /// In en, this message translates to:
  /// **'Open the product CONV-BELT-1M from the Products list. Its first tab, Prices, holds the prices per zone.'**
  String get tutPricesOpenCartBody;

  /// No description provided for @tutPricesPriceExportTitle.
  ///
  /// In en, this message translates to:
  /// **'A price in the new zone'**
  String get tutPricesPriceExportTitle;

  /// No description provided for @tutPricesPriceExportBody.
  ///
  /// In en, this message translates to:
  /// **'Press New price, choose zone TUT-EXPORT, enter unit price 1450 (excluding VAT) and save.'**
  String get tutPricesPriceExportBody;

  /// No description provided for @tutPricesPriceExportHint.
  ///
  /// In en, this message translates to:
  /// **'The valid-from date defaults to today; a later date schedules a price change.'**
  String get tutPricesPriceExportHint;

  /// No description provided for @tutPricesPriceHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A price in another zone'**
  String get tutPricesPriceHomeTitle;

  /// No description provided for @tutPricesPriceHomeBody.
  ///
  /// In en, this message translates to:
  /// **'Add a second price for the conveyor in one of the existing zones, for example Z1 at 1200. The same product can now cost different amounts depending on the customer\'s zone.'**
  String get tutPricesPriceHomeBody;

  /// No description provided for @tutPricesDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutPricesDoneTitle;

  /// No description provided for @tutPricesDoneBody.
  ///
  /// In en, this message translates to:
  /// **'A price zone groups customers that get the same price list, and a product has one price per zone and date. Quotations pick the price of the customer\'s zone. Next: a new customer writes in.'**
  String get tutPricesDoneBody;

  /// No description provided for @tutCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'A new customer writes in'**
  String get tutCustomerTitle;

  /// No description provided for @tutCustomerSummary.
  ///
  /// In en, this message translates to:
  /// **'Hats: sales and helpdesk. A customer e-mail becomes a ticket; the sender is new, so you ask for company details and create the customer.'**
  String get tutCustomerSummary;

  /// No description provided for @tutCustomerNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 6 first'**
  String get tutCustomerNeedsTitle;

  /// No description provided for @tutCustomerNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the price zone TUT-EXPORT from chapter 6 (the new customer gets it) and could not find it. Finish the earlier chapters first.'**
  String get tutCustomerNeedsBody;

  /// No description provided for @tutCustomerMail1Title.
  ///
  /// In en, this message translates to:
  /// **'An e-mail arrives'**
  String get tutCustomerMail1Title;

  /// No description provided for @tutCustomerMail1Body.
  ///
  /// In en, this message translates to:
  /// **'Someone you do not know asks for a quotation for your conveyor. A real mailbox would deliver the message by itself; here the button below plays the customer and hands a ready-made e-mail (from Maya Okafor, example.test) to the helpdesk, exactly as the mail importer does.'**
  String get tutCustomerMail1Body;

  /// No description provided for @tutCustomerMail1Action.
  ///
  /// In en, this message translates to:
  /// **'Simulate customer e-mail'**
  String get tutCustomerMail1Action;

  /// No description provided for @tutCustomerOpenHelpdeskTitle.
  ///
  /// In en, this message translates to:
  /// **'The ticket'**
  String get tutCustomerOpenHelpdeskTitle;

  /// No description provided for @tutCustomerOpenHelpdeskBody.
  ///
  /// In en, this message translates to:
  /// **'Every incoming message becomes a ticket. Open Helpdesk: the ticket from Maya Okafor is in the list.'**
  String get tutCustomerOpenHelpdeskBody;

  /// No description provided for @tutCustomerOpenTicketTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the ticket'**
  String get tutCustomerOpenTicketTitle;

  /// No description provided for @tutCustomerOpenTicketBody.
  ///
  /// In en, this message translates to:
  /// **'Open the ticket. The conversation is on the left; on the right are its properties. No customer is linked yet, because nobody with this address exists in the system.'**
  String get tutCustomerOpenTicketBody;

  /// No description provided for @tutCustomerReplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for company details'**
  String get tutCustomerReplyTitle;

  /// No description provided for @tutCustomerReplyBody.
  ///
  /// In en, this message translates to:
  /// **'Reply to Maya: thank her and ask for the company name, VAT number and address, then press Send. The reply is queued for the mail worker. In test and tutorial environments outgoing mail is only written to files on the server, so Maya never receives it.'**
  String get tutCustomerReplyBody;

  /// No description provided for @tutCustomerReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Make sure the Reply tab (not Internal note) is selected above the message box.'**
  String get tutCustomerReplyHint;

  /// No description provided for @tutCustomerMail2Title.
  ///
  /// In en, this message translates to:
  /// **'The customer answers'**
  String get tutCustomerMail2Title;

  /// No description provided for @tutCustomerMail2Body.
  ///
  /// In en, this message translates to:
  /// **'Use the button to play Maya\'s answer. It is a reply to her first message, so it lands in the same ticket as a new message, with her company name, VAT number and address.'**
  String get tutCustomerMail2Body;

  /// No description provided for @tutCustomerMail2Action.
  ///
  /// In en, this message translates to:
  /// **'Simulate customer e-mail'**
  String get tutCustomerMail2Action;

  /// No description provided for @tutCustomerReadDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Read the details'**
  String get tutCustomerReadDetailsTitle;

  /// No description provided for @tutCustomerReadDetailsBody.
  ///
  /// In en, this message translates to:
  /// **'Go back to the ticket (reopen it if it does not show the new message yet) and read Maya\'s answer: company Brightwheel Logistics BV, VAT number BE0123456749, Voorbeeldlaan 12, 9000 Gent, Belgium. Press Next when you have it.'**
  String get tutCustomerReadDetailsBody;

  /// No description provided for @tutCustomerCreateCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create the customer'**
  String get tutCustomerCreateCustomerTitle;

  /// No description provided for @tutCustomerCreateCustomerBody.
  ///
  /// In en, this message translates to:
  /// **'In the ticket properties press New customer. Fill in name Brightwheel Logistics BV, a code such as TUT-CUST, VAT number, the address, and choose the price zone TUT-EXPORT. The ticket is linked to the new customer when you save.'**
  String get tutCustomerCreateCustomerBody;

  /// No description provided for @tutCustomerCreateCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Street Voorbeeldlaan 12, postal code 9000, city Gent, country BE. Language and payment terms can stay as they are.'**
  String get tutCustomerCreateCustomerHint;

  /// No description provided for @tutCustomerLinkedTitle.
  ///
  /// In en, this message translates to:
  /// **'Link the customer'**
  String get tutCustomerLinkedTitle;

  /// No description provided for @tutCustomerLinkedBody.
  ///
  /// In en, this message translates to:
  /// **'The ticket should link the new customer automatically. If it does not, select Brightwheel Logistics BV in the Customer field and press Save changes. The tutorial continues when the link is saved.'**
  String get tutCustomerLinkedBody;

  /// No description provided for @tutCustomerDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutCustomerDoneTitle;

  /// No description provided for @tutCustomerDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Incoming mail becomes tickets, a reply asks the customer for what is missing, and a customer can be created from the ticket so that everything stays linked. Next: the quotation.'**
  String get tutCustomerDoneBody;

  /// No description provided for @tutQuotationTitle.
  ///
  /// In en, this message translates to:
  /// **'The quotation'**
  String get tutQuotationTitle;

  /// No description provided for @tutQuotationSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: salesperson. Quote 8 conveyors to the new customer, get an answer from production on timing and send it.'**
  String get tutQuotationSummary;

  /// No description provided for @tutQuotationNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 7 first'**
  String get tutQuotationNeedsTitle;

  /// No description provided for @tutQuotationNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the customer Brightwheel Logistics BV from chapter 7 and could not find it. Finish chapter 7 first.'**
  String get tutQuotationNeedsBody;

  /// No description provided for @tutQuotationOpenQuotationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quotations'**
  String get tutQuotationOpenQuotationsTitle;

  /// No description provided for @tutQuotationOpenQuotationsBody.
  ///
  /// In en, this message translates to:
  /// **'Open Quotations in the menu. This list holds every quotation with its number, customer and status.'**
  String get tutQuotationOpenQuotationsBody;

  /// No description provided for @tutQuotationCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Write the quotation'**
  String get tutQuotationCreateTitle;

  /// No description provided for @tutQuotationCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Press New quotation, choose Brightwheel Logistics BV, add CONV-BELT-1M with quantity 8 and save the draft. The unit price comes from the customer\'s price zone, TUT-EXPORT, so it is the 1450 you entered in chapter 6.'**
  String get tutQuotationCreateBody;

  /// No description provided for @tutQuotationCreateHint.
  ///
  /// In en, this message translates to:
  /// **'Use the product search in the lines section; type CONV-BELT-1M. If the customer is not preselected, search for Brightwheel.'**
  String get tutQuotationCreateHint;

  /// No description provided for @tutQuotationLeadTitle.
  ///
  /// In en, this message translates to:
  /// **'How long will it take?'**
  String get tutQuotationLeadTitle;

  /// No description provided for @tutQuotationLeadBody.
  ///
  /// In en, this message translates to:
  /// **'The customer asked for a delivery time. Honestly: the app does not calculate lead times automatically yet, and a quotation has no delivery date field. So ask production (put on that hat, look at the production queue and the components in stock) and write the answer into the quotation\'s notes, for example: Delivery about 3 weeks after order. Save the draft.'**
  String get tutQuotationLeadBody;

  /// No description provided for @tutQuotationLeadHint.
  ///
  /// In en, this message translates to:
  /// **'On an order you can send production a question as a ticket (you will see that in chapter 9); quotations do not have that button yet.'**
  String get tutQuotationLeadHint;

  /// No description provided for @tutQuotationSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send the quotation'**
  String get tutQuotationSendTitle;

  /// No description provided for @tutQuotationSendBody.
  ///
  /// In en, this message translates to:
  /// **'Press Mark as sent. From now on the quotation is frozen: it can only be accepted, rejected or revised. (Mail is not sent from this button; you would send the PDF yourself or reply in the ticket.)'**
  String get tutQuotationSendBody;

  /// No description provided for @tutQuotationPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'The PDF'**
  String get tutQuotationPdfTitle;

  /// No description provided for @tutQuotationPdfBody.
  ///
  /// In en, this message translates to:
  /// **'The PDF button shows the quotation as the customer would see it. It is made on the server with a typesetting tool; on a server without it you get an error message, which does not affect anything else. Look if you like, then press Next.'**
  String get tutQuotationPdfBody;

  /// No description provided for @tutQuotationPdfHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing breaks if the PDF fails: the quotation is already sent.'**
  String get tutQuotationPdfHint;

  /// No description provided for @tutQuotationDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutQuotationDoneTitle;

  /// No description provided for @tutQuotationDoneBody.
  ///
  /// In en, this message translates to:
  /// **'A quotation takes the price of the customer\'s zone, carries notes and freezes when it is sent. Delivery times are still your judgement call, together with production. Next: the customer wants a change.'**
  String get tutQuotationDoneBody;

  /// No description provided for @tutChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change, order, production'**
  String get tutChangeTitle;

  /// No description provided for @tutChangeSummary.
  ///
  /// In en, this message translates to:
  /// **'Hats: sales and production. Revise the quotation, turn it into an order, build the conveyors and a few extra for stock.'**
  String get tutChangeSummary;

  /// No description provided for @tutChangeNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 8 first'**
  String get tutChangeNeedsTitle;

  /// No description provided for @tutChangeNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter needs the sent quotation from chapter 8 and could not find it. Finish chapter 8 first.'**
  String get tutChangeNeedsBody;

  /// No description provided for @tutChangeMail3Title.
  ///
  /// In en, this message translates to:
  /// **'The customer answers again'**
  String get tutChangeMail3Title;

  /// No description provided for @tutChangeMail3Body.
  ///
  /// In en, this message translates to:
  /// **'Maya is happy with the quotation but wants 10 conveyors instead of 8. Use the button to play her e-mail; it joins the same ticket.'**
  String get tutChangeMail3Body;

  /// No description provided for @tutChangeMail3Action.
  ///
  /// In en, this message translates to:
  /// **'Simulate customer e-mail'**
  String get tutChangeMail3Action;

  /// No description provided for @tutChangeOpenQuoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the sent quotation'**
  String get tutChangeOpenQuoteTitle;

  /// No description provided for @tutChangeOpenQuoteBody.
  ///
  /// In en, this message translates to:
  /// **'A sent quotation is frozen, so a change means a new revision. Open the quotation from chapter 8.'**
  String get tutChangeOpenQuoteBody;

  /// No description provided for @tutChangeReviseTitle.
  ///
  /// In en, this message translates to:
  /// **'Make a revision'**
  String get tutChangeReviseTitle;

  /// No description provided for @tutChangeReviseBody.
  ///
  /// In en, this message translates to:
  /// **'Press New revision and choose Keep agreed prices. The old revision is marked superseded and a new draft with the same number opens.'**
  String get tutChangeReviseBody;

  /// No description provided for @tutChangeReviseHint.
  ///
  /// In en, this message translates to:
  /// **'Update to current prices would reprice at today\'s price list; here the customer keeps the agreed price.'**
  String get tutChangeReviseHint;

  /// No description provided for @tutChangeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Change the quantity'**
  String get tutChangeEditTitle;

  /// No description provided for @tutChangeEditBody.
  ///
  /// In en, this message translates to:
  /// **'Set the quantity of CONV-BELT-1M to 10 and save the draft.'**
  String get tutChangeEditBody;

  /// No description provided for @tutChangeEditHint.
  ///
  /// In en, this message translates to:
  /// **'The notes of the first revision were copied; adjust them if the delivery time changes.'**
  String get tutChangeEditHint;

  /// No description provided for @tutChangeSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send the revision'**
  String get tutChangeSendTitle;

  /// No description provided for @tutChangeSendBody.
  ///
  /// In en, this message translates to:
  /// **'Mark the new revision as sent, as before.'**
  String get tutChangeSendBody;

  /// No description provided for @tutChangeAcceptTitle.
  ///
  /// In en, this message translates to:
  /// **'The customer accepts'**
  String get tutChangeAcceptTitle;

  /// No description provided for @tutChangeAcceptBody.
  ///
  /// In en, this message translates to:
  /// **'Maya agrees with the new revision: press Accepted to record it.'**
  String get tutChangeAcceptBody;

  /// No description provided for @tutChangeConvertTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn it into a sales order'**
  String get tutChangeConvertTitle;

  /// No description provided for @tutChangeConvertBody.
  ///
  /// In en, this message translates to:
  /// **'Press Convert to order. A draft sales order is created from the accepted revision and opens.'**
  String get tutChangeConvertBody;

  /// No description provided for @tutChangeConvertHint.
  ///
  /// In en, this message translates to:
  /// **'The dialog asks for the customer\'s own reference; type for instance TUT-PO-1 or leave it empty.'**
  String get tutChangeConvertHint;

  /// No description provided for @tutChangeOpenOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'The sales order'**
  String get tutChangeOpenOrderTitle;

  /// No description provided for @tutChangeOpenOrderBody.
  ///
  /// In en, this message translates to:
  /// **'If the order did not open by itself, open it from Orders. It has the 10 conveyors, the price and the customer reference. Orders go from draft to sent to confirmed.'**
  String get tutChangeOpenOrderBody;

  /// No description provided for @tutChangeSendOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Send the order confirmation'**
  String get tutChangeSendOrderTitle;

  /// No description provided for @tutChangeSendOrderBody.
  ///
  /// In en, this message translates to:
  /// **'Press Send order confirmation. The order becomes sent: the customer can now confirm it.'**
  String get tutChangeSendOrderBody;

  /// No description provided for @tutChangeSendOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Making the confirmation document needs the server\'s typesetting tool; if it is missing the server refuses this step and a server with the tool is needed to continue.'**
  String get tutChangeSendOrderHint;

  /// No description provided for @tutChangeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm on the customer\'s behalf'**
  String get tutChangeConfirmTitle;

  /// No description provided for @tutChangeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Maya already said yes by e-mail, so press Confirm on behalf and add a note such as confirmed by e-mail. The order is now confirmed and can go to production.'**
  String get tutChangeConfirmBody;

  /// No description provided for @tutChangeReleaseTitle.
  ///
  /// In en, this message translates to:
  /// **'To release'**
  String get tutChangeReleaseTitle;

  /// No description provided for @tutChangeReleaseBody.
  ///
  /// In en, this message translates to:
  /// **'Put on the production hat. Open Production > To release: the confirmed order line with 10 conveyors is waiting. Press Release to production to create the production order for exactly that line.'**
  String get tutChangeReleaseBody;

  /// No description provided for @tutChangeStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Start production'**
  String get tutChangeStartTitle;

  /// No description provided for @tutChangeStartBody.
  ///
  /// In en, this message translates to:
  /// **'Press Start on the new production order.'**
  String get tutChangeStartBody;

  /// No description provided for @tutChangeWarehouseTitle.
  ///
  /// In en, this message translates to:
  /// **'A place for the conveyors'**
  String get tutChangeWarehouseTitle;

  /// No description provided for @tutChangeWarehouseBody.
  ///
  /// In en, this message translates to:
  /// **'The finished conveyors need a location to go into, and there is no warehouse yet (chapter 3 creates it). Open Stock, press Warehouses and create the warehouse MAIN with the name Main warehouse, then go back to the production order. If saving is refused because the code MAIN is taken, an inactive warehouse holds it: switch it (and its location) back on in Stock > Warehouses, or give it another code with its edit button, then press Next.'**
  String get tutChangeWarehouseBody;

  /// No description provided for @tutChangeWarehouseHint.
  ///
  /// In en, this message translates to:
  /// **'The location MAIN is created together with the warehouse. If a warehouse with a location exists already, this step is skipped.'**
  String get tutChangeWarehouseHint;

  /// No description provided for @tutChangeCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete production'**
  String get tutChangeCompleteTitle;

  /// No description provided for @tutChangeCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Press Complete, choose the warehouse location MAIN in Put into and confirm the 10 conveyors. The components are consumed and the conveyors go to the order.'**
  String get tutChangeCompleteBody;

  /// No description provided for @tutChangeReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready for shipping'**
  String get tutChangeReadyTitle;

  /// No description provided for @tutChangeReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Open the order again: with all its lines produced it is ready for shipping. Delivery (picking, shipping, invoicing the customer) is outside this tutorial. Press Next.'**
  String get tutChangeReadyBody;

  /// No description provided for @tutChangeStockTitle.
  ///
  /// In en, this message translates to:
  /// **'A few extra for stock'**
  String get tutChangeStockTitle;

  /// No description provided for @tutChangeStockBody.
  ///
  /// In en, this message translates to:
  /// **'Production is often ahead of orders. Open Production, press Build for stock and release 4 more conveyors of CONV-BELT-1M. Without an order they simply land in stock when completed.'**
  String get tutChangeStockBody;

  /// No description provided for @tutChangeStockHint.
  ///
  /// In en, this message translates to:
  /// **'You can start and complete that order as in chapter 5, or leave it released.'**
  String get tutChangeStockHint;

  /// No description provided for @tutChangeDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Well done: the whole story'**
  String get tutChangeDoneTitle;

  /// No description provided for @tutChangeDoneBody.
  ///
  /// In en, this message translates to:
  /// **'You went from suppliers to purchasing, invoices, production, prices, a ticket, a new customer, a revised quotation, an order and production for the order and for stock. Where next: deliveries and shipping, repairs, field service and the reports each have their own menu entry. Any chapter can be replayed from the chapter map; steps that are already done are skipped.'**
  String get tutChangeDoneBody;

  /// No description provided for @tutHelpdeskTitle.
  ///
  /// In en, this message translates to:
  /// **'Working a ticket'**
  String get tutHelpdeskTitle;

  /// No description provided for @tutHelpdeskSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: helpdesk agent. On the ticket from chapter 7: an internal note, a tag, time spent and an escalation.'**
  String get tutHelpdeskSummary;

  /// No description provided for @tutHelpdeskNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter 7 first'**
  String get tutHelpdeskNeedsTitle;

  /// No description provided for @tutHelpdeskNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter works on the ticket Maya\'s e-mail created in chapter 7 and could not find it. Finish chapter 7 first.'**
  String get tutHelpdeskNeedsBody;

  /// No description provided for @tutHelpdeskNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave an internal note'**
  String get tutHelpdeskNoteTitle;

  /// No description provided for @tutHelpdeskNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Open the ticket, switch to Internal note and write what a colleague needs to know, for example that the customer wants a quotation for 8 conveyors. Press Add note. The customer never sees a note.'**
  String get tutHelpdeskNoteBody;

  /// No description provided for @tutHelpdeskNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Choose Internal note above the message box; with Reply selected the text would go to the customer.'**
  String get tutHelpdeskNoteHint;

  /// No description provided for @tutHelpdeskTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a tag'**
  String get tutHelpdeskTagTitle;

  /// No description provided for @tutHelpdeskTagBody.
  ///
  /// In en, this message translates to:
  /// **'Tags group tickets for lists and reports. Add the tag \"quotation\" to this ticket in the details panel.'**
  String get tutHelpdeskTagBody;

  /// No description provided for @tutHelpdeskTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Log the time you spent'**
  String get tutHelpdeskTimeTitle;

  /// No description provided for @tutHelpdeskTimeBody.
  ///
  /// In en, this message translates to:
  /// **'Add a time entry of 15 minutes with a short note. Mark it billable if the customer would be charged for it.'**
  String get tutHelpdeskTimeBody;

  /// No description provided for @tutHelpdeskEscalateTitle.
  ///
  /// In en, this message translates to:
  /// **'Escalate the ticket'**
  String get tutHelpdeskEscalateTitle;

  /// No description provided for @tutHelpdeskEscalateBody.
  ///
  /// In en, this message translates to:
  /// **'Some tickets need more attention than you can give. Escalate this one: give a reason, choose a person or a team and, if you like, raise the priority one step. They are told at once.'**
  String get tutHelpdeskEscalateBody;

  /// No description provided for @tutHelpdeskEscalateHint.
  ///
  /// In en, this message translates to:
  /// **'In the ticket details, scroll to Actions and choose Escalate. On a narrow screen, open Ticket details first. A reason is required.'**
  String get tutHelpdeskEscalateHint;

  /// No description provided for @tutHelpdeskTourTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepared answers'**
  String get tutHelpdeskTourTitle;

  /// No description provided for @tutHelpdeskTourBody.
  ///
  /// In en, this message translates to:
  /// **'This is where the team keeps prepared answers: reusable replies per team and language that the ticket suggests while you write. Reports, automation rules and settings (business hours, SLA, mailboxes) sit next to it. Look around, then press Next.'**
  String get tutHelpdeskTourBody;

  /// No description provided for @tutHelpdeskDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'What you learned'**
  String get tutHelpdeskDoneTitle;

  /// No description provided for @tutHelpdeskDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Internal notes stay inside, tags and time entries make the work visible in lists and reports, and an escalation puts the ticket in front of the right person.'**
  String get tutHelpdeskDoneBody;

  /// No description provided for @tutInvoicesOpenSecondTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the suspicious invoice'**
  String get tutInvoicesOpenSecondTitle;

  /// No description provided for @tutInvoicesOpenSecondBody.
  ///
  /// In en, this message translates to:
  /// **'Open invoice TUT-INV-002, the one you just registered, from the list in Finance.'**
  String get tutInvoicesOpenSecondBody;

  /// No description provided for @adminIdentityProviders.
  ///
  /// In en, this message translates to:
  /// **'Identity providers'**
  String get adminIdentityProviders;

  /// No description provided for @idpIntro.
  ///
  /// In en, this message translates to:
  /// **'Identity providers decide who can sign in to TradoCraft. People are still created in the ERP; the provider only proves who someone is.'**
  String get idpIntro;

  /// No description provided for @idpPrimaryCompany.
  ///
  /// In en, this message translates to:
  /// **'Primary company: {name}'**
  String idpPrimaryCompany(String name);

  /// No description provided for @idpPrimaryNote.
  ///
  /// In en, this message translates to:
  /// **'Only administrators of the installation\'s primary company can change these settings.'**
  String get idpPrimaryNote;

  /// No description provided for @idpReadOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'You are not an administrator of the installation\'s primary company, so these settings are not available to you. Ask an administrator of that company.'**
  String get idpReadOnlyNotice;

  /// No description provided for @idpAdd.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get idpAdd;

  /// No description provided for @idpNone.
  ///
  /// In en, this message translates to:
  /// **'No identity providers configured yet.'**
  String get idpNone;

  /// No description provided for @idpEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get idpEnabled;

  /// No description provided for @idpDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get idpDisabled;

  /// No description provided for @idpSourceEnv.
  ///
  /// In en, this message translates to:
  /// **'Server environment'**
  String get idpSourceEnv;

  /// No description provided for @idpSourceDatabase.
  ///
  /// In en, this message translates to:
  /// **'Saved in the app'**
  String get idpSourceDatabase;

  /// No description provided for @idpEnvExplain.
  ///
  /// In en, this message translates to:
  /// **'Set by the server\'s OIDC_ISSUER / OIDC_AUDIENCE. It cannot be changed here; it stays available as an emergency fallback.'**
  String get idpEnvExplain;

  /// No description provided for @idpRuleVerified.
  ///
  /// In en, this message translates to:
  /// **'Links people by e-mail when the claim {claim} is true'**
  String idpRuleVerified(String claim);

  /// No description provided for @idpRuleTrust.
  ///
  /// In en, this message translates to:
  /// **'Links people by e-mail and trusts the provider\'s address'**
  String get idpRuleTrust;

  /// No description provided for @idpRuleSubject.
  ///
  /// In en, this message translates to:
  /// **'Only existing subjects: no linking by e-mail'**
  String get idpRuleSubject;

  /// No description provided for @idpRuleDomains.
  ///
  /// In en, this message translates to:
  /// **'only for {domains}'**
  String idpRuleDomains(String domains);

  /// No description provided for @idpAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add identity provider'**
  String get idpAddTitle;

  /// No description provided for @idpEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit identity provider'**
  String get idpEditTitle;

  /// No description provided for @idpPreset.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get idpPreset;

  /// No description provided for @idpPresetEntra.
  ///
  /// In en, this message translates to:
  /// **'Microsoft Entra ID'**
  String get idpPresetEntra;

  /// No description provided for @idpPresetGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get idpPresetGoogle;

  /// No description provided for @idpPresetGeneric.
  ///
  /// In en, this message translates to:
  /// **'Generic OpenID Connect'**
  String get idpPresetGeneric;

  /// No description provided for @idpTenantId.
  ///
  /// In en, this message translates to:
  /// **'Tenant id (directory id)'**
  String get idpTenantId;

  /// No description provided for @idpAudienceEntraHint.
  ///
  /// In en, this message translates to:
  /// **'The application (client) id of your Entra app registration'**
  String get idpAudienceEntraHint;

  /// No description provided for @idpFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get idpFieldName;

  /// No description provided for @idpFieldIssuer.
  ///
  /// In en, this message translates to:
  /// **'Issuer URL'**
  String get idpFieldIssuer;

  /// No description provided for @idpFieldAudience.
  ///
  /// In en, this message translates to:
  /// **'Audience'**
  String get idpFieldAudience;

  /// No description provided for @idpFieldClientId.
  ///
  /// In en, this message translates to:
  /// **'Client id (public client, no secret)'**
  String get idpFieldClientId;

  /// No description provided for @idpFieldScopes.
  ///
  /// In en, this message translates to:
  /// **'Scopes'**
  String get idpFieldScopes;

  /// No description provided for @idpFieldTokenUse.
  ///
  /// In en, this message translates to:
  /// **'Token to send (not used for sign-in yet)'**
  String get idpFieldTokenUse;

  /// No description provided for @idpTokenUseIdTitle.
  ///
  /// In en, this message translates to:
  /// **'ID token'**
  String get idpTokenUseIdTitle;

  /// No description provided for @idpTokenUseIdBody.
  ///
  /// In en, this message translates to:
  /// **'Default. Works with Keycloak and most OpenID Connect providers: the audience is the client id.'**
  String get idpTokenUseIdBody;

  /// No description provided for @idpTokenUseAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get idpTokenUseAccessTitle;

  /// No description provided for @idpTokenUseAccessBody.
  ///
  /// In en, this message translates to:
  /// **'For Microsoft Entra ID: the access token of your own API (scope api://<client-id>/access_as_user).'**
  String get idpTokenUseAccessBody;

  /// No description provided for @idpFieldEmailClaim.
  ///
  /// In en, this message translates to:
  /// **'E-mail claim'**
  String get idpFieldEmailClaim;

  /// No description provided for @idpFieldVerifiedClaim.
  ///
  /// In en, this message translates to:
  /// **'Verified claim'**
  String get idpFieldVerifiedClaim;

  /// No description provided for @idpFieldDomains.
  ///
  /// In en, this message translates to:
  /// **'Allowed e-mail domains'**
  String get idpFieldDomains;

  /// No description provided for @idpDomainsHint.
  ///
  /// In en, this message translates to:
  /// **'Type a domain and press Enter, for example example.com'**
  String get idpDomainsHint;

  /// No description provided for @idpAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get idpAdvanced;

  /// No description provided for @idpAlgorithms.
  ///
  /// In en, this message translates to:
  /// **'Accepted signature algorithms'**
  String get idpAlgorithms;

  /// No description provided for @idpEmailRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'How may an e-mail address be used to link a person?'**
  String get idpEmailRuleTitle;

  /// No description provided for @idpRuleVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Require a verified claim (recommended)'**
  String get idpRuleVerifiedTitle;

  /// No description provided for @idpRuleVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'The first sign-in is linked to the ERP user with the same e-mail address only when the token carries a claim, such as email_verified, saying the provider checked that address. Risk: if the provider does not really check addresses, the claim is worthless and a stranger could take over a user.'**
  String get idpRuleVerifiedBody;

  /// No description provided for @idpRuleTrustTitle.
  ///
  /// In en, this message translates to:
  /// **'Trust the provider\'s e-mail address'**
  String get idpRuleTrustTitle;

  /// No description provided for @idpRuleTrustBody.
  ///
  /// In en, this message translates to:
  /// **'The address in the token is accepted without any verification claim. Only use this for a directory where your company controls every address, such as a single Entra tenant, and add allowed domains. Risk: if people can set their own address at the provider, they can sign in as any user.'**
  String get idpRuleTrustBody;

  /// No description provided for @idpRuleSubjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Only existing subjects'**
  String get idpRuleSubjectTitle;

  /// No description provided for @idpRuleSubjectBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody is linked by e-mail. An administrator links each user to an identity at the provider (Users, Link identity). Safest, but more work.'**
  String get idpRuleSubjectBody;

  /// No description provided for @idpEntraAdvice.
  ///
  /// In en, this message translates to:
  /// **'Entra ID: either trust the provider\'s e-mail and list your allowed domains (a tenant only holds your own people), or require the claim xms_edov, which Entra only sends when you add it as an optional claim in the app registration.'**
  String get idpEntraAdvice;

  /// No description provided for @idpErrName.
  ///
  /// In en, this message translates to:
  /// **'A name is required.'**
  String get idpErrName;

  /// No description provided for @idpErrIssuer.
  ///
  /// In en, this message translates to:
  /// **'The issuer must be an https:// URL.'**
  String get idpErrIssuer;

  /// No description provided for @idpErrAudience.
  ///
  /// In en, this message translates to:
  /// **'The audience is required.'**
  String get idpErrAudience;

  /// No description provided for @idpErrDomain.
  ///
  /// In en, this message translates to:
  /// **'{domain} does not look like a domain.'**
  String idpErrDomain(String domain);

  /// No description provided for @idpErrAlgorithms.
  ///
  /// In en, this message translates to:
  /// **'Select at least one algorithm.'**
  String get idpErrAlgorithms;

  /// No description provided for @idpSaveRefused.
  ///
  /// In en, this message translates to:
  /// **'The server refused these settings: {reason}'**
  String idpSaveRefused(String reason);

  /// No description provided for @idpSaved.
  ///
  /// In en, this message translates to:
  /// **'Identity provider saved'**
  String get idpSaved;

  /// No description provided for @idpDeleted.
  ///
  /// In en, this message translates to:
  /// **'Identity provider deleted'**
  String get idpDeleted;

  /// No description provided for @idpDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete identity provider {name}? People who sign in through it can no longer do so.'**
  String idpDeleteConfirm(String name);

  /// No description provided for @idpLockoutTitle.
  ///
  /// In en, this message translates to:
  /// **'This can lock people out'**
  String get idpLockoutTitle;

  /// No description provided for @idpLockoutLast.
  ///
  /// In en, this message translates to:
  /// **'This is the last enabled identity provider and the server has no OIDC_ISSUER fallback. If you continue, nobody can sign in until the server\'s configuration is fixed.'**
  String get idpLockoutLast;

  /// No description provided for @idpLockoutOwn.
  ///
  /// In en, this message translates to:
  /// **'You are signed in through this provider. If you continue, you will be signed out and cannot sign in again unless another provider accepts you.'**
  String get idpLockoutOwn;

  /// No description provided for @idpLockoutContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get idpLockoutContinue;

  /// No description provided for @idpTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get idpTest;

  /// No description provided for @idpTestSampleToken.
  ///
  /// In en, this message translates to:
  /// **'Sample token (optional)'**
  String get idpTestSampleToken;

  /// No description provided for @idpTestSampleHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an access token of a person from this provider to see how it would be handled.'**
  String get idpTestSampleHint;

  /// No description provided for @idpTestNothing.
  ///
  /// In en, this message translates to:
  /// **'Testing reads the provider and checks the token only. Nothing is linked or stored.'**
  String get idpTestNothing;

  /// No description provided for @idpTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the provider: {error}'**
  String idpTestFailed(String error);

  /// No description provided for @idpTestDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery document reachable'**
  String get idpTestDiscovery;

  /// No description provided for @idpTestIssuerMatch.
  ///
  /// In en, this message translates to:
  /// **'Issuer matches the discovery document'**
  String get idpTestIssuerMatch;

  /// No description provided for @idpTestKeys.
  ///
  /// In en, this message translates to:
  /// **'{count} signing keys, algorithms: {algorithms}'**
  String idpTestKeys(int count, String algorithms);

  /// No description provided for @idpTestClaims.
  ///
  /// In en, this message translates to:
  /// **'Claims the provider says it supports: {claims}'**
  String idpTestClaims(String claims);

  /// No description provided for @idpTestToken.
  ///
  /// In en, this message translates to:
  /// **'Sample token'**
  String get idpTestToken;

  /// No description provided for @idpTestSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get idpTestSignature;

  /// No description provided for @idpTestAudience.
  ///
  /// In en, this message translates to:
  /// **'Audience'**
  String get idpTestAudience;

  /// No description provided for @idpTestExpiry.
  ///
  /// In en, this message translates to:
  /// **'Not expired'**
  String get idpTestExpiry;

  /// No description provided for @idpTestOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get idpTestOk;

  /// No description provided for @idpTestNotOk.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get idpTestNotOk;

  /// No description provided for @idpTestEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail found: {email}'**
  String idpTestEmail(String email);

  /// No description provided for @idpTestNoEmail.
  ///
  /// In en, this message translates to:
  /// **'No e-mail address found in the token'**
  String get idpTestNoEmail;

  /// No description provided for @idpTestVerified.
  ///
  /// In en, this message translates to:
  /// **'The provider marks the address as verified'**
  String get idpTestVerified;

  /// No description provided for @idpTestNotVerified.
  ///
  /// In en, this message translates to:
  /// **'The address is not marked as verified'**
  String get idpTestNotVerified;

  /// No description provided for @idpBindWould.
  ///
  /// In en, this message translates to:
  /// **'Would sign in as {email}'**
  String idpBindWould(String email);

  /// No description provided for @idpBindExisting.
  ///
  /// In en, this message translates to:
  /// **'Already linked to {email}'**
  String idpBindExisting(String email);

  /// No description provided for @idpBindRefused.
  ///
  /// In en, this message translates to:
  /// **'Would be refused: {reason}'**
  String idpBindRefused(String reason);

  /// No description provided for @idpLinkIdentity.
  ///
  /// In en, this message translates to:
  /// **'Link identity'**
  String get idpLinkIdentity;

  /// No description provided for @idpLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link identity of {name}'**
  String idpLinkTitle(String name);

  /// No description provided for @idpLinkExplain.
  ///
  /// In en, this message translates to:
  /// **'Only needed for providers that use the rule \'Only existing subjects\'. Choose the provider and enter the subject (the sub claim) this person has there. Leave it empty to remove the link.'**
  String get idpLinkExplain;

  /// No description provided for @idpLinkProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get idpLinkProvider;

  /// No description provided for @idpLinkSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject (sub)'**
  String get idpLinkSubject;

  /// No description provided for @idpLinkNoProviders.
  ///
  /// In en, this message translates to:
  /// **'No identity providers are saved in the app yet.'**
  String get idpLinkNoProviders;

  /// No description provided for @idpLinkSaved.
  ///
  /// In en, this message translates to:
  /// **'Identity link saved'**
  String get idpLinkSaved;

  /// No description provided for @idpLinkCleared.
  ///
  /// In en, this message translates to:
  /// **'Identity link removed'**
  String get idpLinkCleared;

  /// No description provided for @tutActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the simulated e-mail: {reason}. Try again.'**
  String tutActionFailed(String reason);

  /// No description provided for @tutActionForbidden.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to import e-mail into the helpdesk (it needs the helpdesk write permission). Ask an administrator, or sign in as one, and try again.'**
  String get tutActionForbidden;

  /// No description provided for @workerDownBanner.
  ///
  /// In en, this message translates to:
  /// **'The background worker has not run since {since}: e-mail is not sent or fetched and SLA breaches are not escalated.'**
  String workerDownBanner(String since);

  /// No description provided for @workerNeverSeenBanner.
  ///
  /// In en, this message translates to:
  /// **'No background worker has run yet: e-mail is not sent or fetched and SLA breaches are not escalated.'**
  String get workerNeverSeenBanner;

  /// No description provided for @workerBannerSemantics.
  ///
  /// In en, this message translates to:
  /// **'Background worker'**
  String get workerBannerSemantics;

  /// No description provided for @vatLookup.
  ///
  /// In en, this message translates to:
  /// **'Look up in VIES'**
  String get vatLookup;

  /// No description provided for @vatValid.
  ///
  /// In en, this message translates to:
  /// **'The format and check digits are right. This does not show that the number is registered.'**
  String get vatValid;

  /// No description provided for @vatFormatOk.
  ///
  /// In en, this message translates to:
  /// **'The format is right. This country\'s check digits are not verified here.'**
  String get vatFormatOk;

  /// No description provided for @vatBadFormat.
  ///
  /// In en, this message translates to:
  /// **'This is not shaped like a VAT number of this country.'**
  String get vatBadFormat;

  /// No description provided for @vatBadChecksum.
  ///
  /// In en, this message translates to:
  /// **'The check digits do not match: please check for a typo.'**
  String get vatBadChecksum;

  /// No description provided for @vatNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not an EU VAT number, so it is not checked.'**
  String get vatNotChecked;

  /// No description provided for @vatDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Also used by: {records}'**
  String vatDuplicates(String records);

  /// No description provided for @vatInactive.
  ///
  /// In en, this message translates to:
  /// **'{record} (inactive)'**
  String vatInactive(String record);

  /// No description provided for @viesValid.
  ///
  /// In en, this message translates to:
  /// **'Registered and active in VIES.'**
  String get viesValid;

  /// No description provided for @viesInvalid.
  ///
  /// In en, this message translates to:
  /// **'VIES does not know this number.'**
  String get viesInvalid;

  /// No description provided for @viesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'VIES could not answer ({reason}). Fill in the details by hand.'**
  String viesUnavailable(String reason);

  /// No description provided for @viesDisabled.
  ///
  /// In en, this message translates to:
  /// **'The VIES lookup is switched off on this server.'**
  String get viesDisabled;

  /// No description provided for @viesFilled.
  ///
  /// In en, this message translates to:
  /// **'Empty fields filled in from VIES.'**
  String get viesFilled;

  /// No description provided for @viesNoDetails.
  ///
  /// In en, this message translates to:
  /// **'The member state does not disclose a name or address.'**
  String get viesNoDetails;

  /// No description provided for @adminAuditTrail.
  ///
  /// In en, this message translates to:
  /// **'Audit trail'**
  String get adminAuditTrail;

  /// No description provided for @auditRecordType.
  ///
  /// In en, this message translates to:
  /// **'Record type'**
  String get auditRecordType;

  /// No description provided for @auditAllRecords.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get auditAllRecords;

  /// No description provided for @auditAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get auditAction;

  /// No description provided for @auditFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get auditFrom;

  /// No description provided for @auditTo.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get auditTo;

  /// No description provided for @auditClearDates.
  ///
  /// In en, this message translates to:
  /// **'Clear dates'**
  String get auditClearDates;

  /// No description provided for @auditSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get auditSystem;

  /// No description provided for @auditNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No events found.'**
  String get auditNoEvents;

  /// No description provided for @auditLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load older events'**
  String get auditLoadMore;

  /// No description provided for @auditHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get auditHistory;

  /// No description provided for @auditHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History of {name}'**
  String auditHistoryTitle(String name);

  /// No description provided for @auditNoDetails.
  ///
  /// In en, this message translates to:
  /// **'No details were recorded.'**
  String get auditNoDetails;

  /// No description provided for @mailboxes.
  ///
  /// In en, this message translates to:
  /// **'Mailboxes'**
  String get mailboxes;

  /// No description provided for @newMailbox.
  ///
  /// In en, this message translates to:
  /// **'New mailbox'**
  String get newMailbox;

  /// No description provided for @mailboxesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No mailboxes yet. E-mail is fetched and sent with the settings of the background worker.'**
  String get mailboxesEmpty;

  /// No description provided for @mailboxRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh the status'**
  String get mailboxRefresh;

  /// No description provided for @mailboxAddress.
  ///
  /// In en, this message translates to:
  /// **'E-mail address'**
  String get mailboxAddress;

  /// No description provided for @mailboxKind.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get mailboxKind;

  /// No description provided for @mailboxKindGraph.
  ///
  /// In en, this message translates to:
  /// **'Microsoft 365 (Exchange Online)'**
  String get mailboxKindGraph;

  /// No description provided for @mailboxKindImap.
  ///
  /// In en, this message translates to:
  /// **'IMAP and SMTP'**
  String get mailboxKindImap;

  /// No description provided for @mailboxTenantId.
  ///
  /// In en, this message translates to:
  /// **'Tenant ID'**
  String get mailboxTenantId;

  /// No description provided for @mailboxClientId.
  ///
  /// In en, this message translates to:
  /// **'Application (client) ID'**
  String get mailboxClientId;

  /// No description provided for @mailboxUsername.
  ///
  /// In en, this message translates to:
  /// **'User name'**
  String get mailboxUsername;

  /// No description provided for @mailboxImapHost.
  ///
  /// In en, this message translates to:
  /// **'IMAP server'**
  String get mailboxImapHost;

  /// No description provided for @mailboxImapPort.
  ///
  /// In en, this message translates to:
  /// **'IMAP port'**
  String get mailboxImapPort;

  /// No description provided for @mailboxImapFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get mailboxImapFolder;

  /// No description provided for @mailboxImapTls.
  ///
  /// In en, this message translates to:
  /// **'Encrypted IMAP connection (TLS)'**
  String get mailboxImapTls;

  /// No description provided for @mailboxSmtpHost.
  ///
  /// In en, this message translates to:
  /// **'SMTP server'**
  String get mailboxSmtpHost;

  /// No description provided for @mailboxSmtpPort.
  ///
  /// In en, this message translates to:
  /// **'SMTP port'**
  String get mailboxSmtpPort;

  /// No description provided for @mailboxSmtpSecurity.
  ///
  /// In en, this message translates to:
  /// **'SMTP encryption'**
  String get mailboxSmtpSecurity;

  /// No description provided for @mailboxSmtpNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get mailboxSmtpNone;

  /// No description provided for @mailboxSecretRef.
  ///
  /// In en, this message translates to:
  /// **'Name of the secret'**
  String get mailboxSecretRef;

  /// No description provided for @mailboxSecretHelp.
  ///
  /// In en, this message translates to:
  /// **'The password or client secret is not stored here. Set it on the server as the worker variable {variable}.'**
  String mailboxSecretHelp(String variable);

  /// No description provided for @mailboxTeam.
  ///
  /// In en, this message translates to:
  /// **'Team for new tickets'**
  String get mailboxTeam;

  /// No description provided for @mailboxTeamDefault.
  ///
  /// In en, this message translates to:
  /// **'The default team'**
  String get mailboxTeamDefault;

  /// No description provided for @mailboxInbound.
  ///
  /// In en, this message translates to:
  /// **'Fetch incoming e-mail'**
  String get mailboxInbound;

  /// No description provided for @mailboxDefault.
  ///
  /// In en, this message translates to:
  /// **'Default mailbox: for system e-mail and tickets without a mailbox'**
  String get mailboxDefault;

  /// No description provided for @mailboxDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get mailboxDefaultBadge;

  /// No description provided for @mailboxSendOnly.
  ///
  /// In en, this message translates to:
  /// **'Sends only'**
  String get mailboxSendOnly;

  /// No description provided for @mailboxNeverPolled.
  ///
  /// In en, this message translates to:
  /// **'No e-mail fetched yet'**
  String get mailboxNeverPolled;

  /// No description provided for @mailboxLastOk.
  ///
  /// In en, this message translates to:
  /// **'E-mail last fetched on {when}'**
  String mailboxLastOk(String when);

  /// No description provided for @mailboxError.
  ///
  /// In en, this message translates to:
  /// **'Problem fetching e-mail: {error}'**
  String mailboxError(String error);

  /// No description provided for @mailboxDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the mailbox {name}? Its tickets stay. Replies on them then leave through the default mailbox.'**
  String mailboxDeleteConfirm(String name);

  /// No description provided for @productionWorkCentres.
  ///
  /// In en, this message translates to:
  /// **'Work centres'**
  String get productionWorkCentres;

  /// No description provided for @productionWorkCentreAdd.
  ///
  /// In en, this message translates to:
  /// **'Add work centre'**
  String get productionWorkCentreAdd;

  /// No description provided for @productionWorkCentreEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit work centre'**
  String get productionWorkCentreEdit;

  /// No description provided for @productionWorkCentreCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity (units working at once)'**
  String get productionWorkCentreCapacity;

  /// No description provided for @productionWorkCentreCost.
  ///
  /// In en, this message translates to:
  /// **'Cost per hour'**
  String get productionWorkCentreCost;

  /// No description provided for @productionWorkCentreOpenOps.
  ///
  /// In en, this message translates to:
  /// **'{count} open operations'**
  String productionWorkCentreOpenOps(String count);

  /// No description provided for @productionWorkCentreEmpty.
  ///
  /// In en, this message translates to:
  /// **'No work centres yet. Add the machines and benches your operations run on.'**
  String get productionWorkCentreEmpty;

  /// No description provided for @productionWorkingHours.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get productionWorkingHours;

  /// No description provided for @productionHoursDefault.
  ///
  /// In en, this message translates to:
  /// **'No hours of its own: Monday to Friday 08:00–12:00 and 13:00–17:00.'**
  String get productionHoursDefault;

  /// No description provided for @productionHoursAddBlock.
  ///
  /// In en, this message translates to:
  /// **'Add block'**
  String get productionHoursAddBlock;

  /// No description provided for @productionClosures.
  ///
  /// In en, this message translates to:
  /// **'Closures'**
  String get productionClosures;

  /// No description provided for @productionClosureAdd.
  ///
  /// In en, this message translates to:
  /// **'Add closure'**
  String get productionClosureAdd;

  /// No description provided for @productionClosureWholePlant.
  ///
  /// In en, this message translates to:
  /// **'Whole plant'**
  String get productionClosureWholePlant;

  /// No description provided for @productionClosureKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get productionClosureKind;

  /// No description provided for @productionClosureMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get productionClosureMaintenance;

  /// No description provided for @productionClosureHoliday.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get productionClosureHoliday;

  /// No description provided for @productionClosureOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get productionClosureOther;

  /// No description provided for @productionClosureEmpty.
  ///
  /// In en, this message translates to:
  /// **'No closures.'**
  String get productionClosureEmpty;

  /// No description provided for @productionCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get productionCapacity;

  /// No description provided for @productionCapacityLegend.
  ///
  /// In en, this message translates to:
  /// **'Load of the open operations against what each work centre can work. Red: overloaded.'**
  String get productionCapacityLegend;

  /// No description provided for @productionCapacityOverloaded.
  ///
  /// In en, this message translates to:
  /// **'Overloaded'**
  String get productionCapacityOverloaded;

  /// No description provided for @productionCapacityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No work centres to show.'**
  String get productionCapacityEmpty;

  /// No description provided for @mrpTitle.
  ///
  /// In en, this message translates to:
  /// **'Planning proposals'**
  String get mrpTitle;

  /// No description provided for @mrpRun.
  ///
  /// In en, this message translates to:
  /// **'Run planning'**
  String get mrpRun;

  /// No description provided for @mrpRunDone.
  ///
  /// In en, this message translates to:
  /// **'Planning done: {count} proposals.'**
  String mrpRunDone(String count);

  /// No description provided for @mrpHorizon.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String mrpHorizon(String days);

  /// No description provided for @mrpEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to buy or build.'**
  String get mrpEmpty;

  /// No description provided for @mrpKindPurchase.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get mrpKindPurchase;

  /// No description provided for @mrpKindProduction.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get mrpKindProduction;

  /// No description provided for @mrpReasonDemand.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get mrpReasonDemand;

  /// No description provided for @mrpReasonSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety stock'**
  String get mrpReasonSafety;

  /// No description provided for @mrpOrderBy.
  ///
  /// In en, this message translates to:
  /// **'Order by {date}'**
  String mrpOrderBy(String date);

  /// No description provided for @mrpNeededOn.
  ///
  /// In en, this message translates to:
  /// **'Needed {date}'**
  String mrpNeededOn(String date);

  /// No description provided for @mrpLate.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get mrpLate;

  /// No description provided for @mrpConvert.
  ///
  /// In en, this message translates to:
  /// **'Create order'**
  String get mrpConvert;

  /// No description provided for @mrpDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get mrpDismiss;

  /// No description provided for @mrpConverted.
  ///
  /// In en, this message translates to:
  /// **'Order {number} created.'**
  String mrpConverted(String number);

  /// No description provided for @mrpDismissed.
  ///
  /// In en, this message translates to:
  /// **'Proposal dismissed.'**
  String get mrpDismissed;

  /// No description provided for @mrpChooseSupplier.
  ///
  /// In en, this message translates to:
  /// **'Choose a supplier'**
  String get mrpChooseSupplier;

  /// No description provided for @mrpNoSupplier.
  ///
  /// In en, this message translates to:
  /// **'This product has no preferred supplier.'**
  String get mrpNoSupplier;

  /// No description provided for @mrpStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get mrpStatusOpen;

  /// No description provided for @mrpStatusConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get mrpStatusConverted;

  /// No description provided for @mrpStatusDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get mrpStatusDismissed;

  /// No description provided for @mrpStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mrpStatusAll;

  /// No description provided for @mrpStatusSuperseded.
  ///
  /// In en, this message translates to:
  /// **'Replaced'**
  String get mrpStatusSuperseded;

  /// No description provided for @mrpLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get mrpLoadMore;

  /// No description provided for @mrpPegSales.
  ///
  /// In en, this message translates to:
  /// **'Order {number}'**
  String mrpPegSales(String number);

  /// No description provided for @mrpPegProduction.
  ///
  /// In en, this message translates to:
  /// **'Production order {number}'**
  String mrpPegProduction(String number);

  /// No description provided for @mrpPegPlanned.
  ///
  /// In en, this message translates to:
  /// **'For building {number}'**
  String mrpPegPlanned(String number);

  /// No description provided for @mrpPegPurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase order {number}'**
  String mrpPegPurchase(String number);

  /// No description provided for @productSafetyStock.
  ///
  /// In en, this message translates to:
  /// **'Safety stock'**
  String get productSafetyStock;

  /// No description provided for @productOrderMultiple.
  ///
  /// In en, this message translates to:
  /// **'Order multiple'**
  String get productOrderMultiple;

  /// No description provided for @mrpLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last run: {number}'**
  String mrpLastRun(String number);

  /// No description provided for @mrpNoRun.
  ///
  /// In en, this message translates to:
  /// **'No planning has been run yet.'**
  String get mrpNoRun;

  /// No description provided for @productionBoardTitle.
  ///
  /// In en, this message translates to:
  /// **'Work-centre board'**
  String get productionBoardTitle;

  /// No description provided for @productionBoardLate.
  ///
  /// In en, this message translates to:
  /// **'Late operations'**
  String get productionBoardLate;

  /// No description provided for @productionBoardNoLate.
  ///
  /// In en, this message translates to:
  /// **'Nothing is late.'**
  String get productionBoardNoLate;

  /// No description provided for @productionBoardUtilisation.
  ///
  /// In en, this message translates to:
  /// **'{percent}% loaded'**
  String productionBoardUtilisation(String percent);

  /// No description provided for @productionBoardMoved.
  ///
  /// In en, this message translates to:
  /// **'Operation moved.'**
  String get productionBoardMoved;

  /// No description provided for @productionBoardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Move with conflicts?'**
  String get productionBoardConfirmTitle;

  /// No description provided for @productionBoardConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This move has errors:'**
  String get productionBoardConfirmBody;

  /// No description provided for @productionBoardMoveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Move anyway'**
  String get productionBoardMoveAnyway;

  /// No description provided for @productionBoardRefusedTitle.
  ///
  /// In en, this message translates to:
  /// **'This operation cannot be moved'**
  String get productionBoardRefusedTitle;

  /// No description provided for @productionConflictInactiveWorkCentre.
  ///
  /// In en, this message translates to:
  /// **'The work centre is not active.'**
  String get productionConflictInactiveWorkCentre;

  /// No description provided for @productionConflictOperationStarted.
  ///
  /// In en, this message translates to:
  /// **'The operation has started and cannot be moved.'**
  String get productionConflictOperationStarted;

  /// No description provided for @productionConflictOnClosure.
  ///
  /// In en, this message translates to:
  /// **'The work centre does not work on {day}.'**
  String productionConflictOnClosure(String day);

  /// No description provided for @productionConflictOverload.
  ///
  /// In en, this message translates to:
  /// **'{day} would be overloaded.'**
  String productionConflictOverload(String day);

  /// No description provided for @productionConflictBeforePredecessor.
  ///
  /// In en, this message translates to:
  /// **'It would start before the previous operation ends ({day}).'**
  String productionConflictBeforePredecessor(String day);

  /// No description provided for @productionConflictAfterSuccessor.
  ///
  /// In en, this message translates to:
  /// **'It would end after the next operation starts ({day}).'**
  String productionConflictAfterSuccessor(String day);

  /// No description provided for @productionConflictLaterThanReady.
  ///
  /// In en, this message translates to:
  /// **'It would end after the planned-ready date ({day}).'**
  String productionConflictLaterThanReady(String day);

  /// No description provided for @productionCapacityEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get productionCapacityEarlier;

  /// No description provided for @productionCapacityLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get productionCapacityLater;

  /// No description provided for @productionCapacityToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get productionCapacityToday;

  /// No description provided for @productionWorkCentreUnits.
  ///
  /// In en, this message translates to:
  /// **'{count} units'**
  String productionWorkCentreUnits(String count);

  /// No description provided for @productionOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get productionOperations;

  /// No description provided for @productionOperationPending.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get productionOperationPending;

  /// No description provided for @productionOperationDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get productionOperationDone;

  /// No description provided for @productionOperationSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get productionOperationSkipped;

  /// No description provided for @productionOperationStart.
  ///
  /// In en, this message translates to:
  /// **'Start operation'**
  String get productionOperationStart;

  /// No description provided for @productionOperationFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish operation'**
  String get productionOperationFinish;

  /// No description provided for @productionOperationReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen operation'**
  String get productionOperationReopen;

  /// No description provided for @productionOperationMove.
  ///
  /// In en, this message translates to:
  /// **'Move operation'**
  String get productionOperationMove;

  /// No description provided for @productionOperationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes worked'**
  String get productionOperationMinutes;

  /// No description provided for @productionOperationPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get productionOperationPlanned;

  /// No description provided for @productionOperationWorked.
  ///
  /// In en, this message translates to:
  /// **'Worked'**
  String get productionOperationWorked;

  /// No description provided for @productionOperationBy.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String productionOperationBy(String name);

  /// No description provided for @productionScheduleAgain.
  ///
  /// In en, this message translates to:
  /// **'Schedule again'**
  String get productionScheduleAgain;

  /// No description provided for @productionStartFrom.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get productionStartFrom;

  /// No description provided for @productionBehindSchedule.
  ///
  /// In en, this message translates to:
  /// **'Behind schedule: the last operation is planned for {date}, after the planned-ready date.'**
  String productionBehindSchedule(String date);

  /// No description provided for @productionBehindScheduleShort.
  ///
  /// In en, this message translates to:
  /// **'Behind schedule'**
  String get productionBehindScheduleShort;

  /// No description provided for @productionUseScheduledEnd.
  ///
  /// In en, this message translates to:
  /// **'Use {date} as planned-ready date'**
  String productionUseScheduledEnd(String date);

  /// No description provided for @productionRemark.
  ///
  /// In en, this message translates to:
  /// **'Production remark (internal)'**
  String get productionRemark;

  /// No description provided for @productionSubOrders.
  ///
  /// In en, this message translates to:
  /// **'Subassembly orders'**
  String get productionSubOrders;

  /// No description provided for @productionSubassemblyOf.
  ///
  /// In en, this message translates to:
  /// **'Subassembly of {number}'**
  String productionSubassemblyOf(String number);

  /// No description provided for @productionCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get productionCost;

  /// No description provided for @productionCostPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get productionCostPlanned;

  /// No description provided for @productionCostActual.
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get productionCostActual;

  /// No description provided for @productionCostMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get productionCostMaterial;

  /// No description provided for @productionCostLabour.
  ///
  /// In en, this message translates to:
  /// **'Labour'**
  String get productionCostLabour;

  /// No description provided for @productionCostIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some costs are missing and left out.'**
  String get productionCostIncomplete;

  /// No description provided for @productionOperationsOpenWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} operations are still open. Fill in the minutes worked to finish them; leave the field empty to skip one.'**
  String productionOperationsOpenWarning(String count);

  /// No description provided for @productionAutoRelease.
  ///
  /// In en, this message translates to:
  /// **'Also release the subassemblies that stock does not cover'**
  String get productionAutoRelease;

  /// No description provided for @productionRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get productionRouting;

  /// No description provided for @productionRoutingNone.
  ///
  /// In en, this message translates to:
  /// **'No routing: production orders for this product have no operations.'**
  String get productionRoutingNone;

  /// No description provided for @productionRoutingAddOperation.
  ///
  /// In en, this message translates to:
  /// **'Add operation'**
  String get productionRoutingAddOperation;

  /// No description provided for @productionRoutingOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get productionRoutingOperation;

  /// No description provided for @productionRoutingSetup.
  ///
  /// In en, this message translates to:
  /// **'Setup (min)'**
  String get productionRoutingSetup;

  /// No description provided for @productionRoutingRun.
  ///
  /// In en, this message translates to:
  /// **'Run per unit (min)'**
  String get productionRoutingRun;

  /// No description provided for @productionRoutingNoWorkCentres.
  ///
  /// In en, this message translates to:
  /// **'Add work centres first (Production, work centres).'**
  String get productionRoutingNoWorkCentres;

  /// No description provided for @productionCostRollup.
  ///
  /// In en, this message translates to:
  /// **'Cost roll-up'**
  String get productionCostRollup;

  /// No description provided for @productionCostRollupHint.
  ///
  /// In en, this message translates to:
  /// **'Material at standard cost and labour at the work centres\' cost per hour, through every level.'**
  String get productionCostRollupHint;

  /// No description provided for @productionCostPerUnit.
  ///
  /// In en, this message translates to:
  /// **'Cost per unit'**
  String get productionCostPerUnit;

  /// No description provided for @productionCostGapProduct.
  ///
  /// In en, this message translates to:
  /// **'No standard cost: {code}'**
  String productionCostGapProduct(String code);

  /// No description provided for @productionCostGapWorkCentre.
  ///
  /// In en, this message translates to:
  /// **'No cost per hour: {code}'**
  String productionCostGapWorkCentre(String code);

  /// No description provided for @productionCostCalculate.
  ///
  /// In en, this message translates to:
  /// **'Calculate'**
  String get productionCostCalculate;

  /// No description provided for @productionOperationMinutesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the minutes as a whole number.'**
  String get productionOperationMinutesInvalid;

  /// No description provided for @productionRoutingLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The routing could not be loaded, so it cannot be changed now.'**
  String get productionRoutingLoadFailed;

  /// No description provided for @productionRoutingChangedWhileSaving.
  ///
  /// In en, this message translates to:
  /// **'The routing changed while it was being saved. Save again to include the latest changes.'**
  String get productionRoutingChangedWhileSaving;

  /// No description provided for @shortcutBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get shortcutBack;

  /// No description provided for @shortcutCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get shortcutCreate;

  /// No description provided for @shortcutHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get shortcutHome;

  /// No description provided for @shortcutDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get shortcutDiscard;

  /// No description provided for @shortcutSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get shortcutSave;

  /// No description provided for @shortcutNextPage.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get shortcutNextPage;

  /// No description provided for @shortcutSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get shortcutSearch;

  /// No description provided for @shortcutNewTodo.
  ///
  /// In en, this message translates to:
  /// **'New to-do'**
  String get shortcutNewTodo;

  /// No description provided for @shortcutKbSearch.
  ///
  /// In en, this message translates to:
  /// **'Search articles'**
  String get shortcutKbSearch;

  /// No description provided for @shortcutKbShare.
  ///
  /// In en, this message translates to:
  /// **'Share article'**
  String get shortcutKbShare;

  /// No description provided for @shortcutPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get shortcutPalette;

  /// No description provided for @shortcutHelp.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutHelp;

  /// No description provided for @shortcutMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Menu item {n}'**
  String shortcutMenuItem(int n);

  /// No description provided for @shortcutHint.
  ///
  /// In en, this message translates to:
  /// **'Shortcut: {keys}'**
  String shortcutHint(String keys);

  /// No description provided for @shortcutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get shortcutConfirm;

  /// No description provided for @shortcutCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel or leave'**
  String get shortcutCancel;

  /// No description provided for @shortcutFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get shortcutFind;

  /// No description provided for @shortcutAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get shortcutAddLine;

  /// No description provided for @shortcutHelpStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard keys'**
  String get shortcutHelpStandard;

  /// No description provided for @shortcutHelpNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get shortcutHelpNavigation;

  /// No description provided for @shortcutHelpAltKeys.
  ///
  /// In en, this message translates to:
  /// **'Hold {modifier} to see a key on every button; press it to use the button.'**
  String shortcutHelpAltKeys(String modifier);

  /// No description provided for @shortcutHelpEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter moves to the next field. Up and Down move between rows, Ctrl with an arrow jumps to the far end.'**
  String get shortcutHelpEnter;

  /// No description provided for @moduleTodo.
  ///
  /// In en, this message translates to:
  /// **'To-do'**
  String get moduleTodo;

  /// No description provided for @todoTitle.
  ///
  /// In en, this message translates to:
  /// **'To-dos'**
  String get todoTitle;

  /// No description provided for @todoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to-do'**
  String get todoAdd;

  /// No description provided for @todoAddSub.
  ///
  /// In en, this message translates to:
  /// **'Add sub-item'**
  String get todoAddSub;

  /// No description provided for @todoWhat.
  ///
  /// In en, this message translates to:
  /// **'What needs doing?'**
  String get todoWhat;

  /// No description provided for @todoNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get todoNotes;

  /// No description provided for @todoDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get todoDueDate;

  /// No description provided for @todoSetDue.
  ///
  /// In en, this message translates to:
  /// **'Set due date'**
  String get todoSetDue;

  /// No description provided for @todoClearDue.
  ///
  /// In en, this message translates to:
  /// **'Clear due date'**
  String get todoClearDue;

  /// No description provided for @todoDue.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String todoDue(String date);

  /// No description provided for @todoOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get todoOverdue;

  /// No description provided for @todoFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get todoFilterOpen;

  /// No description provided for @todoFilterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get todoFilterDone;

  /// No description provided for @todoFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get todoFilterAll;

  /// No description provided for @todoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do. Add your first to-do.'**
  String get todoEmpty;

  /// No description provided for @todoEmptyDone.
  ///
  /// In en, this message translates to:
  /// **'No finished to-dos.'**
  String get todoEmptyDone;

  /// No description provided for @todoComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get todoComplete;

  /// No description provided for @todoReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get todoReopen;

  /// No description provided for @todoDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? Its sub-items are deleted too.'**
  String todoDeleteConfirm(String title);

  /// No description provided for @todoCompleteAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete the sub-items too?'**
  String get todoCompleteAllTitle;

  /// No description provided for @todoCompleteAllBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" still has open sub-items. Completing it marks them as done too.'**
  String todoCompleteAllBody(String title);

  /// No description provided for @todoCompleteAll.
  ///
  /// In en, this message translates to:
  /// **'Complete all'**
  String get todoCompleteAll;

  /// No description provided for @todoLinkedItem.
  ///
  /// In en, this message translates to:
  /// **'Linked item'**
  String get todoLinkedItem;

  /// No description provided for @todoFromOwner.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String todoFromOwner(String name);

  /// No description provided for @todoSubProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} sub-items done'**
  String todoSubProgress(int done, int total);

  /// No description provided for @todoReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get todoReorder;

  /// No description provided for @changeProduct.
  ///
  /// In en, this message translates to:
  /// **'Change product'**
  String get changeProduct;

  /// No description provided for @changeProductOf.
  ///
  /// In en, this message translates to:
  /// **'New main product for {product}'**
  String changeProductOf(String product);

  /// No description provided for @changeProductNew.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get changeProductNew;

  /// No description provided for @changeProductNetNote.
  ///
  /// In en, this message translates to:
  /// **'{product} has a net price: the line discount was cleared.'**
  String changeProductNetNote(String product);

  /// No description provided for @changeProductOnRequestNote.
  ///
  /// In en, this message translates to:
  /// **'{product} is priced on request: enter the price before sending.'**
  String changeProductOnRequestNote(String product);

  /// No description provided for @optionsNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'{count} option(s) do not apply to {product}: remove them.'**
  String optionsNotApplicable(int count, String product);

  /// No description provided for @removeNamedLine.
  ///
  /// In en, this message translates to:
  /// **'Remove {code}'**
  String removeNamedLine(String code);

  /// No description provided for @optionNotOffered.
  ///
  /// In en, this message translates to:
  /// **'Not offered with {product}'**
  String optionNotOffered(String product);

  /// No description provided for @sentWithNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Sent with {count} option(s) that do not apply to their main product.'**
  String sentWithNotApplicable(int count);

  /// No description provided for @tabCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get tabCustomer;

  /// No description provided for @todoAdded.
  ///
  /// In en, this message translates to:
  /// **'To-do added'**
  String get todoAdded;

  /// No description provided for @todoLinkToScreen.
  ///
  /// In en, this message translates to:
  /// **'Link to current screen'**
  String get todoLinkToScreen;

  /// No description provided for @todoLinkNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This screen has no record to link to.'**
  String get todoLinkNotAvailable;

  /// No description provided for @todoOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open the linked record'**
  String get todoOpenLink;

  /// No description provided for @todoRemoveLink.
  ///
  /// In en, this message translates to:
  /// **'Remove link from my to-dos'**
  String get todoRemoveLink;

  /// No description provided for @recordNotFound.
  ///
  /// In en, this message translates to:
  /// **'This record was not found. It may have been deleted, or you may not have access to it.'**
  String get recordNotFound;

  /// No description provided for @todoForObject.
  ///
  /// In en, this message translates to:
  /// **'To-dos for this record'**
  String get todoForObject;

  /// No description provided for @todoForObjectCount.
  ///
  /// In en, this message translates to:
  /// **'To-dos for this record ({count} open)'**
  String todoForObjectCount(int count);

  /// No description provided for @todoForObjectEmpty.
  ///
  /// In en, this message translates to:
  /// **'No open to-dos for this record.'**
  String get todoForObjectEmpty;

  /// No description provided for @todoEmailReminders.
  ///
  /// In en, this message translates to:
  /// **'E-mail reminders'**
  String get todoEmailReminders;

  /// No description provided for @csvExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export as CSV'**
  String get csvExportCsv;

  /// No description provided for @csvExportXlsx.
  ///
  /// In en, this message translates to:
  /// **'Export as Excel (XLSX)'**
  String get csvExportXlsx;

  /// No description provided for @csvExportOds.
  ///
  /// In en, this message translates to:
  /// **'Export as OpenDocument (ODS)'**
  String get csvExportOds;

  /// No description provided for @adminImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get adminImport;

  /// No description provided for @impNew.
  ///
  /// In en, this message translates to:
  /// **'New import'**
  String get impNew;

  /// No description provided for @impHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get impHistory;

  /// No description provided for @impStepFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get impStepFile;

  /// No description provided for @impStepWhat.
  ///
  /// In en, this message translates to:
  /// **'What and where'**
  String get impStepWhat;

  /// No description provided for @impStepColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get impStepColumns;

  /// No description provided for @impStepCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get impStepCheck;

  /// No description provided for @impStepApply.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get impStepApply;

  /// No description provided for @impFileHelp.
  ///
  /// In en, this message translates to:
  /// **'CSV, Excel (XLSX) or OpenDocument (ODS) file, up to 50 MiB. The file is stored for a week.'**
  String get impFileHelp;

  /// No description provided for @impChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get impChooseFile;

  /// No description provided for @impChooseOther.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get impChooseOther;

  /// No description provided for @impUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get impUploading;

  /// No description provided for @impFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is larger than the limit of 50 MiB.'**
  String get impFileTooLarge;

  /// No description provided for @impFileFormatSize.
  ///
  /// In en, this message translates to:
  /// **'Format: {format}, size: {size}'**
  String impFileFormatSize(String format, String size);

  /// No description provided for @impEntity.
  ///
  /// In en, this message translates to:
  /// **'What do you import?'**
  String get impEntity;

  /// No description provided for @impNoEntities.
  ///
  /// In en, this message translates to:
  /// **'You need the permission to write an entity, for example customers or products, to import it here.'**
  String get impNoEntities;

  /// No description provided for @impSheet.
  ///
  /// In en, this message translates to:
  /// **'Sheet'**
  String get impSheet;

  /// No description provided for @impPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get impPreview;

  /// No description provided for @impRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 data row} other{{count} data rows}}'**
  String impRowCount(int count);

  /// No description provided for @impFirstRows.
  ///
  /// In en, this message translates to:
  /// **'The first {count} rows are shown.'**
  String impFirstRows(int count);

  /// No description provided for @impNoHeader.
  ///
  /// In en, this message translates to:
  /// **'The file has no header row.'**
  String get impNoHeader;

  /// No description provided for @impColFile.
  ///
  /// In en, this message translates to:
  /// **'File column'**
  String get impColFile;

  /// No description provided for @impColSample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get impColSample;

  /// No description provided for @impColField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get impColField;

  /// No description provided for @impIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get impIgnore;

  /// No description provided for @impRequiredNew.
  ///
  /// In en, this message translates to:
  /// **'Required for new records'**
  String get impRequiredNew;

  /// No description provided for @impKeyBadge.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get impKeyBadge;

  /// No description provided for @impKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Choose a file column for the key field {field}: rows are matched on it.'**
  String impKeyMissing(String field);

  /// No description provided for @impDuplicateField.
  ///
  /// In en, this message translates to:
  /// **'The field {field} is chosen for more than one column.'**
  String impDuplicateField(String field);

  /// No description provided for @impUnmapped.
  ///
  /// In en, this message translates to:
  /// **'Fields without a column: {fields}'**
  String impUnmapped(String fields);

  /// No description provided for @impUnmappedRequired.
  ///
  /// In en, this message translates to:
  /// **'Needed to create new records: {fields}'**
  String impUnmappedRequired(String fields);

  /// No description provided for @impAllMapped.
  ///
  /// In en, this message translates to:
  /// **'Every field has a column.'**
  String get impAllMapped;

  /// No description provided for @impMappingsMenu.
  ///
  /// In en, this message translates to:
  /// **'Saved mappings'**
  String get impMappingsMenu;

  /// No description provided for @impNoMappings.
  ///
  /// In en, this message translates to:
  /// **'No saved mappings for this entity yet.'**
  String get impNoMappings;

  /// No description provided for @impSaveMapping.
  ///
  /// In en, this message translates to:
  /// **'Save mapping'**
  String get impSaveMapping;

  /// No description provided for @impMappingName.
  ///
  /// In en, this message translates to:
  /// **'Name of the mapping'**
  String get impMappingName;

  /// No description provided for @impOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the mapping?'**
  String get impOverwriteTitle;

  /// No description provided for @impOverwriteBody.
  ///
  /// In en, this message translates to:
  /// **'A mapping named {name} already exists. Replace it with the current one?'**
  String impOverwriteBody(String name);

  /// No description provided for @impOverwriteAction.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get impOverwriteAction;

  /// No description provided for @impMappingSaved.
  ///
  /// In en, this message translates to:
  /// **'Mapping {name} saved'**
  String impMappingSaved(String name);

  /// No description provided for @impDeleteMapping.
  ///
  /// In en, this message translates to:
  /// **'Delete mapping {name}'**
  String impDeleteMapping(String name);

  /// No description provided for @impDeleteMappingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the saved mapping {name}?'**
  String impDeleteMappingConfirm(String name);

  /// No description provided for @impMappingDeleted.
  ///
  /// In en, this message translates to:
  /// **'Mapping {name} deleted'**
  String impMappingDeleted(String name);

  /// No description provided for @impProposalSaved.
  ///
  /// In en, this message translates to:
  /// **'Columns taken from the saved mapping {name}.'**
  String impProposalSaved(String name);

  /// No description provided for @impProposalByName.
  ///
  /// In en, this message translates to:
  /// **'Columns paired with fields of the same name. Check them before you continue.'**
  String get impProposalByName;

  /// No description provided for @impRunCheck.
  ///
  /// In en, this message translates to:
  /// **'Check the file'**
  String get impRunCheck;

  /// No description provided for @impChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the file...'**
  String get impChecking;

  /// No description provided for @impBackgroundNote.
  ///
  /// In en, this message translates to:
  /// **'Large files run in the background. You can leave this page: the job appears in the history.'**
  String get impBackgroundNote;

  /// No description provided for @impOutdated.
  ///
  /// In en, this message translates to:
  /// **'The file, entity, sheet or columns changed after this check. Run the check again.'**
  String get impOutdated;

  /// No description provided for @impCheckClean.
  ///
  /// In en, this message translates to:
  /// **'No problems found. Nothing has been imported yet.'**
  String get impCheckClean;

  /// No description provided for @impStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get impStatusQueued;

  /// No description provided for @impStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get impStatusRunning;

  /// No description provided for @impStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get impStatusDone;

  /// No description provided for @impStatusDoneErrors.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Done with 1 error} other{Done with {count} errors}}'**
  String impStatusDoneErrors(int count);

  /// No description provided for @impStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get impStatusFailed;

  /// No description provided for @impStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get impStatusCancelled;

  /// No description provided for @impPhaseReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the file'**
  String get impPhaseReading;

  /// No description provided for @impPhaseValidating.
  ///
  /// In en, this message translates to:
  /// **'Validating the rows'**
  String get impPhaseValidating;

  /// No description provided for @impPhaseWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing the records'**
  String get impPhaseWriting;

  /// No description provided for @impProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} rows'**
  String impProgress(int done, int total);

  /// No description provided for @impCancelJob.
  ///
  /// In en, this message translates to:
  /// **'Cancel job'**
  String get impCancelJob;

  /// No description provided for @impDownloadErrors.
  ///
  /// In en, this message translates to:
  /// **'Download error report'**
  String get impDownloadErrors;

  /// No description provided for @impErrorsTotal.
  ///
  /// In en, this message translates to:
  /// **'Showing the first {shown} of {total} problems. The error report lists the same problems. A file with very many problems lists only the first ones: fix these and check again.'**
  String impErrorsTotal(int shown, int total);

  /// No description provided for @impApplyHint.
  ///
  /// In en, this message translates to:
  /// **'Importing is possible after a check without problems.'**
  String get impApplyHint;

  /// No description provided for @impApplyAction.
  ///
  /// In en, this message translates to:
  /// **'Import now'**
  String get impApplyAction;

  /// No description provided for @impApplyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Import {entity}?'**
  String impApplyConfirmTitle(String entity);

  /// No description provided for @impApplyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{created} will be created and {updated} updated. This changes data.'**
  String impApplyConfirmBody(int created, int updated);

  /// No description provided for @impImportAnother.
  ///
  /// In en, this message translates to:
  /// **'Import another file'**
  String get impImportAnother;

  /// No description provided for @impHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No imports yet.'**
  String get impHistoryEmpty;

  /// No description provided for @impDryRun.
  ///
  /// In en, this message translates to:
  /// **'Check only'**
  String get impDryRun;

  /// No description provided for @impApplied.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get impApplied;

  /// No description provided for @impCountsPlanned.
  ///
  /// In en, this message translates to:
  /// **'{created} to create, {updated} to update, {unchanged} unchanged'**
  String impCountsPlanned(int created, int updated, int unchanged);

  /// No description provided for @impCountsDone.
  ///
  /// In en, this message translates to:
  /// **'{created} created, {updated} updated, {unchanged} unchanged'**
  String impCountsDone(int created, int updated, int unchanged);

  /// No description provided for @impJobBy.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String impJobBy(String name);

  /// No description provided for @impJobDetails.
  ///
  /// In en, this message translates to:
  /// **'Import details'**
  String get impJobDetails;

  /// No description provided for @impJobMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get impJobMessage;

  /// No description provided for @impJobSheet.
  ///
  /// In en, this message translates to:
  /// **'Sheet {sheet}'**
  String impJobSheet(String sheet);

  /// No description provided for @impRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get impRefresh;

  /// No description provided for @actionSendEmail.
  ///
  /// In en, this message translates to:
  /// **'Send e-mail'**
  String get actionSendEmail;

  /// No description provided for @mailRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get mailRecipient;

  /// No description provided for @mailRecipientCustomer.
  ///
  /// In en, this message translates to:
  /// **'The customer'**
  String get mailRecipientCustomer;

  /// No description provided for @mailRecipientAssignee.
  ///
  /// In en, this message translates to:
  /// **'The assignee'**
  String get mailRecipientAssignee;

  /// No description provided for @mailRecipientTeam.
  ///
  /// In en, this message translates to:
  /// **'A team'**
  String get mailRecipientTeam;

  /// No description provided for @mailRecipientAddress.
  ///
  /// In en, this message translates to:
  /// **'A fixed address'**
  String get mailRecipientAddress;

  /// No description provided for @mailAddress.
  ///
  /// In en, this message translates to:
  /// **'E-mail address'**
  String get mailAddress;

  /// No description provided for @mailBody.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get mailBody;

  /// No description provided for @mailPeriodHours.
  ///
  /// In en, this message translates to:
  /// **'At most one mail per ticket in (hours)'**
  String get mailPeriodHours;

  /// No description provided for @mailPeriodInvalid.
  ///
  /// In en, this message translates to:
  /// **'The period must be a whole number of hours.'**
  String get mailPeriodInvalid;

  /// No description provided for @mailPlaceholdersHint.
  ///
  /// In en, this message translates to:
  /// **'Placeholders: {placeholders}'**
  String mailPlaceholdersHint(String placeholders);

  /// No description provided for @actionSendEmailSummary.
  ///
  /// In en, this message translates to:
  /// **'{recipient}: {subject}'**
  String actionSendEmailSummary(String recipient, String subject);

  /// No description provided for @slaNotices.
  ///
  /// In en, this message translates to:
  /// **'Customer notices'**
  String get slaNotices;

  /// No description provided for @slaNoticesHelp.
  ///
  /// In en, this message translates to:
  /// **'Send the customer an acknowledgement with the ticket number and the target response time when a request arrives by e-mail or the portal, and optionally a notice when the first response time has run out (only during business hours). The most specific rule wins: team and priority, then team, then priority, then all. Nothing is sent without a rule. Mails are in the customer\'s language.'**
  String get slaNoticesHelp;

  /// No description provided for @slaNoticesNone.
  ///
  /// In en, this message translates to:
  /// **'No notices are sent to customers.'**
  String get slaNoticesNone;

  /// No description provided for @slaNoticesAllTeams.
  ///
  /// In en, this message translates to:
  /// **'All teams'**
  String get slaNoticesAllTeams;

  /// No description provided for @slaNoticesAllPriorities.
  ///
  /// In en, this message translates to:
  /// **'All priorities'**
  String get slaNoticesAllPriorities;

  /// No description provided for @slaNoticeAck.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgement'**
  String get slaNoticeAck;

  /// No description provided for @slaNoticeBreach.
  ///
  /// In en, this message translates to:
  /// **'Late notice'**
  String get slaNoticeBreach;

  /// No description provided for @slaNoticesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a rule'**
  String get slaNoticesAdd;

  /// No description provided for @rsTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled report mails'**
  String get rsTitle;

  /// No description provided for @rsOpen.
  ///
  /// In en, this message translates to:
  /// **'Scheduled mails'**
  String get rsOpen;

  /// No description provided for @rsHelp.
  ///
  /// In en, this message translates to:
  /// **'Mail a saved report or a helpdesk report on a schedule, as CSV or PDF, to colleagues and other addresses. Each mail is built with the permissions of the schedule\'s owner at the time it is sent.'**
  String get rsHelp;

  /// No description provided for @rsNew.
  ///
  /// In en, this message translates to:
  /// **'New schedule'**
  String get rsNew;

  /// No description provided for @rsEdit.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get rsEdit;

  /// No description provided for @rsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports are scheduled.'**
  String get rsEmpty;

  /// No description provided for @rsSource.
  ///
  /// In en, this message translates to:
  /// **'Kind of report'**
  String get rsSource;

  /// No description provided for @rsSourceCustom.
  ///
  /// In en, this message translates to:
  /// **'Saved report'**
  String get rsSourceCustom;

  /// No description provided for @rsSourceHelpdesk.
  ///
  /// In en, this message translates to:
  /// **'Helpdesk report'**
  String get rsSourceHelpdesk;

  /// No description provided for @rsReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get rsReport;

  /// No description provided for @rsTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get rsTable;

  /// No description provided for @rsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get rsPeriod;

  /// No description provided for @rsPeriodYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get rsPeriodYesterday;

  /// No description provided for @rsPeriodLast7.
  ///
  /// In en, this message translates to:
  /// **'The last 7 days'**
  String get rsPeriodLast7;

  /// No description provided for @rsPeriodLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last week (Monday to Sunday)'**
  String get rsPeriodLastWeek;

  /// No description provided for @rsPeriodLast30.
  ///
  /// In en, this message translates to:
  /// **'The last 30 days'**
  String get rsPeriodLast30;

  /// No description provided for @rsPeriodLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last calendar month'**
  String get rsPeriodLastMonth;

  /// No description provided for @rsFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get rsFrequency;

  /// No description provided for @rsDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get rsDaily;

  /// No description provided for @rsWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get rsWeekly;

  /// No description provided for @rsMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get rsMonthly;

  /// No description provided for @rsWeekday.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get rsWeekday;

  /// No description provided for @rsDayOfMonth.
  ///
  /// In en, this message translates to:
  /// **'Day of the month (1-28)'**
  String get rsDayOfMonth;

  /// No description provided for @rsTime.
  ///
  /// In en, this message translates to:
  /// **'Time (HH:MM)'**
  String get rsTime;

  /// No description provided for @rsFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get rsFormat;

  /// No description provided for @rsColleagues.
  ///
  /// In en, this message translates to:
  /// **'Colleagues'**
  String get rsColleagues;

  /// No description provided for @rsAddresses.
  ///
  /// In en, this message translates to:
  /// **'Other e-mail addresses (separated by commas)'**
  String get rsAddresses;

  /// No description provided for @rsMon.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get rsMon;

  /// No description provided for @rsTue.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get rsTue;

  /// No description provided for @rsWed.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get rsWed;

  /// No description provided for @rsThu.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get rsThu;

  /// No description provided for @rsFri.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get rsFri;

  /// No description provided for @rsSat.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get rsSat;

  /// No description provided for @rsSun.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get rsSun;

  /// No description provided for @rsSummary.
  ///
  /// In en, this message translates to:
  /// **'{when} · {format} · {recipients} recipients'**
  String rsSummary(String when, String format, int recipients);

  /// No description provided for @rsNextRun.
  ///
  /// In en, this message translates to:
  /// **'Next mail: {when}'**
  String rsNextRun(String when);

  /// No description provided for @rsLastSent.
  ///
  /// In en, this message translates to:
  /// **'Last run: queued {when}'**
  String rsLastSent(String when);

  /// No description provided for @rsLastFailed.
  ///
  /// In en, this message translates to:
  /// **'Last run failed ({when}): {reason}'**
  String rsLastFailed(String when, String reason);

  /// No description provided for @rsSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get rsSendNow;

  /// No description provided for @rsQueued.
  ///
  /// In en, this message translates to:
  /// **'{count} mails queued.'**
  String rsQueued(int count);

  /// No description provided for @rsPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get rsPaused;

  /// No description provided for @rsNeedsRecipient.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one recipient.'**
  String get rsNeedsRecipient;

  /// No description provided for @powerVoltageMin.
  ///
  /// In en, this message translates to:
  /// **'Min voltage (V)'**
  String get powerVoltageMin;

  /// No description provided for @powerVoltageMax.
  ///
  /// In en, this message translates to:
  /// **'Max voltage (V)'**
  String get powerVoltageMax;

  /// No description provided for @powerBoundsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional voltage range. Leave both empty to use the nominal voltage ± tolerance.'**
  String get powerBoundsHint;

  /// No description provided for @powerBoundsIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Enter both the minimum and the maximum voltage, or neither.'**
  String get powerBoundsIncomplete;

  /// No description provided for @powerBoundsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Voltage bounds must be whole numbers from 1 to 100000.'**
  String get powerBoundsInvalid;

  /// No description provided for @powerBoundsOrder.
  ///
  /// In en, this message translates to:
  /// **'The minimum voltage must not exceed the maximum.'**
  String get powerBoundsOrder;

  /// No description provided for @powerBoundsNominal.
  ///
  /// In en, this message translates to:
  /// **'The nominal voltage must lie within the minimum and maximum.'**
  String get powerBoundsNominal;

  /// No description provided for @suitabilityTab.
  ///
  /// In en, this message translates to:
  /// **'Suitability'**
  String get suitabilityTab;

  /// No description provided for @suitabilityHelp.
  ///
  /// In en, this message translates to:
  /// **'What this product is suitable for. Empty fields are not stored.'**
  String get suitabilityHelp;

  /// No description provided for @suitabilityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No product attributes are defined yet. An administrator can add them under Administration, Attributes.'**
  String get suitabilityEmpty;

  /// No description provided for @attrMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get attrMin;

  /// No description provided for @attrMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get attrMax;

  /// No description provided for @attrEnterNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number.'**
  String get attrEnterNumber;

  /// No description provided for @attrRangeIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Enter both the minimum and the maximum, or neither.'**
  String get attrRangeIncomplete;

  /// No description provided for @attrRangeOrder.
  ///
  /// In en, this message translates to:
  /// **'The minimum must not exceed the maximum.'**
  String get attrRangeOrder;

  /// No description provided for @attrNotInOptions.
  ///
  /// In en, this message translates to:
  /// **'Choose one of the listed options.'**
  String get attrNotInOptions;

  /// No description provided for @adminAttributes.
  ///
  /// In en, this message translates to:
  /// **'Attributes'**
  String get adminAttributes;

  /// No description provided for @attrDefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Attribute definitions'**
  String get attrDefsTitle;

  /// No description provided for @attrDefsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No attribute definitions yet.'**
  String get attrDefsEmpty;

  /// No description provided for @newAttrDef.
  ///
  /// In en, this message translates to:
  /// **'New attribute'**
  String get newAttrDef;

  /// No description provided for @editAttrDef.
  ///
  /// In en, this message translates to:
  /// **'Edit attribute'**
  String get editAttrDef;

  /// No description provided for @attrKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get attrKey;

  /// No description provided for @attrLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get attrLabel;

  /// No description provided for @attrScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get attrScope;

  /// No description provided for @attrKindNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get attrKindNumber;

  /// No description provided for @attrKindRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get attrKindRange;

  /// No description provided for @attrKindSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get attrKindSelect;

  /// No description provided for @attrKindText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get attrKindText;

  /// No description provided for @attrKindBoolean.
  ///
  /// In en, this message translates to:
  /// **'Yes/No'**
  String get attrKindBoolean;

  /// No description provided for @attrOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get attrOptions;

  /// No description provided for @attrOptionValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get attrOptionValue;

  /// No description provided for @attrOptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Option label'**
  String get attrOptionLabel;

  /// No description provided for @attrAddOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get attrAddOption;

  /// No description provided for @attrKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The key must be lowercase letters, digits and underscores, start with a letter and have at most 64 characters.'**
  String get attrKeyInvalid;

  /// No description provided for @attrLabelRequired.
  ///
  /// In en, this message translates to:
  /// **'A label is required.'**
  String get attrLabelRequired;

  /// No description provided for @attrSelectNeedsOptions.
  ///
  /// In en, this message translates to:
  /// **'A select needs at least one option.'**
  String get attrSelectNeedsOptions;

  /// No description provided for @attrOptionBlank.
  ///
  /// In en, this message translates to:
  /// **'Every option needs a value and a label.'**
  String get attrOptionBlank;

  /// No description provided for @attrOptionDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Option values must be unique.'**
  String get attrOptionDuplicate;

  /// No description provided for @attrDefDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete attribute {key}? If it is in use, deactivate it instead.'**
  String attrDefDeleteConfirm(String key);

  /// No description provided for @attrDefDeleted.
  ///
  /// In en, this message translates to:
  /// **'Attribute deleted.'**
  String get attrDefDeleted;

  /// No description provided for @baselineTitle.
  ///
  /// In en, this message translates to:
  /// **'Site baseline'**
  String get baselineTitle;

  /// No description provided for @baselineEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet. Add the clock dials and bells at the site so suitable products can be found.'**
  String get baselineEmpty;

  /// No description provided for @baselineAdd.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get baselineAdd;

  /// No description provided for @baselineNewItem.
  ///
  /// In en, this message translates to:
  /// **'New baseline item'**
  String get baselineNewItem;

  /// No description provided for @baselineEditItem.
  ///
  /// In en, this message translates to:
  /// **'Edit baseline item'**
  String get baselineEditItem;

  /// No description provided for @baselineParent.
  ///
  /// In en, this message translates to:
  /// **'Placed under'**
  String get baselineParent;

  /// No description provided for @baselineTopLevel.
  ///
  /// In en, this message translates to:
  /// **'Top level'**
  String get baselineTopLevel;

  /// No description provided for @baselineNoTypes.
  ///
  /// In en, this message translates to:
  /// **'No baseline item types are available. An administrator can add them under Administration, Baseline types.'**
  String get baselineNoTypes;

  /// No description provided for @baselineNoFields.
  ///
  /// In en, this message translates to:
  /// **'This type has no attributes defined.'**
  String get baselineNoFields;

  /// No description provided for @baselineTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an item type.'**
  String get baselineTypeRequired;

  /// No description provided for @baselineParentRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the item to place this under.'**
  String get baselineParentRequired;

  /// No description provided for @baselineQuantityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be a whole number of at least 1.'**
  String get baselineQuantityInvalid;

  /// No description provided for @baselineQty.
  ///
  /// In en, this message translates to:
  /// **'Qty {count}'**
  String baselineQty(int count);

  /// No description provided for @baselineDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String baselineDeleteConfirm(String name);

  /// No description provided for @baselineDeleted.
  ///
  /// In en, this message translates to:
  /// **'Item deleted.'**
  String get baselineDeleted;

  /// No description provided for @adminBaselineTypes.
  ///
  /// In en, this message translates to:
  /// **'Baseline types'**
  String get adminBaselineTypes;

  /// No description provided for @baselineTypesTitle.
  ///
  /// In en, this message translates to:
  /// **'Baseline item types'**
  String get baselineTypesTitle;

  /// No description provided for @baselineTypesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No baseline item types yet.'**
  String get baselineTypesEmpty;

  /// No description provided for @newBaselineType.
  ///
  /// In en, this message translates to:
  /// **'New baseline type'**
  String get newBaselineType;

  /// No description provided for @editBaselineType.
  ///
  /// In en, this message translates to:
  /// **'Edit baseline type'**
  String get editBaselineType;

  /// No description provided for @baselineTypeParents.
  ///
  /// In en, this message translates to:
  /// **'Allowed parent types'**
  String get baselineTypeParents;

  /// No description provided for @baselineTypeTopLevel.
  ///
  /// In en, this message translates to:
  /// **'Can stand at the top level'**
  String get baselineTypeTopLevel;

  /// No description provided for @baselineTypeCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'The code must be lowercase letters, digits and underscores, start with a letter and have at most 64 characters.'**
  String get baselineTypeCodeInvalid;

  /// No description provided for @baselineTypeCodeReserved.
  ///
  /// In en, this message translates to:
  /// **'The code product is reserved for the product attributes; choose another code.'**
  String get baselineTypeCodeReserved;

  /// No description provided for @baselineTypeNameRequired.
  ///
  /// In en, this message translates to:
  /// **'A name is required.'**
  String get baselineTypeNameRequired;

  /// No description provided for @baselineTypePlacement.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one parent type or allow the top level, or items of this type could never be placed.'**
  String get baselineTypePlacement;

  /// No description provided for @baselineTypeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete type {code}? If it is in use, deactivate it instead.'**
  String baselineTypeDeleteConfirm(String code);

  /// No description provided for @baselineTypeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Baseline type deleted.'**
  String get baselineTypeDeleted;

  /// No description provided for @attrScopeProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get attrScopeProduct;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Product matches'**
  String get matchesTitle;

  /// No description provided for @matchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No products to show.'**
  String get matchesEmpty;

  /// No description provided for @matchesShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} products'**
  String matchesShowing(int shown, int total);

  /// No description provided for @matchesSuggest.
  ///
  /// In en, this message translates to:
  /// **'Suggest products'**
  String get matchesSuggest;

  /// No description provided for @matchesForItem.
  ///
  /// In en, this message translates to:
  /// **'Products for {name}'**
  String matchesForItem(String name);

  /// No description provided for @matchesSuitable.
  ///
  /// In en, this message translates to:
  /// **'Suitable'**
  String get matchesSuitable;

  /// No description provided for @matchesUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get matchesUnknown;

  /// No description provided for @matchesUnsuitable.
  ///
  /// In en, this message translates to:
  /// **'Not suitable'**
  String get matchesUnsuitable;

  /// No description provided for @matchesNoReason.
  ///
  /// In en, this message translates to:
  /// **'Could not be judged.'**
  String get matchesNoReason;

  /// No description provided for @baselineUnknownSet.
  ///
  /// In en, this message translates to:
  /// **'{label}: unknown — set'**
  String baselineUnknownSet(String label);

  /// No description provided for @baselineImportTower.
  ///
  /// In en, this message translates to:
  /// **'Import from tower configurator'**
  String get baselineImportTower;

  /// No description provided for @baselineImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import preview'**
  String get baselineImportTitle;

  /// No description provided for @baselineImportCreates.
  ///
  /// In en, this message translates to:
  /// **'Creates {groups} bell group(s), {bells} bell(s) and {dials} clock dial(s).'**
  String baselineImportCreates(int groups, int bells, int dials);

  /// No description provided for @baselineImportReplaces.
  ///
  /// In en, this message translates to:
  /// **'This replaces {count} item(s) from a previous import of the same source; items entered by hand are kept.'**
  String baselineImportReplaces(int count);

  /// No description provided for @baselineImportFresh.
  ///
  /// In en, this message translates to:
  /// **'There is no previous import to replace.'**
  String get baselineImportFresh;

  /// No description provided for @baselineImportWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get baselineImportWarnings;

  /// No description provided for @baselineImportWarning.
  ///
  /// In en, this message translates to:
  /// **'{bell}, {field}: {message}'**
  String baselineImportWarning(String bell, String field, String message);

  /// No description provided for @baselineImportUnmapped.
  ///
  /// In en, this message translates to:
  /// **'Fields not mapped (kept with the imported item)'**
  String get baselineImportUnmapped;

  /// No description provided for @baselineImportUnmappedRow.
  ///
  /// In en, this message translates to:
  /// **'{field} ({count})'**
  String baselineImportUnmappedRow(String field, int count);

  /// No description provided for @baselineImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get baselineImportConfirm;

  /// No description provided for @baselineImportDone.
  ///
  /// In en, this message translates to:
  /// **'Baseline imported.'**
  String get baselineImportDone;

  /// No description provided for @baselineImportBadFile.
  ///
  /// In en, this message translates to:
  /// **'This file is not valid JSON.'**
  String get baselineImportBadFile;

  /// No description provided for @baselineImportReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read.'**
  String get baselineImportReadFailed;

  /// No description provided for @baselineImported.
  ///
  /// In en, this message translates to:
  /// **'imported'**
  String get baselineImported;

  /// No description provided for @plTitle.
  ///
  /// In en, this message translates to:
  /// **'Price lists'**
  String get plTitle;

  /// No description provided for @plNew.
  ///
  /// In en, this message translates to:
  /// **'New price list'**
  String get plNew;

  /// No description provided for @plEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit price list'**
  String get plEdit;

  /// No description provided for @plNone.
  ///
  /// In en, this message translates to:
  /// **'No price lists yet.'**
  String get plNone;

  /// No description provided for @plDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete price list {code} with its groups and items? Products and prices are not affected.'**
  String plDeleteConfirm(String code);

  /// No description provided for @plDeleted.
  ///
  /// In en, this message translates to:
  /// **'Price list deleted'**
  String get plDeleted;

  /// No description provided for @plShowLogo.
  ///
  /// In en, this message translates to:
  /// **'Print the company logo'**
  String get plShowLogo;

  /// No description provided for @plProductCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products'**
  String plProductCount(int count);

  /// No description provided for @plOpen.
  ///
  /// In en, this message translates to:
  /// **'Edit layout'**
  String get plOpen;

  /// No description provided for @plBack.
  ///
  /// In en, this message translates to:
  /// **'Price lists'**
  String get plBack;

  /// No description provided for @plGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get plGroups;

  /// No description provided for @plAddGroup.
  ///
  /// In en, this message translates to:
  /// **'Add group'**
  String get plAddGroup;

  /// No description provided for @plAddSubgroup.
  ///
  /// In en, this message translates to:
  /// **'Add subgroup'**
  String get plAddSubgroup;

  /// No description provided for @plGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Group title'**
  String get plGroupTitle;

  /// No description provided for @plGroupTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a title in at least one language.'**
  String get plGroupTitleRequired;

  /// No description provided for @plPageBreak.
  ///
  /// In en, this message translates to:
  /// **'Page break before'**
  String get plPageBreak;

  /// No description provided for @plShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Print title'**
  String get plShowTitle;

  /// No description provided for @plGapMm.
  ///
  /// In en, this message translates to:
  /// **'Gap (mm)'**
  String get plGapMm;

  /// No description provided for @plGapInvalid.
  ///
  /// In en, this message translates to:
  /// **'The gap must be a number from 0 to 50.'**
  String get plGapInvalid;

  /// No description provided for @plIndent.
  ///
  /// In en, this message translates to:
  /// **'Make subgroup of the group above'**
  String get plIndent;

  /// No description provided for @plOutdent.
  ///
  /// In en, this message translates to:
  /// **'Move up one level'**
  String get plOutdent;

  /// No description provided for @plDepthMax.
  ///
  /// In en, this message translates to:
  /// **'Groups can be nested at most four levels deep.'**
  String get plDepthMax;

  /// No description provided for @plDeleteGroupConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{title}\"? Only empty groups can be deleted.'**
  String plDeleteGroupConfirm(String title);

  /// No description provided for @plNoGroups.
  ///
  /// In en, this message translates to:
  /// **'Add a group first, then add products to it.'**
  String get plNoGroups;

  /// No description provided for @plTitleHidden.
  ///
  /// In en, this message translates to:
  /// **'title not printed'**
  String get plTitleHidden;

  /// No description provided for @plItems.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get plItems;

  /// No description provided for @plAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get plAddProduct;

  /// No description provided for @plSortKey.
  ///
  /// In en, this message translates to:
  /// **'Sort key'**
  String get plSortKey;

  /// No description provided for @plSortKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use dotted letters and digits, for example 2.10.3.'**
  String get plSortKeyInvalid;

  /// No description provided for @plGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get plGroup;

  /// No description provided for @plPriceOnRequest.
  ///
  /// In en, this message translates to:
  /// **'Price on request'**
  String get plPriceOnRequest;

  /// No description provided for @plNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get plNet;

  /// No description provided for @plIndicative.
  ///
  /// In en, this message translates to:
  /// **'Indicative'**
  String get plIndicative;

  /// No description provided for @plHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get plHidden;

  /// No description provided for @plDescriptionOverride.
  ///
  /// In en, this message translates to:
  /// **'Description (replaces the product name)'**
  String get plDescriptionOverride;

  /// No description provided for @plNoItems.
  ///
  /// In en, this message translates to:
  /// **'No products in this list yet.'**
  String get plNoItems;

  /// No description provided for @plNotPrintedNote.
  ///
  /// In en, this message translates to:
  /// **'Hidden products, and products without a zone price that are not \"price on request\", are not printed.'**
  String get plNotPrintedNote;

  /// No description provided for @plNotPrinted.
  ///
  /// In en, this message translates to:
  /// **'not printed'**
  String get plNotPrinted;

  /// No description provided for @plGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get plGenerate;

  /// No description provided for @plGeneratePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get plGeneratePdf;

  /// No description provided for @plGenerateXlsx.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get plGenerateXlsx;

  /// No description provided for @adminCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get adminCompany;

  /// No description provided for @logoTitle.
  ///
  /// In en, this message translates to:
  /// **'Company logo'**
  String get logoTitle;

  /// No description provided for @logoHint.
  ///
  /// In en, this message translates to:
  /// **'PNG, JPEG or SVG, at most 512 KB. Printed in the header of price lists.'**
  String get logoHint;

  /// No description provided for @logoNone.
  ///
  /// In en, this message translates to:
  /// **'No logo uploaded.'**
  String get logoNone;

  /// No description provided for @logoChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get logoChoose;

  /// No description provided for @logoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove logo'**
  String get logoRemove;

  /// No description provided for @logoRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the company logo?'**
  String get logoRemoveConfirm;

  /// No description provided for @logoTooBig.
  ///
  /// In en, this message translates to:
  /// **'The file is larger than 512 KB.'**
  String get logoTooBig;

  /// No description provided for @logoBadType.
  ///
  /// In en, this message translates to:
  /// **'Only PNG, JPEG or SVG files are accepted.'**
  String get logoBadType;

  /// No description provided for @logoSaved.
  ///
  /// In en, this message translates to:
  /// **'Logo saved'**
  String get logoSaved;

  /// No description provided for @logoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Logo removed'**
  String get logoRemoved;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @fileSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String fileSavedTo(String path);

  /// No description provided for @plZones.
  ///
  /// In en, this message translates to:
  /// **'Zones and languages'**
  String get plZones;

  /// No description provided for @plZonesHint.
  ///
  /// In en, this message translates to:
  /// **'The list is published for these zones, in this order, each in its own languages. The first language of a zone is its default.'**
  String get plZonesHint;

  /// No description provided for @plNoZones.
  ///
  /// In en, this message translates to:
  /// **'No zones yet. Add a zone to be able to generate files.'**
  String get plNoZones;

  /// No description provided for @plAddZone.
  ///
  /// In en, this message translates to:
  /// **'Add zone'**
  String get plAddZone;

  /// No description provided for @plExports.
  ///
  /// In en, this message translates to:
  /// **'Export profiles'**
  String get plExports;

  /// No description provided for @plExportsHint.
  ///
  /// In en, this message translates to:
  /// **'Each profile is one file per zone and language, with the chapters you choose. The whole list is always generated as well.'**
  String get plExportsHint;

  /// No description provided for @plNoExports.
  ///
  /// In en, this message translates to:
  /// **'No export profiles yet.'**
  String get plNoExports;

  /// No description provided for @plAddExport.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get plAddExport;

  /// No description provided for @plEditExport.
  ///
  /// In en, this message translates to:
  /// **'Edit export profile'**
  String get plEditExport;

  /// No description provided for @plPerChapter.
  ///
  /// In en, this message translates to:
  /// **'One profile per chapter'**
  String get plPerChapter;

  /// No description provided for @plPerLevelTitle.
  ///
  /// In en, this message translates to:
  /// **'One profile per level'**
  String get plPerLevelTitle;

  /// No description provided for @plPerLevelHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the level of the groups that each get a profile (level 1 = top level). Groups that already have a profile of their own are skipped.'**
  String get plPerLevelHint;

  /// No description provided for @plLevelN.
  ///
  /// In en, this message translates to:
  /// **'Level {n}'**
  String plLevelN(int n);

  /// No description provided for @plWholeList.
  ///
  /// In en, this message translates to:
  /// **'Whole list'**
  String get plWholeList;

  /// No description provided for @plExportDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete export profile \"{name}\"?'**
  String plExportDeleteConfirm(String name);

  /// No description provided for @plExportCodeLength.
  ///
  /// In en, this message translates to:
  /// **'The code can have at most 32 characters.'**
  String get plExportCodeLength;

  /// No description provided for @plChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get plChapters;

  /// No description provided for @plChaptersHint.
  ///
  /// In en, this message translates to:
  /// **'Tick the groups in this file, at any level. Everything below a ticked group is included automatically. None ticked means the whole list.'**
  String get plChaptersHint;

  /// No description provided for @plFileName.
  ///
  /// In en, this message translates to:
  /// **'File name template (optional)'**
  String get plFileName;

  /// No description provided for @plFileNameHint.
  ///
  /// In en, this message translates to:
  /// **'Placeholders: {placeholders}. Without a template the profile name is used.'**
  String plFileNameHint(String placeholders);

  /// No description provided for @plGroupInUseTitle.
  ///
  /// In en, this message translates to:
  /// **'Group is in use'**
  String get plGroupInUseTitle;

  /// No description provided for @plGenSummary.
  ///
  /// In en, this message translates to:
  /// **'{written} of {total} files saved'**
  String plGenSummary(int written, int total);

  /// No description provided for @plGenTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder: {folder}'**
  String plGenTargetFolder(String folder);

  /// No description provided for @plGenSentToBrowser.
  ///
  /// In en, this message translates to:
  /// **'The files were handed to the browser or the share sheet.'**
  String get plGenSentToBrowser;

  /// No description provided for @plGenDownloads.
  ///
  /// In en, this message translates to:
  /// **'Folder: Downloads'**
  String get plGenDownloads;

  /// No description provided for @plGenChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get plGenChooseFolder;

  /// No description provided for @plGenNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to generate: add zones and chapters first.'**
  String get plGenNothing;

  /// No description provided for @plGenProgress.
  ///
  /// In en, this message translates to:
  /// **'File {current} of {total}: {file}'**
  String plGenProgress(int current, int total, String file);

  /// No description provided for @plGenOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get plGenOpenFolder;

  /// No description provided for @plGenBack.
  ///
  /// In en, this message translates to:
  /// **'Back to the plan'**
  String get plGenBack;

  /// No description provided for @vatRegimeDomesticReverseCharge.
  ///
  /// In en, this message translates to:
  /// **'Domestic reverse charge (construction)'**
  String get vatRegimeDomesticReverseCharge;

  /// No description provided for @vatRegimeOverride.
  ///
  /// In en, this message translates to:
  /// **'VAT regime override'**
  String get vatRegimeOverride;

  /// No description provided for @vatRegimeAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (default)'**
  String get vatRegimeAuto;

  /// No description provided for @domesticReverseChargeNotice.
  ///
  /// In en, this message translates to:
  /// **'VAT reverse charge — work on immovable property'**
  String get domesticReverseChargeNotice;

  /// No description provided for @buildingConstructionYear.
  ///
  /// In en, this message translates to:
  /// **'Building construction year'**
  String get buildingConstructionYear;

  /// No description provided for @buildingConstructionYearHint.
  ///
  /// In en, this message translates to:
  /// **'Optional (800–2200) for renovation VAT rules'**
  String get buildingConstructionYearHint;

  /// No description provided for @buildingConstructionYearError.
  ///
  /// In en, this message translates to:
  /// **'Enter a year between 800 and 2200'**
  String get buildingConstructionYearError;

  /// No description provided for @vatCategory.
  ///
  /// In en, this message translates to:
  /// **'VAT category'**
  String get vatCategory;

  /// No description provided for @vatCategoryStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get vatCategoryStandard;

  /// No description provided for @vatCategoryIntermediate.
  ///
  /// In en, this message translates to:
  /// **'Intermediate'**
  String get vatCategoryIntermediate;

  /// No description provided for @vatCategoryReduced.
  ///
  /// In en, this message translates to:
  /// **'Reduced'**
  String get vatCategoryReduced;

  /// No description provided for @vatCategoryZero.
  ///
  /// In en, this message translates to:
  /// **'Zero rate'**
  String get vatCategoryZero;

  /// No description provided for @vatCategoryConstruction.
  ///
  /// In en, this message translates to:
  /// **'Construction (renovation)'**
  String get vatCategoryConstruction;

  /// No description provided for @vatRateOverride.
  ///
  /// In en, this message translates to:
  /// **'Custom VAT rate override (%)'**
  String get vatRateOverride;

  /// No description provided for @vatRateOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the company\'s country default'**
  String get vatRateOverrideHint;

  /// No description provided for @adminVatRates.
  ///
  /// In en, this message translates to:
  /// **'VAT rates'**
  String get adminVatRates;

  /// No description provided for @vatRatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Country VAT rates'**
  String get vatRatesTitle;

  /// No description provided for @vatRateAdd.
  ///
  /// In en, this message translates to:
  /// **'Add VAT rate'**
  String get vatRateAdd;

  /// No description provided for @vatRateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit VAT rate'**
  String get vatRateEdit;

  /// No description provided for @vatRateCountry.
  ///
  /// In en, this message translates to:
  /// **'Country code'**
  String get vatRateCountry;

  /// No description provided for @vatRateCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get vatRateCategory;

  /// No description provided for @vatRatePercent.
  ///
  /// In en, this message translates to:
  /// **'Rate (%)'**
  String get vatRatePercent;

  /// No description provided for @vatRateMinBuildingAge.
  ///
  /// In en, this message translates to:
  /// **'Min. building age (years)'**
  String get vatRateMinBuildingAge;

  /// No description provided for @vatRateStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date (YYYY-MM-DD)'**
  String get vatRateStartDate;

  /// No description provided for @vatRateEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date (optional)'**
  String get vatRateEndDate;

  /// No description provided for @vatRateNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get vatRateNotes;

  /// No description provided for @vatRateClosePrevious.
  ///
  /// In en, this message translates to:
  /// **'Close previous open rule automatically'**
  String get vatRateClosePrevious;

  /// No description provided for @vatRateOverlapError.
  ///
  /// In en, this message translates to:
  /// **'Dates overlap an existing rule for this country and category'**
  String get vatRateOverlapError;

  /// No description provided for @vatRateDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete VAT rate rule for {country} ({category})?'**
  String vatRateDeleteConfirm(String country, String category);

  /// No description provided for @vatRateOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get vatRateOngoing;

  /// No description provided for @reloadRecord.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reloadRecord;

  /// No description provided for @recordUpdatedBy.
  ///
  /// In en, this message translates to:
  /// **'Updated by {name}. Reload to see the latest changes.'**
  String recordUpdatedBy(String name);

  /// No description provided for @recordConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'Someone else saved changes to this record. Reload to see their changes before saving again.'**
  String get recordConflictMessage;

  /// No description provided for @ticketLiveChange.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, note{{name} added a message.} escalated{{name} escalated this ticket.} delegated{{name} handed this ticket over.} tag{{name} changed the tags.} timeEntry{{name} logged time.} merge{{name} merged tickets.} split{{name} split this ticket.} attachment{{name} added an attachment.} checklist{{name} changed the checklist.} links{{name} changed the linked tickets.} other{{name} changed this ticket.}}'**
  String ticketLiveChange(String kind, String name);

  /// No description provided for @ticketLiveUnsaved.
  ///
  /// In en, this message translates to:
  /// **'{name} changed this ticket while you have unsaved edits. Compare before you save.'**
  String ticketLiveUnsaved(String name);

  /// No description provided for @ticketLiveMerged.
  ///
  /// In en, this message translates to:
  /// **'{name} changed this ticket. Their changes were merged into your form.'**
  String ticketLiveMerged(String name);

  /// No description provided for @ticketMergeSomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get ticketMergeSomeone;

  /// No description provided for @linksTitle.
  ///
  /// In en, this message translates to:
  /// **'Linked tickets'**
  String get linksTitle;

  /// No description provided for @linksNone.
  ///
  /// In en, this message translates to:
  /// **'No linked tickets.'**
  String get linksNone;

  /// No description provided for @linksAdd.
  ///
  /// In en, this message translates to:
  /// **'Add link…'**
  String get linksAdd;

  /// No description provided for @linksAddAction.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linksAddAction;

  /// No description provided for @linksParent.
  ///
  /// In en, this message translates to:
  /// **'Part of the bundle of'**
  String get linksParent;

  /// No description provided for @linksChildren.
  ///
  /// In en, this message translates to:
  /// **'Bundle'**
  String get linksChildren;

  /// No description provided for @linksBundleProgress.
  ///
  /// In en, this message translates to:
  /// **'{open} of {total} still open'**
  String linksBundleProgress(int open, int total);

  /// No description provided for @linksRelated.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get linksRelated;

  /// No description provided for @linksDuplicateOf.
  ///
  /// In en, this message translates to:
  /// **'Duplicate of'**
  String get linksDuplicateOf;

  /// No description provided for @linksDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Duplicates'**
  String get linksDuplicates;

  /// No description provided for @linksMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get linksMerged;

  /// No description provided for @linksRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get linksRemove;

  /// No description provided for @linksSearch.
  ///
  /// In en, this message translates to:
  /// **'Search tickets'**
  String get linksSearch;

  /// No description provided for @linksNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No tickets found.'**
  String get linksNoMatches;

  /// No description provided for @linksRelationChild.
  ///
  /// In en, this message translates to:
  /// **'Add the other ticket to this bundle'**
  String get linksRelationChild;

  /// No description provided for @linksRelationParent.
  ///
  /// In en, this message translates to:
  /// **'Join the bundle of the other ticket'**
  String get linksRelationParent;

  /// No description provided for @linksRelationRelated.
  ///
  /// In en, this message translates to:
  /// **'Related to the other ticket'**
  String get linksRelationRelated;

  /// No description provided for @linksRelationDuplicateOf.
  ///
  /// In en, this message translates to:
  /// **'This ticket is a duplicate of the other'**
  String get linksRelationDuplicateOf;

  /// No description provided for @linksRelationDuplicatedBy.
  ///
  /// In en, this message translates to:
  /// **'The other ticket is a duplicate of this one'**
  String get linksRelationDuplicatedBy;

  /// No description provided for @bundleUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update bundle…'**
  String get bundleUpdate;

  /// No description provided for @bundleUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update the bundle'**
  String get bundleUpdateTitle;

  /// No description provided for @bundleUpdateHelp.
  ///
  /// In en, this message translates to:
  /// **'Send the same reply, note or status to every ticket in the bundle. You see what would happen first; nothing changes until you apply.'**
  String get bundleUpdateHelp;

  /// No description provided for @bundleActionReply.
  ///
  /// In en, this message translates to:
  /// **'Reply to the customers'**
  String get bundleActionReply;

  /// No description provided for @bundleActionNote.
  ///
  /// In en, this message translates to:
  /// **'Internal note'**
  String get bundleActionNote;

  /// No description provided for @bundleActionStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get bundleActionStatus;

  /// No description provided for @bundleStatusAfter.
  ///
  /// In en, this message translates to:
  /// **'Status afterwards'**
  String get bundleStatusAfter;

  /// No description provided for @bundleStatusUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get bundleStatusUnchanged;

  /// No description provided for @bundlePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get bundlePreview;

  /// No description provided for @bundleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get bundleEdit;

  /// No description provided for @bundleApply.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Apply to 1 ticket} other{Apply to {count} tickets}}'**
  String bundleApply(int count);

  /// No description provided for @bundleDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 ticket updated.} other{{count} tickets updated.}}'**
  String bundleDone(int count);

  /// No description provided for @bundleOutcomeWouldApply.
  ///
  /// In en, this message translates to:
  /// **'Will be updated'**
  String get bundleOutcomeWouldApply;

  /// No description provided for @bundleOutcomeApplied.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get bundleOutcomeApplied;

  /// No description provided for @bundleOutcomeSkipped.
  ///
  /// In en, this message translates to:
  /// **'Left out'**
  String get bundleOutcomeSkipped;

  /// No description provided for @bundleOutcomeFailed.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get bundleOutcomeFailed;

  /// No description provided for @bundleRecipient.
  ///
  /// In en, this message translates to:
  /// **'to {email}'**
  String bundleRecipient(String email);

  /// No description provided for @ticketMergeCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get ticketMergeCompare;

  /// No description provided for @ticketMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your changes and theirs'**
  String get ticketMergeTitle;

  /// No description provided for @ticketMergeIntro.
  ///
  /// In en, this message translates to:
  /// **'{name} saved changes to fields you also edited. Choose which value to keep for each.'**
  String ticketMergeIntro(String name);

  /// No description provided for @ticketMergeMine.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get ticketMergeMine;

  /// No description provided for @ticketMergeTheirs.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s'**
  String ticketMergeTheirs(String name);

  /// No description provided for @ticketMergeApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get ticketMergeApply;

  /// No description provided for @ticketMergeEmpty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get ticketMergeEmpty;

  /// No description provided for @ticketMergeTakenOver.
  ///
  /// In en, this message translates to:
  /// **'Also taken over from their change: {fields}'**
  String ticketMergeTakenOver(String fields);

  /// No description provided for @checklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklistTitle;

  /// No description provided for @checklistProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total}'**
  String checklistProgress(int done, int total);

  /// No description provided for @checklistAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add checklist item'**
  String get checklistAddItem;

  /// No description provided for @checklistApplyTemplate.
  ///
  /// In en, this message translates to:
  /// **'Apply template'**
  String get checklistApplyTemplate;

  /// No description provided for @checklistNoTemplates.
  ///
  /// In en, this message translates to:
  /// **'No checklist templates available'**
  String get checklistNoTemplates;

  /// No description provided for @checklistEmpty.
  ///
  /// In en, this message translates to:
  /// **'No checklist items yet'**
  String get checklistEmpty;

  /// No description provided for @checklistTemplatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Checklist templates'**
  String get checklistTemplatesTitle;

  /// No description provided for @checklistTemplateNew.
  ///
  /// In en, this message translates to:
  /// **'New checklist template'**
  String get checklistTemplateNew;

  /// No description provided for @checklistTemplateName.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get checklistTemplateName;

  /// No description provided for @checklistTemplateItemsHint.
  ///
  /// In en, this message translates to:
  /// **'Items (one per line)'**
  String get checklistTemplateItemsHint;

  /// No description provided for @teamRequireChecklistDone.
  ///
  /// In en, this message translates to:
  /// **'Require checklist done before closing'**
  String get teamRequireChecklistDone;

  /// No description provided for @ticketCloseBlockedChecklist.
  ///
  /// In en, this message translates to:
  /// **'Complete all checklist items before closing this ticket'**
  String get ticketCloseBlockedChecklist;

  /// No description provided for @automationActionApplyChecklist.
  ///
  /// In en, this message translates to:
  /// **'Apply checklist'**
  String get automationActionApplyChecklist;

  /// No description provided for @automationTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Checklist template'**
  String get automationTemplateLabel;

  /// No description provided for @answerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get answerUnavailable;

  /// No description provided for @themeMenu.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeMenu;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @appSwitcherTitle.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get appSwitcherTitle;

  /// No description provided for @appSwitcherTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch application'**
  String get appSwitcherTooltip;

  /// No description provided for @breadcrumbLabel.
  ///
  /// In en, this message translates to:
  /// **'Breadcrumbs'**
  String get breadcrumbLabel;

  /// No description provided for @appGroupSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get appGroupSales;

  /// No description provided for @appGroupService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get appGroupService;

  /// No description provided for @appGroupOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get appGroupOperations;

  /// No description provided for @appGroupMasterData.
  ///
  /// In en, this message translates to:
  /// **'Master data'**
  String get appGroupMasterData;

  /// No description provided for @appGroupBackOffice.
  ///
  /// In en, this message translates to:
  /// **'Back office'**
  String get appGroupBackOffice;

  /// No description provided for @appGroupInsight.
  ///
  /// In en, this message translates to:
  /// **'Insight'**
  String get appGroupInsight;

  /// No description provided for @globalSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search ({shortcut})'**
  String globalSearchTooltip(String shortcut);

  /// No description provided for @globalSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search records and sections'**
  String get globalSearchHint;

  /// No description provided for @globalSearchGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get globalSearchGoTo;

  /// No description provided for @globalSearchStart.
  ///
  /// In en, this message translates to:
  /// **'Type to search customers, orders, tickets and more.'**
  String get globalSearchStart;

  /// No description provided for @globalSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String globalSearchEmpty(String query);

  /// No description provided for @globalSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'{entity} could not be searched'**
  String globalSearchFailed(String entity);

  /// No description provided for @globalSearchSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get globalSearchSuppliers;

  /// No description provided for @globalSearchSupplierInvoices.
  ///
  /// In en, this message translates to:
  /// **'Supplier invoices'**
  String get globalSearchSupplierInvoices;

  /// No description provided for @notificationsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTooltip;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs your attention'**
  String get notificationsEmpty;

  /// No description provided for @notificationsOverdueTodos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue to-do} other{{count} overdue to-dos}}'**
  String notificationsOverdueTodos(int count);

  /// No description provided for @notificationsOpenTodos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open to-do} other{{count} open to-dos}}'**
  String notificationsOpenTodos(int count);

  /// No description provided for @notificationsTodosDueToday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 due today} other{{count} due today}}'**
  String notificationsTodosDueToday(int count);

  /// No description provided for @notificationsWorkerDown.
  ///
  /// In en, this message translates to:
  /// **'The background worker is down'**
  String get notificationsWorkerDown;

  /// No description provided for @notificationsWorkerNeverSeen.
  ///
  /// In en, this message translates to:
  /// **'The background worker has never reported'**
  String get notificationsWorkerNeverSeen;

  /// No description provided for @notificationsWorkerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mail is neither sent nor fetched'**
  String get notificationsWorkerSubtitle;

  /// No description provided for @listColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get listColumns;

  /// No description provided for @listResetLayout.
  ///
  /// In en, this message translates to:
  /// **'Reset layout'**
  String get listResetLayout;

  /// No description provided for @listSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by {column}'**
  String listSortBy(String column);

  /// No description provided for @listSortedAscending.
  ///
  /// In en, this message translates to:
  /// **'sorted ascending'**
  String get listSortedAscending;

  /// No description provided for @listSortedDescending.
  ///
  /// In en, this message translates to:
  /// **'sorted descending'**
  String get listSortedDescending;

  /// No description provided for @listNotSorted.
  ///
  /// In en, this message translates to:
  /// **'not sorted'**
  String get listNotSorted;

  /// No description provided for @listResizeColumn.
  ///
  /// In en, this message translates to:
  /// **'Resize column {column}'**
  String listResizeColumn(String column);

  /// No description provided for @listSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all loaded rows'**
  String get listSelectAll;

  /// No description provided for @listSelectRow.
  ///
  /// In en, this message translates to:
  /// **'Select {name}'**
  String listSelectRow(String name);

  /// No description provided for @listSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String listSelectedCount(int count);

  /// No description provided for @listClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get listClearSelection;

  /// No description provided for @listConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get listConfirm;

  /// No description provided for @listFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get listFilters;

  /// No description provided for @listClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get listClearFilters;

  /// No description provided for @listOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get listOr;

  /// No description provided for @listRemoveFilter.
  ///
  /// In en, this message translates to:
  /// **'Remove filter {filter}'**
  String listRemoveFilter(String filter);

  /// No description provided for @listFiltersActive.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String listFiltersActive(int count);

  /// No description provided for @listFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get listFavourites;

  /// No description provided for @listSaveFavourite.
  ///
  /// In en, this message translates to:
  /// **'Save current view as favourite'**
  String get listSaveFavourite;

  /// No description provided for @listFavouriteName.
  ///
  /// In en, this message translates to:
  /// **'Favourite name'**
  String get listFavouriteName;

  /// No description provided for @listNoFavourites.
  ///
  /// In en, this message translates to:
  /// **'No favourites yet'**
  String get listNoFavourites;

  /// No description provided for @listDeleteFavourite.
  ///
  /// In en, this message translates to:
  /// **'Delete favourite {name}'**
  String listDeleteFavourite(String name);

  /// No description provided for @listApplyFavourite.
  ///
  /// In en, this message translates to:
  /// **'Apply favourite {name}'**
  String listApplyFavourite(String name);

  /// No description provided for @formChooseFromList.
  ///
  /// In en, this message translates to:
  /// **'Choose an entry from the list'**
  String get formChooseFromList;

  /// No description provided for @formClearValue.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get formClearValue;

  /// No description provided for @formOpenRecord.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String formOpenRecord(String name);

  /// No description provided for @formStatusCurrent.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String formStatusCurrent(String status);

  /// No description provided for @formUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get formUnsavedChanges;

  /// No description provided for @chatterTitle.
  ///
  /// In en, this message translates to:
  /// **'Chatter'**
  String get chatterTitle;

  /// No description provided for @chatterNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Write a note…'**
  String get chatterNoteHint;

  /// No description provided for @chatterPost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get chatterPost;

  /// No description provided for @chatterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get chatterEmpty;

  /// No description provided for @chatterEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get chatterEdited;

  /// No description provided for @chatterEditNote.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get chatterEditNote;

  /// No description provided for @chatterDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chatterDeleteNote;

  /// No description provided for @chatterSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get chatterSaveNote;

  /// No description provided for @chatterLoadOlder.
  ///
  /// In en, this message translates to:
  /// **'Show older'**
  String get chatterLoadOlder;

  /// No description provided for @chatterFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get chatterFollow;

  /// No description provided for @chatterFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get chatterFollowing;

  /// No description provided for @chatterFollowers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No followers} =1{1 follower} other{{count} followers}}'**
  String chatterFollowers(int count);

  /// No description provided for @chatterActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get chatterActivities;

  /// No description provided for @chatterSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule activity'**
  String get chatterSchedule;

  /// No description provided for @chatterKindTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get chatterKindTodo;

  /// No description provided for @chatterKindCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get chatterKindCall;

  /// No description provided for @chatterKindEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get chatterKindEmail;

  /// No description provided for @chatterKindMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting'**
  String get chatterKindMeeting;

  /// No description provided for @chatterSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get chatterSummary;

  /// No description provided for @chatterAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get chatterAssignee;

  /// No description provided for @chatterDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get chatterDueDate;

  /// No description provided for @chatterNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get chatterNote;

  /// No description provided for @chatterMarkDone.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get chatterMarkDone;

  /// No description provided for @chatterDoneNote.
  ///
  /// In en, this message translates to:
  /// **'What came of it? (optional)'**
  String get chatterDoneNote;

  /// No description provided for @chatterOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get chatterOverdue;

  /// No description provided for @chatterDueOn.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String chatterDueOn(String date);

  /// No description provided for @chatterSystemActor.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get chatterSystemActor;

  /// No description provided for @chatterChanged.
  ///
  /// In en, this message translates to:
  /// **'{who} changed {field}: {from} → {to}'**
  String chatterChanged(String who, String field, String from, String to);

  /// No description provided for @chatterActivityDone.
  ///
  /// In en, this message translates to:
  /// **'{who} completed {kind}: {summary}'**
  String chatterActivityDone(String who, String kind, String summary);

  /// No description provided for @chatterFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get chatterFieldName;

  /// No description provided for @chatterFieldVatNumber.
  ///
  /// In en, this message translates to:
  /// **'VAT number'**
  String get chatterFieldVatNumber;

  /// No description provided for @chatterFieldVatRegime.
  ///
  /// In en, this message translates to:
  /// **'VAT regime'**
  String get chatterFieldVatRegime;

  /// No description provided for @chatterFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'E-mail'**
  String get chatterFieldEmail;

  /// No description provided for @chatterFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get chatterFieldPhone;

  /// No description provided for @chatterFieldLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get chatterFieldLanguage;

  /// No description provided for @chatterFieldActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get chatterFieldActive;

  /// No description provided for @chatterFieldDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount %'**
  String get chatterFieldDiscount;

  /// No description provided for @chatterFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get chatterFieldStatus;

  /// No description provided for @chatterFieldStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get chatterFieldStage;

  /// No description provided for @chatterFieldRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get chatterFieldRevision;

  /// No description provided for @chatterFieldOrderSent.
  ///
  /// In en, this message translates to:
  /// **'Order sent'**
  String get chatterFieldOrderSent;

  /// No description provided for @chatterFieldOrderConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Order confirmed'**
  String get chatterFieldOrderConfirmed;

  /// No description provided for @chatterLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The messages could not be loaded.'**
  String get chatterLoadFailed;

  /// No description provided for @chatterRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get chatterRetry;

  /// No description provided for @notificationsChatterUnread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new message on {label}} other{{count} new messages on {label}}}'**
  String notificationsChatterUnread(int count, String label);

  /// No description provided for @notificationsActivityDue.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {summary}'**
  String notificationsActivityDue(String kind, String summary);

  /// No description provided for @kanbanMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get kanbanMoveTo;

  /// No description provided for @kanbanMoveToColumn.
  ///
  /// In en, this message translates to:
  /// **'Move to {column}'**
  String kanbanMoveToColumn(String column);

  /// No description provided for @kanbanEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get kanbanEmpty;

  /// No description provided for @kanbanMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 more} other{Show {count} more}}'**
  String kanbanMore(int count);

  /// No description provided for @kanbanColumnFailed.
  ///
  /// In en, this message translates to:
  /// **'This column could not be loaded.'**
  String get kanbanColumnFailed;

  /// No description provided for @kanbanAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to {column}'**
  String kanbanAdd(String column);

  /// No description provided for @kanbanViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get kanbanViewList;

  /// No description provided for @kanbanViewBoard.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get kanbanViewBoard;

  /// No description provided for @kanbanLostCancelled.
  ///
  /// In en, this message translates to:
  /// **'Moved back: a reason is needed to mark an opportunity as lost.'**
  String get kanbanLostCancelled;

  /// No description provided for @ticketsBoardCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close this ticket?'**
  String get ticketsBoardCloseTitle;

  /// No description provided for @ticketsBoardCloseBody.
  ///
  /// In en, this message translates to:
  /// **'Closing {number} can send the customer a satisfaction survey, which cannot be taken back.'**
  String ticketsBoardCloseBody(String number);

  /// No description provided for @ticketsBoardClose.
  ///
  /// In en, this message translates to:
  /// **'Close ticket'**
  String get ticketsBoardClose;

  /// No description provided for @documentLibrary.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentLibrary;

  /// No description provided for @documentNew.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get documentNew;

  /// No description provided for @documentTitle.
  ///
  /// In en, this message translates to:
  /// **'Document title'**
  String get documentTitle;

  /// No description provided for @documentMemo.
  ///
  /// In en, this message translates to:
  /// **'Technical memo'**
  String get documentMemo;

  /// No description provided for @documentPresentation.
  ///
  /// In en, this message translates to:
  /// **'Product presentation'**
  String get documentPresentation;

  /// No description provided for @documentKeywords.
  ///
  /// In en, this message translates to:
  /// **'Keywords (comma separated)'**
  String get documentKeywords;

  /// No description provided for @documentProductCodes.
  ///
  /// In en, this message translates to:
  /// **'Product codes (comma separated)'**
  String get documentProductCodes;

  /// No description provided for @documentUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload PDF'**
  String get documentUpload;

  /// No description provided for @documentPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish revision'**
  String get documentPublish;

  /// No description provided for @documentRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision {revision}'**
  String documentRevision(int revision);

  /// No description provided for @documentDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get documentDraft;

  /// No description provided for @documentDownload.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get documentDownload;

  /// No description provided for @documentPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview PDF'**
  String get documentPreview;

  /// No description provided for @attachFromDocuments.
  ///
  /// In en, this message translates to:
  /// **'Attach from Documents'**
  String get attachFromDocuments;

  /// No description provided for @noLibraryPdfs.
  ///
  /// In en, this message translates to:
  /// **'No published PDFs found.'**
  String get noLibraryPdfs;

  /// No description provided for @libraryLanguageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No PDF in the ticket language. Choose an available language.'**
  String get libraryLanguageUnavailable;

  /// No description provided for @mailMerge.
  ///
  /// In en, this message translates to:
  /// **'Mail merge'**
  String get mailMerge;

  /// No description provided for @mergeRevision.
  ///
  /// In en, this message translates to:
  /// **'Published revision'**
  String get mergeRevision;

  /// No description provided for @mergeSavePreview.
  ///
  /// In en, this message translates to:
  /// **'Save and preview'**
  String get mergeSavePreview;

  /// No description provided for @mergePreviewStale.
  ///
  /// In en, this message translates to:
  /// **'Save to refresh the preview.'**
  String get mergePreviewStale;

  /// No description provided for @mergeAudience.
  ///
  /// In en, this message translates to:
  /// **'Audience preview'**
  String get mergeAudience;

  /// No description provided for @mergeSelectContact.
  ///
  /// In en, this message translates to:
  /// **'Select a contact'**
  String get mergeSelectContact;

  /// No description provided for @mergeMissingAddress.
  ///
  /// In en, this message translates to:
  /// **'Missing email address'**
  String get mergeMissingAddress;

  /// No description provided for @mergeMissingTranslation.
  ///
  /// In en, this message translates to:
  /// **'Missing subject or message translation'**
  String get mergeMissingTranslation;

  /// No description provided for @mergeMissingPdf.
  ///
  /// In en, this message translates to:
  /// **'Missing PDF in this language'**
  String get mergeMissingPdf;

  /// No description provided for @mergeDuplicateAddress.
  ///
  /// In en, this message translates to:
  /// **'Duplicate email address'**
  String get mergeDuplicateAddress;

  /// No description provided for @mergeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm mailing'**
  String get mergeConfirm;

  /// No description provided for @mergeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Queue one email for each of the {count} eligible recipients in this preview?'**
  String mergeConfirmBody(int count);

  /// No description provided for @mergeQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue mailing'**
  String get mergeQueue;

  /// No description provided for @mergeHistory.
  ///
  /// In en, this message translates to:
  /// **'Delivery history'**
  String get mergeHistory;

  /// No description provided for @mergeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get mergeRefresh;

  /// No description provided for @mergeQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get mergeQueued;

  /// No description provided for @mergeSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get mergeSent;

  /// No description provided for @mergeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get mergeFailed;

  /// No description provided for @mergeOptedOut.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribed from mailings'**
  String get mergeOptedOut;

  /// No description provided for @mergeOptOuts.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribed addresses'**
  String get mergeOptOuts;

  /// No description provided for @mergeOptOutsHelp.
  ///
  /// In en, this message translates to:
  /// **'These addresses receive no mailings from this company. Add an address when someone asks not to be mailed; remove it only when they ask to receive mailings again.'**
  String get mergeOptOutsHelp;

  /// No description provided for @mergeOptOutsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No unsubscribed addresses.'**
  String get mergeOptOutsEmpty;

  /// No description provided for @mergeOptOutViaLink.
  ///
  /// In en, this message translates to:
  /// **'Via the unsubscribe link'**
  String get mergeOptOutViaLink;

  /// No description provided for @mergeOptOutViaStaff.
  ///
  /// In en, this message translates to:
  /// **'Added by {name}'**
  String mergeOptOutViaStaff(String name);

  /// No description provided for @mergeUnsubscribeFooter.
  ///
  /// In en, this message translates to:
  /// **'Every email ends with an unsubscribe link in the recipient\'s language.'**
  String get mergeUnsubscribeFooter;

  /// No description provided for @unsubscribeTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe from mailings'**
  String get unsubscribeTitle;

  /// No description provided for @unsubscribeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Stop receiving mailings from {company} at {email}?'**
  String unsubscribeQuestion(String company, String email);

  /// No description provided for @unsubscribeAction.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribeAction;

  /// No description provided for @unsubscribeDone.
  ///
  /// In en, this message translates to:
  /// **'You have been unsubscribed. You will no longer receive these mailings.'**
  String get unsubscribeDone;

  /// No description provided for @unsubscribeAlready.
  ///
  /// In en, this message translates to:
  /// **'This address is already unsubscribed.'**
  String get unsubscribeAlready;

  /// No description provided for @unsubscribeInvalid.
  ///
  /// In en, this message translates to:
  /// **'This unsubscribe link is not valid.'**
  String get unsubscribeInvalid;

  /// No description provided for @productMedia.
  ///
  /// In en, this message translates to:
  /// **'Pictures & videos'**
  String get productMedia;

  /// No description provided for @addPictureOrVideo.
  ///
  /// In en, this message translates to:
  /// **'Add pictures or videos'**
  String get addPictureOrVideo;

  /// No description provided for @noMedia.
  ///
  /// In en, this message translates to:
  /// **'No pictures or videos yet.'**
  String get noMedia;

  /// No description provided for @makeDefault.
  ///
  /// In en, this message translates to:
  /// **'Make default'**
  String get makeDefault;

  /// No description provided for @defaultMedia.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultMedia;

  /// No description provided for @tutAttributesTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom product properties'**
  String get tutAttributesTitle;

  /// No description provided for @tutAttributesSummary.
  ///
  /// In en, this message translates to:
  /// **'Define company-specific product attributes in Admin and fill them in on a product.'**
  String get tutAttributesSummary;

  /// No description provided for @tutAttributesNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tutorial controller required'**
  String get tutAttributesNeedsTitle;

  /// No description provided for @tutAttributesNeedsBody.
  ///
  /// In en, this message translates to:
  /// **'This chapter records technical properties on PLC-BASE (Standard PLC). Create PLC-BASE in Chapter 2 (PLCs, parallel licensing & network) or use Assist to create it now.'**
  String get tutAttributesNeedsBody;

  /// No description provided for @tutAttributesIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Why generic product properties'**
  String get tutAttributesIntroTitle;

  /// No description provided for @tutAttributesIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Every company has properties specific to its own product lines—such as relay counts, FET counts, digital inputs, or 4-20 mA analog inputs, RS-485 ports, I2C bus, or licensed outputs—that are irrelevant to other companies. Instead of hard-coding columns, an administrator defines them once under Admin → Attributes, and they immediately appear on every product.'**
  String get tutAttributesIntroBody;

  /// No description provided for @tutAttributesOpenAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Admin → Attributes'**
  String get tutAttributesOpenAdminTitle;

  /// No description provided for @tutAttributesOpenAdminBody.
  ///
  /// In en, this message translates to:
  /// **'Open Admin from the navigation rail and select the Attributes tab.'**
  String get tutAttributesOpenAdminBody;

  /// No description provided for @tutAttributesRelaysTitle.
  ///
  /// In en, this message translates to:
  /// **'Define the relay count property'**
  String get tutAttributesRelaysTitle;

  /// No description provided for @tutAttributesRelaysBody.
  ///
  /// In en, this message translates to:
  /// **'Click New attribute and create a Number property with key relay_count, label Relays, type Number, and scope Product.'**
  String get tutAttributesRelaysBody;

  /// No description provided for @tutAttributesRelaysHint.
  ///
  /// In en, this message translates to:
  /// **'Keys use snake_case (lowercase letters, digits, and underscores) so configurators and match rules can reference them reliably.'**
  String get tutAttributesRelaysHint;

  /// No description provided for @tutAttributesFetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Define the FET count property'**
  String get tutAttributesFetsTitle;

  /// No description provided for @tutAttributesFetsBody.
  ///
  /// In en, this message translates to:
  /// **'Click New attribute and create a Number property with key fet_count, label FETs, type Number, and scope Product.'**
  String get tutAttributesFetsBody;

  /// No description provided for @tutAttributesDigitalInputsTitle.
  ///
  /// In en, this message translates to:
  /// **'Define the digital inputs property'**
  String get tutAttributesDigitalInputsTitle;

  /// No description provided for @tutAttributesDigitalInputsBody.
  ///
  /// In en, this message translates to:
  /// **'Click New attribute and create a Number property with key digital_inputs, label Digital inputs, type Number, and scope Product.'**
  String get tutAttributesDigitalInputsBody;

  /// No description provided for @tutAttributesOpenControllerTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the Controller product'**
  String get tutAttributesOpenControllerTitle;

  /// No description provided for @tutAttributesOpenControllerBody.
  ///
  /// In en, this message translates to:
  /// **'Open Products and select PLC-BASE (Controller).'**
  String get tutAttributesOpenControllerBody;

  /// No description provided for @tutAttributesSuitabilityTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the Suitability tab'**
  String get tutAttributesSuitabilityTabTitle;

  /// No description provided for @tutAttributesSuitabilityTabBody.
  ///
  /// In en, this message translates to:
  /// **'Switch to the Suitability tab. Every active Product-scope attribute you defined in Admin now appears here as a typed input.'**
  String get tutAttributesSuitabilityTabBody;

  /// No description provided for @tutAttributesFillPropertiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Record the controller properties'**
  String get tutAttributesFillPropertiesTitle;

  /// No description provided for @tutAttributesFillPropertiesBody.
  ///
  /// In en, this message translates to:
  /// **'Fill in the fields for keys relay_count = 4, fet_count = 2, digital_inputs = 8, and analog_4_20ma_inputs = 2, rs485_ports = 2, i2c_bus = Yes, licensed_outputs_tier = 10 (if a displayed label differs, use the existing field with that key), then click Save.'**
  String get tutAttributesFillPropertiesBody;

  /// No description provided for @tutAttributesFillPropertiesHint.
  ///
  /// In en, this message translates to:
  /// **'Leave any property blank if it does not apply to a given product; only filled values are saved.'**
  String get tutAttributesFillPropertiesHint;

  /// No description provided for @tutAttributesDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Company-specific properties saved'**
  String get tutAttributesDoneTitle;

  /// No description provided for @tutAttributesDoneBody.
  ///
  /// In en, this message translates to:
  /// **'PLC-BASE now stores typed, validated properties specific to your product line. Configurator formulas can read them with product(code).attr(\'relay_count\') and CRM match rules can check them without changing the database schema.'**
  String get tutAttributesDoneBody;

  /// No description provided for @cbAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get cbAddLine;

  /// No description provided for @cbAddSchedule.
  ///
  /// In en, this message translates to:
  /// **'Add schedule'**
  String get cbAddSchedule;

  /// No description provided for @cbAddTier.
  ///
  /// In en, this message translates to:
  /// **'Add tier'**
  String get cbAddTier;

  /// No description provided for @cbAnnualRebates.
  ///
  /// In en, this message translates to:
  /// **'Annual rebates'**
  String get cbAnnualRebates;

  /// No description provided for @cbApproveRate.
  ///
  /// In en, this message translates to:
  /// **'Approve rate'**
  String get cbApproveRate;

  /// No description provided for @cbApprovedRate.
  ///
  /// In en, this message translates to:
  /// **'Approved rate'**
  String get cbApprovedRate;

  /// No description provided for @cbAssignedSchedule.
  ///
  /// In en, this message translates to:
  /// **'Assigned schedule'**
  String get cbAssignedSchedule;

  /// No description provided for @cbCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit note'**
  String get cbCredit;

  /// No description provided for @cbCreditReason.
  ///
  /// In en, this message translates to:
  /// **'Credit reason'**
  String get cbCreditReason;

  /// No description provided for @cbCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get cbCurrency;

  /// No description provided for @cbCustomerInvoices.
  ///
  /// In en, this message translates to:
  /// **'Customer invoices'**
  String get cbCustomerInvoices;

  /// No description provided for @cbCutoff.
  ///
  /// In en, this message translates to:
  /// **'Cutoff date'**
  String get cbCutoff;

  /// No description provided for @cbDate.
  ///
  /// In en, this message translates to:
  /// **'Document date'**
  String get cbDate;

  /// No description provided for @cbDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get cbDescription;

  /// No description provided for @cbDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get cbDiscard;

  /// No description provided for @cbDomestic.
  ///
  /// In en, this message translates to:
  /// **'Domestic'**
  String get cbDomestic;

  /// No description provided for @cbDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get cbDraft;

  /// No description provided for @cbEligible.
  ///
  /// In en, this message translates to:
  /// **'Counts toward rebate turnover'**
  String get cbEligible;

  /// No description provided for @cbEligibleSales.
  ///
  /// In en, this message translates to:
  /// **'Eligible sales'**
  String get cbEligibleSales;

  /// No description provided for @cbEvidence.
  ///
  /// In en, this message translates to:
  /// **'Accounting evidence reference'**
  String get cbEvidence;

  /// No description provided for @cbHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden on invoices'**
  String get cbHidden;

  /// No description provided for @cbHighestTierWording.
  ///
  /// In en, this message translates to:
  /// **'Highest-tier wording'**
  String get cbHighestTierWording;

  /// No description provided for @cbImportBalance.
  ///
  /// In en, this message translates to:
  /// **'Import verified balance'**
  String get cbImportBalance;

  /// No description provided for @cbIntraEu.
  ///
  /// In en, this message translates to:
  /// **'Intra-EU'**
  String get cbIntraEu;

  /// No description provided for @cbInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get cbInvoice;

  /// No description provided for @cbInvoiceWording.
  ///
  /// In en, this message translates to:
  /// **'Invoice wording'**
  String get cbInvoiceWording;

  /// No description provided for @cbLegacyInvoice.
  ///
  /// In en, this message translates to:
  /// **'Historical invoice'**
  String get cbLegacyInvoice;

  /// No description provided for @cbNet.
  ///
  /// In en, this message translates to:
  /// **'Excluding VAT'**
  String get cbNet;

  /// No description provided for @cbNewCredit.
  ///
  /// In en, this message translates to:
  /// **'New credit note'**
  String get cbNewCredit;

  /// No description provided for @cbNewInvoice.
  ///
  /// In en, this message translates to:
  /// **'New customer invoice'**
  String get cbNewInvoice;

  /// No description provided for @cbNextTierWording.
  ///
  /// In en, this message translates to:
  /// **'Next-tier wording'**
  String get cbNextTierWording;

  /// No description provided for @cbNoDocuments.
  ///
  /// In en, this message translates to:
  /// **'No customer invoices or credit notes'**
  String get cbNoDocuments;

  /// No description provided for @cbNoSchedule.
  ///
  /// In en, this message translates to:
  /// **'No schedule'**
  String get cbNoSchedule;

  /// No description provided for @cbOpeningBalances.
  ///
  /// In en, this message translates to:
  /// **'Verified opening balances'**
  String get cbOpeningBalances;

  /// No description provided for @cbOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original invoice number'**
  String get cbOriginal;

  /// No description provided for @cbOutsideEu.
  ///
  /// In en, this message translates to:
  /// **'Outside EU'**
  String get cbOutsideEu;

  /// No description provided for @cbPost.
  ///
  /// In en, this message translates to:
  /// **'Post document'**
  String get cbPost;

  /// No description provided for @cbProductCode.
  ///
  /// In en, this message translates to:
  /// **'Product code'**
  String get cbProductCode;

  /// No description provided for @cbQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get cbQuantity;

  /// No description provided for @cbRate.
  ///
  /// In en, this message translates to:
  /// **'Rebate (%)'**
  String get cbRate;

  /// No description provided for @cbRateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Earned rate unavailable'**
  String get cbRateUnavailable;

  /// No description provided for @cbRateYear.
  ///
  /// In en, this message translates to:
  /// **'Rate year'**
  String get cbRateYear;

  /// No description provided for @cbRegisterLegacy.
  ///
  /// In en, this message translates to:
  /// **'Register historical invoice'**
  String get cbRegisterLegacy;

  /// No description provided for @cbRemoveLine.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get cbRemoveLine;

  /// No description provided for @cbReverseCharge.
  ///
  /// In en, this message translates to:
  /// **'Domestic reverse charge'**
  String get cbReverseCharge;

  /// No description provided for @cbReviewRate.
  ///
  /// In en, this message translates to:
  /// **'Review earned rate'**
  String get cbReviewRate;

  /// No description provided for @cbSalesYear.
  ///
  /// In en, this message translates to:
  /// **'Sales year'**
  String get cbSalesYear;

  /// No description provided for @cbSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cbSave;

  /// No description provided for @cbSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get cbSaveDraft;

  /// No description provided for @cbScheduleName.
  ///
  /// In en, this message translates to:
  /// **'Schedule name'**
  String get cbScheduleName;

  /// No description provided for @cbSchedules.
  ///
  /// In en, this message translates to:
  /// **'Rebate schedules'**
  String get cbSchedules;

  /// No description provided for @cbShippedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Shipped delivery'**
  String get cbShippedDelivery;

  /// No description provided for @cbShowProgress.
  ///
  /// In en, this message translates to:
  /// **'Show rebate progress on invoices'**
  String get cbShowProgress;

  /// No description provided for @cbThreshold.
  ///
  /// In en, this message translates to:
  /// **'Eligible sales threshold'**
  String get cbThreshold;

  /// No description provided for @cbTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cbTotal;

  /// No description provided for @cbUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get cbUnit;

  /// No description provided for @cbVatRate.
  ///
  /// In en, this message translates to:
  /// **'VAT rate (%)'**
  String get cbVatRate;

  /// No description provided for @cbVatRegime.
  ///
  /// In en, this message translates to:
  /// **'VAT regime'**
  String get cbVatRegime;

  /// No description provided for @cbVatTotal.
  ///
  /// In en, this message translates to:
  /// **'VAT amount'**
  String get cbVatTotal;

  /// No description provided for @cbVisible.
  ///
  /// In en, this message translates to:
  /// **'Shown on invoices'**
  String get cbVisible;

  /// No description provided for @cbWordingHelp.
  ///
  /// In en, this message translates to:
  /// **'Use these placeholders in your invoice wording.'**
  String get cbWordingHelp;

  /// No description provided for @defaultMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Default multiplier'**
  String get defaultMultiplier;

  /// No description provided for @defaultMultiplierHelp.
  ///
  /// In en, this message translates to:
  /// **'Relative to the first zone (e.g. 1.15 = +15%)'**
  String get defaultMultiplierHelp;

  /// No description provided for @defaultMultiplierInvalid.
  ///
  /// In en, this message translates to:
  /// **'Multiplier must be a positive number'**
  String get defaultMultiplierInvalid;

  /// No description provided for @defaultRounding.
  ///
  /// In en, this message translates to:
  /// **'Rounding'**
  String get defaultRounding;

  /// No description provided for @roundingNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get roundingNone;

  /// No description provided for @baseZone.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get baseZone;

  /// No description provided for @formula.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get formula;

  /// No description provided for @enterAtLeastOnePrice.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one price'**
  String get enterAtLeastOnePrice;

  /// No description provided for @resetToFormula.
  ///
  /// In en, this message translates to:
  /// **'Reset to formula'**
  String get resetToFormula;

  /// No description provided for @applyFormulas.
  ///
  /// In en, this message translates to:
  /// **'Apply formulas'**
  String get applyFormulas;

  /// No description provided for @copyFromProduct.
  ///
  /// In en, this message translates to:
  /// **'Copy from product...'**
  String get copyFromProduct;

  /// No description provided for @copiedFromProduct.
  ///
  /// In en, this message translates to:
  /// **'Copied from {code}'**
  String copiedFromProduct(String code);

  /// No description provided for @selectProductToCopy.
  ///
  /// In en, this message translates to:
  /// **'Select product to copy properties from'**
  String get selectProductToCopy;

  /// No description provided for @filterSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get filterSelectAll;

  /// No description provided for @listDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get listDeselectAll;

  /// No description provided for @userPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get userPreferences;

  /// No description provided for @shortcutsTab.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcutsTab;

  /// No description provided for @shortcutSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all / Deselect all'**
  String get shortcutSelectAll;

  /// No description provided for @shortcutResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset all to defaults'**
  String get shortcutResetDefaults;

  /// No description provided for @shortcutReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get shortcutReset;

  /// No description provided for @shortcutPressKeys.
  ///
  /// In en, this message translates to:
  /// **'Press a key combination...'**
  String get shortcutPressKeys;

  /// No description provided for @shortcutConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflicts with: {action} ({keys})'**
  String shortcutConflict(String action, String keys);

  /// No description provided for @shortcutNeedsModifier.
  ///
  /// In en, this message translates to:
  /// **'Use Ctrl, Alt, or Cmd with a key'**
  String get shortcutNeedsModifier;

  /// No description provided for @shortcutCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get shortcutCustom;

  /// No description provided for @tutConveyorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Conveyor belts & motors'**
  String get tutConveyorsTitle;

  /// No description provided for @tutConveyorsSummary.
  ///
  /// In en, this message translates to:
  /// **'Create single-phase and three-phase motors, a VFD, and a conveyor belt assembly with an SVG diagram and BOM.'**
  String get tutConveyorsSummary;

  /// No description provided for @tutConveyorsOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get tutConveyorsOpenTitle;

  /// No description provided for @tutConveyorsOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Open the Products section to build the conveyor belt and motor line.'**
  String get tutConveyorsOpenBody;

  /// No description provided for @tutConveyorsMotor1pTitle.
  ///
  /// In en, this message translates to:
  /// **'Single-phase AC motor'**
  String get tutConveyorsMotor1pTitle;

  /// No description provided for @tutConveyorsMotor1pBody.
  ///
  /// In en, this message translates to:
  /// **'Create code MOT-1P-037, name Single-Phase AC Motor, type Purchased (for fixed-speed belts via PLC relay outputs).'**
  String get tutConveyorsMotor1pBody;

  /// No description provided for @tutConveyorsMotorTitle.
  ///
  /// In en, this message translates to:
  /// **'Three-phase AC motor'**
  String get tutConveyorsMotorTitle;

  /// No description provided for @tutConveyorsMotorBody.
  ///
  /// In en, this message translates to:
  /// **'Create code MOT-3P-055, name 3-Phase AC Motor, type Purchased (for variable-speed main conveyors).'**
  String get tutConveyorsMotorBody;

  /// No description provided for @tutConveyorsMotorHint.
  ///
  /// In en, this message translates to:
  /// **'Product codes do not need a prefix; keep them clean and descriptive.'**
  String get tutConveyorsMotorHint;

  /// No description provided for @tutConveyorsVfdTitle.
  ///
  /// In en, this message translates to:
  /// **'Variable frequency drive'**
  String get tutConveyorsVfdTitle;

  /// No description provided for @tutConveyorsVfdBody.
  ///
  /// In en, this message translates to:
  /// **'Create code VFD-3P-055, name Variable Frequency Drive, type Purchased to control the 3-phase motor.'**
  String get tutConveyorsVfdBody;

  /// No description provided for @tutConveyorsConveyorTitle.
  ///
  /// In en, this message translates to:
  /// **'Conveyor belt assembly'**
  String get tutConveyorsConveyorTitle;

  /// No description provided for @tutConveyorsConveyorBody.
  ///
  /// In en, this message translates to:
  /// **'Create code CONV-BELT-1M, name Conveyor Belt Assembly, type Manufactured.'**
  String get tutConveyorsConveyorBody;

  /// No description provided for @tutConveyorsOpenConveyorTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the conveyor assembly'**
  String get tutConveyorsOpenConveyorTitle;

  /// No description provided for @tutConveyorsOpenConveyorBody.
  ///
  /// In en, this message translates to:
  /// **'Open CONV-BELT-1M to inspect its SVG assembly diagram and bill of materials.'**
  String get tutConveyorsOpenConveyorBody;

  /// No description provided for @tutConveyorsSvgPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'SVG assembly preview (with or without motor)'**
  String get tutConveyorsSvgPreviewTitle;

  /// No description provided for @tutConveyorsSvgPreviewBody.
  ///
  /// In en, this message translates to:
  /// **'Use the toggles below to preview the conveyor belt SVG with or without a motor (1-phase or 3-phase + VFD). You can also upload image/svg+xml drawings on the Media tab.'**
  String get tutConveyorsSvgPreviewBody;

  /// No description provided for @tutConveyorsBomTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Bill of materials'**
  String get tutConveyorsBomTabTitle;

  /// No description provided for @tutConveyorsBomTabBody.
  ///
  /// In en, this message translates to:
  /// **'Open the Bill of materials tab on CONV-BELT-1M, then press Next.'**
  String get tutConveyorsBomTabBody;

  /// No description provided for @tutConveyorsRevisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a BOM revision'**
  String get tutConveyorsRevisionTitle;

  /// No description provided for @tutConveyorsRevisionBody.
  ///
  /// In en, this message translates to:
  /// **'Press New revision to start a draft BOM.'**
  String get tutConveyorsRevisionBody;

  /// No description provided for @tutConveyorsLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Add motor and VFD'**
  String get tutConveyorsLinesTitle;

  /// No description provided for @tutConveyorsLinesBody.
  ///
  /// In en, this message translates to:
  /// **'Add MOT-3P-055 and VFD-3P-055 to the draft BOM, then save.'**
  String get tutConveyorsLinesBody;

  /// No description provided for @tutConveyorsLinesHint.
  ///
  /// In en, this message translates to:
  /// **'Search for MOT-3P-055 and VFD-3P-055 in the component picker.'**
  String get tutConveyorsLinesHint;

  /// No description provided for @tutConveyorsActivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate the BOM'**
  String get tutConveyorsActivateTitle;

  /// No description provided for @tutConveyorsActivateBody.
  ///
  /// In en, this message translates to:
  /// **'Press Activate so production and configurators can use this conveyor assembly.'**
  String get tutConveyorsActivateBody;

  /// No description provided for @tutConveyorsDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Conveyor assembly ready'**
  String get tutConveyorsDoneTitle;

  /// No description provided for @tutConveyorsDoneBody.
  ///
  /// In en, this message translates to:
  /// **'You created the conveyor belt, 1-phase/3-phase motors, VFD, SVG assembly preview, and active BOM.'**
  String get tutConveyorsDoneBody;

  /// No description provided for @tutPlcTitle.
  ///
  /// In en, this message translates to:
  /// **'PLCs, parallel licensing & network'**
  String get tutPlcTitle;

  /// No description provided for @tutPlcSummary.
  ///
  /// In en, this message translates to:
  /// **'Model standard PLCs (10 outputs), parallel output licenses (30/50/100), RS-485 expansion, and a master controller.'**
  String get tutPlcSummary;

  /// No description provided for @tutPlcOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Products'**
  String get tutPlcOpenTitle;

  /// No description provided for @tutPlcOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Open Products to add the PLC family and its parallel licensing SKUs.'**
  String get tutPlcOpenBody;

  /// No description provided for @tutPlcBaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Standard PLC (10 outputs)'**
  String get tutPlcBaseTitle;

  /// No description provided for @tutPlcBaseBody.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-BASE, name Standard PLC (10 Outputs), type Purchased.'**
  String get tutPlcBaseBody;

  /// No description provided for @tutPlcBaseHint.
  ///
  /// In en, this message translates to:
  /// **'A standard PLC ships with 10 usable outputs; parallel licenses unlock 30, 50, or 100 outputs.'**
  String get tutPlcBaseHint;

  /// No description provided for @tutPlcLic30Title.
  ///
  /// In en, this message translates to:
  /// **'30-output parallel license'**
  String get tutPlcLic30Title;

  /// No description provided for @tutPlcLic30Body.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-LIC-30, name PLC 30-Output Parallel License, type Service.'**
  String get tutPlcLic30Body;

  /// No description provided for @tutPlcLic50Title.
  ///
  /// In en, this message translates to:
  /// **'50-output parallel license'**
  String get tutPlcLic50Title;

  /// No description provided for @tutPlcLic50Body.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-LIC-50, name PLC 50-Output Parallel License, type Service.'**
  String get tutPlcLic50Body;

  /// No description provided for @tutPlcLic100Title.
  ///
  /// In en, this message translates to:
  /// **'100-output parallel license'**
  String get tutPlcLic100Title;

  /// No description provided for @tutPlcLic100Body.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-LIC-100, name PLC 100-Output Parallel License, type Service.'**
  String get tutPlcLic100Body;

  /// No description provided for @tutPlcExpansionTitle.
  ///
  /// In en, this message translates to:
  /// **'RS-485 I/O expansion module'**
  String get tutPlcExpansionTitle;

  /// No description provided for @tutPlcExpansionBody.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-EXP-RS485, name RS-485 I/O Expansion Module, type Purchased.'**
  String get tutPlcExpansionBody;

  /// No description provided for @tutPlcMasterTitle.
  ///
  /// In en, this message translates to:
  /// **'Master network controller'**
  String get tutPlcMasterTitle;

  /// No description provided for @tutPlcMasterBody.
  ///
  /// In en, this message translates to:
  /// **'Create code PLC-MASTER, name Master Network Controller, type Purchased to govern networked PLCs.'**
  String get tutPlcMasterBody;

  /// No description provided for @tutPlcDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'PLC & licensing catalog ready'**
  String get tutPlcDoneTitle;

  /// No description provided for @tutPlcDoneBody.
  ///
  /// In en, this message translates to:
  /// **'The PLC-CONVEYOR-LINE configurator validates required outputs against the 10/30/50/100 license tier and adds RS-485 expansion and Master Controller automatically.'**
  String get tutPlcDoneBody;

  /// No description provided for @tutDisplaysTitle.
  ///
  /// In en, this message translates to:
  /// **'RS-485 displays & I2C peripherals'**
  String get tutDisplaysTitle;

  /// No description provided for @tutDisplaysSummary.
  ///
  /// In en, this message translates to:
  /// **'Add operator displays on the RS-485 bus with I2C swipe card and temperature measurement modules.'**
  String get tutDisplaysSummary;

  /// No description provided for @tutDisplaysOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Products'**
  String get tutDisplaysOpenTitle;

  /// No description provided for @tutDisplaysOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Open Products to add the RS-485 display and its I2C bus peripherals.'**
  String get tutDisplaysOpenBody;

  /// No description provided for @tutDisplaysDisplayTitle.
  ///
  /// In en, this message translates to:
  /// **'RS-485 operator display'**
  String get tutDisplaysDisplayTitle;

  /// No description provided for @tutDisplaysDisplayBody.
  ///
  /// In en, this message translates to:
  /// **'Create code DISP-RS485, name RS-485 Operator Display, type Purchased.'**
  String get tutDisplaysDisplayBody;

  /// No description provided for @tutDisplaysDisplayHint.
  ///
  /// In en, this message translates to:
  /// **'DISP-RS485 connects to the PLC over RS-485 and exposes an I2C bus for local peripherals.'**
  String get tutDisplaysDisplayHint;

  /// No description provided for @tutDisplaysSwipeTitle.
  ///
  /// In en, this message translates to:
  /// **'I2C swipe card reader'**
  String get tutDisplaysSwipeTitle;

  /// No description provided for @tutDisplaysSwipeBody.
  ///
  /// In en, this message translates to:
  /// **'Create code MOD-I2C-SWIPE, name I2C Swipe Card Reader, type Purchased.'**
  String get tutDisplaysSwipeBody;

  /// No description provided for @tutDisplaysTempTitle.
  ///
  /// In en, this message translates to:
  /// **'I2C temperature sensor'**
  String get tutDisplaysTempTitle;

  /// No description provided for @tutDisplaysTempBody.
  ///
  /// In en, this message translates to:
  /// **'Create code SENS-I2C-TEMP, name I2C Temperature Sensor, type Purchased.'**
  String get tutDisplaysTempBody;

  /// No description provided for @tutDisplaysDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Displays & I2C bus ready'**
  String get tutDisplaysDoneTitle;

  /// No description provided for @tutDisplaysDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Operators can authenticate via swipe card and monitor cabinet temperature over the display I2C bus.'**
  String get tutDisplaysDoneBody;

  /// No description provided for @tutSensorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensors & PowerFET devices'**
  String get tutSensorsTitle;

  /// No description provided for @tutSensorsSummary.
  ///
  /// In en, this message translates to:
  /// **'Add IR digital inputs, 4-20 mA analog sensors, and PowerFET-operated solenoid actuators.'**
  String get tutSensorsSummary;

  /// No description provided for @tutSensorsOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Products'**
  String get tutSensorsOpenTitle;

  /// No description provided for @tutSensorsOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Open Products to add the line sensors and PowerFET solenoid devices.'**
  String get tutSensorsOpenBody;

  /// No description provided for @tutSensorsIrTitle.
  ///
  /// In en, this message translates to:
  /// **'IR photoelectric sensor'**
  String get tutSensorsIrTitle;

  /// No description provided for @tutSensorsIrBody.
  ///
  /// In en, this message translates to:
  /// **'Create code SENS-IR-24V, name IR Photoelectric Sensor, type Purchased (digital input).'**
  String get tutSensorsIrBody;

  /// No description provided for @tutSensorsIrHint.
  ///
  /// In en, this message translates to:
  /// **'Detects products passing on the conveyor belt and feeds a PLC digital input.'**
  String get tutSensorsIrHint;

  /// No description provided for @tutSensorsAnalogTitle.
  ///
  /// In en, this message translates to:
  /// **'4-20 mA analog sensor'**
  String get tutSensorsAnalogTitle;

  /// No description provided for @tutSensorsAnalogBody.
  ///
  /// In en, this message translates to:
  /// **'Create code SENS-420MA, name 4-20 mA Analog Sensor, type Purchased.'**
  String get tutSensorsAnalogBody;

  /// No description provided for @tutSensorsPusherTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerFET solenoid pusher'**
  String get tutSensorsPusherTitle;

  /// No description provided for @tutSensorsPusherBody.
  ///
  /// In en, this message translates to:
  /// **'Create code SOL-PUSH, name PowerFET Solenoid Pusher, type Purchased.'**
  String get tutSensorsPusherBody;

  /// No description provided for @tutSensorsLabelerTitle.
  ///
  /// In en, this message translates to:
  /// **'PowerFET label stamper'**
  String get tutSensorsLabelerTitle;

  /// No description provided for @tutSensorsLabelerBody.
  ///
  /// In en, this message translates to:
  /// **'Create code SOL-LABEL, name PowerFET Label Stamper, type Purchased.'**
  String get tutSensorsLabelerBody;

  /// No description provided for @tutSensorsDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensors & actuators ready'**
  String get tutSensorsDoneTitle;

  /// No description provided for @tutSensorsDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Your automation catalog now covers conveyors, motors, PLCs, buses, sensors, and PowerFET mechanical devices.'**
  String get tutSensorsDoneBody;

  /// No description provided for @tutAttributesAnalog420Title.
  ///
  /// In en, this message translates to:
  /// **'Define 4-20 mA analog inputs'**
  String get tutAttributesAnalog420Title;

  /// No description provided for @tutAttributesAnalog420Body.
  ///
  /// In en, this message translates to:
  /// **'Create a Number property with key analog_4_20ma_inputs, label 4-20 mA analog inputs, scope Product.'**
  String get tutAttributesAnalog420Body;

  /// No description provided for @tutAttributesRs485PortsTitle.
  ///
  /// In en, this message translates to:
  /// **'Define RS-485 ports'**
  String get tutAttributesRs485PortsTitle;

  /// No description provided for @tutAttributesRs485PortsBody.
  ///
  /// In en, this message translates to:
  /// **'Create a Number property with key rs485_ports, label RS-485 ports, scope Product.'**
  String get tutAttributesRs485PortsBody;

  /// No description provided for @tutAttributesI2cBusTitle.
  ///
  /// In en, this message translates to:
  /// **'Define I2C peripheral bus'**
  String get tutAttributesI2cBusTitle;

  /// No description provided for @tutAttributesI2cBusBody.
  ///
  /// In en, this message translates to:
  /// **'Create a Yes/No property with key i2c_bus, label I2C peripheral bus, scope Product.'**
  String get tutAttributesI2cBusBody;

  /// No description provided for @tutAttributesLicensedOutputsTitle.
  ///
  /// In en, this message translates to:
  /// **'Define licensed outputs tier'**
  String get tutAttributesLicensedOutputsTitle;

  /// No description provided for @tutAttributesLicensedOutputsBody.
  ///
  /// In en, this message translates to:
  /// **'Create a Number property with key licensed_outputs_tier, label Licensed outputs tier, scope Product.'**
  String get tutAttributesLicensedOutputsBody;

  /// No description provided for @tutConveyorsSvgWithMotor.
  ///
  /// In en, this message translates to:
  /// **'With motor'**
  String get tutConveyorsSvgWithMotor;

  /// No description provided for @tutConveyorsSvgThreePhase.
  ///
  /// In en, this message translates to:
  /// **'3-Phase + VFD'**
  String get tutConveyorsSvgThreePhase;

  /// No description provided for @tutConveyorsSvgOnePhase.
  ///
  /// In en, this message translates to:
  /// **'1-Phase'**
  String get tutConveyorsSvgOnePhase;

  /// No description provided for @tutConveyorsSvgWithoutMotor.
  ///
  /// In en, this message translates to:
  /// **'without motor'**
  String get tutConveyorsSvgWithoutMotor;

  /// No description provided for @quotationLineLayoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Quotation item layout'**
  String get quotationLineLayoutTitle;

  /// No description provided for @quotationSingleLineLabel.
  ///
  /// In en, this message translates to:
  /// **'Single line per item'**
  String get quotationSingleLineLabel;

  /// No description provided for @quotationSingleLineHelp.
  ///
  /// In en, this message translates to:
  /// **'Show each item on one compact row with remarks in a dialog; turn off to show remark fields on a second line.'**
  String get quotationSingleLineHelp;

  /// No description provided for @quotationSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Company settings saved'**
  String get quotationSettingsSaved;

  /// No description provided for @remarks.
  ///
  /// In en, this message translates to:
  /// **'Remarks'**
  String get remarks;

  /// No description provided for @autosaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Draft autosave'**
  String get autosaveTitle;

  /// No description provided for @autosaveOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autosaveOff;

  /// No description provided for @autosaveMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String autosaveMinutes(int minutes);

  /// No description provided for @autosaveDefault.
  ///
  /// In en, this message translates to:
  /// **'Company default ({minutes} min)'**
  String autosaveDefault(int minutes);

  /// No description provided for @autosaveDefaultOff.
  ///
  /// In en, this message translates to:
  /// **'Company default (Off)'**
  String get autosaveDefaultOff;

  /// No description provided for @autosaveUserHelp.
  ///
  /// In en, this message translates to:
  /// **'Override how often open drafts autosave.'**
  String get autosaveUserHelp;

  /// No description provided for @autosaveAdminHelp.
  ///
  /// In en, this message translates to:
  /// **'Default interval for autosaving open drafts (users can override this in their preferences).'**
  String get autosaveAdminHelp;

  /// No description provided for @listGroupBy.
  ///
  /// In en, this message translates to:
  /// **'Group by'**
  String get listGroupBy;

  /// No description provided for @listGroupNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get listGroupNone;

  /// No description provided for @listGroupChip.
  ///
  /// In en, this message translates to:
  /// **'Group: {group}'**
  String listGroupChip(String group);

  /// No description provided for @listRemoveGrouping.
  ///
  /// In en, this message translates to:
  /// **'Remove grouping {group}'**
  String listRemoveGrouping(String group);

  /// No description provided for @listGroupExpanded.
  ///
  /// In en, this message translates to:
  /// **'{label}, {count} rows, expanded'**
  String listGroupExpanded(String label, int count);

  /// No description provided for @listGroupCollapsed.
  ///
  /// In en, this message translates to:
  /// **'{label}, {count} rows, collapsed'**
  String listGroupCollapsed(String label, int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
