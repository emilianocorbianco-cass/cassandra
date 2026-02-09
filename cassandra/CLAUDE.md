# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build, Test, and Dev Commands

```sh
flutter pub get              # Install/update dependencies
flutter run                  # Run on connected device/simulator
flutter test                 # Run all tests
flutter test test/scoring_engine_test.dart   # Run a single test file
flutter analyze              # Static analysis (must pass before commits)
dart format .                # Format all Dart files
flutter build apk            # Android build
flutter build ios            # iOS build (requires Xcode)
```

Pre-commit checklist: `flutter analyze`, `flutter test`, `dart format .`

## Architecture

**Cassandra** is a bilingual (IT/EN) Flutter app for Serie A football prediction scoring. It uses no external state management, DI, or routing frameworks — everything is built on Flutter primitives.

### State Management: InheritedNotifier + ChangeNotifier

- **`AppState`** (`lib/app/state/app_state.dart`): Single `ChangeNotifier` holding all global state — user profile, predictions, outcomes, matchday progress, cached fixtures, locale. Persists to `SharedPreferences` with versioned keys (v1 suffix).
- **`CassandraScope`** (`lib/app/state/cassandra_scope.dart`): `InheritedNotifier<AppState>` wrapping the app. Access state anywhere via `CassandraScope.of(context)`.
- No Provider, BLoC, or Riverpod. State is centralized, not distributed across features.

### Navigation

Tab-based via `HomeShell` (`lib/app/navigation/home_shell.dart`) using `IndexedStack` with 6 tabs: Predictions, Group, Leaderboards, Serie A Live, Stats, Settings. No named routes or router package.

### Feature Modules (`lib/features/`)

Each feature is a self-contained folder with its own pages, models, widgets, adapters, and engines:

- **predictions/** — Match picking UI, prediction history, adapters from API fixtures to `PredictionMatch`
- **scoring/** — `CassandraScoringEngine` with single/double-chance scoring rules and bonus table
- **leaderboards/** — Season standings and matchday rankings
- **group/** — Group predictions and leaderboard views
- **badges/** — `CassandraBadgeEngine` (crown, loser, eyes, owl badges), `SeasonBadgeEngine`, `TrophyEngine`
- **stats/** — `StatsEngine` and player season statistics
- **serie_a/** — Live Serie A fixtures (read-only display)
- **profile/** — User hub with stats, picks, trophies views
- **settings/** — App settings and API-Football diagnostics page
- **dev/** — Debug page for simulating postponed/voided matches

Features communicate only through global `AppState` — no direct inter-feature imports.

### Domain Layer (`lib/domain/`)

Minimal, rule-focused. Key file: `matchday/matchday_recovery_rules.dart` containing pure functions for matchday lifecycle:
- `clusterByKickoff()` — groups matches by kickoff time
- `resolveFixture()` — determines fixture status (final/pending/voided) with 48-hour postponement window
- `computeMatchdayProgress()` — lock times, played/void counts, primary/final done states

### Service Layer (`lib/services/`)

- **`ApiFootballClient`** (`api_football/api_football_client.dart`): HTTP wrapper handling auth headers for direct API-Sports or RapidAPI proxy mode.
- **`ApiFootballService`** (`api_football/api_football_service.dart`): High-level methods for fetching Serie A fixtures by round, upcoming, or completed matches. Handles season calculation and league ID resolution.
- Services are instantiated directly where needed (no DI container).

### Configuration

- **`.env`** file loaded via `flutter_dotenv` — contains `API_FOOTBALL_KEY`, `API_FOOTBALL_USE_RAPIDAPI`, `API_FOOTBALL_BASE_URL`. See `.env.example` for template.
- **`Env`** class (`lib/app/config/env.dart`): Safe reads that return null if dotenv not loaded.

### Adapters

Data transformation between API responses and domain models follows an adapter pattern:
- `ApiFootballFixtureAdapter` — API fixtures → `PredictionMatch`
- `ApiFootballOutcomeAdapter` — API results → `MatchOutcome`

## Scoring Rules

Per match: single pick (1/X/2) scores +/- the chosen odds. Double chance (1X/X2/12) scores + double-chance odds if correct, or minus both component odds if wrong. Unplayed by user: -max(all three odds). Voided match: 0.

Bonus table by correct count (0–10): -20, -10, -5, -2, -1, 0, +1, +2, +5, +10, +20.

## Non-Negotiable Rules

- No API keys in client Flutter code — use `.env` and backend/caching.
- All user-facing strings must be localized (IT/EN).
- Conventional Commit prefixes for commit messages (e.g., `feat:`, `fix:`, `chore:`).
- Keep platform-specific changes in separate PRs from Dart refactors.

## Coding Style

- 2-space indentation, trailing commas for formatting
- `lower_snake_case` for file names, `UpperCamelCase` for types
- Linting via `package:flutter_lints` — keep analyzer clean
- `_backup/` directory is excluded from analysis
