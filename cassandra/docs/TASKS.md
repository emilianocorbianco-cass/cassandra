# TASKS — Cassandra

## Next (alta priorità)
1) **Definire e implementare la logica “recuperi”**
   - Non considerare recuperi di matchday vecchie come “giornata corrente”
   - Stabilire criterio di avanzamento alla prossima giornata “completa”
   - Adeguare calcolo bonus: scala con numero partite realmente giocate (quelle non giocate valgono 0 per tutti)

2) Verifiche UI/UX col nuovo criterio
   - Titoli e label giornata coerenti ovunque (Pronostici / Gruppo / Serie A)
   - Lock/unlock coerente con la “giornata corrente” nuova

## Miglioramenti (non bloccanti)
- Colori pulsanti a partita finita (pick corretta/errata) — in attesa palette
- Pulizia `.gitignore` (cache varie Xcode/SwiftPM se ricompaiono)

## Aggiornamento 2026-01-15
Done
- Recuperi v1: lib/domain/matchday/matchday_recovery_rules.dart + test.
- Fix Pronostici live: dedup fixtureId + caching scope safe (no use_build_context_synchronously).
- Predictions: filtro matchday per round + ID coerenti; matchday cursor al posto di hardcode.

Next
- Wiring MatchdayProgress: lock UI, bump cursor su primaryDone, leaderboard/calcolo su finalDone (ricalcolo retroattivo).
- Scoring: integrare bonus scaling su partite giocate + regola validità >=6 nel motore punteggio + test.
- Pulizia: rimuovere/ignorare backup temporanei se riappaiono.
<!-- TASKS_UPDATE:2026-01-16 -->
## TODO (agg. 2026-01-16)

### DONE
- Recuperi: logica giornata effettiva + 48h rule (passati/futuri coerenti con posticipi).
- AppState: cache recenti per matchday + setter bulk.
- UI: “Serie A” → “Live” (tab + header).
- Fix scaling navigazione entrando in `UserHubPage` (via `rootNavigator: true` su push principali).

### NEXT
- [ ] Fix definitivo `UserHubPage` AppBar/safe-area su iOS notch (titolo + back sempre visibili, no overlap).
- [ ] Aggiungere test “a freddo” per recuperi:
  - matchday con recupero a distanza (parziale/pending),
  - determinazione giornata giocabile,
  - coerenza passati vs futuri.
- [ ] Cleanup repo: rimuovere `.bak.*` e artefatti di patch/script non necessari.
- [ ] Audit Navigator pushes/modals: standardizzare `rootNavigator` dove serve per evitare regressioni scaling.

### Rischi
- UI notch/safe-area fragile senza checklist/test dedicati.
- Recuperi: regressioni future senza suite di test specifica.
<!-- /TASKS_UPDATE:2026-01-16 -->
