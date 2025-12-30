# Repository Guidelines

## Project Structure & Module Organization
This is a Flutter app. Core Dart code lives in `lib/` (entry point: `lib/main.dart`). Tests are in `test/` (for example `test/widget_test.dart`). Platform-specific host projects live in `android/`, `ios/`, `macos/`, `windows/`, `linux/`, and `web/`. Web assets such as icons and `index.html` are under `web/`.

## Build, Test, and Development Commands
Run these from the repo root:

```sh
flutter pub get        # Install/update dependencies
flutter run            # Run the app on a connected device or simulator
flutter test           # Execute all tests in test/
flutter analyze        # Static analysis using analysis_options.yaml
```

Common builds (choose the platform you need):

```sh
flutter build apk      # Android APK
flutter build ios      # iOS app (requires Xcode)
flutter build web      # Web build in build/web
```

## Coding Style & Naming Conventions
Use standard Dart/Flutter style: 2-space indentation, trailing commas for formatting, and lower_snake_case for file names (for example `my_widget.dart`). Type names should be UpperCamelCase. Linting follows `package:flutter_lints` via `analysis_options.yaml`; keep the analyzer clean before opening a PR.

## Testing Guidelines
Tests use `flutter_test` and live under `test/`. Name tests by feature and behavior (for example `test/widgets/login_form_test.dart`) and keep widget tests focused. Run `flutter test` before submitting changes; add tests for any new UI or logic.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commit-style prefixes (for example `chore: bootstrap Flutter app`). Follow that pattern for new commits. PRs should include a short summary, testing notes (commands and results), and screenshots or screen recordings for UI changes. Link related issues if applicable.

## Configuration Tips
App metadata (name, version) is in `pubspec.yaml`. Platform-specific configuration and signing live in the respective `android/`, `ios/`, and `macos/` folders; avoid mixing platform changes with unrelated Dart refactors in a single PR.

# Cassandra (Flutter) — AGENTS.md

## Obiettivo
Costruire Cassandra: app Flutter iOS+Android bilingue (IT/EN) per pronostici Serie A con regole di punteggio e bonus.

## Regole non negoziabili
- NON mettere chiavi API nel client Flutter.
- Qualsiasi cosa legata a quote/risultati deve passare da backend/caching (più avanti).
- Ogni stringa visibile all’utente deve essere localizzata IT/EN.
- Prima di ogni commit:
  - flutter analyze
  - flutter test
  - dart format .

## UI base (v1)
- Splash: sfondo #F1E6D1, testo "Cassandra" colore #804046, stile pulito.
- Font: Avenir-like (valutare licenza; evitare font non ridistribuibili su Android).

## Scoring (v1)
Per match:
- Singola (1/X/2):
  - corretta: +quota scelta
  - sbagliata: -quota scelta
- Doppia chance (1X/X2/12):
  - corretta: +quota doppia chance
  - sbagliata: -(quota singola A + quota singola B)
- Non giocata dall’utente: -max(quota 1, X, 2)
- Match non giocata (rinviata/void): 0

Bonus per numero risultati esatti (singola o doppia corretta = 1):
0:-20, 1:-10, 2:-5, 3:-2, 4:-1, 5:0, 6:+1, 7:+2, 8:+5, 9:+10, 10:+20

Totale giornata = somma punti match + bonus.
Spareggio: quota media giocata più alta.

