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
  /// **'Rules run in this order when a ticket is created, changed or answered by the customer. A rule applies when all its conditions match. Rules change tickets only; they send no e-mail.'**
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

  /// No description provided for @indicativeLine.
  ///
  /// In en, this message translates to:
  /// **'{description} (indicative, to confirm)'**
  String indicativeLine(String description);

  /// No description provided for @indicativeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count} indicative price(s) to confirm before the quotation can be sent: enter the agreed price in the list price field.'**
  String indicativeToConfirm(int count);

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

  /// No description provided for @pricingIndicativeHelp.
  ///
  /// In en, this message translates to:
  /// **'Indicative (confirm per quote)'**
  String get pricingIndicativeHelp;

  /// No description provided for @pricingList.
  ///
  /// In en, this message translates to:
  /// **'list price'**
  String get pricingList;

  /// No description provided for @pricingListHelp.
  ///
  /// In en, this message translates to:
  /// **'List price (rebates apply)'**
  String get pricingListHelp;

  /// No description provided for @pricingNet.
  ///
  /// In en, this message translates to:
  /// **'net'**
  String get pricingNet;

  /// No description provided for @pricingNetHelp.
  ///
  /// In en, this message translates to:
  /// **'Net price (never discounted)'**
  String get pricingNetHelp;

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
  /// **'CSV export and import'**
  String get csvMenu;

  /// No description provided for @csvExport.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get csvExport;

  /// No description provided for @csvImport.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
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
  /// **'Import CSV: {entity}'**
  String csvImportTitle(String entity);

  /// No description provided for @csvImportHelp.
  ///
  /// In en, this message translates to:
  /// **'Rows are matched on the code: an existing code is updated, a new code is created. Columns that are missing from the file are left untouched, and nothing is ever deleted. It is all or nothing: if any row has an error, nothing is imported. Semicolon or comma separated, UTF-8.'**
  String get csvImportHelp;

  /// No description provided for @csvChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose CSV file'**
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

  /// No description provided for @csvNotUtf8.
  ///
  /// In en, this message translates to:
  /// **'The file is not UTF-8 text. Save it as CSV (UTF-8) and try again.'**
  String get csvNotUtf8;

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

  /// No description provided for @tutProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Your first product'**
  String get tutProductTitle;

  /// No description provided for @tutProductSummary.
  ///
  /// In en, this message translates to:
  /// **'Hat: product manager. Create three components, a finished product and its bill of materials.'**
  String get tutProductSummary;

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
  /// **'The sections are on the left (or in the bottom bar on a phone). Opening a record, such as a product or a quotation, adds a tab to the workspace, so you can keep several records open and come back to them.'**
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

  /// No description provided for @tutProductOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get tutProductOpenTitle;

  /// No description provided for @tutProductOpenBody.
  ///
  /// In en, this message translates to:
  /// **'Today you are the product manager. Everything the company sells or builds is a product. Open the Products section.'**
  String get tutProductOpenBody;

  /// No description provided for @tutProductMotorTitle.
  ///
  /// In en, this message translates to:
  /// **'Component: Motor'**
  String get tutProductMotorTitle;

  /// No description provided for @tutProductMotorBody.
  ///
  /// In en, this message translates to:
  /// **'Create the first component. Press New product, enter code TUT-MOTOR and name Motor, keep the type Purchased, and save.'**
  String get tutProductMotorBody;

  /// No description provided for @tutProductMotorHint.
  ///
  /// In en, this message translates to:
  /// **'The TUT- prefix marks tutorial data, so you can recognise it later.'**
  String get tutProductMotorHint;

  /// No description provided for @tutProductFrameTitle.
  ///
  /// In en, this message translates to:
  /// **'Component: Frame'**
  String get tutProductFrameTitle;

  /// No description provided for @tutProductFrameBody.
  ///
  /// In en, this message translates to:
  /// **'Create a second component the same way: code TUT-FRAME, name Frame, type Purchased.'**
  String get tutProductFrameBody;

  /// No description provided for @tutProductControllerTitle.
  ///
  /// In en, this message translates to:
  /// **'Component: Controller'**
  String get tutProductControllerTitle;

  /// No description provided for @tutProductControllerBody.
  ///
  /// In en, this message translates to:
  /// **'And a third one: code TUT-CTRL, name Controller, type Purchased.'**
  String get tutProductControllerBody;

  /// No description provided for @tutProductCartTitle.
  ///
  /// In en, this message translates to:
  /// **'The finished product'**
  String get tutProductCartTitle;

  /// No description provided for @tutProductCartBody.
  ///
  /// In en, this message translates to:
  /// **'Now the product you build from those parts. Create code TUT-CART, name Cart, and choose the type Manufactured: only manufactured products have a bill of materials.'**
  String get tutProductCartBody;

  /// No description provided for @tutProductOpenCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the cart'**
  String get tutProductOpenCartTitle;

  /// No description provided for @tutProductOpenCartBody.
  ///
  /// In en, this message translates to:
  /// **'Open the new Cart product from the list to see its tabs.'**
  String get tutProductOpenCartBody;

  /// No description provided for @tutProductBomTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Bill of materials'**
  String get tutProductBomTabTitle;

  /// No description provided for @tutProductBomTabBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the Bill of materials tab. It lists the components needed to build one unit. A revision is a draft you edit, or the active one that production uses. Press Next when you are there.'**
  String get tutProductBomTabBody;

  /// No description provided for @tutProductRevisionTitle.
  ///
  /// In en, this message translates to:
  /// **'A first revision'**
  String get tutProductRevisionTitle;

  /// No description provided for @tutProductRevisionBody.
  ///
  /// In en, this message translates to:
  /// **'Press New revision to start a draft.'**
  String get tutProductRevisionBody;

  /// No description provided for @tutProductLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Add the components'**
  String get tutProductLinesTitle;

  /// No description provided for @tutProductLinesBody.
  ///
  /// In en, this message translates to:
  /// **'Search each component and add it: Motor, Frame and Controller. Then press Save draft.'**
  String get tutProductLinesBody;

  /// No description provided for @tutProductLinesHint.
  ///
  /// In en, this message translates to:
  /// **'Type TUT in the search box to find the three components.'**
  String get tutProductLinesHint;

  /// No description provided for @tutProductActivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate it'**
  String get tutProductActivateTitle;

  /// No description provided for @tutProductActivateBody.
  ///
  /// In en, this message translates to:
  /// **'Press Activate. From now on production and quotations use this revision; later changes go through a new revision.'**
  String get tutProductActivateBody;

  /// No description provided for @tutProductDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Well done'**
  String get tutProductDoneTitle;

  /// No description provided for @tutProductDoneBody.
  ///
  /// In en, this message translates to:
  /// **'You have a finished product with a bill of materials of three components. Later chapters build on it.'**
  String get tutProductDoneBody;

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
  /// **'This chapter needs the four products from chapter 1 (TUT-MOTOR, TUT-FRAME, TUT-CTRL and TUT-CART) and could not find them. Go back to the chapter map and finish chapter 1 first, then come back here.'**
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
  /// **'Add TUT-MOTOR to the price list: unit price 120, lead time 14 days, minimum order quantity 5. Purchase orders use these values to pre-fill their lines.'**
  String get tutSuppliersPriceMotorBody;

  /// No description provided for @tutSuppliersPriceMotorHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the product with the search box in the dialog; type TUT-MOTOR.'**
  String get tutSuppliersPriceMotorHint;

  /// No description provided for @tutSuppliersPriceFrameTitle.
  ///
  /// In en, this message translates to:
  /// **'A price for the frame'**
  String get tutSuppliersPriceFrameTitle;

  /// No description provided for @tutSuppliersPriceFrameBody.
  ///
  /// In en, this message translates to:
  /// **'Same again for TUT-FRAME: unit price 45, lead time 10 days, minimum order quantity 5.'**
  String get tutSuppliersPriceFrameBody;

  /// No description provided for @tutSuppliersPriceControllerTitle.
  ///
  /// In en, this message translates to:
  /// **'A price for the controller'**
  String get tutSuppliersPriceControllerTitle;

  /// No description provided for @tutSuppliersPriceControllerBody.
  ///
  /// In en, this message translates to:
  /// **'And TUT-CTRL: unit price 30, lead time 7 days, minimum order quantity 5. This supplier now covers all three components.'**
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
  /// **'Give this supplier a price for TUT-MOTOR too: unit price 135, lead time 5 days, minimum order quantity 1. It is dearer but faster; that is the kind of choice a price list helps with.'**
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
  /// **'This chapter needs the products of chapter 1 and the supplier Voltaic Drives Ltd with its price list from chapter 2, and could not find the products. Finish those chapters first.'**
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
  /// **'Create a purchase order for Voltaic Drives Ltd with three lines: TUT-MOTOR, TUT-FRAME and TUT-CTRL, 30 pieces each. The prices come from the price list.'**
  String get tutBuyingOrderBody;

  /// No description provided for @tutBuyingOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the supplier first: the line prices fill in once its price list has loaded. Use Add line for the second and third component.'**
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
  /// **'Open Stock. The 30 motors, frames and controllers are on hand in warehouse MAIN. Every receipt created a stock movement, so the quantity can always be traced back.'**
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
  /// **'The three-way match compares order, receipt and invoice before money moves. Matching invoices are approved and paid, doubtful ones are disputed. Next: building the carts yourself.'**
  String get tutInvoicesDoneBody;

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
