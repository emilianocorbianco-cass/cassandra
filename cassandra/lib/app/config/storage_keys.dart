class StorageKeys {
  StorageKeys._();

  // Profile
  static const profileTeamName = 'profile.teamName';
  static const profileFavoriteTeam = 'profile.favoriteTeam';
  static const teamNameLegacy = 'teamName';
  static const favoriteTeamLegacy = 'favoriteTeam';
  static const profileIdV1 = 'profile.id.v1';
  static const profileDisplayNameV1 = 'profile.displayName.v1';
  static const profileEmailV1 = 'profile.email.v1';
  static const profilePhotoUrlV1 = 'profile.photoUrl.v1';
  static const profileLocalUpdatedAtMsV1 = 'profile.localUpdatedAtMs.v1';
  static const profileLocalFieldUpdatedAtMsV1 =
      'profile.localFieldUpdatedAtMs.v1';
  static const demoSeedV1 = 'demo_seed.v1';

  // Auth / remember
  static const rememberMeEnabledV1 = 'auth.rememberMe.enabled.v1';
  static const rememberedUidV1 = 'auth.remembered.uid.v1';
  static const rememberedHandleV1 = 'auth.remembered.handle.v1';
  static const rememberedPhotoUrlV1 = 'auth.remembered.photoUrl.v1';
  static const rememberedProviderV1 = 'auth.remembered.provider.v1';
  static const anonymousHistoryScopeV1 = 'auth.anonymousHistoryScope.v1';
  static const devicePushTokenV1 = 'push.deviceToken.v1';

  // Firestore migration
  static const firestoreMigrationV1Done = 'firestore_migration_v1_done';

  // App settings
  static const language = 'language';
  static const defaultVisibility = 'defaultVisibility';
  static const themeMode = 'themeMode';

  // Group
  static const groupNameV1 = 'group.name.v1';
  static const groupInviteCodeV1 = 'group.inviteCode.v1';
  static const groupImagePathV1 = 'group.imagePath.v1';
  static const groupAdminApprovalV1 = 'group.adminApproval.v1';
  static const groupActiveGroupIdV1 = 'group.activeGroupId.v1';

  // Prediction
  static const currentUserPicksByMatchIdV1 =
      'cassandra.current_user_picks_by_match_id_v1';
  static const currentUserPicksByMatchdayV1 = 'picks.currentUser.byMatchday.v1';
  static const pendingPicksOutboxV1 = 'picks.pendingOutbox.v1';
  static const predictionOutcomesByMatchdayV1 = 'outcomes.byMatchday.v1';
  static const memberPicksByMemberIdV1 =
      'cassandra.member_picks_by_member_id_v1';
  static const matchdayMatchesByDayV1 = 'matchdayMatchesByDay.v1';

  // Matchday
  static const cassandraMatchdayCursorV1 = 'cassandra.matchday.cursor.v1';
  static const finalizedMatchdaysV1 = 'matchday.finalized.v1';
  static const cassandraMatchdayLastAutoBumpFromV1 =
      'cassandra.matchday.lastAutoBumpFrom.v1';
  static const originKickoffsByMatchIdV1 =
      'fixtures.originKickoffsByMatchId.v1';
}
