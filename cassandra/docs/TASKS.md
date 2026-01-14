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
