# Tournament Architecture — Sessione 1

## Obiettivo

Estendere Cassandra dal solo formato campionato (Serie A) a tornei misti
(Mondiali, Champions League) mantenendo un unico codebase e un unico progetto
Firebase, con la logica tornei nascosta dietro feature flag finché non è pronta.

---

## Decisioni di Sessione 1

| # | Decisione |
|---|-----------|
| D1 | `MatchOutcome` viene esteso con campo `decidedIn: regulation \| extraTime \| penalties` — Serie A lo ignora, knockout lo usa per calcolare il punteggio. |
| D2 | Meta-pronostici in collezione Firestore separata `meta_predictions/{uid}_{tournamentId}` — non mescolati ai pick ordinari. |
| D3 | Pick tardivo ai tornei = **0 punti** (non -2 come Serie A). La policy è parte di `ScoringRules`, non hardcoded. |
| D4 | Feature flag **per torneo** (`enable_world_cup_2026`, `enable_champions_2025_26`, ecc.) — non un unico flag globale. |

---

## Le sei astrazioni

Serie A e Mondiali/Champions non sono varianti dello stesso gioco: condividono
solo utenti, gruppi, auth e persistenza. Tutto il resto — tipi di pick, scoring,
lock semantics, standings — è specifico del formato. Invece di una super-interfaccia
monolitica, si usano **sei astrazioni piccole e ortogonali**, ciascuna con una
implementazione per formato. `TournamentMode` aggrega queste astrazioni (vedi §4).

### 1. `PickStrategy<P extends Enum>`

Definisce quali pronostici si possono fare su una partita e come si confrontano
con l'esito.

```
availableOptionsFor(Match match, RoundPhase phase) → List<P>
isCorrect(P pick, MatchOutcome outcome) → bool
```

Implementazioni:
- `SerieAPickStrategy` — 6 valori (1, X, 2, 1X, X2, 12)
- `WorldCupGroupStrategy` — 3 valori (1, X, 2)
- `WorldCupKnockoutStrategy` — 8 valori (1/X/2 al 90', 1/X/2 al 120', 1/2 ai rigori); `availableOptionsFor` varia per fase

### 2. `ScoringRules<P>`

Calcola punti per singola partita e per un round completo.

```
scoreMatch(match, pick, outcome, submittedAt?) → MatchScore
scoreRound(List<MatchScore>, RoundContext) → RoundScore
```

Policy late submission: parte di `scoreMatch` (0 o penalità, a seconda delle regole).

Implementazioni:
- `SerieAScoringRules` — logica attuale di `CassandraScoringEngine` (odds ± bonus SQV + #corretti)
- `WorldCupGroupScoringRules` — +3/0 fisso, nessun bonus di giornata, late = 0
- `WorldCupKnockoutScoringRules` — +3/+6/+10 in base a `outcome.decidedIn`, late = 0

### 3. `FixtureSource`

Astrae la provenienza di partite e risultati.

```
watchRound(RoundId) → Stream<List<Match>>
outcomeOf(MatchId) → Future<MatchOutcome>
```

Implementazioni:
- `ApiFootballFixtureSource` — Serie A (esistente, da rinominare/astrarre)
- per tornei: stesso client `ApiFootballClient` con `leagueId` diverso,
  ma adapter distinto perché i Mondiali espongono supplementari/rigori in campi separati

### 4. `TournamentStandings` (sealed)

```
sealed class TournamentStandings {}

class TableStandings          // Serie A; singola tabella
class GroupStageStandings     // Mondiali gironi: Map<GroupId, TableStandings> (12 tabelle)
class SwissLeagueStandings    // Champions fase unica: tabella da 36 squadre
class BracketStandings        // Knockout: albero
```

La UI fa pattern matching e mostra il widget appropriato.
Il provider che le calcola è specifico per torneo — per Serie A è già
`streamSeasonStandings()` da Firestore.

### 5. `MetaPredictionSpec`

Pronostici "ex ante" sulla struttura del torneo. Assente in Serie A.

```
slotsFor(TournamentStage) → List<MetaPredictionSlot>
score(UserMetaPrediction, ActualResult) → int
```

Implementazioni Mondiali:
- `GroupOrderMeta` — 4 posizioni × 12 gironi; +1 per posizione corretta (max 48 pt)
- `Top4Meta` — pronostico prime 4 squadre; 2/5/10/20 pt in base a quante azzeccate

Champions: `FinalistsMeta`, `WinnerMeta` (da definire in Sessione 3).

### 6. `RoundLifecycle`

Definisce semantica di lock/unlock per un round. Sostituisce la logica
hardcoded di `matchday_recovery_rules.dart`.

```
lockTimeFor(List<Match> inRound)   → DateTime   // quando smettono di accettarsi pick
unlockTimeFor(List<Match> inRound) → DateTime   // quando il round successivo diventa disponibile
```

Implementazioni:
- `SerieARoundLifecycle` — lock 30 min prima del primo kickoff (ADR-004 esistente)
- `WorldCupGroupRoundLifecycle` — stesso comportamento (giornata = tutti i gironi simultanei)
- `WorldCupKnockoutBlockLifecycle` — lock **5 min** prima del primo match del blocco;
  sblocco round successivo **30 min dopo** l'ultima partita del blocco

---

## TournamentMode — l'aggregatore

`TournamentMode` non è un'interfaccia funzionale; è una **configurazione** che
lega insieme le sei astrazioni per un torneo specifico.

```
class TournamentMode {
  TournamentId  id               // 'serie-a-2024-25', 'world-cup-2026'
  TournamentKind kind            // league | knockout | hybrid
  List<TournamentPhase> phases   // una per Serie A, due per Mondiali/Champions
  String featureFlagKey          // 'enable_world_cup_2026'
}

class TournamentPhase {
  String label                   // 'Gironi', 'Knockout', ecc.
  PickStrategy   pickStrategy
  ScoringRules   scoringRules
  FixtureSource  fixtureSource
  RoundLifecycle roundLifecycle
  MetaPredictionSpec? metaPrediction  // null se non applicabile
}
```

Le standings vivono fuori da `TournamentPhase` perché spesso aggregano
i risultati di più fasi (es. il bracket Champions si costruisce con chi
è passato dalla fase league).

---

## I tre tornei come configurazioni

### Serie A
```
TournamentMode(
  id: 'serie-a-2024-25',
  kind: league,
  phases: [
    TournamentPhase(
      label: 'Campionato',
      pickStrategy:  SerieAPickStrategy,
      scoringRules:  SerieAScoringRules,
      fixtureSource: ApiFootballFixtureSource(leagueId: 135),
      roundLifecycle: SerieARoundLifecycle,
      metaPrediction: null,
    )
  ],
  featureFlagKey: 'enable_serie_a',   // sempre true, è il default
)
```

### Mondiali 2026
```
TournamentMode(
  id: 'world-cup-2026',
  kind: hybrid,
  phases: [
    TournamentPhase(
      label: 'Gironi',
      pickStrategy:   WorldCupGroupStrategy,
      scoringRules:   WorldCupGroupScoringRules,
      fixtureSource:  ApiFootballFixtureSource(leagueId: 1 /*FIFA WC*/),
      roundLifecycle: WorldCupGroupRoundLifecycle,
      metaPrediction: GroupOrderMeta(groups: 12, positionsPerGroup: 4),
    ),
    TournamentPhase(
      label: 'Eliminazione',
      pickStrategy:   WorldCupKnockoutStrategy,
      scoringRules:   WorldCupKnockoutScoringRules,
      fixtureSource:  stesso source, filtrato per round knockout,
      roundLifecycle: WorldCupKnockoutBlockLifecycle,
      metaPrediction: Top4Meta,
    ),
  ],
  featureFlagKey: 'enable_world_cup_2026',
)
```

### Champions League (Swiss-model + KO)
```
TournamentMode(
  id: 'champions-2025-26',
  kind: hybrid,
  phases: [
    TournamentPhase(
      label: 'Fase Campionato',  // 36 squadre, 8 giornate, singola tabella
      pickStrategy:   WorldCupGroupStrategy,       // 1/X/2 secco — da confermare
      scoringRules:   WorldCupGroupScoringRules,   // stesso schema? da definire in S3
      fixtureSource:  ApiFootballFixtureSource(leagueId: 2 /*UEFA CL*/),
      roundLifecycle: SerieARoundLifecycle,         // lock per giornata
      metaPrediction: null,  // o TopNQualifiedMeta — da decidere
    ),
    TournamentPhase(
      label: 'Playoff + Eliminazione',
      pickStrategy:   WorldCupKnockoutStrategy,
      scoringRules:   WorldCupKnockoutScoringRules,
      fixtureSource:  stesso source, filtrato per round KO,
      roundLifecycle: WorldCupKnockoutBlockLifecycle,
      metaPrediction: FinalistsMeta,   // da definire in S3
    ),
  ],
  featureFlagKey: 'enable_champions_2025_26',
)
```

---

## Mappatura: codice esistente → astrazione

| File attuale | Cosa diventa |
|---|---|
| `scoring_engine.dart` | `SerieAScoringRules` (stessa logica, wrappata nell'interfaccia) |
| `PickOption` (enum 6 valori) | rimane — è il tipo `P` di `SerieAPickStrategy` |
| `MatchOutcome` (enum) | rimane + campo `decidedIn` opzionale |
| `matchday_recovery_rules.dart` | funzioni pure estratte in `SerieARoundLifecycle` |
| `ApiFootballService` | base per `ApiFootballFixtureSource` (adattatore) |
| `ApiFootballFixtureAdapter` | rimane specifico Serie A; nuovi adapter per WC/CL |
| `streamSeasonStandings()` | implementazione `TableStandings` per Serie A |
| `MatchdayDocument` | rimane — modella un "round" in ogni fase |
| `GroupDocument.competitions` | già pronto; aggiungere `'world-cup-2026'` ecc. |
| `AppState` / `MatchdayState` | aggiungere `activeTournament: TournamentMode` |
| `CassandraScope` | espone `activeTournament` ai widget |
| `HomeShell` (tab navigation) | aggiunge `TournamentSelector` widget dietro feature flag |
| `picks/{uid}_{day}_{matchId}` | non cambia struttura; `seasonKey` diventa `tournamentId` |

---

## Schema Firestore proposto

```
// Collezioni esistenti — invariate
users/{uid}
groups/{groupId}
  members/{uid}
picks/{uid}_{roundKey}_{matchId}        // seasonKey → può essere 'world-cup-2026_r1' ecc.

// Esistente — da estendere con tournament_type
seasons/{tournamentId}                  // era 'serie-a-2024-25', ora qualsiasi torneo
  matchdays/{roundNumber}
    matches[], outcomesByMatchId, lockTime, finalized
  standings/current                     // struttura varia per tipo

// Nuovo
meta_predictions/{uid}_{tournamentId}
  groupOrderPicks: { groupId: [team1, team2, team3, team4] }   // Mondiali gironi
  top4Picks: [team1, team2, team3, team4]                       // Mondiali knockout
  scoreCache: { groupOrder: int, top4: int }
```

Nessuna migrazione delle collezioni esistenti Serie A — si affiancano.
`GroupDocument.competitions` già supporta `['serie-a', 'world-cup-2026']`.

---

## Feature flag policy

- Provider: Firebase Remote Config (già usato) oppure `Env` locale per sviluppo.
- Chiavi: una per torneo — `enable_world_cup_2026`, `enable_champions_2025_26`.
- Accesso: classe `FeatureFlags` in `lib/core/config/feature_flags.dart` (da creare).
- Default: tutti `false` in produzione; `true` solo in ambienti dev/staging.
- Granularità: il flag abilita l'intera `TournamentMode`; non serve granularità per fase.
- Serie A: non ha flag (sempre attivo, è il default).

---

## Punti aperti per Sessione 2

1. **`MatchOutcome.decidedIn`**: campo inline nell'enum oppure sub-oggetto separato?
   Scegliere prima del refactoring per non rompere i serializer Firestore.
2. **Scoring Champions fase league**: stesso schema 1/X/2 + punteggio fisso dei Mondiali,
   o mantenere le odds come Serie A? Da decidere prima di implementare.
3. **Meta-pronostici Champions**: cosa pronosticare sulla fase league (top 8 diretti?
   prime 24 ai playoff?)? Rimandato a Sessione 3 dopo aver capito meglio il formato.
4. **`TournamentSelector` UI**: tab aggiuntiva in `HomeShell` o drawer? Da allineare
   con le schermate Figma prima di implementare.
5. **Spareggio classifica Mondiali**: i Mondiali usano la quota media come spareggio
   (come Serie A) o un criterio diverso? Da verificare con le regole.

---

## Dipendenze Sessione 2 (refactoring a rischio zero su main)

Sessione 2 non richiede feature branch. Operazioni sicure su `main`:

1. Riorganizzare `/lib` in `features/league | tournament | shared | core/config`
2. Spostare codice Serie A in `features/league` senza modificare logica
3. Creare `lib/core/config/feature_flags.dart` (shell vuota)
4. Estendere `MatchOutcome` con `decidedIn` (compatibile, campo opzionale)
5. Astrarre `CassandraScoringEngine` dietro `ScoringRules` (rinominare, non riscrivere)
6. Aggiungere `activeTournament` a `AppState` (default Serie A, nessun cambio comportamento)

Tutto questo è reversibile e utile indipendentemente dai tornei.
