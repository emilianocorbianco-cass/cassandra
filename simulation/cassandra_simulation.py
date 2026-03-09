#!/usr/bin/env python3
"""
Cassandra Game Simulation - 20 Giornate Serie A
8 giocatori con personalità distinte, quote realistiche, senza bonus/malus.

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
        # Prima partita: fixed vs primo della lista rotante
        if round_num % 2 == 0:
            matches.append((fixed, rotating[0]))
        else:
            matches.append((rotating[0], fixed))

        # Altre partite
        for i in range(1, n // 2):
            home = rotating[i]
            away = rotating[n - 2 - i]
            if (round_num + i) % 2 == 0:
                matches.append((home, away))
            else:
                matches.append((away, home))

        calendar.append(matches)
        # Ruota
        rotating = rotating[1:] + rotating[:1]

    # Con 20 squadre si generano esattamente 19 giornate (andata).
    # Per arrivare a 20, aggiungiamo la prima giornata di ritorno (invertendo casa/trasferta).
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

    # Fattore casa
    home_advantage = 5
    diff = (home_str + home_advantage) - away_str

    # Probabilità base
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

    # Aggiungi varianza
    noise = lambda: random.uniform(-0.03, 0.03)
    p_home = max(0.08, p_home + noise())
    p_draw = max(0.08, p_draw + noise())
    p_away = max(0.08, p_away + noise())

    # Normalizza
    total = p_home + p_draw + p_away
    p_home /= total
    p_draw /= total
    p_away /= total

    # Margine bookmaker (~8%)
    margin = 1.08

    q_home = round(margin / p_home, 2)
    q_draw = round(margin / p_draw, 2)
    q_away = round(margin / p_away, 2)

    # Quote doppie chance
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
# DEFINIZIONE DEGLI 8 GIOCATORI
# ============================================================

def pick_cauto(home, away, odds, result_history):
    """Il Cauto - gioca sempre sicuro, molte doppie chance sui match incerti."""
    diff = TEAMS[home] - TEAMS[away]
    # Favorita netta -> singola sulla favorita
    if diff > 15:
        return "1"
    elif diff < -15:
        return "2"
    # Favorita moderata -> doppia chance
    elif diff > 5:
        return "1X"
    elif diff < -5:
        return "X2"
    # Match equilibrato -> 1X (leggero favore casa)
    else:
        return "1X"


def pick_studioso(home, away, odds, result_history):
    """Lo Studioso del Calcio - analizza forma, precedenti, tende a essere preciso."""
    diff = TEAMS[home] - TEAMS[away]
    # Lo studioso "sente" il calcio, a volte azzecca i pareggi
    r = random.random()

    if diff > 18:
        return "1"
    elif diff < -18:
        return "2"
    elif diff > 8:
        if r < 0.75:
            return "1"
        elif r < 0.90:
            return "X"
        else:
            return "1X"
    elif diff < -8:
        if r < 0.75:
            return "2"
        elif r < 0.90:
            return "X"
        else:
            return "X2"
    else:
        # Match equilibrato: lo studioso sa che ci sono molti pareggi
        if r < 0.30:
            return "X"
        elif r < 0.55:
            return "1"
        elif r < 0.80:
            return "2"
        else:
            return "12"


def pick_avventato(home, away, odds, result_history):
    """L'Avventato - ama le sorprese, gioca spesso la sfavorita o il pareggio ad alta quota."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if diff > 15:
        # Contro la favorita!
        if r < 0.40:
            return "X"
        elif r < 0.70:
            return "2"
        else:
            return "X2"
    elif diff < -15:
        if r < 0.40:
            return "X"
        elif r < 0.70:
            return "1"
        else:
            return "1X"
    elif diff > 5:
        if r < 0.35:
            return "2"
        elif r < 0.60:
            return "X"
        else:
            return "1"
    elif diff < -5:
        if r < 0.35:
            return "1"
        elif r < 0.60:
            return "X"
        else:
            return "2"
    else:
        # Match equilibrato: sceglie quasi a caso, tendenza upset
        choices = ["1", "X", "2"]
        return random.choice(choices)


def pick_superficiale(home, away, odds, result_history):
    """Il Superficiale - conosce poco il calcio, segue il nome blasonato."""
    # Conosce le big: Inter, Juve, Milan, Napoli. Per il resto va un po' a caso.
    big_teams = {"Inter", "Juventus", "Milan", "Napoli"}
    r = random.random()

    home_big = home in big_teams
    away_big = away in big_teams

    if home_big and not away_big:
        if r < 0.80:
            return "1"
        else:
            return "1X"
    elif away_big and not home_big:
        if r < 0.75:
            return "2"
        else:
            return "X2"
    elif home_big and away_big:
        # Scontro diretto: va un po' a caso tra le due
        choices = ["1", "X", "2", "1X", "X2"]
        return random.choice(choices)
    else:
        # Non conosce bene: scelte quasi casuali, con leggera tendenza all'1
        if r < 0.40:
            return "1"
        elif r < 0.60:
            return "X"
        elif r < 0.80:
            return "2"
        else:
            return random.choice(["1X", "X2", "12"])


def pick_moderato_eccessi(home, away, odds, result_history):
    """Il Moderato con Eccessi - solitamente moderato, ma 20% delle volte rischia troppo."""
    r_eccesso = random.random()

    if r_eccesso < 0.20:
        # Momento di follia: gioca come l'avventato
        return pick_avventato(home, away, odds, result_history)
    else:
        # Moderato: segue le quote
        diff = TEAMS[home] - TEAMS[away]
        if diff > 12:
            return "1"
        elif diff < -12:
            return "2"
        elif diff > 3:
            return random.choice(["1", "1X"])
        elif diff < -3:
            return random.choice(["2", "X2"])
        else:
            return random.choice(["1", "X", "2"])


def pick_calcolatore(home, away, odds, result_history):
    """Il Calcolatore - segue le quote al millimetro, gioca value bets."""
    # Segue rigorosamente le probabilità implicite delle quote
    p_home = 1 / odds["home"]
    p_draw = 1 / odds["draw"]
    p_away = 1 / odds["away"]
    total = p_home + p_draw + p_away
    p_home /= total
    p_draw /= total
    p_away /= total

    # Sceglie la più probabile, ma usa anche doppie chance se il margine è stretto
    if p_home > 0.50:
        return "1"
    elif p_away > 0.50:
        return "2"
    elif p_home > p_away and p_home > 0.38:
        return "1"
    elif p_away > p_home and p_away > 0.38:
        return "2"
    elif p_home > p_away:
        # Margine stretto: doppia chance
        return "1X"
    elif p_away > p_home:
        return "X2"
    else:
        return "1X"


def pick_tifoso(home, away, odds, result_history):
    """Il Tifoso del Lecce - gioca sempre 1 quando il Lecce è in casa, 2 in trasferta.
    Per le altre partite è abbastanza ragionevole."""
    squadra_cuore = "Lecce"  # Parte bassa della classifica

    if home == squadra_cuore:
        return "1"  # Sempre fiducia!
    elif away == squadra_cuore:
        return "2"  # Sempre fiducia!
    else:
        # Per le altre partite è ragionevole
        diff = TEAMS[home] - TEAMS[away]
        if diff > 10:
            return "1"
        elif diff < -10:
            return "2"
        elif diff > 3:
            return random.choice(["1", "1X"])
        elif diff < -3:
            return random.choice(["2", "X2"])
        else:
            return random.choice(["1", "X", "2"])


def pick_moderato(home, away, odds, result_history):
    """Tu (Il Moderato) - sempre equilibrato, segue la logica senza eccessi."""
    diff = TEAMS[home] - TEAMS[away]
    r = random.random()

    if diff > 18:
        return "1"
    elif diff < -18:
        return "2"
    elif diff > 10:
        if r < 0.70:
            return "1"
        else:
            return "1X"
    elif diff < -10:
        if r < 0.70:
            return "2"
        else:
            return "X2"
    elif diff > 3:
        if r < 0.55:
            return "1"
        elif r < 0.80:
            return "1X"
        else:
            return "X"
    elif diff < -3:
        if r < 0.55:
            return "2"
        elif r < 0.80:
            return "X2"
        else:
            return "X"
    else:
        if r < 0.35:
            return "1"
        elif r < 0.55:
            return "X"
        elif r < 0.75:
            return "2"
        else:
            return "12"


# ============================================================
# GIOCATORI
# ============================================================
PLAYERS = [
    {"name": "Il Cauto", "emoji": "", "pick_fn": pick_cauto},
    {"name": "Lo Studioso", "emoji": "", "pick_fn": pick_studioso},
    {"name": "L'Avventato", "emoji": "", "pick_fn": pick_avventato},
    {"name": "Il Superficiale", "emoji": "", "pick_fn": pick_superficiale},
    {"name": "Il Moderato con Eccessi", "emoji": "", "pick_fn": pick_moderato_eccessi},
    {"name": "Il Calcolatore", "emoji": "", "pick_fn": pick_calcolatore},
    {"name": "Il Tifoso (Lecce)", "emoji": "", "pick_fn": pick_tifoso},
    {"name": "Tu (Il Moderato)", "emoji": "", "pick_fn": pick_moderato},
]


# ============================================================
# SCORING
# ============================================================
def score_pick(pick, result, odds):
    """Calcola il punteggio per un singolo pronostico."""
    if pick == "-":
        # Non giocata
        return -max(odds["home"], odds["draw"], odds["away"]), False

    # Singole
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

    # Doppie chance
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

    # Struttura risultati
    all_results = []  # Per ogni giornata
    player_totals = {p["name"]: 0.0 for p in PLAYERS}
    player_matchday_scores = {p["name"]: [] for p in PLAYERS}
    player_all_odds = {p["name"]: [] for p in PLAYERS}
    player_correct_total = {p["name"]: 0 for p in PLAYERS}

    result_history = []

    for gday_idx, matches in enumerate(calendar):
        gday_num = gday_idx + 1
        gday_data = {
            "giornata": gday_num,
            "matches": [],
            "player_scores": {},
        }

        match_results = []
        match_odds_list = []

        # Genera quote e risultati per ogni partita
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

        # Ogni giocatore fa i pronostici
        for player in PLAYERS:
            pname = player["name"]
            day_score = 0.0
            day_correct = 0
            day_picks = []

            for i, (home, away) in enumerate(matches):
                odds = match_odds_list[i]
                result = match_results[i]

                pick = player["pick_fn"](home, away, odds, result_history)
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

        result_history.append(match_results)
        all_results.append(gday_data)

    return all_results, player_totals, player_matchday_scores, player_all_odds, player_correct_total


def print_results(all_results, player_totals, player_matchday_scores, player_all_odds, player_correct_total):
    print("=" * 120)
    print("CASSANDRA - SIMULAZIONE 20 GIORNATE SERIE A (SENZA BONUS/MALUS)")
    print("=" * 120)

    for gday in all_results:
        gnum = gday["giornata"]
        print(f"\n{'='*120}")
        print(f"  GIORNATA {gnum}")
        print(f"{'='*120}")

        # Stampa partite e risultati
        print(f"\n  {'Partita':<30} {'Ris':>4}  {'1':>6} {'X':>6} {'2':>6} {'1X':>6} {'X2':>6} {'12':>6}")
        print(f"  {'-'*96}")
        for m in gday["matches"]:
            match_str = f"{m['home']}-{m['away']}"
            print(f"  {match_str:<30} {m['result']:>4}  "
                  f"{m['odds']['1']:>6.2f} {m['odds']['X']:>6.2f} {m['odds']['2']:>6.2f} "
                  f"{m['odds']['1X']:>6.2f} {m['odds']['X2']:>6.2f} {m['odds']['12']:>6.2f}")

        # Stampa pronostici e punteggi per ogni giocatore
        print(f"\n  {'Giocatore':<28}", end="")
        for i, m in enumerate(gday["matches"]):
            short = f"{m['home'][:3]}-{m['away'][:3]}"
            print(f" {short:>8}", end="")
        print(f"  {'TOT':>8} {'OK':>3} {'CUM':>10}")
        print(f"  {'-'*28}", end="")
        for _ in gday["matches"]:
            print(f" {'-'*8}", end="")
        print(f"  {'-'*8} {'-'*3} {'-'*10}")

        for player in PLAYERS:
            pname = player["name"]
            pdata = gday["player_scores"][pname]
            print(f"  {pname:<28}", end="")
            for pick_data in pdata["picks"]:
                marker = "+" if pick_data["correct"] else " "
                print(f" {marker}{pick_data['pick']:>4}{pick_data['points']:>+.0f}" if abs(pick_data['points']) < 10
                      else f" {marker}{pick_data['pick']:>3}{pick_data['points']:>+.0f}", end="")
            print(f"  {pdata['day_total']:>+8.2f} {pdata['correct']:>3} {pdata['cumulative']:>+10.2f}")

        # Mini classifica giornata
        print(f"\n  Classifica dopo Giornata {gnum}:")
        sorted_players = sorted(
            PLAYERS,
            key=lambda p: (-round(player_totals_at_gday(player_matchday_scores, p["name"], gnum), 2),
                           -avg_odds_at_gday(player_all_odds, p["name"]),
                           p["name"])
        )
        for rank, p in enumerate(sorted_players, 1):
            cum = round(player_totals_at_gday(player_matchday_scores, p["name"], gnum), 2)
            print(f"  {rank}. {p['name']:<28} {cum:>+10.2f}")

    # ============================================================
    # CLASSIFICA FINALE
    # ============================================================
    print(f"\n\n{'='*120}")
    print("  CLASSIFICA FINALE DOPO 20 GIORNATE")
    print(f"{'='*120}")

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

    # Tabella riassuntiva punteggi per giornata
    print(f"\n\n{'='*120}")
    print("  RIEPILOGO PUNTEGGI PER GIORNATA")
    print(f"{'='*120}")

    # Header
    print(f"\n  {'Giocatore':<28}", end="")
    for g in range(1, 21):
        print(f" G{g:>2}", end="")
    print(f"  {'TOTALE':>8}")
    print(f"  {'-'*28}", end="")
    for _ in range(20):
        print(f" {'-'*4}", end="")
    print(f"  {'-'*8}")

    for p in final_ranking:
        pname = p["name"]
        print(f"  {pname:<28}", end="")
        for score in player_matchday_scores[pname]:
            print(f" {score:>+4.0f}" if abs(score) < 100 else f" {score:>+.0f}", end="")
        print(f"  {player_totals[pname]:>+8.2f}")

    # Andamento cumulativo
    print(f"\n\n{'='*120}")
    print("  ANDAMENTO CUMULATIVO PER GIORNATA")
    print(f"{'='*120}")

    print(f"\n  {'Giocatore':<28}", end="")
    for g in range(1, 21):
        print(f"  G{g:>2} ", end="")
    print()
    print(f"  {'-'*28}", end="")
    for _ in range(20):
        print(f" {'-'*5}", end="")
    print()

    for p in final_ranking:
        pname = p["name"]
        print(f"  {pname:<28}", end="")
        cumul = 0
        for score in player_matchday_scores[pname]:
            cumul += score
            print(f" {cumul:>+5.0f}", end="")
        print()


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
    print_results(all_results, player_totals, player_matchday_scores, player_all_odds, player_correct_total)
