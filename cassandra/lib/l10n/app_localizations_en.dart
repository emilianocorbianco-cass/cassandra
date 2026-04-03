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
  String get loginDifferentAccountTitle => 'Different account detected';

  @override
  String loginDifferentAccountBody(Object handle) {
    return 'This device remembers account $handle. Do you want to continue with this new account?';
  }

  @override
  String get loginDifferentAccountContinue => 'Continue with this account';

  @override
  String get loginDifferentAccountCancelled => 'Sign-in cancelled. Press Sign in again if you want to retry.';

  @override
  String get loginPrivacyNotice => 'We only use what\'s strictly necessary to identify you.';

  @override
  String get loginAccountConflictTitle => 'Account already exists';

  @override
  String loginAccountConflictBody(Object email, Object provider) {
    return 'An account with $email already exists using $provider. Sign in with $provider first to link your accounts.';
  }

  @override
  String get loginAccountConflictLink => 'Sign in and link';

  @override
  String get profileSetupTitle => 'Complete your profile';

  @override
  String get profileSetupSubtitle => 'Set your details so Cassandra can recognize you instantly.';

  @override
  String get profileSetupRememberMe => 'Remember me on this device';

  @override
  String get profileSetupContinue => 'Continue';

  @override
  String welcomeBackTitle(Object handle) {
    return 'Hi $handle';
  }

  @override
  String get welcomeBackEnter => 'Enter';

  @override
  String get welcomeBackNotYou => 'Not you?';

  @override
  String get welcomeBackAuthReason => 'Confirm your identity to enter Cassandra.';

  @override
  String get welcomeBackAuthCancelled => 'Authentication was cancelled. Please try again.';

  @override
  String get welcomeBackQuickSignInUnavailable => 'Quick sign-in is unavailable. Tap \"Not you?\" to use another account.';

  @override
  String get welcomeBackUidMismatch => 'This account does not match the profile saved on this device. Tap \"Not you?\" to switch account.';

  @override
  String get createGroupTitle => 'Create your group';

  @override
  String get createGroupSubtitle => 'Challenge your friends on Serie A predictions';

  @override
  String get createGroupTapAddPhoto => 'Tap to add photo';

  @override
  String get createGroupNameLabel => 'Group name';

  @override
  String get createGroupButton => 'Create group';

  @override
  String get createGroupHaveInviteCode => 'Invite a friend';

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
  String get createGroupError => 'Unable to create the group. Please try again.';

  @override
  String groupShareInviteMessage(Object groupName, Object inviteCode) {
    return 'Join my group \"$groupName\" on Cassandra!\n\nCode: $inviteCode\n\nhttps://cassandrabet.app/join/$inviteCode';
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
  String get joinGroupPendingApproval => 'Request sent! The group admin must approve your access.';

  @override
  String get groupPendingMembers => 'Pending requests';

  @override
  String get groupApprove => 'Approve';

  @override
  String get groupReject => 'Reject';

  @override
  String get joinGroupInvalidCode => 'Invalid invite code';

  @override
  String get joinGroupAlreadyMember => 'Already a member of this group';

  @override
  String get joinGroupFull => 'This group is full';

  @override
  String get joinGroupUnavailable => 'This group is unavailable';

  @override
  String get groupTitle => 'My group';

  @override
  String get groupEmptyCreateButton => 'Create a group';

  @override
  String get groupEmptyJoinButton => 'Join a group';

  @override
  String get groupJoinTooltip => 'Join a group';

  @override
  String get groupDefaultName => 'Cassandra Crew';

  @override
  String get groupSampleDataBanner => 'Sample data - join a group to see real data';

  @override
  String get groupDataRefreshing => 'refreshing...';

  @override
  String get groupDataRealApi => 'data: real (API)';

  @override
  String get groupDataDemo => 'data: demo';

  @override
  String get groupSignInRequired => 'Sign in to continue.';

  @override
  String get backendPermissionDenied => 'Backend access denied. Check login and Firestore rules.';

  @override
  String get groupShareUnavailableCodeCopied => 'Sharing is unavailable here. Invite code copied.';

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
  String get groupStats => 'stats';

  @override
  String get groupHistoryDemoCard => 'Matchday history (DEMO)\nShowing 16-19 from mocks. Once we have real history via API, we\'ll make it live.';

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
  String get settingsBackendNotConfigured => 'Backend not configured on this device';

  @override
  String get settingsNoBackendDataCurrentMatchday => 'No backend data available for the current matchday';

  @override
  String get settingsCacheRefreshedFromBackend => 'Cache refreshed from backend';

  @override
  String get settingsCacheRefreshError => 'Error refreshing from backend';

  @override
  String get settingsDevModeNoFirebase => 'Dev mode - Firebase not configured';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteGroup => 'Delete group';

  @override
  String get settingsDeleteGroupQuestion => 'This action will delete the group for all members. Continue?';

  @override
  String get settingsDeleteGroupDone => 'Group deleted';

  @override
  String get settingsDeleteGroupOnlyAdmin => 'Only the group creator can delete it.';

  @override
  String get settingsDeleteGroupFailed => 'Unable to delete group. Please try again.';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsConfirm => 'Confirm';

  @override
  String get settingsSignOutQuestion => 'Sign out of your account?';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsDeleteAccountQuestion => 'This action is irreversible. Continue?';

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
  String get settingsProfileImageLabel => 'Profile image';

  @override
  String get settingsDisplayNameLabel => 'User name';

  @override
  String get settingsDisplayNameHint => 'Name';

  @override
  String get settingsHandleLabel => 'Handle';

  @override
  String get settingsHandleHint => 'Ex: @emiliano';

  @override
  String get settingsSegmentMySettings => 'my settings';

  @override
  String get settingsSegmentMyStats => 'my stats';

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
  String get settingsAdminApprovalSubtitle => 'Only the admin can accept new members';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsLanguage => 'Language selection';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageIt => 'IT';

  @override
  String get settingsLanguageEn => 'EN';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get settingsThemeModeSystem => 'System';

  @override
  String get settingsThemeModeLight => 'Light';

  @override
  String get settingsThemeModeDark => 'Dark';

  @override
  String get settingsTranslationNote => 'Note: translations are continuously maintained.';

  @override
  String get settingsPicksPrivacyDefault => 'Picks privacy (default)';

  @override
  String get settingsPrivacyPublic => 'Public';

  @override
  String get settingsPrivacyFriends => 'Friends';

  @override
  String get settingsPrivacyPrivate => 'Private';

  @override
  String get settingsPrivacyNote => 'This preference will be used once we connect picks submission + backend.';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsFixturesCacheTitle => 'Fixtures cache';

  @override
  String get settingsRefreshCacheNowTitle => 'Refresh cache now';

  @override
  String get settingsRefreshCacheNowSubtitle => 'Reads current matchday from backend cache.';

  @override
  String get settingsClearFixturesCacheTitle => 'Clear fixtures cache';

  @override
  String get settingsClearFixturesCacheSubtitle => 'Fallback to local demo data until next refresh.';

  @override
  String get settingsCacheCleared => 'Cache cleared';

  @override
  String get settingsBackendDiagnosticsTitle => 'Backend diagnostics';

  @override
  String get settingsBackendDiagnosticsSubtitle => 'Verify matchday cache loaded from Firestore.';

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
  String get predHistoryInfo => 'Here you can find the matchdays you saved/submitted.\nIf we don\'t have historical fixtures via API, we use a DEMO fallback to show details anyway.';

  @override
  String get predHistoryEmpty => 'No matchday saved.\nGo to Predictions and submit at least one matchday to see it here.';

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
  String get serieASignInRequired => 'Sign in to see live data.';

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
  String get liveStatusFirstHalf => 'First Half';

  @override
  String get liveStatusHalftime => 'Halftime';

  @override
  String get liveStatusSecondHalf => 'Second Half';

  @override
  String get liveStatusFinal => 'Final';

  @override
  String get liveNoEvents => 'No key events available';

  @override
  String get liveEventGoal => 'Goal';

  @override
  String get liveEventPenaltyScored => 'Penalty scored';

  @override
  String get liveEventPenaltyMissed => 'Penalty missed';

  @override
  String get liveEventPenalty => 'Penalty';

  @override
  String get liveEventSubstitution => 'Substitution';

  @override
  String get liveEventYellowCard => 'Yellow card';

  @override
  String get liveEventRedCard => 'Red card';

  @override
  String get liveEventWoodwork => 'Post/Crossbar';

  @override
  String get liveEventVarGoal => 'Cancelled goal (VAR)';

  @override
  String get liveEventGeneric => 'Event';

  @override
  String get kickoffLabel => 'Kickoff';

  @override
  String get leaderboardsTitle => 'Standings';

  @override
  String get leaderboardsDemoBanner => 'Sample data - real data will appear after first submission';

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
    return 'Best matchday$value';
  }

  @override
  String statsWorstMatchday(Object value) {
    return 'Worst matchday$value';
  }

  @override
  String statsTotalBonus(Object value) {
    return 'Total bonus: $value';
  }

  @override
  String get statsMatchdays => 'matchdays';

  @override
  String get statsCorrect => 'correct';

  @override
  String get tabPredictions => 'Predictions';

  @override
  String get tabStats => 'Stats';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabTrophies => 'Trophies';

  @override
  String get groupYou => 'you';

  @override
  String get groupOutcomesSavedTag => 'OUT: SAVED';

  @override
  String get groupOutcomesRuntimeTag => 'OUT: runtime';

  @override
  String get groupPicksSavedTag => 'PICK: SAVED';

  @override
  String get groupPicksDemoRuntimeTag => 'PICK: demo/runtime';

  @override
  String get groupBonusLabel => 'Bonus';

  @override
  String get groupAvgOddsPlayedLabel => 'avg. odds played';

  @override
  String get groupPickLabel => 'pick';

  @override
  String get groupOutcomeLabel => 'outcome';

  @override
  String get groupOddsLabel => 'odds';

  @override
  String get groupSyncError => 'Error loading group data';

  @override
  String get groupSyncRetry => 'Retry';

  @override
  String get tabGroup => 'Group';

  @override
  String get tabLive => 'Livescore';

  @override
  String get tabSettings => 'Settings';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatNoGroupTitle => 'Chat is available only inside your group';

  @override
  String get chatNoGroupSubtitle => 'Create or join a group in the Group tab to start chatting.';

  @override
  String get chatEphemeralNotice => 'Messages are automatically deleted after 24 hours.';

  @override
  String get chatEmpty => 'No messages in the last 24 hours.';

  @override
  String get chatInputHint => 'Write a message';

  @override
  String get chatStickerPickerTitle => 'Stickers';

  @override
  String get chatPhotoButton => 'Photo';

  @override
  String get chatPhotoTooLarge => 'Photo is too large. Pick a lighter one.';

  @override
  String leaderboardsPlayersCount(Object count) {
    return 'Players: $count';
  }

  @override
  String get serieAStandingsTitle => 'Serie A Standings';

  @override
  String get serieATeamColumn => 'Team';

  @override
  String get serieAPlayedColumn => 'MP';

  @override
  String get serieAWinsColumn => 'W';

  @override
  String get serieADrawsColumn => 'D';

  @override
  String get serieALossesColumn => 'L';

  @override
  String get serieAGoalsAgainstColumn => 'GA';

  @override
  String get serieAGoalDiffColumn => 'GD';

  @override
  String get serieAPointsColumn => 'Pts';

  @override
  String get serieALastFiveColumn => 'Last 5';

  @override
  String statsBestDayShort(Object day, Object points) {
    return 'MD$day: $points';
  }

  @override
  String statsWorstDayShort(Object day, Object points) {
    return 'MD$day: $points';
  }

  @override
  String get profileTrophiesHistory => 'Trophies (history)';

  @override
  String profileTrophiesDescription(Object displayName) {
    return 'Trophies for $displayName (demo season history).\nRules: 👑 group winner • L last place • 👁️ 10/10 correct • 🦉 jinxed own favorite team.';
  }

  @override
  String predictionsVoidCount(Object count) {
    return 'void $count';
  }

  @override
  String get predictionsValidStatus => 'valid';

  @override
  String get predictionsInvalidStatus => 'invalid';

  @override
  String get predictionsPickLockedSnack => 'Match already started: pick locked';

  @override
  String predictionsMissingConfirm(Object missing) {
    return 'You left $missing matches without a prediction.\n\nCassandra rule: for each unplayed match a penalty equal to -highest odds (among 1/X/2) will be applied when scoring.\n\nSubmit anyway?';
  }

  @override
  String get predictionsSubmitAnyway => 'Submit anyway';

  @override
  String get predictionsVisibilityPublic => 'public';

  @override
  String get predictionsVisibilityPrivate => 'private';

  @override
  String predictionsSlipSubmitted(Object visibility) {
    return 'Slip submitted (visibility: $visibility)';
  }

  @override
  String get predictionsSlipSubmitFailed => 'Unable to submit slip. Please try again.';

  @override
  String get predictionsDebugScoreTitle => 'Debug: score calculation';

  @override
  String predictionsDebugBase(Object value) {
    return 'base: $value';
  }

  @override
  String predictionsDebugBonus(Object value) {
    return 'bonus: $value';
  }

  @override
  String predictionsDebugTotal(Object value) {
    return 'total: $value';
  }

  @override
  String predictionsDebugCorrect(Object value) {
    return 'correct: $value';
  }

  @override
  String predictionsDebugAvgOdds(Object value) {
    return 'avg odds: $value';
  }

  @override
  String predictionsDebugPickRow(Object pick, Object outcome, Object points) {
    return 'pick $pick  •  result $outcome  •  $points';
  }

  @override
  String get predictionsTagLive => 'LIVE';

  @override
  String get predictionsTagDemo => 'DEMO';

  @override
  String get predictionsTagSaved => 'SAVED';

  @override
  String get predictionsTagRecoveries => 'RECOVERIES';

  @override
  String get predictionsHistoryDemoInfo => 'Predictions history (DEMO)\nShowing 16-19 from mocks. Current matchday is visible above (LIVE/DEMO).';

  @override
  String get predictionsPicksLocked => 'picks locked';

  @override
  String predictionsEditableUntil(Object time) {
    return 'editable until $time';
  }

  @override
  String predictionsScoreSummary(Object total, Object base, Object bonus, Object correct, Object count, Object avgOdds) {
    return 'points: $total (base $base • bonus $bonus) • correct $correct/$count • avg odds $avgOdds';
  }

  @override
  String get predictionsDataRealBackendCache => 'data: real (backend cache)';

  @override
  String get predictionsRefreshMatches => 'Refresh matches';

  @override
  String get predictionsUseBackendCache => 'Use backend cache';

  @override
  String get predictionsForceDemoData => 'Force demo data';

  @override
  String get predictionsSampleDataBanner => 'Sample data - wait for backend sync';

  @override
  String get predictionsOfflineStatus => 'You\'re offline';

  @override
  String get predictionsPastSegment => 'past predictions';

  @override
  String get predictionsUpcomingSegment => 'predictions';

  @override
  String predictionsCorrectLine(Object correct, Object total) {
    return 'Correct predictions $correct/$total';
  }

  @override
  String predictionsPointsLine(Object total, Object base, Object bonus) {
    return 'Points: $total (Base $base - Bonus $bonus)';
  }

  @override
  String predictionsDebugShifted(Object shifted, Object under48, Object over48) {
    return 'debug: shifted $shifted • <48h $under48 • >48h $over48';
  }

  @override
  String predictionsDebugPlayedVoid(Object played, Object voidCount) {
    return 'debug: played $played • void $voidCount';
  }

  @override
  String predictionsPicksSummary(Object picked, Object total, Object avgOdds) {
    return 'picks: $picked/$total  •  avg odds: $avgOdds';
  }

  @override
  String predictionsLastSubmit(Object submittedAt, Object visibility) {
    return 'last submit: $submittedAt ($visibility)';
  }

  @override
  String get predictionsSubmitWithoutShowing => 'Submit without showing';

  @override
  String get predictionsSubmitAndShow => 'Submit and show';

  @override
  String get predictionsConfirmSubmit => 'Do you want to submit?';

  @override
  String get predictionsConfirmYes => 'Yes';

  @override
  String get predictionsConfirmNo => 'No';

  @override
  String get predictionsAlreadySubmitted => 'Picks already submitted for this matchday.';

  @override
  String get memberPickNotSubmitted => 'Not submitted';

  @override
  String get commonNoDataAvailable => 'No data available';

  @override
  String get predictionsBaseLabel => 'Base';

  @override
  String get predictionsDataDemoFixturesNotSaved => 'Data: DEMO (fixtures not saved)';

  @override
  String get predictionsDataSaved => 'Data: saved';

  @override
  String get predictionsOutcomePending => 'pending';

  @override
  String get settingsDiagNoMatchdayDoc => 'No matchday document found in Firestore.';

  @override
  String get settingsDiagSourceFirestore => 'Source: Firestore /seasons/<season>/matchdays/<day>';

  @override
  String settingsDiagSeasonKey(Object value) {
    return 'seasonKey: $value';
  }

  @override
  String settingsDiagDayNumber(Object value) {
    return 'dayNumber: $value';
  }

  @override
  String settingsDiagMatchesCount(Object count) {
    return 'matches: $count';
  }

  @override
  String settingsDiagOutcomesCount(Object count) {
    return 'outcomes: $count';
  }

  @override
  String settingsDiagUpdatedAt(Object value) {
    return 'updatedAt: $value';
  }

  @override
  String get settingsDiagErrorTitle => 'Error';

  @override
  String get commonVersusShort => 'vs';

  @override
  String get predictionsDoubleChance => 'Double chance';

  @override
  String get predictionsClearPick => 'Clear pick';

  @override
  String get groupHubTitle => 'Choose your group';

  @override
  String get groupHubSubtitle => 'Select a group to enter';

  @override
  String get groupHubCreateGroup => 'Create a group';

  @override
  String get groupHubJoinGroup => 'Join a group';

  @override
  String groupHubMemberCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get settingsSwitchGroup => 'Switch group';

  @override
  String get predictionsSubmitButton => 'Submit';

  @override
  String get predictionsSubmittedButton => 'Submitted';

  @override
  String get predictionsPicksMade => 'Picks made';

  @override
  String get predictionsMaxPoints => 'Max Points';

  @override
  String get predictionsMinPoints => 'Min Points';

  @override
  String get groupEditHandleTitle => 'Group handle';

  @override
  String get groupEditHandleHint => 'Custom handle';

  @override
  String get groupEditHandleReset => 'Use profile name';

  @override
  String get groupEditHandleSaved => 'Handle updated';
}
