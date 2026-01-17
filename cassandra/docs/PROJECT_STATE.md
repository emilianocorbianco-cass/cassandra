# PROJECT_STATE — Cassandra

## Obiettivo
App Flutter (iOS/Android) per pronostici Serie A con quote e risultati (API), calcolo punteggi/bonus e leaderboard di gruppo.

## Stato attuale (ultimo checkpoint)
- Build/Run/Analyze OK.
- Lock pronostici: modificabili fino a **30 minuti prima della prima partita** della “giornata selezionata”; tornano attivi dopo l’ultima partita della finestra corrente.
- Integrazione API-Football:
  - fetch fixtures Serie A “next” (con count) e parsing modelli
  - pagina diagnostica API (settings)
- Cache/snapshot locali (SharedPreferences):
  - salvataggio matches per matchday (snapshot)
  - salvataggio picks per matchday
  - salvataggio outcomes per matchday
- Selezione “giornata” in Predictions:
  - euristica per scegliere il **round** più rappresentato tra i fixtures ottenuti
  - riduzione recuperi “sparsi” tramite cluster temporale (per evitare mischi tra giornate)

## Problema aperto (recuperi/posticipi)
- La Serie A può avere recuperi di giornate vecchie inseriti nel feed “next”.
- Requisito: **non vogliamo tornare a una matchday vecchia** per completarla quando il recupero viene giocato.
- Nuova regola richiesta: partite non giocate valgono 0 per tutti e i bonus si ridimensionano sul numero di partite effettivamente giocate; i recuperi successivi NON devono essere considerati e l’app deve passare alla giornata completa successiva.

## File toccati di recente
- cassandra/lib/features/predictions/predictions_page.dart
- cassandra/lib/app/state/app_state.dart
- cassandra/lib/features/group/group_page.dart
- cassandra/lib/features/profile/user_hub_page.dart
- cassandra/lib/services/api_football/api_football_service.dart

## Note repo
- Il progetto Flutter sta sotto la cartella `cassandra/`
- Comandi da lanciare da `cassandra/`:
  - `flutter analyze`
  - `flutter test`
  - `flutter run`

## Sessione 2026-01-15 — Recuperi/Fixtures
- Fix runtime Pronostici: dedup fixtures su fixtureId (non .id) per evitare crash NoSuchMethodError.
- Fix lint: evitare BuildContext dopo await in _tryLoadRealFixtures catturando CassandraScope prima degli await.
- Recuperi: introdotto domain rules (lockAt/primaryDone/finalDone) + regola 48h (void) + validità matchday >=6 + bonus scaling (correct->/10).
- Predictions: filtro matchday su round + ID coerenti fixtureId.toString() tra matches/outcomes; matchday corrente da cassandraMatchdayCursor.
<!-- SESSION_LOG:2026-01-16 -->
## Sessione 2026-01-16 — Recuperi + UI

### Cambiamenti
- Recuperi: “giornata effettiva” + regola 48h → i futuri mostrano la prossima giornata giocabile; i recuperi restano nei passati con esiti `pending`.
- AppState: cache recenti per matchday (`recentMatchesByMatchday`, `recentOutcomesByMatchday`) + setter bulk.
- UI: tab “Serie A” rinominato in “Live” (tab + titolo pagina).
- Navigazione verso UserHub: introdotto `rootNavigator: true` in vari push per eliminare scaling.
- UI: tentativi di allineamento titoli/header (Pronostici/UserHub) e safe-area notch; rimane un problema visivo in UserHub su iOS.

### Decisioni (ADR)
- ADR-RECUPERI-001: corrente = prossima giocabile; recuperi non spostano automaticamente la giornata nei futuri (48h rule).
- ADR-STATE-RECENT-001: storicizzazione recent matchdays in AppState via mappe + bulk setter.

### Problemi aperti
- iOS notch: titolo/back e header di `UserHubPage` ancora tagliati/sovrapposti (safe-area/AppBar).
- Residui `.bak.*` generati durante le patch: da ripulire prima del merge/release.
<!-- /SESSION_LOG:2026-01-16 -->
<!-- SESSION_LOG:2026-01-17 -->
## Sessione 2026-01-17 — Theme/Color tokens

### Cambiamenti
- UI: fix scaling/overlap in UserHub riducendo bottoni dev (Reset/Demo).
- UI: bottom nav bar: bg `0xFF031926`, icone+testi `0xFFF6F4EF`.
- UI: label tab “Classifiche” accorciata a “Classifica”.
- Theme: token in `CassandraColors`:
  - `bg = 0xFFF2EEE8` (sfondo app)
  - `cardBg = 0xFFF5F5F5` + `ThemeData.cardTheme` (CardThemeData) per neutralizzare il “rosa” sulle Card
- Lint: `MaterialStateProperty` → `WidgetStateProperty` (deprecation) in home_shell.

### Decisioni (ADR)
- ADR-THEME-001: colori gestiti via token (`CassandraColors`) + `ThemeData`; evitare palette/debug runtime e patch per-singola pagina.

### Problemi aperti
- iOS notch: `UserHubPage` AppBar/safe-area ancora da stabilizzare.
- Copertura token incompleta: restano colori hardcoded (Container/BoxDecoration) da migrare.
<!-- /SESSION_LOG:2026-01-17 -->
