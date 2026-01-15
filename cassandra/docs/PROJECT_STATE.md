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
