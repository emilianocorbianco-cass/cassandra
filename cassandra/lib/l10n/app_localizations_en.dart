// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginSeriesAPredictions => 'Serie A Predictions';

  @override
  String get loginSignInGoogle => 'Sign in with Google';

  @override
  String get loginSignInApple => 'Sign in with Apple';

  @override
  String get loginSignInError => 'Sign-in error. Please try again.';

  @override
  String get loginPrivacyNotice =>
      'We only use what\'s strictly necessary to identify you.';

  @override
  String get createGroupTitle => 'Create your group';

  @override
  String get createGroupSubtitle =>
      'Challenge your friends on Serie A predictions';

  @override
  String get createGroupTapAddPhoto => 'Tap to add photo';

  @override
  String get createGroupNameLabel => 'Group name';

  @override
  String get createGroupButton => 'Create group';

  @override
  String get createGroupHaveInviteCode => 'Have an invite code?';

  @override
  String get createGroupCreated => 'Group created!';

  @override
  String get createGroupInviteCode => 'Invite code';

  @override
  String get createGroupCodeCopied => 'Code copied!';

  @override
  String get createGroupTapToCopy => 'Tap to copy';

  @override
  String get createGroupShareInviteCode => 'Share invite code';

  @override
  String get createGroupContinue => 'Continue';

  @override
  String groupShareInviteMessage(Object groupName, Object inviteCode) {
    return 'Join my group \"$groupName\" on Cassandra! Code: $inviteCode';
  }

  @override
  String get joinGroupTitle => 'Join a group';

  @override
  String get joinGroupEnterInviteCode => 'Enter the group invite code';

  @override
  String get joinGroupInviteCode => 'Invite code';

  @override
  String get joinGroupCodeHint => 'CASS-XXXX';

  @override
  String get joinGroupButton => 'Join';

  @override
  String get joinGroupJoined => 'Joined group!';

  @override
  String get joinGroupInvalidCode => 'Invalid invite code';

  @override
  String get joinGroupAlreadyMember => 'Already a member of this group';

  @override
  String get groupTitle => 'My group';

  @override
  String get groupJoinTooltip => 'Join a group';

  @override
  String get groupDefaultName => 'Cassandra Crew';

  @override
  String get groupSampleDataBanner =>
      'Sample data - join a group to see real data';

  @override
  String get groupDataRefreshing => 'refreshing...';

  @override
  String get groupDataRealApi => 'data: real (API)';

  @override
  String get groupDataDemo => 'data: demo';

  @override
  String get shortUpdated => 'upd.';

  @override
  String groupMatchdayLabel(Object matchdayNumber, Object daysLabel) {
    return 'matchday $matchdayNumber - $daysLabel';
  }

  @override
  String groupResultsLabel(Object graded, Object total) {
    return 'results: $graded/$total';
  }

  @override
  String groupResultsLabelPartial(Object graded, Object total) {
    return 'results: $graded/$total (partial)';
  }

  @override
  String get groupStandings => 'standings';

  @override
  String get groupMatchdays => 'matchdays';

  @override
  String get groupHistoryDemoCard =>
      'Matchday history (DEMO)\nShowing 16-19 from mocks. Once we have real history via API, we\'ll make it live.';

  @override
  String groupMatchdayTitle(Object dayNumber) {
    return 'Matchday $dayNumber';
  }

  @override
  String get groupResultsPrefix => 'results';

  @override
  String groupResultsShort(Object graded, Object total) {
    return '$graded/$total';
  }

  @override
  String groupResultsShortPartial(Object graded, Object total) {
    return '$graded/$total (partial)';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get settingsResetDone => 'Reset done';

  @override
  String get settingsBackendNotConfigured =>
      'Backend not configured on this device';

  @override
  String get settingsNoBackendDataCurrentMatchday =>
      'No backend data available for the current matchday';

  @override
  String get settingsCacheRefreshedFromBackend =>
      'Cache refreshed from backend';

  @override
  String get settingsCacheRefreshError => 'Error refreshing from backend';

  @override
  String get settingsDevModeNoFirebase => 'Dev mode - Firebase not configured';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsConfirm => 'Confirm';

  @override
  String get settingsSignOutQuestion => 'Sign out of your account?';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsDeleteAccountQuestion =>
      'This action is irreversible. Continue?';

  @override
  String get settingsDelete => 'Delete';

  @override
  String get settingsReauthError => 'Error: sign in again and retry.';

  @override
  String get settingsCacheEmpty => 'cache: empty';

  @override
  String get settingsDataBackendCache => 'data: backend cache';

  @override
  String get settingsDataDemo => 'data: demo';

  @override
  String get settingsDebugCacheTitle => 'Debug cache';

  @override
  String settingsDebugFixturesLine(Object kind) {
    return 'fixtures: $kind';
  }

  @override
  String settingsDebugMatchInCacheLine(Object count) {
    return 'match in cache: $count';
  }

  @override
  String settingsDebugOutcomesInCacheLine(Object count) {
    return 'outcomes in cache: $count';
  }

  @override
  String settingsDebugUpdateLine(Object updated) {
    return 'update: $updated';
  }

  @override
  String get settingsNever => 'never';

  @override
  String get settingsSimulationGroupTitle => 'Group simulation';

  @override
  String settingsSimulationSavedPicksLine(Object count) {
    return 'saved simulated picks: $count';
  }

  @override
  String get settingsGeneratePicks => 'Generate picks';

  @override
  String get settingsCopyMyPicks => 'Copy mine';

  @override
  String get settingsClearSimulatedPicks => 'Clear simulated';

  @override
  String settingsGeneratedPicksForMembers(Object count) {
    return 'Generated picks for $count members';
  }

  @override
  String settingsCopiedMyPicksToMembers(Object count) {
    return 'Copied your picks to $count members';
  }

  @override
  String get settingsSimulatedPicksCleared => 'Simulated picks cleared';

  @override
  String get settingsClearFixtures => 'Clear fixtures';

  @override
  String get settingsClearOutcomes => 'Clear outcomes';

  @override
  String get settingsClearAll => 'Clear all';

  @override
  String get settingsFixturesCacheCleared => 'Fixtures cache cleared';

  @override
  String get settingsOutcomesCacheCleared => 'Outcomes cache cleared';

  @override
  String get settingsPredictionCacheCleared => 'Predictions cache cleared';

  @override
  String get settingsProfile => 'Profile';

  @override
  String get settingsTeamNameLabel => 'Team name (handle)';

  @override
  String get settingsTeamNameHint => 'Ex: FC Cassandra';

  @override
  String get settingsFavoriteTeamLabel => 'Favorite team';

  @override
  String get settingsFavoriteTeamHint => 'Ex: Roma';

  @override
  String get settingsGroup => 'Group';

  @override
  String get settingsGroupImageTitle => 'Group image';

  @override
  String get settingsGroupImageSubtitle => 'Tap to change the photo';

  @override
  String get settingsAdminApprovalTitle => 'Admin approval';

  @override
  String get settingsAdminApprovalSubtitle =>
      'Only the admin can accept new members';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageIt => 'IT';

  @override
  String get settingsLanguageEn => 'EN';

  @override
  String get settingsTranslationNote =>
      'Note: many labels are still hardcoded for now. We will translate in batches.';

  @override
  String get settingsPicksPrivacyDefault => 'Picks privacy (default)';

  @override
  String get settingsPrivacyPublic => 'Public';

  @override
  String get settingsPrivacyFriends => 'Friends';

  @override
  String get settingsPrivacyPrivate => 'Private';

  @override
  String get settingsPrivacyNote =>
      'This preference will be used once we connect picks submission + backend.';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsFixturesCacheTitle => 'Fixtures cache';

  @override
  String get settingsRefreshCacheNowTitle => 'Refresh cache now';

  @override
  String get settingsRefreshCacheNowSubtitle =>
      'Reads current matchday from backend cache.';

  @override
  String get settingsClearFixturesCacheTitle => 'Clear fixtures cache';

  @override
  String get settingsClearFixturesCacheSubtitle =>
      'Fallback to local demo data until next refresh.';

  @override
  String get settingsCacheCleared => 'Cache cleared';

  @override
  String get settingsBackendDiagnosticsTitle => 'Backend diagnostics';

  @override
  String get settingsBackendDiagnosticsSubtitle =>
      'Verify matchday cache loaded from Firestore.';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsReset => 'Reset';

  @override
  String get settingsKindBackendCache => 'backend cache';

  @override
  String get settingsKindDemo => 'demo';

  @override
  String get settingsKindEmpty => 'empty';

  @override
  String get predHistoryTitle => 'Predictions history';

  @override
  String get predHistoryInfo =>
      'Here you can find the matchdays you saved/submitted.\nIf we don\'t have historical fixtures via API, we use a DEMO fallback to show details anyway.';

  @override
  String get predHistoryEmpty =>
      'No matchday saved.\nGo to Predictions and submit at least one matchday to see it here.';

  @override
  String get predHistoryTagSaved => 'SAVED';

  @override
  String get predHistoryTagApi => 'API';

  @override
  String get predHistoryTagDemo => 'DEMO';

  @override
  String get serieATitle => 'Live';

  @override
  String get serieASegmentResults => 'results';

  @override
  String get serieASegmentStandings => 'standings';

  @override
  String get serieADataDemo => 'data: demo';

  @override
  String serieAErrorLoadingBackendCache(Object errorMessage) {
    return 'Error loading backend cache: $errorMessage';
  }

  @override
  String get serieANoMatchDataAvailable => 'No match data available';

  @override
  String get serieANoMatchesToShow => 'No matches to show';

  @override
  String get serieANoResults => 'No results';

  @override
  String get serieANoUpcomingMatches => 'No upcoming matches';

  @override
  String get kickoffLabel => 'Kickoff';

  @override
  String get leaderboardsTitle => 'Standings';

  @override
  String get leaderboardsDemoBanner =>
      'Sample data - real data will appear after first submission';

  @override
  String get leaderboardsDataRefreshing => 'refreshing...';

  @override
  String get leaderboardsDataRealApi => 'real (API)';

  @override
  String get leaderboardsDataEmpty => 'empty';

  @override
  String get leaderboardsNever => 'never';

  @override
  String leaderboardsDataLine(Object kind, Object updatedLabel) {
    return 'data: $kind • upd. $updatedLabel';
  }

  @override
  String get leaderboardsOverall => 'overall';

  @override
  String get leaderboardsMatchdays => 'matchdays';

  @override
  String get leaderboardsPoints => 'points';

  @override
  String get leaderboardsAverage => 'average';

  @override
  String leaderboardsMatchdayLiveTitle(Object dayNumber) {
    return 'Matchday $dayNumber (LIVE)';
  }

  @override
  String get statsTitle => 'Stats';

  @override
  String get statsSegmentPersonal => 'personal';

  @override
  String get statsSegmentGroup => 'group';

  @override
  String get statsMetricAverage => 'average';

  @override
  String get statsMetricTotal => 'total';

  @override
  String get statsMetricPercentCorrect => '% correct';

  @override
  String get statsMetricPerfectWeeks => 'perfect weeks';

  @override
  String get statsTotal => 'total';

  @override
  String get statsAvgMatchday => 'avg/matchday';

  @override
  String get statsMatchdaysPlayed => 'matchdays played';

  @override
  String get statsAvgOdds => 'avg odds';

  @override
  String get statsTotalCorrect => 'total correct';

  @override
  String get statsAvgBonus => 'avg bonus';

  @override
  String get statsHighlights => 'Highlights';

  @override
  String statsBestMatchday(Object value) {
    return 'Best matchday: $value';
  }

  @override
  String statsWorstMatchday(Object value) {
    return 'Worst matchday: $value';
  }

  @override
  String statsTotalBonus(Object value) {
    return 'Total bonus: $value';
  }

  @override
  String get statsMatchdays => 'matchdays';

  @override
  String get statsCorrect => 'correct';
}
