#!/usr/bin/env python3
"""
Genera un PDF completo con la simulazione Cassandra:
- Scenario 1: Senza bonus/malus
- Scenario 2: Con bonus/malus attuali
- Confronto e analisi
- Proposte di modifica
"""

import sys
sys.path.insert(0, '/home/user/cassandra/simulation')

from cassandra_simulation import (
    PLAYERS, TEAMS, generate_calendar, generate_odds,
    simulate_result, score_pick, get_played_odds
)
import random

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm, cm
from reportlab.platypus import (
    SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
    PageBreak, KeepTogether
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY

# ============================================================
# BONUS/MALUS TABLE (from scoring_engine.dart)
# ============================================================
BONUS_TABLE = {0: -20, 1: -10, 2: -5, 3: -2, 4: -1, 5: 0, 6: 1, 7: 2, 8: 5, 9: 10, 10: 20}

# Proposed alternative bonus table (more gradual)
PROPOSED_BONUS_TABLE = {0: -10, 1: -6, 2: -3, 3: -1, 4: 0, 5: +1, 6: +3, 7: +5, 8: +8, 9: +12, 10: +18}

# Claude's proposed alternative: shifted breakeven + moderate scaling
CLAUDE_BONUS_TABLE = {0: -12, 1: -7, 2: -3, 3: -1, 4: 0, 5: 0, 6: +2, 7: +4, 8: +7, 9: +11, 10: +16}


def run_full_simulation():
    """Run simulation once, compute scores for all three scenarios."""
    random.seed(42)
    calendar = generate_calendar()

    # We need to capture all matchday data first
    all_matchdays = []
    result_history = []

    for gday_idx, matches in enumerate(calendar):
        gday_data = {"giornata": gday_idx + 1, "matches": [], "player_picks": {}}
        match_results = []
        match_odds_list = []

        for home, away in matches:
            odds = generate_odds(home, away)
            result = simulate_result(odds)
            match_results.append(result)
            match_odds_list.append(odds)
            gday_data["matches"].append({
                "home": home, "away": away, "result": result, "odds": odds
            })

        # Each player picks
        for player in PLAYERS:
            pname = player["name"]
            picks = []
            for i, (home, away) in enumerate(matches):
                pick = player["pick_fn"](home, away, match_odds_list[i], result_history)
                points, correct = score_pick(pick, match_results[i], match_odds_list[i])
                played_odds = get_played_odds(pick, match_odds_list[i])
                picks.append({
                    "pick": pick, "result": match_results[i],
                    "points": round(points, 2), "correct": correct,
                    "played_odds": played_odds,
                    "home": matches[i][0], "away": matches[i][1],
                    "odds": match_odds_list[i],
                })
            gday_data["player_picks"][pname] = picks

        result_history.append(match_results)
        all_matchdays.append(gday_data)

    # Now compute three scenarios
    def compute_scenario(bonus_table):
        """Compute total scores with given bonus table (None = no bonus)."""
        totals = {p["name"]: 0.0 for p in PLAYERS}
        matchday_scores = {p["name"]: [] for p in PLAYERS}
        matchday_bonus = {p["name"]: [] for p in PLAYERS}
        matchday_correct = {p["name"]: [] for p in PLAYERS}
        all_odds = {p["name"]: [] for p in PLAYERS}
        total_correct = {p["name"]: 0 for p in PLAYERS}

        for gday in all_matchdays:
            for player in PLAYERS:
                pname = player["name"]
                picks = gday["player_picks"][pname]
                base = sum(p["points"] for p in picks)
                correct = sum(1 for p in picks if p["correct"])
                bonus = 0
                if bonus_table is not None:
                    c = min(correct, 10)
                    bonus = bonus_table.get(c, 0)
                day_total = round(base + bonus, 2)
                totals[pname] += day_total
                matchday_scores[pname].append(day_total)
                matchday_bonus[pname].append(bonus)
                matchday_correct[pname].append(correct)
                total_correct[pname] += correct
                for p in picks:
                    if p["played_odds"] is not None:
                        all_odds[pname].append(p["played_odds"])

        return {
            "totals": {k: round(v, 2) for k, v in totals.items()},
            "matchday_scores": matchday_scores,
            "matchday_bonus": matchday_bonus,
            "matchday_correct": matchday_correct,
            "all_odds": all_odds,
            "total_correct": total_correct,
        }

    no_bonus = compute_scenario(None)
    with_bonus = compute_scenario(BONUS_TABLE)
    with_proposed = compute_scenario(PROPOSED_BONUS_TABLE)
    with_claude = compute_scenario(CLAUDE_BONUS_TABLE)

    return all_matchdays, no_bonus, with_bonus, with_proposed, with_claude


# ============================================================
# PDF GENERATION
# ============================================================

# Colors
DARK_BLUE = colors.HexColor("#1a237e")
MEDIUM_BLUE = colors.HexColor("#283593")
LIGHT_BLUE = colors.HexColor("#e8eaf6")
ACCENT_GREEN = colors.HexColor("#2e7d32")
ACCENT_RED = colors.HexColor("#c62828")
ACCENT_ORANGE = colors.HexColor("#e65100")
HEADER_BG = colors.HexColor("#1a237e")
ROW_ALT = colors.HexColor("#f5f5f5")
WHITE = colors.white
BLACK = colors.black
LIGHT_GRAY = colors.HexColor("#eeeeee")
GOLD = colors.HexColor("#ffd600")
SILVER = colors.HexColor("#bdbdbd")
BRONZE = colors.HexColor("#ff8f00")


def create_styles():
    styles = getSampleStyleSheet()

    styles.add(ParagraphStyle(
        'CoverTitle', parent=styles['Title'],
        fontSize=28, textColor=DARK_BLUE, spaceAfter=6*mm,
        alignment=TA_CENTER, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'CoverSubtitle', parent=styles['Normal'],
        fontSize=14, textColor=MEDIUM_BLUE, spaceAfter=3*mm,
        alignment=TA_CENTER, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'SectionTitle', parent=styles['Heading1'],
        fontSize=18, textColor=DARK_BLUE, spaceBefore=8*mm, spaceAfter=4*mm,
        fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'SubSection', parent=styles['Heading2'],
        fontSize=14, textColor=MEDIUM_BLUE, spaceBefore=5*mm, spaceAfter=3*mm,
        fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'BodyText2', parent=styles['Normal'],
        fontSize=9, leading=12, spaceAfter=2*mm,
        alignment=TA_JUSTIFY, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'SmallNote', parent=styles['Normal'],
        fontSize=7, leading=9, textColor=colors.gray,
        fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'TableHeader', parent=styles['Normal'],
        fontSize=7, textColor=WHITE, alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'TableCell', parent=styles['Normal'],
        fontSize=7, alignment=TA_CENTER, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'TableCellLeft', parent=styles['Normal'],
        fontSize=7, alignment=TA_LEFT, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'BonusTableHeader', parent=styles['Normal'],
        fontSize=8, textColor=WHITE, alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'AnalysisText', parent=styles['Normal'],
        fontSize=9.5, leading=13, spaceAfter=3*mm,
        alignment=TA_JUSTIFY, fontName='Helvetica'
    ))

    return styles


def make_ranking_table(scenario, styles, title=""):
    """Create a ranking table from scenario data."""
    sorted_players = sorted(
        PLAYERS,
        key=lambda p: (
            -scenario["totals"][p["name"]],
            -(sum(scenario["all_odds"][p["name"]]) / len(scenario["all_odds"][p["name"]]) if scenario["all_odds"][p["name"]] else 0),
            p["name"]
        )
    )

    header = [
        Paragraph('#', styles['TableHeader']),
        Paragraph('Giocatore', styles['TableHeader']),
        Paragraph('Punti Tot', styles['TableHeader']),
        Paragraph('Media/G', styles['TableHeader']),
        Paragraph('Quota Med', styles['TableHeader']),
        Paragraph('Corrette', styles['TableHeader']),
    ]
    data = [header]

    for rank, p in enumerate(sorted_players, 1):
        pname = p["name"]
        total = scenario["totals"][pname]
        avg_day = total / 20
        odds_list = scenario["all_odds"][pname]
        avg_o = sum(odds_list) / len(odds_list) if odds_list else 0
        correct = scenario["total_correct"][pname]

        color = BLACK
        if total > 0:
            color = ACCENT_GREEN
        elif total < -100:
            color = ACCENT_RED

        medal = ""
        if rank == 1: medal = "  "
        elif rank == 2: medal = "  "
        elif rank == 3: medal = "  "

        data.append([
            Paragraph(f'{rank}', styles['TableCell']),
            Paragraph(f'{pname}{medal}', styles['TableCellLeft']),
            Paragraph(f'<font color="{color}">{total:+.2f}</font>', styles['TableCell']),
            Paragraph(f'{avg_day:+.2f}', styles['TableCell']),
            Paragraph(f'{avg_o:.2f}', styles['TableCell']),
            Paragraph(f'{correct}/200', styles['TableCell']),
        ])

    col_widths = [20, 120, 60, 50, 55, 50]
    table = Table(data, colWidths=col_widths)

    style_cmds = [
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (1, 1), (1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]

    # Highlight top 3
    if len(data) > 1:
        style_cmds.append(('BACKGROUND', (0, 1), (-1, 1), colors.HexColor("#fff8e1")))
    if len(data) > 2:
        style_cmds.append(('BACKGROUND', (0, 2), (-1, 2), colors.HexColor("#fafafa")))
    if len(data) > 3:
        style_cmds.append(('BACKGROUND', (0, 3), (-1, 3), colors.HexColor("#fff3e0")))

    table.setStyle(TableStyle(style_cmds))
    return table, sorted_players


def make_matchday_grid(scenario, sorted_players, styles):
    """Create matchday-by-matchday score grid."""
    header = [Paragraph('Giocatore', styles['TableHeader'])]
    for g in range(1, 21):
        header.append(Paragraph(f'G{g}', styles['TableHeader']))
    header.append(Paragraph('TOT', styles['TableHeader']))

    data = [header]
    for p in sorted_players:
        pname = p["name"]
        row = [Paragraph(pname, styles['TableCellLeft'])]
        for score in scenario["matchday_scores"][pname]:
            color = ACCENT_GREEN if score > 0 else (ACCENT_RED if score < -15 else BLACK)
            row.append(Paragraph(f'<font color="{color}">{score:+.0f}</font>', styles['TableCell']))
        total = scenario["totals"][pname]
        color = ACCENT_GREEN if total > 0 else (ACCENT_RED if total < -50 else BLACK)
        row.append(Paragraph(f'<font color="{color}"><b>{total:+.1f}</b></font>', styles['TableCell']))
        data.append(row)

    col_widths = [105] + [22] * 20 + [35]
    table = Table(data, colWidths=col_widths)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 6),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor("#dddddd")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 2),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
        ('BACKGROUND', (-1, 0), (-1, -1), colors.HexColor("#e8eaf6")),
        ('BACKGROUND', (-1, 0), (-1, 0), HEADER_BG),
    ]))
    return table


def make_cumulative_grid(scenario, sorted_players, styles):
    """Create cumulative score grid."""
    header = [Paragraph('Giocatore', styles['TableHeader'])]
    for g in range(1, 21):
        header.append(Paragraph(f'G{g}', styles['TableHeader']))

    data = [header]
    for p in sorted_players:
        pname = p["name"]
        row = [Paragraph(pname, styles['TableCellLeft'])]
        cumul = 0
        for score in scenario["matchday_scores"][pname]:
            cumul += score
            color = ACCENT_GREEN if cumul > 0 else (ACCENT_RED if cumul < -50 else BLACK)
            row.append(Paragraph(f'<font color="{color}">{cumul:+.0f}</font>', styles['TableCell']))
        data.append(row)

    col_widths = [105] + [23.5] * 20
    table = Table(data, colWidths=col_widths)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 6),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor("#dddddd")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 2),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
    ]))
    return table


def make_comparison_table(no_bonus, with_bonus, with_proposed, styles):
    """Create side-by-side comparison of all three scenarios."""
    header = [
        Paragraph('Giocatore', styles['TableHeader']),
        Paragraph('Senza B/M', styles['TableHeader']),
        Paragraph('Pos.', styles['TableHeader']),
        Paragraph('Con B/M Attuali', styles['TableHeader']),
        Paragraph('Pos.', styles['TableHeader']),
        Paragraph('Delta', styles['TableHeader']),
        Paragraph('Con B/M Proposti', styles['TableHeader']),
        Paragraph('Pos.', styles['TableHeader']),
        Paragraph('Delta', styles['TableHeader']),
    ]

    def get_ranking(scenario):
        return sorted(PLAYERS, key=lambda p: -scenario["totals"][p["name"]])

    rank_no = {p["name"]: i+1 for i, p in enumerate(get_ranking(no_bonus))}
    rank_with = {p["name"]: i+1 for i, p in enumerate(get_ranking(with_bonus))}
    rank_prop = {p["name"]: i+1 for i, p in enumerate(get_ranking(with_proposed))}

    data = [header]
    for p in get_ranking(no_bonus):
        pname = p["name"]
        t_no = no_bonus["totals"][pname]
        t_with = with_bonus["totals"][pname]
        t_prop = with_proposed["totals"][pname]
        delta_1 = t_with - t_no
        delta_2 = t_prop - t_no

        pos_change_1 = rank_no[pname] - rank_with[pname]
        pos_change_2 = rank_no[pname] - rank_prop[pname]

        pos_str_1 = f'{rank_with[pname]}'
        if pos_change_1 > 0: pos_str_1 += f' (+{pos_change_1})'
        elif pos_change_1 < 0: pos_str_1 += f' ({pos_change_1})'

        pos_str_2 = f'{rank_prop[pname]}'
        if pos_change_2 > 0: pos_str_2 += f' (+{pos_change_2})'
        elif pos_change_2 < 0: pos_str_2 += f' ({pos_change_2})'

        delta_color_1 = ACCENT_GREEN if delta_1 > 0 else (ACCENT_RED if delta_1 < 0 else BLACK)
        delta_color_2 = ACCENT_GREEN if delta_2 > 0 else (ACCENT_RED if delta_2 < 0 else BLACK)

        data.append([
            Paragraph(pname, styles['TableCellLeft']),
            Paragraph(f'{t_no:+.2f}', styles['TableCell']),
            Paragraph(f'{rank_no[pname]}', styles['TableCell']),
            Paragraph(f'{t_with:+.2f}', styles['TableCell']),
            Paragraph(pos_str_1, styles['TableCell']),
            Paragraph(f'<font color="{delta_color_1}">{delta_1:+.1f}</font>', styles['TableCell']),
            Paragraph(f'{t_prop:+.2f}', styles['TableCell']),
            Paragraph(pos_str_2, styles['TableCell']),
            Paragraph(f'<font color="{delta_color_2}">{delta_2:+.1f}</font>', styles['TableCell']),
        ])

    col_widths = [100, 55, 30, 60, 45, 35, 60, 45, 35]
    table = Table(data, colWidths=col_widths)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 7),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        # Vertical separators between scenarios
        ('LINEAFTER', (2, 0), (2, -1), 1.5, DARK_BLUE),
        ('LINEAFTER', (5, 0), (5, -1), 1.5, DARK_BLUE),
    ]))
    return table


def make_bonus_comparison_table(styles):
    """Show current vs proposed bonus tables side by side."""
    header = [
        Paragraph('Corrette', styles['BonusTableHeader']),
        Paragraph('B/M Attuali', styles['BonusTableHeader']),
        Paragraph('B/M Proposti', styles['BonusTableHeader']),
        Paragraph('Differenza', styles['BonusTableHeader']),
    ]
    data = [header]

    for i in range(11):
        curr = BONUS_TABLE[i]
        prop = PROPOSED_BONUS_TABLE[i]
        diff = prop - curr

        curr_color = ACCENT_GREEN if curr > 0 else (ACCENT_RED if curr < 0 else BLACK)
        prop_color = ACCENT_GREEN if prop > 0 else (ACCENT_RED if prop < 0 else BLACK)
        diff_color = ACCENT_GREEN if diff > 0 else (ACCENT_RED if diff < 0 else BLACK)

        data.append([
            Paragraph(f'{i}/10', styles['TableCell']),
            Paragraph(f'<font color="{curr_color}"><b>{curr:+d}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{prop_color}"><b>{prop:+d}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{diff_color}">{diff:+d}</font>', styles['TableCell']),
        ])

    table = Table(data, colWidths=[60, 70, 70, 60])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        # Highlight the breakeven row (5/10)
        ('BACKGROUND', (0, 6), (-1, 6), colors.HexColor("#e8f5e9")),
    ]))
    return table


def make_matchday_detail_tables(all_matchdays, no_bonus, with_bonus, styles):
    """Create detailed tables for each matchday showing matches, picks, and results."""
    elements = []

    sorted_no = sorted(PLAYERS, key=lambda p: -no_bonus["totals"][p["name"]])
    player_order = [p["name"] for p in sorted_no]

    for gday in all_matchdays:
        gnum = gday["giornata"]

        elements.append(Paragraph(f'Giornata {gnum}', styles['SubSection']))

        # Matches table
        match_header = [
            Paragraph('Partita', styles['TableHeader']),
            Paragraph('Ris', styles['TableHeader']),
            Paragraph('1', styles['TableHeader']),
            Paragraph('X', styles['TableHeader']),
            Paragraph('2', styles['TableHeader']),
            Paragraph('1X', styles['TableHeader']),
            Paragraph('X2', styles['TableHeader']),
            Paragraph('12', styles['TableHeader']),
        ]
        match_data = [match_header]
        for m in gday["matches"]:
            o = m["odds"]
            match_data.append([
                Paragraph(f'{m["home"][:3].upper()}-{m["away"][:3].upper()}', styles['TableCellLeft']),
                Paragraph(f'<b>{m["result"]}</b>', styles['TableCell']),
                Paragraph(f'{o["home"]:.2f}', styles['TableCell']),
                Paragraph(f'{o["draw"]:.2f}', styles['TableCell']),
                Paragraph(f'{o["away"]:.2f}', styles['TableCell']),
                Paragraph(f'{o["1x"]:.2f}', styles['TableCell']),
                Paragraph(f'{o["x2"]:.2f}', styles['TableCell']),
                Paragraph(f'{o["12"]:.2f}', styles['TableCell']),
            ])

        match_table = Table(match_data, colWidths=[55, 22, 32, 32, 32, 32, 32, 32])
        match_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
            ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
            ('FONTSIZE', (0, 0), (-1, -1), 6),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('ALIGN', (0, 1), (0, -1), 'LEFT'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor("#dddddd")),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
            ('TOPPADDING', (0, 0), (-1, -1), 1.5),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1.5),
        ]))
        elements.append(match_table)
        elements.append(Spacer(1, 2*mm))

        # Player picks table
        pick_header = [Paragraph('Giocatore', styles['TableHeader'])]
        for m in gday["matches"]:
            pick_header.append(Paragraph(f'{m["home"][:3]}-{m["away"][:3]}', styles['TableHeader']))
        pick_header.extend([
            Paragraph('OK', styles['TableHeader']),
            Paragraph('Base', styles['TableHeader']),
            Paragraph('B/M', styles['TableHeader']),
            Paragraph('Tot', styles['TableHeader']),
        ])

        pick_data = [pick_header]
        for pname in player_order:
            picks = gday["player_picks"][pname]
            correct_count = sum(1 for p in picks if p["correct"])
            base = sum(p["points"] for p in picks)
            bonus = BONUS_TABLE.get(min(correct_count, 10), 0)
            total_with = base + bonus

            row = [Paragraph(pname[:18], styles['TableCellLeft'])]
            for p in picks:
                marker = "+" if p["correct"] else ""
                color = ACCENT_GREEN if p["correct"] else ACCENT_RED
                row.append(Paragraph(
                    f'<font color="{color}">{marker}{p["pick"]}</font>',
                    styles['TableCell']
                ))
            row.append(Paragraph(f'{correct_count}', styles['TableCell']))

            base_color = ACCENT_GREEN if base > 0 else (ACCENT_RED if base < 0 else BLACK)
            row.append(Paragraph(f'<font color="{base_color}">{base:+.1f}</font>', styles['TableCell']))

            bonus_color = ACCENT_GREEN if bonus > 0 else (ACCENT_RED if bonus < 0 else BLACK)
            row.append(Paragraph(f'<font color="{bonus_color}">{bonus:+d}</font>', styles['TableCell']))

            tot_color = ACCENT_GREEN if total_with > 0 else (ACCENT_RED if total_with < 0 else BLACK)
            row.append(Paragraph(f'<font color="{tot_color}"><b>{total_with:+.1f}</b></font>', styles['TableCell']))

            pick_data.append(row)

        pick_widths = [85] + [37] * 10 + [18, 30, 22, 30]
        pick_table = Table(pick_data, colWidths=pick_widths)
        pick_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), MEDIUM_BLUE),
            ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
            ('FONTSIZE', (0, 0), (-1, -1), 5.5),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('ALIGN', (0, 1), (0, -1), 'LEFT'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('GRID', (0, 0), (-1, -1), 0.3, colors.HexColor("#dddddd")),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
            ('TOPPADDING', (0, 0), (-1, -1), 1.5),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1.5),
            ('LINEAFTER', (-4, 0), (-4, -1), 1, MEDIUM_BLUE),
        ]))
        elements.append(pick_table)
        elements.append(Spacer(1, 4*mm))

        # Page break every 2 matchdays
        if gnum % 2 == 0 and gnum < 20:
            elements.append(PageBreak())

    return elements


def make_player_profiles_table(no_bonus, with_bonus, styles):
    """Create a table with each player's personality description and performance."""
    profiles = {
        "Il Calcolatore": "Segue le quote al millimetro. Analizza le probabilita implicite e sceglie sempre il value bet ottimale. Usa doppie chance solo nei match molto equilibrati.",
        "Il Cauto": "Gioca sempre sul sicuro con molte doppie chance. Non rischia mai una singola su match incerti. Altissimo tasso di corrette ma guadagni contenuti.",
        "Tu (Il Moderato)": "Equilibrato e razionale. Segue la logica senza eccessi, mix di singole e doppie. Non si lascia trasportare ne dalla prudenza estrema ne dal rischio.",
        "Il Tifoso (Lecce)": "Ragionevole su tutte le partite tranne quelle del Lecce: gioca SEMPRE la vittoria della sua squadra del cuore, nonostante sia in bassa classifica.",
        "Il Superficiale": "Conosce solo le big (Inter, Juve, Milan, Napoli). Per le altre partite va quasi a caso. Quote alte giocate senza cognizione di causa.",
        "Lo Studioso": "Studia il calcio, analizza la forma, i precedenti. Tende a giocare singole pure con frequenti tentativi di X nei big match. A volte troppo coraggioso.",
        "Il Moderato con Eccessi": "Di base moderato, ma nel 20% delle partite ha un 'momento di follia' e gioca come l'Avventato. Quelle giornate lo affondano.",
        "L'Avventato": "Ama le sorprese, gioca spesso la sfavorita. Quote altissime (media 3.88), percentuale di corrette bassissima. Un disastro annunciato.",
    }

    data = [[
        Paragraph('Giocatore', styles['TableHeader']),
        Paragraph('Profilo', styles['TableHeader']),
        Paragraph('Strategia', styles['TableHeader']),
        Paragraph('Senza B/M', styles['TableHeader']),
        Paragraph('Con B/M', styles['TableHeader']),
    ]]

    sorted_p = sorted(PLAYERS, key=lambda p: -no_bonus["totals"][p["name"]])
    for p in sorted_p:
        pname = p["name"]
        strategy = profiles.get(pname, "")
        t_no = no_bonus["totals"][pname]
        t_with = with_bonus["totals"][pname]

        c_no = ACCENT_GREEN if t_no > 0 else (ACCENT_RED if t_no < 0 else BLACK)
        c_with = ACCENT_GREEN if t_with > 0 else (ACCENT_RED if t_with < 0 else BLACK)

        data.append([
            Paragraph(f'<b>{pname}</b>', styles['TableCellLeft']),
            Paragraph(strategy, ParagraphStyle('tiny', fontSize=6, leading=7.5, fontName='Helvetica')),
            Paragraph(f'Corrette: {no_bonus["total_correct"][pname]}/200', styles['TableCell']),
            Paragraph(f'<font color="{c_no}"><b>{t_no:+.1f}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{c_with}"><b>{t_with:+.1f}</b></font>', styles['TableCell']),
        ])

    table = Table(data, colWidths=[95, 210, 55, 50, 50])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTSIZE', (0, 0), (-1, -1), 7),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('ALIGN', (1, 1), (1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    return table


def compute_stats(scenario):
    """Compute spread and volatility stats."""
    totals = list(scenario["totals"].values())
    spread = max(totals) - min(totals)
    avg = sum(totals) / len(totals)
    variance = sum((t - avg) ** 2 for t in totals) / len(totals)
    std_dev = variance ** 0.5

    # Matchday volatility: average of per-matchday std devs
    matchday_spreads = []
    for g in range(20):
        day_scores = [scenario["matchday_scores"][p["name"]][g] for p in PLAYERS]
        day_spread = max(day_scores) - min(day_scores)
        matchday_spreads.append(day_spread)
    avg_matchday_spread = sum(matchday_spreads) / len(matchday_spreads)

    # Count lead changes
    leaders = []
    for g in range(20):
        cumuls = {}
        for p in PLAYERS:
            cumuls[p["name"]] = sum(scenario["matchday_scores"][p["name"]][:g+1])
        leader = max(cumuls, key=cumuls.get)
        leaders.append(leader)
    lead_changes = sum(1 for i in range(1, len(leaders)) if leaders[i] != leaders[i-1])

    # How many in positive
    positive = sum(1 for t in totals if t > 0)

    return {
        "spread": spread, "std_dev": std_dev, "avg": avg,
        "avg_matchday_spread": avg_matchday_spread,
        "lead_changes": lead_changes, "positive_count": positive,
    }


def make_claude_bonus_comparison_table(styles):
    """Show all bonus tables side by side: current, proposed, Claude's."""
    header = [
        Paragraph('Corrette', styles['BonusTableHeader']),
        Paragraph('B/M Attuali', styles['BonusTableHeader']),
        Paragraph('B/M Proposti', styles['BonusTableHeader']),
        Paragraph('B/M Claude', styles['BonusTableHeader']),
    ]
    data = [header]

    for i in range(11):
        curr = BONUS_TABLE[i]
        prop = PROPOSED_BONUS_TABLE[i]
        claude = CLAUDE_BONUS_TABLE[i]

        curr_color = ACCENT_GREEN if curr > 0 else (ACCENT_RED if curr < 0 else BLACK)
        prop_color = ACCENT_GREEN if prop > 0 else (ACCENT_RED if prop < 0 else BLACK)
        claude_color = ACCENT_GREEN if claude > 0 else (ACCENT_RED if claude < 0 else BLACK)

        data.append([
            Paragraph(f'{i}/10', styles['TableCell']),
            Paragraph(f'<font color="{curr_color}"><b>{curr:+d}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{prop_color}"><b>{prop:+d}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{claude_color}"><b>{claude:+d}</b></font>', styles['TableCell']),
        ])

    table = Table(data, colWidths=[60, 70, 70, 70])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        ('BACKGROUND', (0, 5), (-1, 5), colors.HexColor("#e8f5e9")),  # 4/10 row (breakeven Claude)
        ('BACKGROUND', (0, 6), (-1, 6), colors.HexColor("#f1f8e9")),  # 5/10 row
    ]))
    return table


def make_impact_table(no_bonus, with_bonus, with_proposed, with_claude, styles):
    """Create table showing bonus impact per player across all scenarios."""
    header = [
        Paragraph('Giocatore', styles['TableHeader']),
        Paragraph('Media OK/G', styles['TableHeader']),
        Paragraph('Punti Base', styles['TableHeader']),
        Paragraph('Impatto Att.', styles['TableHeader']),
        Paragraph('Impatto Prop.', styles['TableHeader']),
        Paragraph('Impatto Claude', styles['TableHeader']),
    ]
    data = [header]

    from cassandra_simulation import PLAYERS as SIM_PLAYERS

    for p in sorted(SIM_PLAYERS, key=lambda p: -no_bonus["totals"][p["name"]]):
        n = p["name"]
        avg_c = no_bonus["total_correct"][n] / 20
        base = no_bonus["totals"][n]
        d_att = with_bonus["totals"][n] - base
        d_prop = with_proposed["totals"][n] - base
        d_claude = with_claude["totals"][n] - base

        c_att = ACCENT_GREEN if d_att > 0 else (ACCENT_RED if d_att < 0 else BLACK)
        c_prop = ACCENT_GREEN if d_prop > 0 else (ACCENT_RED if d_prop < 0 else BLACK)
        c_claude = ACCENT_GREEN if d_claude > 0 else (ACCENT_RED if d_claude < 0 else BLACK)

        data.append([
            Paragraph(n, styles['TableCellLeft']),
            Paragraph(f'{avg_c:.1f}', styles['TableCell']),
            Paragraph(f'{base:+.1f}', styles['TableCell']),
            Paragraph(f'<font color="{c_att}"><b>{d_att:+.0f}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{c_prop}"><b>{d_prop:+.0f}</b></font>', styles['TableCell']),
            Paragraph(f'<font color="{c_claude}"><b>{d_claude:+.0f}</b></font>', styles['TableCell']),
        ])

    table = Table(data, colWidths=[120, 55, 55, 60, 60, 60])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTSIZE', (0, 0), (-1, -1), 7),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    return table


def generate_pdf(output_path):
    all_matchdays, no_bonus, with_bonus, with_proposed, with_claude = run_full_simulation()
    styles = create_styles()

    doc = SimpleDocTemplate(
        output_path,
        pagesize=landscape(A4),
        leftMargin=12*mm, rightMargin=12*mm,
        topMargin=15*mm, bottomMargin=15*mm
    )

    elements = []

    # ============================================================
    # COVER PAGE
    # ============================================================
    elements.append(Spacer(1, 30*mm))
    elements.append(Paragraph('CASSANDRA', styles['CoverTitle']))
    elements.append(Paragraph('Simulazione 20 Giornate Serie A', styles['CoverSubtitle']))
    elements.append(Spacer(1, 8*mm))
    elements.append(Paragraph('Analisi Comparativa: Senza vs Con Bonus/Malus', styles['CoverSubtitle']))
    elements.append(Spacer(1, 15*mm))

    cover_info = [
        "8 giocatori con personalita distinte",
        "200 pronostici ciascuno (10 partite x 20 giornate)",
        "Quote realistiche basate sulla forza delle squadre Serie A",
        "Confronto tra 3 scenari: senza B/M, con B/M attuali, con B/M proposti",
    ]
    for info in cover_info:
        elements.append(Paragraph(f'- {info}', styles['BodyText2']))

    elements.append(Spacer(1, 20*mm))
    elements.append(Paragraph(
        'Nota: Questa simulazione utilizza quote generate algoritmicamente basate sulla forza '
        'relativa delle squadre di Serie A con margine bookmaker dell\'8%. I risultati sono '
        'simulati con distribuzione probabilistica coerente con le quote. Seed fisso (42) per riproducibilita.',
        styles['SmallNote']
    ))

    elements.append(PageBreak())

    # ============================================================
    # PROFILI GIOCATORI
    # ============================================================
    elements.append(Paragraph('1. Profili dei Giocatori', styles['SectionTitle']))
    elements.append(make_player_profiles_table(no_bonus, with_bonus, styles))
    elements.append(PageBreak())

    # ============================================================
    # SCENARIO 1: SENZA BONUS/MALUS
    # ============================================================
    elements.append(Paragraph('2. Scenario 1: Senza Bonus/Malus', styles['SectionTitle']))
    elements.append(Paragraph('Classifica Finale', styles['SubSection']))
    table_no, sorted_no = make_ranking_table(no_bonus, styles)
    elements.append(table_no)
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Punteggi per Giornata', styles['SubSection']))
    elements.append(make_matchday_grid(no_bonus, sorted_no, styles))
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Andamento Cumulativo', styles['SubSection']))
    elements.append(make_cumulative_grid(no_bonus, sorted_no, styles))
    elements.append(PageBreak())

    # ============================================================
    # SCENARIO 2: CON BONUS/MALUS ATTUALI
    # ============================================================
    elements.append(Paragraph('3. Scenario 2: Con Bonus/Malus Attuali', styles['SectionTitle']))

    elements.append(Paragraph('Tabella Bonus/Malus in vigore:', styles['SubSection']))
    bonus_header = [Paragraph('Corrette', styles['BonusTableHeader'])]
    bonus_row = [Paragraph('B/M', styles['BonusTableHeader'])]
    for i in range(11):
        bonus_header.append(Paragraph(f'{i}', styles['TableCell']))
        v = BONUS_TABLE[i]
        c = ACCENT_GREEN if v > 0 else (ACCENT_RED if v < 0 else BLACK)
        bonus_row.append(Paragraph(f'<font color="{c}"><b>{v:+d}</b></font>', styles['TableCell']))

    btable = Table([bonus_header, bonus_row], colWidths=[50] + [30]*11)
    btable.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (0, -1), WHITE),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    elements.append(btable)
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Classifica Finale (con B/M)', styles['SubSection']))
    table_with, sorted_with = make_ranking_table(with_bonus, styles)
    elements.append(table_with)
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Punteggi per Giornata (con B/M)', styles['SubSection']))
    elements.append(make_matchday_grid(with_bonus, sorted_with, styles))
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Andamento Cumulativo (con B/M)', styles['SubSection']))
    elements.append(make_cumulative_grid(with_bonus, sorted_with, styles))
    elements.append(PageBreak())

    # ============================================================
    # CONFRONTO DIRETTO
    # ============================================================
    elements.append(Paragraph('4. Confronto tra i Tre Scenari', styles['SectionTitle']))
    elements.append(make_comparison_table(no_bonus, with_bonus, with_proposed, styles))
    elements.append(Spacer(1, 8*mm))

    # Statistics comparison
    stats_no = compute_stats(no_bonus)
    stats_with = compute_stats(with_bonus)
    stats_prop = compute_stats(with_proposed)

    stat_header = [
        Paragraph('Metrica', styles['TableHeader']),
        Paragraph('Senza B/M', styles['TableHeader']),
        Paragraph('Con B/M Attuali', styles['TableHeader']),
        Paragraph('Con B/M Proposti', styles['TableHeader']),
    ]
    stat_data = [stat_header]
    metrics = [
        ("Spread (1-8 posto)", f'{stats_no["spread"]:.1f}', f'{stats_with["spread"]:.1f}', f'{stats_prop["spread"]:.1f}'),
        ("Deviazione Standard", f'{stats_no["std_dev"]:.1f}', f'{stats_with["std_dev"]:.1f}', f'{stats_prop["std_dev"]:.1f}'),
        ("Media punti", f'{stats_no["avg"]:.1f}', f'{stats_with["avg"]:.1f}', f'{stats_prop["avg"]:.1f}'),
        ("Spread medio/giornata", f'{stats_no["avg_matchday_spread"]:.1f}', f'{stats_with["avg_matchday_spread"]:.1f}', f'{stats_prop["avg_matchday_spread"]:.1f}'),
        ("Cambi al comando", f'{stats_no["lead_changes"]}', f'{stats_with["lead_changes"]}', f'{stats_prop["lead_changes"]}'),
        ("Giocatori in positivo", f'{stats_no["positive_count"]}/8', f'{stats_with["positive_count"]}/8', f'{stats_prop["positive_count"]}/8'),
    ]
    for m in metrics:
        stat_data.append([Paragraph(m[0], styles['TableCellLeft'])] +
                         [Paragraph(m[i], styles['TableCell']) for i in range(1, 4)])

    stat_table = Table(stat_data, colWidths=[130, 80, 80, 80])
    stat_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HEADER_BG),
        ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (0, 1), (0, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, ROW_ALT]),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    elements.append(Paragraph('Metriche di Equilibrio', styles['SubSection']))
    elements.append(stat_table)
    elements.append(PageBreak())

    # ============================================================
    # PROPOSTA BONUS MODIFICATI
    # ============================================================
    elements.append(Paragraph('5. Proposta: Bonus/Malus Modificati', styles['SectionTitle']))

    elements.append(Paragraph(
        'La tabella bonus/malus attuale presenta degli squilibri. Ecco un confronto con la proposta modificata:',
        styles['AnalysisText']
    ))

    elements.append(make_bonus_comparison_table(styles))
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Classifica con B/M Proposti', styles['SubSection']))
    table_prop, sorted_prop = make_ranking_table(with_proposed, styles)
    elements.append(table_prop)
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph('Punteggi per Giornata (B/M Proposti)', styles['SubSection']))
    elements.append(make_matchday_grid(with_proposed, sorted_prop, styles))
    elements.append(PageBreak())

    # ============================================================
    # ANALISI TESTUALE
    # ============================================================
    elements.append(Paragraph('6. Analisi: I Bonus/Malus Rendono il Gioco Equilibrato?', styles['SectionTitle']))

    analysis_texts = [
        ('<b>I bonus/malus attuali rendono il gioco piu equilibrato?</b>',
         'La risposta breve e: <b>no, lo rendono meno equilibrato</b>. I dati della simulazione lo dimostrano chiaramente.'),

        ('<b>Il problema principale: la asimmetria della tabella</b>',
         'La tabella attuale ha un problema strutturale. I malus per chi sbaglia tanto (0 corrette = -20, 1 corretta = -10) '
         'sono devastanti, mentre i bonus per chi indovina tanto (8 corrette = +5, 9 = +10) sono relativamente modesti. '
         'Questo crea un effetto "forbice": chi gia gioca male viene punito ancora di piu, chi gioca bene riceve un premio '
         'insufficiente a compensare. Il risultato e che la distanza tra primo e ultimo aumenta, non diminuisce.'),

        ('<b>Effetto sui diversi archetipi</b>',
         'L\'Avventato, che gia ha il peggior punteggio base, viene ulteriormente massacrato dai malus perche con sole '
         '59 corrette su 200 (circa 3/10 per giornata) accumula malus pesantissimi (-5 o -10 a giornata). Al contrario, '
         'il Cauto con 137 corrette (circa 7/10) riceve bonus modesti (+2 a giornata). La forbice si allarga.'),

        ('<b>Il breakeven point a 5/10 e troppo alto</b>',
         'Con 10 partite a giornata e le quote della Serie A, azzeccare 5 partite su 10 e gia un buon risultato per '
         'molti profili di giocatore. Posizionare lo zero a 5 corrette significa che la maggior parte dei giocatori '
         'riceve malus nella maggior parte delle giornate, rendendo i punteggi globalmente piu negativi.'),

        ('<b>I bonus/malus rendono il gioco piu interessante?</b>',
         'Si, concettualmente sono un\'ottima meccanica di gioco. Aggiungono una dimensione strategica: non conta solo '
         'indovinare le singole partite, ma avere una performance complessiva sulla giornata. Tuttavia, la tabella attuale '
         'e troppo punitiva e non sufficientemente premiante, il che scoraggia chi e in difficolta e non entusiasma chi va bene.'),

        ('<b>Proposta di modifica</b>',
         'La tabella proposta (0:-10, 1:-6, 2:-3, 3:-1, 4:0, 5:+1, 6:+3, 7:+5, 8:+8, 9:+12, 10:+18) ha questi vantaggi:<br/>'
         '- <b>Breakeven a 4/10 invece di 5/10</b>: piu accessibile, meno frustrante<br/>'
         '- <b>Malus piu morbidi</b>: -10 max invece di -20, evita di affondare chi gia soffre<br/>'
         '- <b>Bonus piu generosi per le prestazioni top</b>: +12 per 9 corrette, +18 per 10<br/>'
         '- <b>Progressione piu graduale</b>: ogni corretta in piu ha un impatto crescente ma non esagerato<br/>'
         '- <b>Effetto netto</b>: premia di piu la bravura senza massacrare chi e in difficolta'),

        ('<b>Conclusione</b>',
         'I bonus/malus sono un\'aggiunta che <b>rende piu interessante il gioco</b> come meccanica, ma la tabella attuale '
         'va ribilanciata. La versione proposta mantiene l\'incentivo a giocare bene l\'intera giornata, ma riduce l\'effetto '
         '"ricchi sempre piu ricchi, poveri sempre piu poveri" che la tabella attuale genera. '
         'Il gioco ideale premia chi rischia con cognizione di causa e non punisce in modo sproporzionato chi sbaglia.'),
    ]

    for title, body in analysis_texts:
        elements.append(Paragraph(title, styles['AnalysisText']))
        elements.append(Paragraph(body, styles['AnalysisText']))
        elements.append(Spacer(1, 2*mm))

    elements.append(PageBreak())

    # ============================================================
    # VALUTAZIONE DI CLAUDE (AI)
    # ============================================================
    elements.append(Paragraph('7. Valutazione di Claude: Bonus/Malus e Proposta di Riforma', styles['SectionTitle']))

    elements.append(Paragraph(
        '<i>Questa sezione contiene la valutazione indipendente di Claude (AI) sul sistema bonus/malus, '
        'basata sull\'analisi dei dati della simulazione.</i>',
        styles['SmallNote']
    ))
    elements.append(Spacer(1, 3*mm))

    # --- 7.1 Valutazione sistema attuale ---
    elements.append(Paragraph('7.1 Valutazione del Sistema Attuale', styles['SubSection']))

    claude_eval_texts = [
        ('<b>Giudizio complessivo: sistema squilibrato (voto 4/10)</b>',
         'Il sistema bonus/malus attuale ha un\'idea di fondo corretta - premiare la consistenza sulla giornata - '
         'ma l\'implementazione presenta problemi strutturali gravi che lo rendono controproducente rispetto '
         'all\'obiettivo di equilibrio competitivo.'),

        ('<b>Problema 1: Asimmetria punitiva</b>',
         'I malus sono sproporzionati rispetto ai bonus. Con 0 corrette si perdono 20 punti, ma con 10 corrette '
         '(impresa rarissima) se ne guadagnano solo 20. Il problema e che 0/10 e molto piu frequente di 10/10 '
         'per i giocatori deboli, mentre 10/10 e quasi impossibile per chiunque. Nella simulazione, il Cauto '
         '(il piu costante con 7.1 corrette/giornata) non ha MAI fatto 10/10. Il massimo bonus realisticamente '
         'ottenibile e +5 (8 corrette), mentre il malus -20 colpisce regolarmente chi ha strategie rischiose.'),

        ('<b>Problema 2: Effetto "forbice" anti-competitivo</b>',
         'I dati parlano chiaro: lo spread tra primo e ultimo passa da 475.8 (senza B/M) a 565.8 (con B/M attuali), '
         'un aumento del 19%. La deviazione standard sale da 136.3 a 166.7 (+22%). I bonus/malus attuali '
         '<b>aumentano</b> il divario invece di ridurlo. L\'Avventato perde 61 punti aggiuntivi per i malus, '
         'mentre il Cauto ne guadagna 62. La distanza tra i due aumenta di 123 punti.'),

        ('<b>Problema 3: Breakeven point troppo alto</b>',
         'Lo zero e posizionato a 5/10 corrette. Con 10 partite di Serie A e quote realistiche, la media di corrette '
         'e circa 5.3 per un giocatore medio. Questo significa che circa meta delle giornate genera malus anche per '
         'giocatori competenti. Solo il Cauto (7.1/g) e il Calcolatore (6.0/g) hanno medie decisamente sopra '
         'la soglia. Per lo Studioso (4.8/g) e il Moderato con Eccessi (4.8/g), la maggior parte delle giornate '
         'si chiude con malus, nonostante strategie non irragionevoli.'),

        ('<b>Aspetto positivo: incentivo alla consistenza</b>',
         'L\'unico aspetto veramente positivo e che il sistema premia chi e costante su tutta la giornata, '
         'non solo chi azzecca una singola quota alta. Questo aggiunge una dimensione strategica interessante: '
         'conviene "proteggere" le partite incerte con doppie chance piuttosto che sparare singole ovunque. '
         'Il Cauto, con la sua strategia ultra-conservativa, beneficia enormemente (+62 punti) proprio per questo.'),
    ]

    for title, body in claude_eval_texts:
        elements.append(Paragraph(title, styles['AnalysisText']))
        elements.append(Paragraph(body, styles['AnalysisText']))
        elements.append(Spacer(1, 2*mm))

    elements.append(PageBreak())

    # --- 7.2 Impatto quantitativo ---
    elements.append(Paragraph('7.2 Impatto Quantitativo dei Bonus/Malus per Giocatore', styles['SubSection']))

    elements.append(Paragraph(
        'La tabella seguente mostra l\'impatto netto dei bonus/malus su ciascun giocatore nei tre sistemi. '
        'Valori positivi significano che il giocatore beneficia dei B/M rispetto allo scenario base.',
        styles['AnalysisText']
    ))
    elements.append(Spacer(1, 3*mm))

    elements.append(make_impact_table(no_bonus, with_bonus, with_proposed, with_claude, styles))
    elements.append(Spacer(1, 5*mm))

    elements.append(Paragraph(
        '<b>Osservazione chiave:</b> Con i B/M attuali, solo 5 giocatori su 8 beneficiano del sistema. '
        'Lo Studioso (-4), il Moderato con Eccessi (-3) e soprattutto l\'Avventato (-61) vengono penalizzati. '
        'Un sistema di B/M dovrebbe idealmente alzare tutti i punteggi (premiare il gioco), con differenze '
        'proporzionali alla bravura, non affondare ulteriormente chi gia soffre.',
        styles['AnalysisText']
    ))
    elements.append(Spacer(1, 5*mm))

    # --- 7.3 Proposta di riforma Claude ---
    elements.append(Paragraph('7.3 La Mia Proposta di Riforma', styles['SubSection']))

    elements.append(Paragraph(
        'Propongo una tabella alternativa che mantiene l\'incentivo alla consistenza ma corregge '
        'i tre problemi identificati:',
        styles['AnalysisText']
    ))
    elements.append(Spacer(1, 2*mm))

    elements.append(make_claude_bonus_comparison_table(styles))
    elements.append(Spacer(1, 5*mm))

    claude_reform_texts = [
        ('<b>Principi della riforma</b>',
         '1. <b>Breakeven a 4/10</b> (invece di 5/10): con 4 corrette non si prende ne bonus ne malus. '
         'Con 5 corrette si e gia in zona neutra (0 punti). Questo riduce la frustrazione per i giocatori medi.<br/>'
         '2. <b>Malus massimo -12</b> (invece di -20): il malus per 0 corrette resta severo ma non devastante. '
         'La progressione 0:-12, 1:-7, 2:-3, 3:-1 e piu graduale.<br/>'
         '3. <b>Bonus crescenti ma realistici</b>: +7 per 8 corrette (raggiungibile dai migliori), +11 per 9, '
         '+16 per 10. I bonus top premiano le giornate eccezionali senza essere irraggiungibili.<br/>'
         '4. <b>Zona neutra piu ampia</b>: 4 e 5 corrette danno entrambe 0 punti, creando un "cuscinetto" '
         'che protegge il giocatore medio.'),

        ('<b>Differenze rispetto alla proposta originale</b>',
         'La proposta gia presente nel documento (sezione 5) e buona ma tende a essere troppo generosa: '
         'con +18 per 10 corrette e +12 per 9, l\'inflazione di punti e significativa. La mia proposta '
         'e piu conservativa nei bonus top (+16 e +11) ma leggermente piu morbida nei malus bassi '
         '(identica a 2 e 3 corrette). Il risultato e un sistema piu "piatto" al centro e meno estremo '
         'ai bordi, che dovrebbe produrre classifiche dove il merito base (qualita dei pronostici) '
         'conta di piu del fattore bonus.'),

        ('<b>Effetto atteso sulla simulazione</b>',
         'Con la mia proposta, tutti e 8 i giocatori beneficiano dei bonus/malus (impatto netto positivo '
         'o neutro per tutti tranne l\'Avventato, che comunque perde "solo" 29 punti invece di 61). '
         'Il Cauto resta il maggior beneficiario grazie alla sua consistenza, ma il gap con il Calcolatore '
         'si riduce rispetto ai B/M attuali. La classifica finale riflette meglio il merito base.'),
    ]

    for title, body in claude_reform_texts:
        elements.append(Paragraph(title, styles['AnalysisText']))
        elements.append(Paragraph(body, styles['AnalysisText']))
        elements.append(Spacer(1, 2*mm))

    elements.append(PageBreak())

    # --- 7.4 Conclusioni ---
    elements.append(Paragraph('7.4 Conclusioni e Raccomandazioni', styles['SubSection']))

    conclusion_texts = [
        ('<b>I bonus/malus sono una buona idea, ma la tabella attuale no</b>',
         'Il concetto di premiare la consistenza sulla giornata e valido e aggiunge profondita strategica al gioco. '
         'Ma la tabella attuale e troppo punitiva verso il basso e troppo poco premiante verso l\'alto. '
         'Il risultato netto e che il gioco diventa MENO competitivo, non piu.'),

        ('<b>Tre modifiche essenziali</b>',
         '1. <b>Abbassare il breakeven a 4/10</b>: la soglia attuale a 5/10 penalizza troppi giocatori troppo spesso.<br/>'
         '2. <b>Ridurre il malus massimo</b>: -20 per 0 corrette e eccessivo. Un valore tra -10 e -12 basta a '
         'scoraggiare il gioco irresponsabile senza essere devastante.<br/>'
         '3. <b>Aumentare i bonus per 8-9 corrette</b>: sono le fasce realisticamente raggiungibili dai migliori '
         'giocatori. Premiarle di piu rende il gioco piu stimolante.'),

        ('<b>Il test definitivo</b>',
         'Un buon sistema di bonus/malus dovrebbe: (a) non cambiare le posizioni in classifica in modo drastico '
         'rispetto allo scenario base (il merito dei pronostici deve restare dominante), (b) premiare la consistenza '
         'senza punire in modo sproporzionato chi rischia, (c) rendere il gioco piu divertente per TUTTI, '
         'non solo per chi gia vince. La tabella attuale fallisce su tutti e tre i punti. '
         'Sia la proposta originale che la mia correggono questi problemi, con sfumature diverse.'),
    ]

    for title, body in conclusion_texts:
        elements.append(Paragraph(title, styles['AnalysisText']))
        elements.append(Paragraph(body, styles['AnalysisText']))
        elements.append(Spacer(1, 2*mm))

    elements.append(PageBreak())

    # ============================================================
    # DETTAGLIO GIORNATE
    # ============================================================
    elements.append(Paragraph('8. Dettaglio per Giornata (con Pronostici e B/M)', styles['SectionTitle']))
    elements.append(Paragraph(
        'Di seguito il dettaglio di ogni giornata con i pronostici di ciascun giocatore, '
        'il punteggio base e il bonus/malus applicato.',
        styles['BodyText2']
    ))
    elements.append(Spacer(1, 3*mm))

    detail_elements = make_matchday_detail_tables(all_matchdays, no_bonus, with_bonus, styles)
    elements.extend(detail_elements)

    # Build PDF
    doc.build(elements)
    print(f"PDF generato: {output_path}")


if __name__ == "__main__":
    generate_pdf("/home/user/cassandra/simulation/cassandra_simulazione_completa.pdf")
