#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]

def fail(msg: str) -> None:
    print(f"ERROR: {msg}")
    sys.exit(1)

def main() -> None:
    pubspec = ROOT / "pubspec.yaml"
    if not pubspec.exists():
        fail(f"pubspec.yaml non trovato in {ROOT}. Esegui da ~/Development/Cassandra/cassandra")

    p = ROOT / "lib/features/predictions/predictions_page.dart"
    if not p.exists():
        fail(f"File non trovato: {p}")

    backup_dir = ROOT / "_backup"
    backup_dir.mkdir(exist_ok=True)
    shutil.copy2(p, backup_dir / "predictions_page.dart.before_patch_01.bak")

    s = p.read_text(encoding="utf-8")
    orig = s

    # 1) Fix crash: ApiFootballFixture non ha .id -> usa fixtureId
    s = s.replace("seen.add((f as dynamic).id)", "seen.add(f.fixtureId)")

    # 2) Fix lint: no BuildContext across async gaps -> cattura scope prima degli await
    scope_line = "      final scope = CassandraScope.of(context);"
    if scope_line not in s:
        marker = "      final service = ApiFootballService(client);"
        if marker in s:
            s = s.replace(marker, marker + "\n" + scope_line, 1)

    # 3) Usa scope (già catturato) invece di CassandraScope.of(context) dopo await
    s = s.replace("CassandraScope.of(context).setCachedPredictionMatches(", "scope.setCachedPredictionMatches(")
    s = s.replace("CassandraScope.of(context).setCachedPredictionOutcomesByMatchId(", "scope.setCachedPredictionOutcomesByMatchId(")

    if s == orig:
        print("OK: patch_01 già applicata (nessuna modifica).")

    else:
        p.write_text(s, encoding="utf-8")
        print("OK: patch_01 applicata -> predictions_page.dart")

if __name__ == "__main__":
    main()
