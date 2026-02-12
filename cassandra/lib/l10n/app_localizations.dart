import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @loginSeriesAPredictions.
  ///
  /// In en, this message translates to:
  /// **'Serie A Predictions'**
  String get loginSeriesAPredictions;

  /// No description provided for @loginSignInGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get loginSignInGoogle;

  /// No description provided for @loginSignInApple.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get loginSignInApple;

  /// No description provided for @loginSignInError.
  ///
  /// In en, this message translates to:
  /// **'Sign-in error. Please try again.'**
  String get loginSignInError;

  /// No description provided for @loginPrivacyNotice.
  ///
  /// In en, this message translates to:
  /// **'We only use what\'s strictly necessary to identify you.'**
  String get loginPrivacyNotice;

  /// No description provided for @createGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your group'**
  String get createGroupTitle;

  /// No description provided for @createGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Challenge your friends on Serie A predictions'**
  String get createGroupSubtitle;

  /// No description provided for @createGroupTapAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photo'**
  String get createGroupTapAddPhoto;

  /// No description provided for @createGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get createGroupNameLabel;

  /// No description provided for @createGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroupButton;

  /// No description provided for @createGroupHaveInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Have an invite code?'**
  String get createGroupHaveInviteCode;

  /// No description provided for @createGroupCreated.
  ///
  /// In en, this message translates to:
  /// **'Group created!'**
  String get createGroupCreated;

  /// No description provided for @createGroupInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get createGroupInviteCode;

  /// No description provided for @createGroupCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied!'**
  String get createGroupCodeCopied;

  /// No description provided for @createGroupTapToCopy.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy'**
  String get createGroupTapToCopy;

  /// No description provided for @createGroupShareInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Share invite code'**
  String get createGroupShareInviteCode;

  /// No description provided for @createGroupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get createGroupContinue;

  /// No description provided for @groupShareInviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Join my group \"{groupName}\" on Cassandra! Code: {inviteCode}'**
  String groupShareInviteMessage(Object groupName, Object inviteCode);

  /// No description provided for @joinGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a group'**
  String get joinGroupTitle;

  /// No description provided for @joinGroupEnterInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the group invite code'**
  String get joinGroupEnterInviteCode;

  /// No description provided for @joinGroupInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get joinGroupInviteCode;

  /// No description provided for @joinGroupCodeHint.
  ///
  /// In en, this message translates to:
  /// **'CASS-XXXX'**
  String get joinGroupCodeHint;

  /// No description provided for @joinGroupButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinGroupButton;

  /// No description provided for @joinGroupJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined group!'**
  String get joinGroupJoined;

  /// No description provided for @joinGroupInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid invite code'**
  String get joinGroupInvalidCode;

  /// No description provided for @joinGroupAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'Already a member of this group'**
  String get joinGroupAlreadyMember;

  /// No description provided for @groupTitle.
  ///
  /// In en, this message translates to:
  /// **'My group'**
  String get groupTitle;

  /// No description provided for @groupJoinTooltip.
  ///
  /// In en, this message translates to:
  /// **'Join a group'**
  String get groupJoinTooltip;

  /// No description provided for @groupDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Cassandra Crew'**
  String get groupDefaultName;

  /// No description provided for @groupSampleDataBanner.
  ///
  /// In en, this message translates to:
  /// **'Sample data - join a group to see real data'**
  String get groupSampleDataBanner;

  /// No description provided for @groupDataRefreshing.
  ///
  /// In en, this message translates to:
  /// **'refreshing...'**
  String get groupDataRefreshing;

  /// No description provided for @groupDataRealApi.
  ///
  /// In en, this message translates to:
  /// **'data: real (API)'**
  String get groupDataRealApi;

  /// No description provided for @groupDataDemo.
  ///
  /// In en, this message translates to:
  /// **'data: demo'**
  String get groupDataDemo;

  /// No description provided for @shortUpdated.
  ///
  /// In en, this message translates to:
  /// **'upd.'**
  String get shortUpdated;

  /// No description provided for @groupMatchdayLabel.
  ///
  /// In en, this message translates to:
  /// **'matchday {matchdayNumber} - {daysLabel}'**
  String groupMatchdayLabel(Object matchdayNumber, Object daysLabel);

  /// No description provided for @groupResultsLabel.
  ///
  /// In en, this message translates to:
  /// **'results: {graded}/{total}'**
  String groupResultsLabel(Object graded, Object total);

  /// No description provided for @groupResultsLabelPartial.
  ///
  /// In en, this message translates to:
  /// **'results: {graded}/{total} (partial)'**
  String groupResultsLabelPartial(Object graded, Object total);

  /// No description provided for @groupStandings.
  ///
  /// In en, this message translates to:
  /// **'standings'**
  String get groupStandings;

  /// No description provided for @groupMatchdays.
  ///
  /// In en, this message translates to:
  /// **'matchdays'**
  String get groupMatchdays;

  /// No description provided for @groupHistoryDemoCard.
  ///
  /// In en, this message translates to:
  /// **'Matchday history (DEMO)\nShowing 16-19 from mocks. Once we have real history via API, we\'ll make it live.'**
  String get groupHistoryDemoCard;

  /// No description provided for @groupMatchdayTitle.
  ///
  /// In en, this message translates to:
  /// **'Matchday {dayNumber}'**
  String groupMatchdayTitle(Object dayNumber);

  /// No description provided for @groupResultsPrefix.
  ///
  /// In en, this message translates to:
  /// **'results'**
  String get groupResultsPrefix;

  /// No description provided for @groupResultsShort.
  ///
  /// In en, this message translates to:
  /// **'{graded}/{total}'**
  String groupResultsShort(Object graded, Object total);

  /// No description provided for @groupResultsShortPartial.
  ///
  /// In en, this message translates to:
  /// **'{graded}/{total} (partial)'**
  String groupResultsShortPartial(Object graded, Object total);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @settingsResetDone.
  ///
  /// In en, this message translates to:
  /// **'Reset done'**
  String get settingsResetDone;

  /// No description provided for @settingsBackendNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Backend not configured on this device'**
  String get settingsBackendNotConfigured;

  /// No description provided for @settingsNoBackendDataCurrentMatchday.
  ///
  /// In en, this message translates to:
  /// **'No backend data available for the current matchday'**
  String get settingsNoBackendDataCurrentMatchday;

  /// No description provided for @settingsCacheRefreshedFromBackend.
  ///
  /// In en, this message translates to:
  /// **'Cache refreshed from backend'**
  String get settingsCacheRefreshedFromBackend;

  /// No description provided for @settingsCacheRefreshError.
  ///
  /// In en, this message translates to:
  /// **'Error refreshing from backend'**
  String get settingsCacheRefreshError;

  /// No description provided for @settingsDevModeNoFirebase.
  ///
  /// In en, this message translates to:
  /// **'Dev mode - Firebase not configured'**
  String get settingsDevModeNoFirebase;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get settingsSignIn;

  /// No description provided for @settingsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get settingsConfirm;

  /// No description provided for @settingsSignOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Sign out of your account?'**
  String get settingsSignOutQuestion;

  /// No description provided for @settingsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// No description provided for @settingsDeleteAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible. Continue?'**
  String get settingsDeleteAccountQuestion;

  /// No description provided for @settingsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsDelete;

  /// No description provided for @settingsReauthError.
  ///
  /// In en, this message translates to:
  /// **'Error: sign in again and retry.'**
  String get settingsReauthError;

  /// No description provided for @settingsCacheEmpty.
  ///
  /// In en, this message translates to:
  /// **'cache: empty'**
  String get settingsCacheEmpty;

  /// No description provided for @settingsDataBackendCache.
  ///
  /// In en, this message translates to:
  /// **'data: backend cache'**
  String get settingsDataBackendCache;

  /// No description provided for @settingsDataDemo.
  ///
  /// In en, this message translates to:
  /// **'data: demo'**
  String get settingsDataDemo;

  /// No description provided for @settingsDebugCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug cache'**
  String get settingsDebugCacheTitle;

  /// No description provided for @settingsDebugFixturesLine.
  ///
  /// In en, this message translates to:
  /// **'fixtures: {kind}'**
  String settingsDebugFixturesLine(Object kind);

  /// No description provided for @settingsDebugMatchInCacheLine.
  ///
  /// In en, this message translates to:
  /// **'match in cache: {count}'**
  String settingsDebugMatchInCacheLine(Object count);

  /// No description provided for @settingsDebugOutcomesInCacheLine.
  ///
  /// In en, this message translates to:
  /// **'outcomes in cache: {count}'**
  String settingsDebugOutcomesInCacheLine(Object count);

  /// No description provided for @settingsDebugUpdateLine.
  ///
  /// In en, this message translates to:
  /// **'update: {updated}'**
  String settingsDebugUpdateLine(Object updated);

  /// No description provided for @settingsNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get settingsNever;

  /// No description provided for @settingsSimulationGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Group simulation'**
  String get settingsSimulationGroupTitle;

  /// No description provided for @settingsSimulationSavedPicksLine.
  ///
  /// In en, this message translates to:
  /// **'saved simulated picks: {count}'**
  String settingsSimulationSavedPicksLine(Object count);

  /// No description provided for @settingsGeneratePicks.
  ///
  /// In en, this message translates to:
  /// **'Generate picks'**
  String get settingsGeneratePicks;

  /// No description provided for @settingsCopyMyPicks.
  ///
  /// In en, this message translates to:
  /// **'Copy mine'**
  String get settingsCopyMyPicks;

  /// No description provided for @settingsClearSimulatedPicks.
  ///
  /// In en, this message translates to:
  /// **'Clear simulated'**
  String get settingsClearSimulatedPicks;

  /// No description provided for @settingsGeneratedPicksForMembers.
  ///
  /// In en, this message translates to:
  /// **'Generated picks for {count} members'**
  String settingsGeneratedPicksForMembers(Object count);

  /// No description provided for @settingsCopiedMyPicksToMembers.
  ///
  /// In en, this message translates to:
  /// **'Copied your picks to {count} members'**
  String settingsCopiedMyPicksToMembers(Object count);

  /// No description provided for @settingsSimulatedPicksCleared.
  ///
  /// In en, this message translates to:
  /// **'Simulated picks cleared'**
  String get settingsSimulatedPicksCleared;

  /// No description provided for @settingsClearFixtures.
  ///
  /// In en, this message translates to:
  /// **'Clear fixtures'**
  String get settingsClearFixtures;

  /// No description provided for @settingsClearOutcomes.
  ///
  /// In en, this message translates to:
  /// **'Clear outcomes'**
  String get settingsClearOutcomes;

  /// No description provided for @settingsClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get settingsClearAll;

  /// No description provided for @settingsFixturesCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Fixtures cache cleared'**
  String get settingsFixturesCacheCleared;

  /// No description provided for @settingsOutcomesCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Outcomes cache cleared'**
  String get settingsOutcomesCacheCleared;

  /// No description provided for @settingsPredictionCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Predictions cache cleared'**
  String get settingsPredictionCacheCleared;

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfile;

  /// No description provided for @settingsTeamNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Team name (handle)'**
  String get settingsTeamNameLabel;

  /// No description provided for @settingsTeamNameHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: FC Cassandra'**
  String get settingsTeamNameHint;

  /// No description provided for @settingsFavoriteTeamLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorite team'**
  String get settingsFavoriteTeamLabel;

  /// No description provided for @settingsFavoriteTeamHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Roma'**
  String get settingsFavoriteTeamHint;

  /// No description provided for @settingsGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get settingsGroup;

  /// No description provided for @settingsGroupImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Group image'**
  String get settingsGroupImageTitle;

  /// No description provided for @settingsGroupImageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to change the photo'**
  String get settingsGroupImageSubtitle;

  /// No description provided for @settingsAdminApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin approval'**
  String get settingsAdminApprovalTitle;

  /// No description provided for @settingsAdminApprovalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only the admin can accept new members'**
  String get settingsAdminApprovalSubtitle;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageIt.
  ///
  /// In en, this message translates to:
  /// **'IT'**
  String get settingsLanguageIt;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get settingsLanguageEn;

  /// No description provided for @settingsTranslationNote.
  ///
  /// In en, this message translates to:
  /// **'Note: many labels are still hardcoded for now. We will translate in batches.'**
  String get settingsTranslationNote;

  /// No description provided for @settingsPicksPrivacyDefault.
  ///
  /// In en, this message translates to:
  /// **'Picks privacy (default)'**
  String get settingsPicksPrivacyDefault;

  /// No description provided for @settingsPrivacyPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get settingsPrivacyPublic;

  /// No description provided for @settingsPrivacyFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get settingsPrivacyFriends;

  /// No description provided for @settingsPrivacyPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get settingsPrivacyPrivate;

  /// No description provided for @settingsPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'This preference will be used once we connect picks submission + backend.'**
  String get settingsPrivacyNote;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsFixturesCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Fixtures cache'**
  String get settingsFixturesCacheTitle;

  /// No description provided for @settingsRefreshCacheNowTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh cache now'**
  String get settingsRefreshCacheNowTitle;

  /// No description provided for @settingsRefreshCacheNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reads current matchday from backend cache.'**
  String get settingsRefreshCacheNowSubtitle;

  /// No description provided for @settingsClearFixturesCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear fixtures cache'**
  String get settingsClearFixturesCacheTitle;

  /// No description provided for @settingsClearFixturesCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fallback to local demo data until next refresh.'**
  String get settingsClearFixturesCacheSubtitle;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get settingsCacheCleared;

  /// No description provided for @settingsBackendDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Backend diagnostics'**
  String get settingsBackendDiagnosticsTitle;

  /// No description provided for @settingsBackendDiagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify matchday cache loaded from Firestore.'**
  String get settingsBackendDiagnosticsSubtitle;

  /// No description provided for @settingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsReset;

  /// No description provided for @settingsKindBackendCache.
  ///
  /// In en, this message translates to:
  /// **'backend cache'**
  String get settingsKindBackendCache;

  /// No description provided for @settingsKindDemo.
  ///
  /// In en, this message translates to:
  /// **'demo'**
  String get settingsKindDemo;

  /// No description provided for @settingsKindEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get settingsKindEmpty;

  /// No description provided for @predHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Predictions history'**
  String get predHistoryTitle;

  /// No description provided for @predHistoryInfo.
  ///
  /// In en, this message translates to:
  /// **'Here you can find the matchdays you saved/submitted.\nIf we don\'t have historical fixtures via API, we use a DEMO fallback to show details anyway.'**
  String get predHistoryInfo;

  /// No description provided for @predHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matchday saved.\nGo to Predictions and submit at least one matchday to see it here.'**
  String get predHistoryEmpty;

  /// No description provided for @predHistoryTagSaved.
  ///
  /// In en, this message translates to:
  /// **'SAVED'**
  String get predHistoryTagSaved;

  /// No description provided for @predHistoryTagApi.
  ///
  /// In en, this message translates to:
  /// **'API'**
  String get predHistoryTagApi;

  /// No description provided for @predHistoryTagDemo.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get predHistoryTagDemo;

  /// No description provided for @serieATitle.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get serieATitle;

  /// No description provided for @serieASegmentResults.
  ///
  /// In en, this message translates to:
  /// **'results'**
  String get serieASegmentResults;

  /// No description provided for @serieASegmentStandings.
  ///
  /// In en, this message translates to:
  /// **'standings'**
  String get serieASegmentStandings;

  /// No description provided for @serieADataDemo.
  ///
  /// In en, this message translates to:
  /// **'data: demo'**
  String get serieADataDemo;

  /// No description provided for @serieAErrorLoadingBackendCache.
  ///
  /// In en, this message translates to:
  /// **'Error loading backend cache: {errorMessage}'**
  String serieAErrorLoadingBackendCache(Object errorMessage);

  /// No description provided for @serieANoMatchDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No match data available'**
  String get serieANoMatchDataAvailable;

  /// No description provided for @serieANoMatchesToShow.
  ///
  /// In en, this message translates to:
  /// **'No matches to show'**
  String get serieANoMatchesToShow;

  /// No description provided for @serieANoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get serieANoResults;

  /// No description provided for @serieANoUpcomingMatches.
  ///
  /// In en, this message translates to:
  /// **'No upcoming matches'**
  String get serieANoUpcomingMatches;

  /// No description provided for @kickoffLabel.
  ///
  /// In en, this message translates to:
  /// **'Kickoff'**
  String get kickoffLabel;

  /// No description provided for @leaderboardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Standings'**
  String get leaderboardsTitle;

  /// No description provided for @leaderboardsDemoBanner.
  ///
  /// In en, this message translates to:
  /// **'Sample data - real data will appear after first submission'**
  String get leaderboardsDemoBanner;

  /// No description provided for @leaderboardsDataRefreshing.
  ///
  /// In en, this message translates to:
  /// **'refreshing...'**
  String get leaderboardsDataRefreshing;

  /// No description provided for @leaderboardsDataRealApi.
  ///
  /// In en, this message translates to:
  /// **'real (API)'**
  String get leaderboardsDataRealApi;

  /// No description provided for @leaderboardsDataEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get leaderboardsDataEmpty;

  /// No description provided for @leaderboardsNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get leaderboardsNever;

  /// No description provided for @leaderboardsDataLine.
  ///
  /// In en, this message translates to:
  /// **'data: {kind} • upd. {updatedLabel}'**
  String leaderboardsDataLine(Object kind, Object updatedLabel);

  /// No description provided for @leaderboardsOverall.
  ///
  /// In en, this message translates to:
  /// **'overall'**
  String get leaderboardsOverall;

  /// No description provided for @leaderboardsMatchdays.
  ///
  /// In en, this message translates to:
  /// **'matchdays'**
  String get leaderboardsMatchdays;

  /// No description provided for @leaderboardsPoints.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get leaderboardsPoints;

  /// No description provided for @leaderboardsAverage.
  ///
  /// In en, this message translates to:
  /// **'average'**
  String get leaderboardsAverage;

  /// No description provided for @leaderboardsMatchdayLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Matchday {dayNumber} (LIVE)'**
  String leaderboardsMatchdayLiveTitle(Object dayNumber);

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsTitle;

  /// No description provided for @statsSegmentPersonal.
  ///
  /// In en, this message translates to:
  /// **'personal'**
  String get statsSegmentPersonal;

  /// No description provided for @statsSegmentGroup.
  ///
  /// In en, this message translates to:
  /// **'group'**
  String get statsSegmentGroup;

  /// No description provided for @statsMetricAverage.
  ///
  /// In en, this message translates to:
  /// **'average'**
  String get statsMetricAverage;

  /// No description provided for @statsMetricTotal.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get statsMetricTotal;

  /// No description provided for @statsMetricPercentCorrect.
  ///
  /// In en, this message translates to:
  /// **'% correct'**
  String get statsMetricPercentCorrect;

  /// No description provided for @statsMetricPerfectWeeks.
  ///
  /// In en, this message translates to:
  /// **'perfect weeks'**
  String get statsMetricPerfectWeeks;

  /// No description provided for @statsTotal.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get statsTotal;

  /// No description provided for @statsAvgMatchday.
  ///
  /// In en, this message translates to:
  /// **'avg/matchday'**
  String get statsAvgMatchday;

  /// No description provided for @statsMatchdaysPlayed.
  ///
  /// In en, this message translates to:
  /// **'matchdays played'**
  String get statsMatchdaysPlayed;

  /// No description provided for @statsAvgOdds.
  ///
  /// In en, this message translates to:
  /// **'avg odds'**
  String get statsAvgOdds;

  /// No description provided for @statsTotalCorrect.
  ///
  /// In en, this message translates to:
  /// **'total correct'**
  String get statsTotalCorrect;

  /// No description provided for @statsAvgBonus.
  ///
  /// In en, this message translates to:
  /// **'avg bonus'**
  String get statsAvgBonus;

  /// No description provided for @statsHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get statsHighlights;

  /// No description provided for @statsBestMatchday.
  ///
  /// In en, this message translates to:
  /// **'Best matchday: {value}'**
  String statsBestMatchday(Object value);

  /// No description provided for @statsWorstMatchday.
  ///
  /// In en, this message translates to:
  /// **'Worst matchday: {value}'**
  String statsWorstMatchday(Object value);

  /// No description provided for @statsTotalBonus.
  ///
  /// In en, this message translates to:
  /// **'Total bonus: {value}'**
  String statsTotalBonus(Object value);

  /// No description provided for @statsMatchdays.
  ///
  /// In en, this message translates to:
  /// **'matchdays'**
  String get statsMatchdays;

  /// No description provided for @statsCorrect.
  ///
  /// In en, this message translates to:
  /// **'correct'**
  String get statsCorrect;

  /// No description provided for @tabPredictions.
  ///
  /// In en, this message translates to:
  /// **'Predictions'**
  String get tabPredictions;

  /// No description provided for @tabStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get tabStats;

  /// No description provided for @tabTrophies.
  ///
  /// In en, this message translates to:
  /// **'Trophies'**
  String get tabTrophies;

  /// No description provided for @groupYou.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get groupYou;

  /// No description provided for @groupOutcomesSavedTag.
  ///
  /// In en, this message translates to:
  /// **'OUT: SAVED'**
  String get groupOutcomesSavedTag;

  /// No description provided for @groupOutcomesRuntimeTag.
  ///
  /// In en, this message translates to:
  /// **'OUT: runtime'**
  String get groupOutcomesRuntimeTag;

  /// No description provided for @groupPicksSavedTag.
  ///
  /// In en, this message translates to:
  /// **'PICK: SAVED'**
  String get groupPicksSavedTag;

  /// No description provided for @groupPicksDemoRuntimeTag.
  ///
  /// In en, this message translates to:
  /// **'PICK: demo/runtime'**
  String get groupPicksDemoRuntimeTag;

  /// No description provided for @groupBonusLabel.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get groupBonusLabel;

  /// No description provided for @groupAvgOddsPlayedLabel.
  ///
  /// In en, this message translates to:
  /// **'avg. odds played'**
  String get groupAvgOddsPlayedLabel;

  /// No description provided for @groupPickLabel.
  ///
  /// In en, this message translates to:
  /// **'pick'**
  String get groupPickLabel;

  /// No description provided for @groupOutcomeLabel.
  ///
  /// In en, this message translates to:
  /// **'outcome'**
  String get groupOutcomeLabel;

  /// No description provided for @groupOddsLabel.
  ///
  /// In en, this message translates to:
  /// **'odds'**
  String get groupOddsLabel;

  /// No description provided for @tabGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get tabGroup;

  /// No description provided for @tabLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get tabLive;

  /// No description provided for @leaderboardsPlayersCount.
  ///
  /// In en, this message translates to:
  /// **'Players: {count}'**
  String leaderboardsPlayersCount(Object count);

  /// No description provided for @serieAStandingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Serie A Standings'**
  String get serieAStandingsTitle;

  /// No description provided for @serieATeamColumn.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get serieATeamColumn;

  /// No description provided for @serieAPlayedColumn.
  ///
  /// In en, this message translates to:
  /// **'MP'**
  String get serieAPlayedColumn;

  /// No description provided for @serieAWinsColumn.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get serieAWinsColumn;

  /// No description provided for @serieADrawsColumn.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get serieADrawsColumn;

  /// No description provided for @serieALossesColumn.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get serieALossesColumn;

  /// No description provided for @serieAGoalsAgainstColumn.
  ///
  /// In en, this message translates to:
  /// **'GA'**
  String get serieAGoalsAgainstColumn;

  /// No description provided for @serieAGoalDiffColumn.
  ///
  /// In en, this message translates to:
  /// **'GD'**
  String get serieAGoalDiffColumn;

  /// No description provided for @serieAPointsColumn.
  ///
  /// In en, this message translates to:
  /// **'Pts'**
  String get serieAPointsColumn;

  /// No description provided for @serieALastFiveColumn.
  ///
  /// In en, this message translates to:
  /// **'Last 5'**
  String get serieALastFiveColumn;

  /// No description provided for @statsBestDayShort.
  ///
  /// In en, this message translates to:
  /// **'MD{day}: {points}'**
  String statsBestDayShort(Object day, Object points);

  /// No description provided for @statsWorstDayShort.
  ///
  /// In en, this message translates to:
  /// **'MD{day}: {points}'**
  String statsWorstDayShort(Object day, Object points);

  /// No description provided for @profileTrophiesHistory.
  ///
  /// In en, this message translates to:
  /// **'Trophies (history)'**
  String get profileTrophiesHistory;

  /// No description provided for @profileTrophiesDescription.
  ///
  /// In en, this message translates to:
  /// **'Trophies for {displayName} (demo season history).\nRules: 👑 group winner • L last place • 👁️ 10/10 correct • 🦉 jinxed own favorite team.'**
  String profileTrophiesDescription(Object displayName);

  /// No description provided for @predictionsVoidCount.
  ///
  /// In en, this message translates to:
  /// **'void {count}'**
  String predictionsVoidCount(Object count);

  /// No description provided for @predictionsValidStatus.
  ///
  /// In en, this message translates to:
  /// **'valid'**
  String get predictionsValidStatus;

  /// No description provided for @predictionsInvalidStatus.
  ///
  /// In en, this message translates to:
  /// **'invalid'**
  String get predictionsInvalidStatus;

  /// No description provided for @predictionsPickLockedSnack.
  ///
  /// In en, this message translates to:
  /// **'Match already started: pick locked'**
  String get predictionsPickLockedSnack;

  /// No description provided for @predictionsMissingConfirm.
  ///
  /// In en, this message translates to:
  /// **'You left {missing} matches without a prediction.\n\nCassandra rule: for each unplayed match a penalty equal to -highest odds (among 1/X/2) will be applied when scoring.\n\nSubmit anyway?'**
  String predictionsMissingConfirm(Object missing);

  /// No description provided for @predictionsSubmitAnyway.
  ///
  /// In en, this message translates to:
  /// **'Submit anyway'**
  String get predictionsSubmitAnyway;

  /// No description provided for @predictionsVisibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'public'**
  String get predictionsVisibilityPublic;

  /// No description provided for @predictionsVisibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'private'**
  String get predictionsVisibilityPrivate;

  /// No description provided for @predictionsSlipSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Slip submitted (visibility: {visibility})'**
  String predictionsSlipSubmitted(Object visibility);

  /// No description provided for @predictionsDebugScoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug: score calculation'**
  String get predictionsDebugScoreTitle;

  /// No description provided for @predictionsDebugBase.
  ///
  /// In en, this message translates to:
  /// **'base: {value}'**
  String predictionsDebugBase(Object value);

  /// No description provided for @predictionsDebugBonus.
  ///
  /// In en, this message translates to:
  /// **'bonus: {value}'**
  String predictionsDebugBonus(Object value);

  /// No description provided for @predictionsDebugTotal.
  ///
  /// In en, this message translates to:
  /// **'total: {value}'**
  String predictionsDebugTotal(Object value);

  /// No description provided for @predictionsDebugCorrect.
  ///
  /// In en, this message translates to:
  /// **'correct: {value}'**
  String predictionsDebugCorrect(Object value);

  /// No description provided for @predictionsDebugAvgOdds.
  ///
  /// In en, this message translates to:
  /// **'avg odds: {value}'**
  String predictionsDebugAvgOdds(Object value);

  /// No description provided for @predictionsDebugPickRow.
  ///
  /// In en, this message translates to:
  /// **'pick {pick}  •  result {outcome}  •  {points}'**
  String predictionsDebugPickRow(Object pick, Object outcome, Object points);

  /// No description provided for @predictionsTagLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get predictionsTagLive;

  /// No description provided for @predictionsTagDemo.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get predictionsTagDemo;

  /// No description provided for @predictionsTagSaved.
  ///
  /// In en, this message translates to:
  /// **'SAVED'**
  String get predictionsTagSaved;

  /// No description provided for @predictionsTagRecoveries.
  ///
  /// In en, this message translates to:
  /// **'RECOVERIES'**
  String get predictionsTagRecoveries;

  /// No description provided for @predictionsHistoryDemoInfo.
  ///
  /// In en, this message translates to:
  /// **'Predictions history (DEMO)\nShowing 16-19 from mocks. Current matchday is visible above (LIVE/DEMO).'**
  String get predictionsHistoryDemoInfo;

  /// No description provided for @predictionsPicksLocked.
  ///
  /// In en, this message translates to:
  /// **'picks locked'**
  String get predictionsPicksLocked;

  /// No description provided for @predictionsEditableUntil.
  ///
  /// In en, this message translates to:
  /// **'editable until {time}'**
  String predictionsEditableUntil(Object time);

  /// No description provided for @predictionsScoreSummary.
  ///
  /// In en, this message translates to:
  /// **'points: {total} (base {base} • bonus {bonus}) • correct {correct}/{count} • avg odds {avgOdds}'**
  String predictionsScoreSummary(
    Object total,
    Object base,
    Object bonus,
    Object correct,
    Object count,
    Object avgOdds,
  );

  /// No description provided for @predictionsDataRealBackendCache.
  ///
  /// In en, this message translates to:
  /// **'data: real (backend cache)'**
  String get predictionsDataRealBackendCache;

  /// No description provided for @predictionsRefreshMatches.
  ///
  /// In en, this message translates to:
  /// **'Refresh matches'**
  String get predictionsRefreshMatches;

  /// No description provided for @predictionsUseBackendCache.
  ///
  /// In en, this message translates to:
  /// **'Use backend cache'**
  String get predictionsUseBackendCache;

  /// No description provided for @predictionsForceDemoData.
  ///
  /// In en, this message translates to:
  /// **'Force demo data'**
  String get predictionsForceDemoData;

  /// No description provided for @predictionsSampleDataBanner.
  ///
  /// In en, this message translates to:
  /// **'Sample data - wait for backend sync'**
  String get predictionsSampleDataBanner;

  /// No description provided for @predictionsPastSegment.
  ///
  /// In en, this message translates to:
  /// **'past predictions'**
  String get predictionsPastSegment;

  /// No description provided for @predictionsUpcomingSegment.
  ///
  /// In en, this message translates to:
  /// **'upcoming predictions'**
  String get predictionsUpcomingSegment;

  /// No description provided for @predictionsDebugShifted.
  ///
  /// In en, this message translates to:
  /// **'debug: shifted {shifted} • <48h {under48} • >48h {over48}'**
  String predictionsDebugShifted(Object shifted, Object under48, Object over48);

  /// No description provided for @predictionsDebugPlayedVoid.
  ///
  /// In en, this message translates to:
  /// **'debug: played {played} • void {voidCount}'**
  String predictionsDebugPlayedVoid(Object played, Object voidCount);

  /// No description provided for @predictionsPicksSummary.
  ///
  /// In en, this message translates to:
  /// **'picks: {picked}/{total}  •  avg odds: {avgOdds}'**
  String predictionsPicksSummary(Object picked, Object total, Object avgOdds);

  /// No description provided for @predictionsLastSubmit.
  ///
  /// In en, this message translates to:
  /// **'last submit: {submittedAt} ({visibility})'**
  String predictionsLastSubmit(Object submittedAt, Object visibility);

  /// No description provided for @predictionsSubmitWithoutShowing.
  ///
  /// In en, this message translates to:
  /// **'submit without showing'**
  String get predictionsSubmitWithoutShowing;

  /// No description provided for @predictionsSubmitAndShow.
  ///
  /// In en, this message translates to:
  /// **'submit and show'**
  String get predictionsSubmitAndShow;

  /// No description provided for @commonNoDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get commonNoDataAvailable;

  /// No description provided for @predictionsBaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get predictionsBaseLabel;

  /// No description provided for @predictionsDataDemoFixturesNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Data: DEMO (fixtures not saved)'**
  String get predictionsDataDemoFixturesNotSaved;

  /// No description provided for @predictionsDataSaved.
  ///
  /// In en, this message translates to:
  /// **'Data: saved'**
  String get predictionsDataSaved;

  /// No description provided for @predictionsOutcomePending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get predictionsOutcomePending;

  /// No description provided for @settingsDiagNoMatchdayDoc.
  ///
  /// In en, this message translates to:
  /// **'No matchday document found in Firestore.'**
  String get settingsDiagNoMatchdayDoc;

  /// No description provided for @settingsDiagSourceFirestore.
  ///
  /// In en, this message translates to:
  /// **'Source: Firestore /seasons/<season>/matchdays/<day>'**
  String get settingsDiagSourceFirestore;

  /// No description provided for @settingsDiagSeasonKey.
  ///
  /// In en, this message translates to:
  /// **'seasonKey: {value}'**
  String settingsDiagSeasonKey(Object value);

  /// No description provided for @settingsDiagDayNumber.
  ///
  /// In en, this message translates to:
  /// **'dayNumber: {value}'**
  String settingsDiagDayNumber(Object value);

  /// No description provided for @settingsDiagMatchesCount.
  ///
  /// In en, this message translates to:
  /// **'matches: {count}'**
  String settingsDiagMatchesCount(Object count);

  /// No description provided for @settingsDiagOutcomesCount.
  ///
  /// In en, this message translates to:
  /// **'outcomes: {count}'**
  String settingsDiagOutcomesCount(Object count);

  /// No description provided for @settingsDiagUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'updatedAt: {value}'**
  String settingsDiagUpdatedAt(Object value);

  /// No description provided for @settingsDiagErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get settingsDiagErrorTitle;

  /// No description provided for @commonVersusShort.
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get commonVersusShort;

  /// No description provided for @predictionsDoubleChance.
  ///
  /// In en, this message translates to:
  /// **'Double chance'**
  String get predictionsDoubleChance;

  /// No description provided for @predictionsClearPick.
  ///
  /// In en, this message translates to:
  /// **'Clear pick'**
  String get predictionsClearPick;
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
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
