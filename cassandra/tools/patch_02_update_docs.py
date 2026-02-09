#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-01-15"

def pick_path(candidates: list[str]) -> Path:
    for c in candidates:
        p = ROOT / c
        if p.exists():
            return p
    raise FileNotFoundError(" / ".join(candidates))

def ensure_append(path: Path, marker: str, block: str) -> bool:
    s = path.read_text(encoding="utf-8")
    if marker in s:
        return False
    out = s.rstrip() + "\n\n" + block.rstrip() + "\n"
    path.write_text(out, encoding="utf-8")
    return True

def main() -> None:
    try:
        ps = pick_path(["docs/PROJECT_STATE.md", "PROJECT_STATE.md"])
        tasks = pick_path(["docs/TASKS.md", "TASKS.md"])
    except FileNotFoundError as e:
        print(f"ERROR: file docs non trovati: {e}")
        sys.exit(1)

    marker = f"## Sessione {DATE} — Recuperi/Fixtures"

    project_block = f"""{marker}
- Fix runtime Pronostici: dedup fixtures su fixtureId (non .id) per evitare crash NoSuchMethodError.
- Fix lint: evitare BuildContext dopo await in _tryLoadRealFixtures catturando CassandraScope prima degli await.
- Recuperi: introdotto domain rules (lockAt/primaryDone/finalDone) + regola 48h (void) + validità matchday >=6 + bonus scaling (correct->/10).
- Predictions: filtro matchday su round + ID coerenti fixtureId.toString() tra matches/outcomes; matchday corrente da cassandraMatchdayCursor.
"""

    tasks_block = f"""## Aggiornamento {DATE}
Done
- Recuperi v1: lib/domain/matchday/matchday_recovery_rules.dart + test.
- Fix Pronostici live: dedup fixtureId + caching scope safe (no use_build_context_synchronously).
- Predictions: filtro matchday per round + ID coerenti; matchday cursor al posto di hardcode.

Next
- Wiring MatchdayProgress: lock UI, bump cursor su primaryDone, leaderboard/calcolo su finalDone (ricalcolo retroattivo).
- Scoring: integrare bonus scaling su partite giocate + regola validità >=6 nel motore punteggio + test.
- Pulizia: rimuovere/ignorare backup temporanei se riappaiono.
"""

    changed_ps = ensure_append(ps, marker, project_block)
    changed_tasks = ensure_append(tasks, f"## Aggiornamento {DATE}", tasks_block)

    if not changed_ps:
        print("OK: PROJECT_STATE già aggiornato (marker presente).")

    else:
        print(f"OK: aggiornato {ps}")

    if not changed_tasks:
        print("OK: TASKS già aggiornato (marker presente).")

    else:
        print(f"OK: aggiornato {tasks}")

if __name__ == "__main__":
    main()
