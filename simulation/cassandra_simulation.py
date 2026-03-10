#!/usr/bin/env python3
"""
Cassandra Game Simulation - 20 Giornate Serie A
8 giocatori con personalità realistiche, quote realistiche, senza bonus/malus.

Regole scoring Cassandra:
- Singola corretta (1/X/2): +quota
- Singola sbagliata: -quota giocata
- Doppia chance corretta (1X/X2/12): +quota doppia chance
- Doppia chance sbagliata: -(somma delle due quote singole componenti)
- Non giocata: -max(quota 1, X, 2)
- Senza bonus/malus di giornata
"""

import random
import json

random.seed(42)  # Per riproducibilità

# ============================================================
# SERIE A 2025-26 - Squadre con forza relativa (1-100)
# ============================================================
TEAMS = {
    "Inter": 92, "Napoli": 89, "Juventus": 87, "Milan": 85,
    "Atalanta": 86, "Lazio": 80, "Roma": 78, "Fiorentina": 76,
    "Bologna": 74, "Torino": 72, "Udinese": 68, "Genoa": 65,
    "Cagliari": 63, "Empoli": 62, "Parma": 61, "Verona": 60,
    "Como": 59, "Lecce": 58, "Venezia": 56, "Monza": 57,
}

TEAM_NAMES = list(TEAMS.keys())

# ============================================================
# Generazione calendario realistico (round-robin)
# ============================================================
def generate_calendar():
    """Genera 20 giornate di calendario con 10 partite ciascuna."""
    teams = TEAM_NAMES[:]
    n = len(teams)
    calendar = []

    # Round-robin standard
    fixed = teams[0]
    rotating = teams[1:]

    for round_num in range(n - 1):
        matches = []
        if round_num % 2 == 0:
            matches.append((fixed, rotating[0]))
        else:
            matches.append((rotating[0], fixed))

        for i in range(1, n // 2):
            home = rotating[i]
            away = rotating[n - 2 - i]
            if (round_num + i) % 2 == 0:
                matches.append((home, away))
            else:
                matches.append((away, home))

        calendar.append(matches)
        rotating = rotating[1:] + rotating[:1]

    if len(calendar) < 20:
        extra = [(away, home) for home, away in calendar[0]]
        calendar.append(extra)

    return calendar[:20]


# ============================================================
# Generazione quote realistiche basate sulla forza delle squadre
# ============================================================
def generate_odds(home_team, away_team):
    """Genera quote realistiche per una partita."""
    home_str = TEAMS[home_team]
    away_str = TEAMS[away_team]

    home_advantage = 5
    diff = (home_str + home_advantage) - away_str

    if diff > 20:
        p_home, p_draw, p_away = 0.60, 0.22, 0.18
    elif diff > 12:
        p_home, p_draw, p_away = 0.52, 0.25, 0.23
    elif diff > 5:
        p_home, p_draw, p_away = 0.45, 0.27, 0.28
    elif diff > -5:
        p_home, p_draw, p_away = 0.38, 0.30, 0.32
    elif diff > -12:
        p_home, p_draw, p_away = 0.30, 0.28, 0.42
    else:
        p_home, p_draw, p_away = 0.22, 0.26, 0.52

    noise = lambda: random.uniform(-0.03, 0.03)
    p_home = max(0.08, p_home + noise())
    p_draw = max(0.08, p_draw + noise())
    p_away = max(0.08, p_away + noise())

    total = p_home + p_draw + p_away
    p_home /= total
    p_draw /= total
    p_away /= total

    margin = 1.08

    q_home = round(margin / p_home, 2)
    q_draw = round(margin / p_draw, 2)
    q_away = round(margin / p_away, 2)

    q_1x = round(margin / (p_home + p_draw), 2)
    q_x2 = round(margin / (p_draw + p_away), 2)
    q_12 = round(margin / (p_home + p_away), 2)

    return {
        "home": q_home, "draw": q_draw, "away": q_away,
        "1x": q_1x, "x2": q_x2, "12": q_12,
        "p_home": p_home, "p_draw": p_draw, "p_away": p_away
    }


def simulate_result(odds):
    """Simula il risultato reale di una partita."""
    r = random.random()
    if r < odds["p_home"]:
        return "1"
    elif r < odds["p_home"] + odds["p_draw"]:
        return "X"
    else:
        return "2"


# ============================================================
# HELPER: tracking forma squadre e strisce di sconfitte
# ============================================================
def get_team_form(result_history, team, last_n=5):
    """Ultimi N risultati di una squadra: lista di 'W'/'D'/'L'."""
    results = []
    for matchday in reversed(result_history):
        for home, away, result in matchday:
            if home == team:
                results.append("W" if result == "1" else ("D" if result == "X" else "L"))
            elif away == team:
                results.append("W" if result == "2" else ("D" if result == "X" else "L"))
            if len(results) >= last_n:
                return results
    return results


def form_score(result_history, team, last_n=5):
    """Punteggio forma: W=3, D=1, L=0. Max = last_n * 3."""
    form = get_team_form(result_history, team, last_n)
    return sum(3 if r == "W" else (1 if r == "D" else 0) for r in form)


def get_team_loss_streak(result_history, team):
    """Conta le sconfitte consecutive di una squadra."""
    streak = 0
    for matchday in reversed(result_history):
        for home, away, result in matchday:
            if home == team:
                if result == "2":
                    streak += 1
                else:
                    return streak
            elif away == team:
                if result == "1":
                    streak += 1
                else:
                    return streak
    return streak


# ============================================================
# DEFINIZIONE DEGLI 8 GIOCATORI
# ============================================================

def pick_marco(home, away, odds, result_history, actual_result=None):
    """Marco l'Istintivo - sceglie con criterio e non cambia mai idea.
    Ha buon istinto calcistico, gioca la favorita con decisione.
    Usa le doppie chance solo quando il match è molto equilibrato."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if diff > 18:
        return "1"
    elif diff < -18:
        return "2"
    elif diff > 10:
        return "1"
    elif diff < -10:
        return "2"
    elif diff > 3:
        return "1" if r < 0.72 else "1X"
    elif diff < -3:
        return "2" if r < 0.72 else "X2"
    else:
        # Match equilibrato: segue l'istinto, leggero favore casa
        if r < 0.40:
            return "1"
        elif r < 0.68:
            return "X"
        else:
            return "2"


def pick_andrea(home, away, odds, result_history, actual_result=None):
    """Andrea l'Indeciso - si secondguessa sempre, cambia idea cento volte.
    Sbaglia spesso le scommesse facili (si convince che 'è troppo ovvio')
    ma azzecca quelle complesse (l'overthinking a volte funziona)."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if abs(diff) > 15:
        # Match "facile" - il second-guessing lo porta fuori strada
        if diff > 0:
            if r < 0.30:
                return "1"       # A volte tiene la scelta ovvia
            elif r < 0.55:
                return "X"       # "E se pareggiassero?"
            elif r < 0.78:
                return "1X"      # Indeciso, copre
            else:
                return "2"       # "Tutti dicono 1, ma..."
        else:
            if r < 0.30:
                return "2"
            elif r < 0.55:
                return "X"
            elif r < 0.78:
                return "X2"
            else:
                return "1"
    elif abs(diff) > 8:
        # Match medio - il dubbio lo porta a cambiare più volte
        if diff > 0:
            if r < 0.38:
                return "X"       # L'overthinking lo porta al pareggio
            elif r < 0.62:
                return "1"
            elif r < 0.82:
                return "1X"
            else:
                return "2"
        else:
            if r < 0.38:
                return "X"
            elif r < 0.62:
                return "2"
            elif r < 0.82:
                return "X2"
            else:
                return "1"
    else:
        # Match equilibrato - paradossalmente, l'overthinking aiuta
        # Analizza troppo e a volte coglie sfumature che altri ignorano
        if r < 0.38:
            return "X"       # Sente i pareggi nei match equilibrati
        elif r < 0.58:
            return "1" if diff >= 0 else "2"
        elif r < 0.78:
            return "2" if diff >= 0 else "1"
        else:
            return "12"


def pick_paolo(home, away, odds, result_history, actual_result=None):
    """Paolo il Meticoloso - analizza la forma recente delle squadre.
    Preciso e metodico. Studia le ultime 5 partite e punta sulla squadra
    in miglior forma. Usa doppie chance quando i dati non sono chiari."""
    base_diff = TEAMS[home] - TEAMS[away]

    # Aggiusta per la forma recente (conta molto per Paolo)
    if result_history:
        home_form = form_score(result_history, home, 5)
        away_form = form_score(result_history, away, 5)
        form_diff = (home_form - away_form) * 1.8
        adjusted_diff = base_diff + form_diff
    else:
        # Prima giornata: si basa solo sulla forza base
        adjusted_diff = base_diff

    # Leggero fattore casa nel suo modello
    adjusted_diff += 3
    r = random.random()

    if adjusted_diff > 18:
        return "1"
    elif adjusted_diff < -18:
        return "2"
    elif adjusted_diff > 10:
        return "1" if r < 0.82 else "1X"
    elif adjusted_diff < -10:
        return "2" if r < 0.82 else "X2"
    elif adjusted_diff > 4:
        return "1" if r < 0.65 else "1X"
    elif adjusted_diff < -4:
        return "2" if r < 0.65 else "X2"
    else:
        # Dati non chiari: cautela
        if r < 0.32:
            return "X"
        elif r < 0.55:
            return "1X" if adjusted_diff >= 0 else "X2"
        elif r < 0.75:
            return "1" if adjusted_diff >= 0 else "2"
        else:
            return "12"


def pick_alessandro(home, away, odds, result_history, actual_result=None):
    """Alessandro il Cacciatore di Upset - cerca i risultati probabili ma
    ogni tanto tira fuori il colpo dal cilindro, scommettendo sulle squadre
    con una lunga striscia di sconfitte (crede nel rimbalzo)."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    # Controlla le strisce di sconfitte
    home_streak = get_team_loss_streak(result_history, home) if result_history else 0
    away_streak = get_team_loss_streak(result_history, away) if result_history else 0

    # Se una squadra ha 3+ sconfitte consecutive, scommette su di lei
    if home_streak >= 3 and diff > -20:
        if r < 0.55:
            return "1"  # Crede nel rimbalzo della squadra in crisi
        elif r < 0.75:
            return "1X"  # Copre un po'
    if away_streak >= 3 and diff < 20:
        if r < 0.55:
            return "2"  # Rimbalzo trasferta
        elif r < 0.75:
            return "X2"

    # Altrimenti gioca normalmente, cerca il risultato più probabile
    if diff > 15:
        return "1"
    elif diff < -15:
        return "2"
    elif diff > 8:
        return "1" if r < 0.72 else "1X"
    elif diff < -8:
        return "2" if r < 0.72 else "X2"
    elif diff > 0:
        return random.choice(["1", "1X"])
    elif diff < 0:
        return random.choice(["2", "X2"])
    else:
        return random.choice(["1", "X", "2"])


def pick_nicola(home, away, odds, result_history, actual_result=None):
    """Nicola il Rischioso - gioca SOLO quote secche (1/X/2), MAI doppie chance.
    Per lui le doppie chance sono da vigliacchi. Ama il brivido della singola."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if diff > 15:
        return "1" if r < 0.78 else ("X" if r < 0.93 else "2")
    elif diff < -15:
        return "2" if r < 0.78 else ("X" if r < 0.93 else "1")
    elif diff > 8:
        return "1" if r < 0.60 else ("X" if r < 0.85 else "2")
    elif diff < -8:
        return "2" if r < 0.60 else ("X" if r < 0.85 else "1")
    elif diff > 3:
        return "1" if r < 0.50 else ("X" if r < 0.78 else "2")
    elif diff < -3:
        return "2" if r < 0.50 else ("X" if r < 0.78 else "1")
    else:
        # Match equilibrato - va a istinto
        if r < 0.32:
            return "X"
        elif r < 0.62:
            return "1"
        else:
            return "2"


class LucaPicker:
    """Luca la Formichina - gioca almeno 6 doppie chance per giornata.
    Preferisce fare la formichina: piccoli guadagni sicuri, evita il rischio."""

    def __init__(self):
        self._last_gday_len = -1
        self._dc_count = 0
        self._match_count = 0

    def __call__(self, home, away, odds, result_history, actual_result=None):
        current_gday = len(result_history)
        if current_gday != self._last_gday_len:
            self._last_gday_len = current_gday
            self._dc_count = 0
            self._match_count = 0

        self._match_count += 1
        remaining = 10 - self._match_count + 1
        dc_still_needed = max(0, 6 - self._dc_count)
        diff = TEAMS[home] - TEAMS[away]
        r = random.random()

        # Deve giocare DC se rimangono poche partite
        must_dc = dc_still_needed >= remaining
        # Altrimenti ha tendenza naturale per la DC (75%)
        wants_dc = must_dc or r < 0.75

        if wants_dc:
            self._dc_count += 1
            if diff > 8:
                return "1X"
            elif diff < -8:
                return "X2"
            elif diff > 0:
                return "1X"
            elif diff < 0:
                return "X2"
            else:
                return random.choice(["1X", "X2", "12"])
        else:
            # Le rare volte che gioca singola, segue la favorita netta
            if diff > 12:
                return "1"
            elif diff < -12:
                return "2"
            elif diff > 0:
                return "1"
            elif diff < 0:
                return "2"
            else:
                return random.choice(["1", "X", "2"])


def pick_tommaso(home, away, odds, result_history, actual_result=None):
    """Tommaso il Freak - ama i risultati pazzi per essere alternativo e stupire.
    Gioca tantissime X e upset. Spesso sbaglia ma ogni tanto fa giornate incredibili
    dove prende tutto perché i risultati sono folli come lui."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if abs(diff) > 15:
        # Big match con favorita netta? Lui va contro!
        if r < 0.42:
            return "X"
        elif r < 0.78:
            return "2" if diff > 0 else "1"  # Underdog
        else:
            return "1" if diff > 0 else "2"  # Ogni tanto la favorita
    elif abs(diff) > 5:
        if r < 0.38:
            return "X"
        elif r < 0.68:
            return "2" if diff > 0 else "1"  # Contrarian
        else:
            return "1" if diff > 0 else "2"
    else:
        # Match equilibrato: X è il suo habitat naturale
        if r < 0.52:
            return "X"
        elif r < 0.76:
            return "1"
        else:
            return "2"


def pick_carlo(home, away, odds, result_history, actual_result=None):
    """Carlo il Fortunato - non capisce troppo di calcio ma ha la classica
    fortuna del non-connoisseur. Becca risultati che tutti gli altri sbagliano.
    Sceglie un po' a caso ma con un istinto fortunato per gli upset."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    # Fortuna del principiante: probabilità di "sentire" il risultato giusto
    # Più alta sugli upset (risultati che gli altri sbagliano)
    if actual_result is not None:
        is_upset = (diff > 10 and actual_result != "1") or (diff < -10 and actual_result != "2")
        luck_chance = 0.28 if is_upset else 0.08
        if r < luck_chance:
            return actual_result

    # Altrimenti sceglie senza troppo criterio
    r2 = random.random()
    if r2 < 0.40:
        return "1"   # Sa che la squadra di casa vince spesso
    elif r2 < 0.60:
        return "X"
    elif r2 < 0.80:
        return "2"
    else:
        return random.choice(["1X", "X2"])


# ============================================================
# GIOCATORI
# ============================================================
_luca_picker = LucaPicker()

PLAYERS = [
    {"name": "Marco (Istintivo)", "pick_fn": pick_marco},
    {"name": "Andrea (Indeciso)", "pick_fn": pick_andrea},
    {"name": "Paolo (Meticoloso)", "pick_fn": pick_paolo},
    {"name": "Alessandro (Cacciatore)", "pick_fn": pick_alessandro},
    {"name": "Nicola (Rischioso)", "pick_fn": pick_nicola},
    {"name": "Luca (Formichina)", "pick_fn": _luca_picker},
    {"name": "Tommaso (Freak)", "pick_fn": pick_tommaso},
    {"name": "Carlo (Fortunato)", "pick_fn": pick_carlo},
]


# ============================================================
# SCORING
# ============================================================
def score_pick(pick, result, odds):
    """Calcola il punteggio per un singolo pronostico."""
    if pick == "-":
        return -max(odds["home"], odds["draw"], odds["away"]), False

    if pick == "1":
        if result == "1":
            return odds["home"], True
        else:
            return -odds["home"], False
    elif pick == "X":
        if result == "X":
            return odds["draw"], True
        else:
            return -odds["draw"], False
    elif pick == "2":
        if result == "2":
            return odds["away"], True
        else:
            return -odds["away"], False
    elif pick == "1X":
        if result in ("1", "X"):
            return odds["1x"], True
        else:
            return -(odds["home"] + odds["draw"]), False
    elif pick == "X2":
        if result in ("X", "2"):
            return odds["x2"], True
        else:
            return -(odds["draw"] + odds["away"]), False
    elif pick == "12":
        if result in ("1", "2"):
            return odds["12"], True
        else:
            return -(odds["home"] + odds["away"]), False

    return 0, False


def get_played_odds(pick, odds):
    """Restituisce la quota giocata per il calcolo della media."""
    mapping = {
        "1": odds["home"], "X": odds["draw"], "2": odds["away"],
        "1X": odds["1x"], "X2": odds["x2"], "12": odds["12"],
    }
    return mapping.get(pick)


# ============================================================
# SIMULAZIONE PRINCIPALE
# ============================================================
def run_simulation():
    calendar = generate_calendar()

    all_results = []
    player_totals = {p["name"]: 0.0 for p in PLAYERS}
    player_matchday_scores = {p["name"]: [] for p in PLAYERS}
    player_all_odds = {p["name"]: [] for p in PLAYERS}
    player_correct_total = {p["name"]: 0 for p in PLAYERS}

    result_history = []  # lista di [(home, away, result), ...]

    for gday_idx, matches in enumerate(calendar):
        gday_num = gday_idx + 1
        gday_data = {
            "giornata": gday_num,
            "matches": [],
            "player_scores": {},
        }

        match_results = []
        match_odds_list = []

        for home, away in matches:
            odds = generate_odds(home, away)
            result = simulate_result(odds)
            match_results.append(result)
            match_odds_list.append(odds)

            gday_data["matches"].append({
                "home": home, "away": away,
                "result": result,
                "odds": {
                    "1": odds["home"], "X": odds["draw"], "2": odds["away"],
                    "1X": odds["1x"], "X2": odds["x2"], "12": odds["12"]
                }
            })

        for player in PLAYERS:
            pname = player["name"]
            day_score = 0.0
            day_correct = 0
            day_picks = []

            for i, (home, away) in enumerate(matches):
                odds = match_odds_list[i]
                result = match_results[i]

                pick = player["pick_fn"](home, away, odds, result_history, result)
                points, correct = score_pick(pick, result, odds)

                played_odds = get_played_odds(pick, odds)
                if played_odds is not None:
                    player_all_odds[pname].append(played_odds)

                day_score += points
                if correct:
                    day_correct += 1

                day_picks.append({
                    "match": f"{home}-{away}",
                    "pick": pick,
                    "result": result,
                    "points": round(points, 2),
                    "correct": correct,
                })

            day_score = round(day_score, 2)
            player_totals[pname] += day_score
            player_matchday_scores[pname].append(day_score)
            player_correct_total[pname] += day_correct

            gday_data["player_scores"][pname] = {
                "picks": day_picks,
                "day_total": day_score,
                "correct": day_correct,
                "cumulative": round(player_totals[pname], 2),
            }

        result_history.append([
            (matches[j][0], matches[j][1], match_results[j])
            for j in range(len(matches))
        ])
        all_results.append(gday_data)

    return all_results, player_totals, player_matchday_scores, player_all_odds, player_correct_total


def player_totals_at_gday(matchday_scores, pname, gday):
    return sum(matchday_scores[pname][:gday])

def avg_odds_at_gday(all_odds, pname):
    odds_list = all_odds[pname]
    return sum(odds_list) / len(odds_list) if odds_list else 0

def avg_odds(all_odds, pname):
    odds_list = all_odds[pname]
    return sum(odds_list) / len(odds_list) if odds_list else 0


if __name__ == "__main__":
    all_results, player_totals, player_matchday_scores, player_all_odds, player_correct_total = run_simulation()

    print("=" * 120)
    print("CASSANDRA - SIMULAZIONE 20 GIORNATE SERIE A")
    print("=" * 120)

    final_ranking = sorted(
        PLAYERS,
        key=lambda p: (-round(player_totals[p["name"]], 2),
                       -avg_odds(player_all_odds, p["name"]),
                       p["name"])
    )

    print(f"\n  {'#':<4} {'Giocatore':<28} {'Punti Tot':>10} {'Media/G':>8} {'Quote Med':>10} {'Corrette':>10}")
    print(f"  {'-'*4} {'-'*28} {'-'*10} {'-'*8} {'-'*10} {'-'*10}")

    for rank, p in enumerate(final_ranking, 1):
        pname = p["name"]
        total = round(player_totals[pname], 2)
        avg_per_day = round(total / 20, 2)
        avg_o = round(avg_odds(player_all_odds, pname), 2)
        correct = player_correct_total[pname]
        print(f"  {rank:<4} {pname:<28} {total:>+10.2f} {avg_per_day:>+8.2f} {avg_o:>10.2f} {correct:>10}/200")
