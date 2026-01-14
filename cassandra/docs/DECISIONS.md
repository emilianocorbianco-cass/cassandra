# DECISIONS / ADR — Cassandra

## ADR-001 — Flutter cross-platform
- Data: 2026-01-xx
- Decisione: Flutter per iOS+Android con una sola codebase.
- Motivo: velocità sviluppo e coerenza UI.

## ADR-002 — Scoring v1 (somma quote + regola doppie)
- Decisione: scoring come somma algebrica con doppia sbagliata = somma delle due singole corrispondenti.
- Bonus: tabella 0..10 (0:-20 ... 10:+20).
- Spareggio: quota media giocata più alta.

## ADR-003 — Concetto “Giornata” coerente
- Decisione: ogni pagina deve mostrare match appartenenti a quella matchday.
- Motivo: evitare anticipo/posticipo di giornate diverse nello stesso elenco.

## ADR-004 — Lock pronostici
- Decisione: lock a 30 minuti prima del primo kickoff della matchday.
- Sblocco: dopo conclusione ultima partita della matchday (tutti outcomes finali).

## ADR-005 — UI feedback post-partita
- Decisione: rimandato (non blocca MVP).
- Motivo: serve definire palette/UX prima di fissare colori.

