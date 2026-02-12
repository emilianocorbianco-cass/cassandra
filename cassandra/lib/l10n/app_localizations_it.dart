// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get loginSeriesAPredictions => 'Pronostici Serie A';

  @override
  String get loginSignInGoogle => 'Accedi con Google';

  @override
  String get loginSignInApple => 'Accedi con Apple';

  @override
  String get loginSignInError => 'Errore di accesso. Riprova.';

  @override
  String get loginPrivacyNotice =>
      'Usiamo solo il minimo necessario per identificarti.';

  @override
  String get createGroupTitle => 'Crea il tuo gruppo';

  @override
  String get createGroupSubtitle =>
      'Sfida i tuoi amici sui pronostici di Serie A';

  @override
  String get createGroupTapAddPhoto => 'Tocca per aggiungere foto';

  @override
  String get createGroupNameLabel => 'Nome del gruppo';

  @override
  String get createGroupButton => 'Crea gruppo';

  @override
  String get createGroupHaveInviteCode => 'Hai un codice invito?';

  @override
  String get createGroupCreated => 'Gruppo creato!';

  @override
  String get createGroupInviteCode => 'Codice invito';

  @override
  String get createGroupCodeCopied => 'Codice copiato!';

  @override
  String get createGroupTapToCopy => 'Tocca per copiare';

  @override
  String get createGroupShareInviteCode => 'Condividi codice invito';

  @override
  String get createGroupContinue => 'Continua';

  @override
  String groupShareInviteMessage(Object groupName, Object inviteCode) {
    return 'Unisciti al mio gruppo \"$groupName\" su Cassandra! Codice: $inviteCode';
  }

  @override
  String get joinGroupTitle => 'Unisciti a un gruppo';

  @override
  String get joinGroupEnterInviteCode =>
      'Inserisci il codice invito del gruppo';

  @override
  String get joinGroupInviteCode => 'Codice invito';

  @override
  String get joinGroupCodeHint => 'CASS-XXXX';

  @override
  String get joinGroupButton => 'Unisciti';

  @override
  String get joinGroupJoined => 'Entrato nel gruppo!';

  @override
  String get joinGroupInvalidCode => 'Codice invito non valido';

  @override
  String get joinGroupAlreadyMember => 'Fai gia parte di questo gruppo';

  @override
  String get groupTitle => 'Il mio gruppo';

  @override
  String get groupJoinTooltip => 'Unisciti a un gruppo';

  @override
  String get groupDefaultName => 'Cassandra Crew';

  @override
  String get groupSampleDataBanner =>
      'Dati di esempio - unisciti a un gruppo per vedere dati reali';

  @override
  String get groupDataRefreshing => 'aggiornamento...';

  @override
  String get groupDataRealApi => 'dati: reali (API)';

  @override
  String get groupDataDemo => 'dati: demo';

  @override
  String get shortUpdated => 'agg.';

  @override
  String groupMatchdayLabel(Object matchdayNumber, Object daysLabel) {
    return 'giornata $matchdayNumber - $daysLabel';
  }

  @override
  String groupResultsLabel(Object graded, Object total) {
    return 'risultati: $graded/$total';
  }

  @override
  String groupResultsLabelPartial(Object graded, Object total) {
    return 'risultati: $graded/$total (parziale)';
  }

  @override
  String get groupStandings => 'classifica';

  @override
  String get groupMatchdays => 'giornate';

  @override
  String get groupHistoryDemoCard =>
      'Storico giornate (DEMO)\nQui mostriamo 16-19 dai mock. Appena abbiamo storico reale via API, lo rendiamo vero.';

  @override
  String groupMatchdayTitle(Object dayNumber) {
    return 'Giornata $dayNumber';
  }

  @override
  String get groupResultsPrefix => 'risultati';

  @override
  String groupResultsShort(Object graded, Object total) {
    return '$graded/$total';
  }

  @override
  String groupResultsShortPartial(Object graded, Object total) {
    return '$graded/$total (parziale)';
  }

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsSaved => 'Impostazioni salvate';

  @override
  String get settingsResetDone => 'Ripristinato';

  @override
  String get settingsBackendNotConfigured =>
      'Backend non configurato su questo device';

  @override
  String get settingsNoBackendDataCurrentMatchday =>
      'Nessun dato backend disponibile per la giornata corrente';

  @override
  String get settingsCacheRefreshedFromBackend => 'Cache aggiornata da backend';

  @override
  String get settingsCacheRefreshError => 'Errore aggiornando da backend';

  @override
  String get settingsDevModeNoFirebase =>
      'Modalita sviluppo - Firebase non configurato';

  @override
  String get settingsSignOut => 'Esci';

  @override
  String get settingsDeleteAccount => 'Elimina account';

  @override
  String get settingsSignIn => 'Accedi';

  @override
  String get settingsConfirm => 'Conferma';

  @override
  String get settingsSignOutQuestion => 'Vuoi uscire dal tuo account?';

  @override
  String get settingsCancel => 'Annulla';

  @override
  String get settingsDeleteAccountQuestion =>
      'Questa azione e irreversibile. Vuoi continuare?';

  @override
  String get settingsDelete => 'Elimina';

  @override
  String get settingsReauthError => 'Errore: riaccedi e riprova.';

  @override
  String get settingsCacheEmpty => 'cache: vuota';

  @override
  String get settingsDataBackendCache => 'dati: cache backend';

  @override
  String get settingsDataDemo => 'dati: demo';

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
    return 'aggiornamento: $updated';
  }

  @override
  String get settingsNever => 'mai';

  @override
  String get settingsSimulationGroupTitle => 'Simulazione gruppo';

  @override
  String settingsSimulationSavedPicksLine(Object count) {
    return 'picks simulati salvati: $count';
  }

  @override
  String get settingsGeneratePicks => 'Genera picks';

  @override
  String get settingsCopyMyPicks => 'Copia i miei';

  @override
  String get settingsClearSimulatedPicks => 'Svuota simulati';

  @override
  String settingsGeneratedPicksForMembers(Object count) {
    return 'Picks generati per $count membri';
  }

  @override
  String settingsCopiedMyPicksToMembers(Object count) {
    return 'Copiati i tuoi pick su $count membri';
  }

  @override
  String get settingsSimulatedPicksCleared => 'Picks simulati svuotati';

  @override
  String get settingsClearFixtures => 'Svuota fixtures';

  @override
  String get settingsClearOutcomes => 'Svuota outcomes';

  @override
  String get settingsClearAll => 'Svuota tutto';

  @override
  String get settingsFixturesCacheCleared => 'Cache fixtures svuotata';

  @override
  String get settingsOutcomesCacheCleared => 'Cache outcomes svuotata';

  @override
  String get settingsPredictionCacheCleared => 'Cache pronostici svuotata';

  @override
  String get settingsProfile => 'Profilo';

  @override
  String get settingsTeamNameLabel => 'Nome squadra (handle)';

  @override
  String get settingsTeamNameHint => 'Es: FC Cassandra';

  @override
  String get settingsFavoriteTeamLabel => 'Squadra del cuore';

  @override
  String get settingsFavoriteTeamHint => 'Es: Roma';

  @override
  String get settingsGroup => 'Gruppo';

  @override
  String get settingsGroupImageTitle => 'Immagine del gruppo';

  @override
  String get settingsGroupImageSubtitle => 'Tocca per cambiare la foto';

  @override
  String get settingsAdminApprovalTitle => 'Approvazione admin';

  @override
  String get settingsAdminApprovalSubtitle =>
      'Solo l\'admin puo accettare nuovi membri';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageSystem => 'Sistema';

  @override
  String get settingsLanguageIt => 'IT';

  @override
  String get settingsLanguageEn => 'EN';

  @override
  String get settingsTranslationNote =>
      'Nota: le traduzioni vengono aggiornate continuamente.';

  @override
  String get settingsPicksPrivacyDefault => 'Privacy pronostici (default)';

  @override
  String get settingsPrivacyPublic => 'Pubblico';

  @override
  String get settingsPrivacyFriends => 'Amici';

  @override
  String get settingsPrivacyPrivate => 'Privato';

  @override
  String get settingsPrivacyNote =>
      'Questa preferenza verra usata quando collegheremo invio pronostici + backend.';

  @override
  String get settingsDiagnostics => 'Diagnostica';

  @override
  String get settingsFixturesCacheTitle => 'Fixtures cache';

  @override
  String get settingsRefreshCacheNowTitle => 'Aggiorna cache ora';

  @override
  String get settingsRefreshCacheNowSubtitle =>
      'Legge la matchday corrente dalla cache backend.';

  @override
  String get settingsClearFixturesCacheTitle => 'Svuota cache fixtures';

  @override
  String get settingsClearFixturesCacheSubtitle =>
      'Torna ai dati demo locali fino al prossimo refresh.';

  @override
  String get settingsCacheCleared => 'Cache svuotata';

  @override
  String get settingsBackendDiagnosticsTitle => 'Diagnostica backend';

  @override
  String get settingsBackendDiagnosticsSubtitle =>
      'Verifica cache matchday letta da Firestore.';

  @override
  String get settingsSave => 'Salva';

  @override
  String get settingsReset => 'Reset';

  @override
  String get settingsKindBackendCache => 'cache backend';

  @override
  String get settingsKindDemo => 'demo';

  @override
  String get settingsKindEmpty => 'vuota';

  @override
  String get predHistoryTitle => 'Storico pronostici';

  @override
  String get predHistoryInfo =>
      'Qui trovi le giornate che hai salvato/inviato.\nSe non abbiamo fixture storiche via API, usiamo un fallback DEMO per mostrare comunque il dettaglio.';

  @override
  String get predHistoryEmpty =>
      'Nessuna giornata salvata.\nVai su Pronostici e invia almeno una giornata per vederla qui.';

  @override
  String get predHistoryTagSaved => 'SALVATI';

  @override
  String get predHistoryTagApi => 'API';

  @override
  String get predHistoryTagDemo => 'DEMO';

  @override
  String get serieATitle => 'Live';

  @override
  String get serieASegmentResults => 'risultati';

  @override
  String get serieASegmentStandings => 'classifica';

  @override
  String get serieADataDemo => 'dati: demo';

  @override
  String serieAErrorLoadingBackendCache(Object errorMessage) {
    return 'Errore caricando cache backend: $errorMessage';
  }

  @override
  String get serieANoMatchDataAvailable => 'Nessun dato partite disponibile';

  @override
  String get serieANoMatchesToShow => 'Nessuna partita da mostrare';

  @override
  String get serieANoResults => 'Nessun risultato';

  @override
  String get serieANoUpcomingMatches => 'Nessuna partita in programma';

  @override
  String get kickoffLabel => 'Kickoff';

  @override
  String get leaderboardsTitle => 'Classifiche';

  @override
  String get leaderboardsDemoBanner =>
      'Dati di esempio - i dati reali appariranno dopo il primo invio';

  @override
  String get leaderboardsDataRefreshing => 'aggiornamento...';

  @override
  String get leaderboardsDataRealApi => 'reali (API)';

  @override
  String get leaderboardsDataEmpty => 'vuota';

  @override
  String get leaderboardsNever => 'mai';

  @override
  String leaderboardsDataLine(Object kind, Object updatedLabel) {
    return 'dati: $kind • agg. $updatedLabel';
  }

  @override
  String get leaderboardsOverall => 'generale';

  @override
  String get leaderboardsMatchdays => 'giornate';

  @override
  String get leaderboardsPoints => 'punti';

  @override
  String get leaderboardsAverage => 'media';

  @override
  String leaderboardsMatchdayLiveTitle(Object dayNumber) {
    return 'Giornata $dayNumber (LIVE)';
  }

  @override
  String get statsTitle => 'Statistiche';

  @override
  String get statsSegmentPersonal => 'personali';

  @override
  String get statsSegmentGroup => 'gruppo';

  @override
  String get statsMetricAverage => 'media';

  @override
  String get statsMetricTotal => 'totale';

  @override
  String get statsMetricPercentCorrect => '% esatti';

  @override
  String get statsMetricPerfectWeeks => 'settimane perfette';

  @override
  String get statsTotal => 'totale';

  @override
  String get statsAvgMatchday => 'media/giornata';

  @override
  String get statsMatchdaysPlayed => 'giornate giocate';

  @override
  String get statsAvgOdds => 'quota media';

  @override
  String get statsTotalCorrect => 'esatti totali';

  @override
  String get statsAvgBonus => 'bonus medio';

  @override
  String get statsHighlights => 'In evidenza';

  @override
  String statsBestMatchday(Object value) {
    return 'Miglior giornata: $value';
  }

  @override
  String statsWorstMatchday(Object value) {
    return 'Peggior giornata: $value';
  }

  @override
  String statsTotalBonus(Object value) {
    return 'Bonus totale: $value';
  }

  @override
  String get statsMatchdays => 'giornate';

  @override
  String get statsCorrect => 'esatti';

  @override
  String get tabPredictions => 'Pronostici';

  @override
  String get tabStats => 'Statistiche';

  @override
  String get tabTrophies => 'Trofei';

  @override
  String get groupYou => 'tu';

  @override
  String get groupOutcomesSavedTag => 'OUT: SALVATI';

  @override
  String get groupOutcomesRuntimeTag => 'OUT: runtime';

  @override
  String get groupPicksSavedTag => 'PICK: SALVATI';

  @override
  String get groupPicksDemoRuntimeTag => 'PICK: demo/runtime';

  @override
  String get groupBonusLabel => 'Bonus';

  @override
  String get groupAvgOddsPlayedLabel => 'quota media giocata';

  @override
  String get groupPickLabel => 'pronostico';

  @override
  String get groupOutcomeLabel => 'esito';

  @override
  String get groupOddsLabel => 'quota';

  @override
  String get tabGroup => 'Gruppo';

  @override
  String get tabLive => 'Live';

  @override
  String leaderboardsPlayersCount(Object count) {
    return 'Giocatori: $count';
  }

  @override
  String get serieAStandingsTitle => 'Classifica Serie A';

  @override
  String get serieATeamColumn => 'Squadra';

  @override
  String get serieAPlayedColumn => 'PG';

  @override
  String get serieAWinsColumn => 'V';

  @override
  String get serieADrawsColumn => 'P';

  @override
  String get serieALossesColumn => 'S';

  @override
  String get serieAGoalsAgainstColumn => 'GS';

  @override
  String get serieAGoalDiffColumn => 'DR';

  @override
  String get serieAPointsColumn => 'Pt';

  @override
  String get serieALastFiveColumn => 'Ultime 5';

  @override
  String statsBestDayShort(Object day, Object points) {
    return 'G$day: $points';
  }

  @override
  String statsWorstDayShort(Object day, Object points) {
    return 'G$day: $points';
  }

  @override
  String get profileTrophiesHistory => 'Trofei (storico)';

  @override
  String profileTrophiesDescription(Object displayName) {
    return 'Trofei di $displayName (storico stagione demo).\nRegole: 👑 primo del gruppo • L ultimo • 👁️ 10/10 esatti • 🦉 gufata sulla squadra del cuore.';
  }

  @override
  String predictionsVoidCount(Object count) {
    return 'nulle $count';
  }

  @override
  String get predictionsValidStatus => 'valida';

  @override
  String get predictionsInvalidStatus => 'non valida';

  @override
  String get predictionsPickLockedSnack =>
      'Partita gia iniziata: pick bloccato';

  @override
  String predictionsMissingConfirm(Object missing) {
    return 'Hai lasciato $missing partite senza pronostico.\n\nRegola Cassandra: per ogni partita non giocata verra applicata una penalita pari a -quota piu alta (tra 1/X/2) in fase di calcolo.\n\nVuoi inviare comunque?';
  }

  @override
  String get predictionsSubmitAnyway => 'Invia comunque';

  @override
  String get predictionsVisibilityPublic => 'pubblica';

  @override
  String get predictionsVisibilityPrivate => 'privata';

  @override
  String predictionsSlipSubmitted(Object visibility) {
    return 'Schedina inviata (visibilita: $visibility)';
  }

  @override
  String get predictionsDebugScoreTitle => 'Debug: calcolo punteggio';

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
    return 'totale: $value';
  }

  @override
  String predictionsDebugCorrect(Object value) {
    return 'esatti: $value';
  }

  @override
  String predictionsDebugAvgOdds(Object value) {
    return 'quota media: $value';
  }

  @override
  String predictionsDebugPickRow(Object pick, Object outcome, Object points) {
    return 'pick $pick  •  esito $outcome  •  $points';
  }

  @override
  String get predictionsTagLive => 'LIVE';

  @override
  String get predictionsTagDemo => 'DEMO';

  @override
  String get predictionsTagSaved => 'SALVATI';

  @override
  String get predictionsTagRecoveries => 'RECUPERI';

  @override
  String get predictionsHistoryDemoInfo =>
      'Storico pronostici (DEMO)\nQui mostriamo 16-19 dai mock. La giornata corrente e visibile sopra (LIVE/DEMO).';

  @override
  String get predictionsPicksLocked => 'giocate bloccate';

  @override
  String predictionsEditableUntil(Object time) {
    return 'modificabile fino alle $time';
  }

  @override
  String predictionsScoreSummary(
    Object total,
    Object base,
    Object bonus,
    Object correct,
    Object count,
    Object avgOdds,
  ) {
    return 'punti: $total (base $base • bonus $bonus) • corretti $correct/$count • quota media $avgOdds';
  }

  @override
  String get predictionsDataRealBackendCache => 'dati: reali (cache backend)';

  @override
  String get predictionsRefreshMatches => 'Aggiorna match';

  @override
  String get predictionsUseBackendCache => 'Usa cache backend';

  @override
  String get predictionsForceDemoData => 'Forza dati demo';

  @override
  String get predictionsSampleDataBanner =>
      'Dati di esempio - attendi sincronizzazione backend';

  @override
  String get predictionsPastSegment => 'pronostici passati';

  @override
  String get predictionsUpcomingSegment => 'pronostici futuri';

  @override
  String predictionsDebugShifted(
    Object shifted,
    Object under48,
    Object over48,
  ) {
    return 'debug: shiftate $shifted • <48h $under48 • >48h $over48';
  }

  @override
  String predictionsDebugPlayedVoid(Object played, Object voidCount) {
    return 'debug: giocate $played • nulle $voidCount';
  }

  @override
  String predictionsPicksSummary(Object picked, Object total, Object avgOdds) {
    return 'scelte: $picked/$total  •  quota media: $avgOdds';
  }

  @override
  String predictionsLastSubmit(Object submittedAt, Object visibility) {
    return 'ultimo invio: $submittedAt ($visibility)';
  }

  @override
  String get predictionsSubmitWithoutShowing => 'Invia senza mostrare';

  @override
  String get predictionsSubmitAndShow => 'Invia e mostra';

  @override
  String get commonNoDataAvailable => 'Nessun dato disponibile';

  @override
  String get predictionsBaseLabel => 'Base';

  @override
  String get predictionsDataDemoFixturesNotSaved =>
      'Dati: DEMO (fixture non storicizzate)';

  @override
  String get predictionsDataSaved => 'Dati: salvati';

  @override
  String get predictionsOutcomePending => 'in attesa';

  @override
  String get settingsDiagNoMatchdayDoc =>
      'Nessun documento matchday trovato in Firestore.';

  @override
  String get settingsDiagSourceFirestore =>
      'Sorgente: Firestore /seasons/<season>/matchdays/<day>';

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
  String get settingsDiagErrorTitle => 'Errore';

  @override
  String get commonVersusShort => 'vs';

  @override
  String get predictionsDoubleChance => 'Doppia chance';

  @override
  String get predictionsClearPick => 'Azzera scelta';
}
