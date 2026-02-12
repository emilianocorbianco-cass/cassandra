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
      'Nota: per ora molte etichette sono ancora hardcoded. Tradurremo a blocchi.';

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
}
