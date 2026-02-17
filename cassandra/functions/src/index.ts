import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineString } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as https from "https";

initializeApp();

const apiFootballKey = defineString("API_FOOTBALL_KEY");
const apiFootballBaseUrl = defineString("API_FOOTBALL_BASE_URL", {
  default: "https://v3.football.api-sports.io",
});

// ─── Types ───────────────────────────────────────────────────────────────────

interface ApiFixture {
  fixtureId: number;
  kickoffUtc: string; // ISO-8601
  homeName: string;
  awayName: string;
  homeLogo: string | null;
  awayLogo: string | null;
  statusShort: string;
  homeGoals: number | null;
  awayGoals: number | null;
  round: string | null;
}

interface FixtureOdds {
  home: number | null;
  draw: number | null;
  away: number | null;
  homeDraw: number | null;
  drawAway: number | null;
  homeAway: number | null;
}

interface MatchDoc {
  id: string;
  kickoff: string; // ISO-8601
  home: string;
  away: string;
  homeLogo?: string;
  awayLogo?: string;
  homeGoals?: number | null;
  awayGoals?: number | null;
  statusShort?: string;
  events?: MatchEventDoc[];
  odds: {
    home: number;
    draw: number;
    away: number;
    homeDraw: number;
    drawAway: number;
    homeAway: number;
  };
}

interface MatchEventDoc {
  minute: number;
  extraMinute?: number | null;
  type: string;
  detail?: string;
  teamName?: string;
  playerName?: string;
  assistName?: string;
}

type Outcome = "home" | "draw" | "away" | "pending" | "voided";
type PickOptionValue =
  | "none"
  | "home"
  | "draw"
  | "away"
  | "homeDraw"
  | "drawAway"
  | "homeAway";

interface PicksScoreDoc {
  baseTotal: number;
  bonusPoints: number;
  total: number;
  correctCount: number;
  averageOddsPlayed?: number;
}

interface ScoringMatchDoc {
  id: string;
  odds: {
    home: number;
    draw: number;
    away: number;
    homeDraw: number;
    drawAway: number;
    homeAway: number;
  };
}

interface StandingDoc {
  rank: number;
  teamName: string;
  teamLogo: string | null;
  played: number;
  wins: number;
  draws: number;
  losses: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDiff: number;
  points: number;
  form: string | null;
}

// Preferred bookmaker IDs (Bet365, Bwin, 1xBet, 10Bet)
const PREFERRED_BOOKMAKER_IDS = [8, 6, 11, 1];

// ─── API-Football HTTP client ────────────────────────────────────────────────

function apiGet(
  endpoint: string,
  query: Record<string, string>
): Promise<Record<string, unknown>> {
  const baseUrl = apiFootballBaseUrl.value();
  const url = new URL(`/${endpoint}`, baseUrl);
  for (const [k, v] of Object.entries(query)) {
    url.searchParams.set(k, v);
  }

  return new Promise((resolve, reject) => {
    const options: https.RequestOptions = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: "GET",
      headers: {
        "x-apisports-key": apiFootballKey.value(),
      },
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk: string) => (data += chunk));
      res.on("end", () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          reject(new Error(`Failed to parse API response for ${endpoint}`));
        }
      });
    });

    req.on("error", reject);
    req.end();
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function seasonStartYear(): number {
  const now = new Date();
  return now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1;
  // JS months: 0=Jan ... 6=Jul. month>=7 in plan → >=6 in 0-indexed
}

function normalizeSerieATeamName(rawName: string): string {
  const name = rawName.trim();
  switch (name.toLowerCase()) {
  case "as roma":
    return "Roma";
  case "ac milan":
    return "Milan";
  default:
    return name;
  }
}

function matchdayFromRound(round: string | null): number | null {
  if (!round) return null;
  const m = round.trim().match(/(\d{1,2})\s*$/);
  if (!m) return null;
  return parseInt(m[1], 10);
}

function parseFixtures(json: Record<string, unknown>): ApiFixture[] {
  const response = json["response"];
  if (!Array.isArray(response)) return [];

  return response
    .filter((e): e is Record<string, unknown> => typeof e === "object" && e !== null)
    .map((e) => {
      const fixture = (e["fixture"] as Record<string, unknown>) ?? {};
      const teams = (e["teams"] as Record<string, unknown>) ?? {};
      const goals = (e["goals"] as Record<string, unknown>) ?? {};
      const league = (e["league"] as Record<string, unknown>) ?? {};

      const home = (teams["home"] as Record<string, unknown>) ?? {};
      const away = (teams["away"] as Record<string, unknown>) ?? {};
      const status = (fixture["status"] as Record<string, unknown>) ?? {};

      return {
        fixtureId: Number(fixture["id"]) || 0,
        kickoffUtc: String(fixture["date"] ?? ""),
        homeName: normalizeSerieATeamName(String(home["name"] ?? "Home")),
        awayName: normalizeSerieATeamName(String(away["name"] ?? "Away")),
        homeLogo: home["logo"] ? String(home["logo"]) : null,
        awayLogo: away["logo"] ? String(away["logo"]) : null,
        statusShort: String(status["short"] ?? ""),
        homeGoals:
          goals["home"] != null ? Number(goals["home"]) : null,
        awayGoals:
          goals["away"] != null ? Number(goals["away"]) : null,
        round: league["round"] ? String(league["round"]) : null,
      } as ApiFixture;
    });
}

function parseStandings(json: Record<string, unknown>): StandingDoc[] {
  const response = json["response"];
  if (!Array.isArray(response) || response.length === 0) return [];

  const first = response[0];
  if (typeof first !== "object" || first == null) return [];

  const league = (first as Record<string, unknown>)["league"];
  if (typeof league !== "object" || league == null) return [];

  const standings = (league as Record<string, unknown>)["standings"];
  if (!Array.isArray(standings) || standings.length === 0) return [];

  const group = standings[0];
  if (!Array.isArray(group)) return [];

  const asInt = (v: unknown): number =>
    typeof v === "number" ? Math.trunc(v) : Number(v) || 0;

  return group
    .filter((e): e is Record<string, unknown> => typeof e === "object" && e !== null)
    .map((entry) => {
      const team = (entry["team"] as Record<string, unknown> | undefined) ?? {};
      const all = (entry["all"] as Record<string, unknown> | undefined) ?? {};
      const goals =
        (all["goals"] as Record<string, unknown> | undefined) ?? {};

      return {
        rank: asInt(entry["rank"]),
        teamName: normalizeSerieATeamName(String(team["name"] ?? "?")),
        teamLogo: team["logo"] ? String(team["logo"]) : null,
        played: asInt(all["played"]),
        wins: asInt(all["win"]),
        draws: asInt(all["draw"]),
        losses: asInt(all["lose"]),
        goalsFor: asInt(goals["for"]),
        goalsAgainst: asInt(goals["against"]),
        goalDiff: asInt(entry["goalsDiff"]),
        points: asInt(entry["points"]),
        form: entry["form"] ? String(entry["form"]) : null,
      };
    });
}

function computeOutcome(f: ApiFixture): Outcome {
  const s = f.statusShort.trim().toUpperCase();
  if (s === "CANC") return "voided";
  const finished = ["FT", "AET", "PEN", "WO", "AWD"].includes(s);
  if (!finished) return "pending";
  if (f.homeGoals == null || f.awayGoals == null) return "pending";
  if (f.homeGoals > f.awayGoals) return "home";
  if (f.homeGoals < f.awayGoals) return "away";
  return "draw";
}

function parseOutcomeValue(value: unknown): Outcome | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (normalized === "home") return "home";
  if (normalized === "draw") return "draw";
  if (normalized === "away") return "away";
  if (normalized === "pending") return "pending";
  if (normalized === "voided") return "voided";
  return null;
}

function parsePickOptionValue(value: unknown): PickOptionValue {
  if (typeof value !== "string") return "none";
  const normalized = value.trim();
  if (normalized === "home") return "home";
  if (normalized === "draw") return "draw";
  if (normalized === "away") return "away";
  if (normalized === "homeDraw") return "homeDraw";
  if (normalized === "drawAway") return "drawAway";
  if (normalized === "homeAway") return "homeAway";
  return "none";
}

const BONUS_BY_CORRECT_COUNT: Record<number, number> = {
  0: -20,
  1: -10,
  2: -5,
  3: -2,
  4: -1,
  5: 0,
  6: 1,
  7: 2,
  8: 5,
  9: 10,
  10: 20,
};

function bonusForCorrectCount(correctCount: number): number {
  const normalized = Math.max(0, Math.min(10, Math.trunc(correctCount)));
  return BONUS_BY_CORRECT_COUNT[normalized] ?? 0;
}

function max1X2(odds: ScoringMatchDoc["odds"]): number {
  return Math.max(odds.home, odds.draw, odds.away);
}

function oddsPlayedForPick(
  match: ScoringMatchDoc,
  pick: PickOptionValue
): number | null {
  switch (pick) {
  case "home":
    return match.odds.home;
  case "draw":
    return match.odds.draw;
  case "away":
    return match.odds.away;
  case "homeDraw":
    return match.odds.homeDraw;
  case "drawAway":
    return match.odds.drawAway;
  case "homeAway":
    return match.odds.homeAway;
  case "none":
    return null;
  }
}

function isCorrectSingle(pick: PickOptionValue, outcome: Outcome): boolean {
  return (
    (pick === "home" && outcome === "home") ||
    (pick === "draw" && outcome === "draw") ||
    (pick === "away" && outcome === "away")
  );
}

function isCorrectDouble(pick: PickOptionValue, outcome: Outcome): boolean {
  if (pick === "homeDraw") return outcome === "home" || outcome === "draw";
  if (pick === "drawAway") return outcome === "draw" || outcome === "away";
  if (pick === "homeAway") return outcome === "home" || outcome === "away";
  return false;
}

function wrongDoublePenaltySumSingles(
  match: ScoringMatchDoc,
  pick: PickOptionValue
): number {
  if (pick === "homeDraw") return match.odds.home + match.odds.draw;
  if (pick === "drawAway") return match.odds.draw + match.odds.away;
  if (pick === "homeAway") return match.odds.home + match.odds.away;
  return 0;
}

function parseScoringMatchesFromMatchdayData(
  data: Record<string, unknown>
): ScoringMatchDoc[] {
  const rawMatches = data["matches"];
  if (!Array.isArray(rawMatches)) return [];

  const matches: ScoringMatchDoc[] = [];
  for (const raw of rawMatches) {
    if (typeof raw !== "object" || raw == null) continue;
    const m = raw as Record<string, unknown>;
    const id = String(m["id"] ?? "").trim();
    if (!id) continue;
    const rawOdds = m["odds"];
    if (typeof rawOdds !== "object" || rawOdds == null) continue;
    const odds = rawOdds as Record<string, unknown>;
    const home = Number(odds["home"]);
    const draw = Number(odds["draw"]);
    const away = Number(odds["away"]);
    const homeDraw = Number(odds["homeDraw"]);
    const drawAway = Number(odds["drawAway"]);
    const homeAway = Number(odds["homeAway"]);

    if (
      !Number.isFinite(home) ||
      !Number.isFinite(draw) ||
      !Number.isFinite(away) ||
      !Number.isFinite(homeDraw) ||
      !Number.isFinite(drawAway) ||
      !Number.isFinite(homeAway)
    ) {
      continue;
    }

    matches.push({
      id,
      odds: {
        home,
        draw,
        away,
        homeDraw,
        drawAway,
        homeAway,
      },
    });
  }

  return matches;
}

function parseOutcomesByMatchIdFromMatchdayData(
  data: Record<string, unknown>
): Record<string, Outcome> {
  const rawOutcomes = data["outcomesByMatchId"];
  if (
    rawOutcomes == null ||
    typeof rawOutcomes !== "object" ||
    Array.isArray(rawOutcomes)
  ) {
    return {};
  }
  const out: Record<string, Outcome> = {};
  for (const [matchId, rawOutcome] of Object.entries(rawOutcomes)) {
    const parsed = parseOutcomeValue(rawOutcome);
    if (parsed != null) out[matchId] = parsed;
  }
  return out;
}

function parsePicksByMatchId(
  value: unknown
): Record<string, PickOptionValue> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  const out: Record<string, PickOptionValue> = {};
  for (const [matchId, rawPick] of Object.entries(value)) {
    out[matchId] = parsePickOptionValue(rawPick);
  }
  return out;
}

function parseStoredScore(value: unknown): PicksScoreDoc | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const baseTotal = Number(raw["baseTotal"]);
  const bonusPoints = Number(raw["bonusPoints"]);
  const total = Number(raw["total"]);
  const correctCount = Number(raw["correctCount"]);
  const averageRaw = raw["averageOddsPlayed"];
  const averageOddsPlayed =
    averageRaw == null ? undefined : Number(averageRaw);

  if (
    !Number.isFinite(baseTotal) ||
    !Number.isFinite(bonusPoints) ||
    !Number.isFinite(total) ||
    !Number.isFinite(correctCount)
  ) {
    return null;
  }

  const parsed: PicksScoreDoc = {
    baseTotal,
    bonusPoints: Math.trunc(bonusPoints),
    total,
    correctCount: Math.trunc(correctCount),
  };
  if (averageOddsPlayed != null && Number.isFinite(averageOddsPlayed)) {
    parsed.averageOddsPlayed = averageOddsPlayed;
  }
  return parsed;
}

function almostEqual(a: number, b: number): boolean {
  return Math.abs(a - b) <= 1e-6;
}

function isSameScore(a: PicksScoreDoc | null, b: PicksScoreDoc): boolean {
  if (a == null) return false;
  const aAvg = a.averageOddsPlayed;
  const bAvg = b.averageOddsPlayed;
  const sameAvg =
    (aAvg == null && bAvg == null) ||
    (aAvg != null && bAvg != null && almostEqual(aAvg, bAvg));
  return (
    almostEqual(a.baseTotal, b.baseTotal) &&
    a.bonusPoints === b.bonusPoints &&
    almostEqual(a.total, b.total) &&
    a.correctCount === b.correctCount &&
    sameAvg
  );
}

function computeScoreForPicks(
  matches: ScoringMatchDoc[],
  picksByMatchId: Record<string, PickOptionValue>,
  outcomesByMatchId: Record<string, Outcome>
): PicksScoreDoc {
  let baseTotal = 0;
  let correctCount = 0;
  const playedOdds: number[] = [];

  for (const match of matches) {
    const pick = picksByMatchId[match.id] ?? "none";
    const outcome = outcomesByMatchId[match.id] ?? "pending";
    const played = oddsPlayedForPick(match, pick);

    if (outcome === "pending") {
      if (played != null) playedOdds.push(played);
      continue;
    }

    if (outcome === "voided") {
      continue;
    }

    if (pick === "none") {
      baseTotal -= max1X2(match.odds);
      continue;
    }

    if (pick === "home" || pick === "draw" || pick === "away") {
      const singlePlayed = played ?? 0;
      const correct = isCorrectSingle(pick, outcome);
      baseTotal += correct ? singlePlayed : -singlePlayed;
      if (correct) correctCount += 1;
      playedOdds.push(singlePlayed);
      continue;
    }

    const doublePlayed = played ?? 0;
    const correct = isCorrectDouble(pick, outcome);
    if (correct) {
      baseTotal += doublePlayed;
      correctCount += 1;
    } else {
      baseTotal -= wrongDoublePenaltySumSingles(match, pick);
    }
    playedOdds.push(doublePlayed);
  }

  const allGraded = matches.every((m) => {
    const outcome = outcomesByMatchId[m.id];
    return outcome != null && outcome !== "pending";
  });
  const bonusPoints = allGraded ? bonusForCorrectCount(correctCount) : 0;
  const total = baseTotal + bonusPoints;
  const averageOddsPlayed =
    playedOdds.length === 0
      ? undefined
      : playedOdds.reduce((sum, v) => sum + v, 0) / playedOdds.length;

  const score: PicksScoreDoc = {
    baseTotal,
    bonusPoints,
    total,
    correctCount,
  };
  if (averageOddsPlayed != null) {
    score.averageOddsPlayed = averageOddsPlayed;
  }
  return score;
}

async function recomputePicksScoresForMatchday(
  db: FirebaseFirestore.Firestore,
  seasonKey: string,
  dayNumber: number,
  logPrefix: string
): Promise<void> {
  const matchdayRef = db
    .collection("seasons")
    .doc(seasonKey)
    .collection("matchdays")
    .doc(dayNumber.toString());
  const matchdaySnap = await matchdayRef.get();
  if (!matchdaySnap.exists) return;
  const matchdayData = matchdaySnap.data();
  if (!matchdayData) return;

  const matches = parseScoringMatchesFromMatchdayData(
    matchdayData as Record<string, unknown>
  );
  if (matches.length === 0) return;
  const outcomesByMatchId = parseOutcomesByMatchIdFromMatchdayData(
    matchdayData as Record<string, unknown>
  );
  const allGraded = matches.every((m) => {
    const outcome = outcomesByMatchId[m.id];
    return outcome != null && outcome !== "pending";
  });
  if (!allGraded) return;

  const picksSnap = await db
    .collection("picks")
    .where("seasonKey", "==", seasonKey)
    .where("dayNumber", "==", dayNumber)
    .get();
  if (picksSnap.empty) return;

  let batch = db.batch();
  let pendingWrites = 0;
  let updatedDocs = 0;

  for (const doc of picksSnap.docs) {
    const data = doc.data();
    const picksByMatchId = parsePicksByMatchId(data["picksByMatchId"]);
    const score = computeScoreForPicks(matches, picksByMatchId, outcomesByMatchId);
    const existingScore = parseStoredScore(data["score"]);
    if (isSameScore(existingScore, score)) continue;

    batch.set(
      doc.ref,
      { score, scoredAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    pendingWrites += 1;
    updatedDocs += 1;

    if (pendingWrites >= 400) {
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
    }
  }

  if (pendingWrites > 0) {
    await batch.commit();
  }

  if (updatedDocs > 0) {
    console.log(
      `[${logPrefix}] Recomputed picks scores for matchday ${dayNumber}: updated=${updatedDocs}`
    );
  }
}

function isInProgressStatus(rawStatus: string | null | undefined): boolean {
  const status = (rawStatus ?? "").trim().toUpperCase();
  return ["1H", "HT", "2H", "ET", "BT", "P", "INT", "LIVE"].includes(status);
}

function isFinalStatus(rawStatus: string | null | undefined): boolean {
  const status = (rawStatus ?? "").trim().toUpperCase();
  return ["FT", "AET", "PEN", "WO", "AWD", "CANC"].includes(status);
}

function hasWoodworkKeyword(raw: string): boolean {
  const s = raw.trim().toLowerCase();
  if (!s) return false;
  return (
    s.includes("woodwork") ||
    s.includes("crossbar") ||
    s.includes("post") ||
    s.includes("bar")
  );
}

function normalizeEventType(typeRaw: string, detailRaw: string, commentsRaw: string): string | null {
  const type = typeRaw.trim().toLowerCase();
  const detail = detailRaw.trim().toLowerCase();
  const comments = commentsRaw.trim().toLowerCase();

  if (type === "goal") {
    if (detail.includes("missed penalty")) return "penalty_missed";
    if (detail.includes("penalty")) return "penalty_scored";
    if (hasWoodworkKeyword(detail) || hasWoodworkKeyword(comments)) return "woodwork";
    return "goal";
  }
  if (type === "card") {
    if (detail.includes("red")) return "red_card";
    if (detail.includes("yellow")) return "yellow_card";
    return "card";
  }
  if (type === "subst") return "substitution";
  if (type === "var") return "var";
  if (hasWoodworkKeyword(detail) || hasWoodworkKeyword(comments)) return "woodwork";
  if (detail.includes("penalty")) return "penalty_event";
  return null;
}

function isRelevantEventType(normalizedType: string): boolean {
  return [
    "goal",
    "penalty_scored",
    "penalty_missed",
    "substitution",
    "yellow_card",
    "red_card",
    "card",
    "woodwork",
    "penalty_event",
  ].includes(normalizedType);
}

function round2(v: number): number {
  return Math.round(v * 100) / 100;
}

function clamp(v: number, min: number, max: number): number {
  if (max < min) return min;
  return Math.max(min, Math.min(max, v));
}

function buildMatchDoc(
  f: ApiFixture,
  odds: FixtureOdds | null,
  events: MatchEventDoc[] | null = null
): MatchDoc {
  // 1/X/2
  let home: number, draw: number, away: number;
  if (odds?.home != null && odds?.draw != null && odds?.away != null) {
    home = odds!.home!;
    draw = odds!.draw!;
    away = odds!.away!;
  } else {
    // Deterministic fallback (same logic as Flutter adapter)
    const seed = f.fixtureId;
    home = deterministicOdds(seed, 1.35, 3.10);
    draw = deterministicOdds(seed * 7 + 13, 2.70, 4.60);
    away = deterministicOdds(seed * 11 + 29, 1.35, 3.40);
  }

  // Double chance
  let homeDraw: number, drawAway: number, homeAway: number;
  if (
    odds?.homeDraw != null &&
    odds?.drawAway != null &&
    odds?.homeAway != null
  ) {
    homeDraw = odds!.homeDraw!;
    drawAway = odds!.drawAway!;
    homeAway = odds!.homeAway!;
  } else {
    // Derive from singles (same formula as Flutter)
    const p1 = 1.0 / home;
    const pX = 1.0 / draw;
    const p2 = 1.0 / away;
    const s = p1 + pX + p2;
    const dc = (a: number, b: number) => round2(s / (a + b));
    homeDraw = clamp(dc(p1, pX), 1.05, round2(Math.min(home, draw) - 0.01));
    drawAway = clamp(dc(pX, p2), 1.05, round2(Math.min(draw, away) - 0.01));
    homeAway = clamp(dc(p1, p2), 1.05, round2(Math.min(home, away) - 0.01));
  }

  const doc: MatchDoc = {
    id: f.fixtureId.toString(),
    kickoff: f.kickoffUtc,
    home: f.homeName,
    away: f.awayName,
    statusShort: f.statusShort,
    odds: { home, draw, away, homeDraw, drawAway, homeAway },
  };
  if (f.homeLogo) doc.homeLogo = f.homeLogo;
  if (f.awayLogo) doc.awayLogo = f.awayLogo;
  if (f.homeGoals != null) doc.homeGoals = f.homeGoals;
  if (f.awayGoals != null) doc.awayGoals = f.awayGoals;
  if (events != null) {
    doc.events = events;
  }
  return doc;
}

function mergeLiveFieldsIntoExistingMatches(
  existingMatches: unknown,
  fixtures: ApiFixture[],
  eventsByMatchId: Map<string, MatchEventDoc[]> | null = null
): Record<string, unknown>[] | null {
  if (!Array.isArray(existingMatches)) return null;

  const fixtureById = new Map<string, ApiFixture>();
  for (const f of fixtures) {
    fixtureById.set(f.fixtureId.toString(), f);
  }

  const updated = existingMatches
    .filter(
      (m): m is Record<string, unknown> => typeof m === "object" && m != null
    )
    .map((m) => {
      const id = String(m["id"] ?? "");
      const fixture = fixtureById.get(id);
      if (!fixture) return { ...m };

      const next: Record<string, unknown> = {
        ...m,
        statusShort: fixture.statusShort,
        homeGoals: fixture.homeGoals,
        awayGoals: fixture.awayGoals,
      };
      if (eventsByMatchId != null) {
        const events = eventsByMatchId.get(id);
        if (events != null) {
          next.events = events;
        }
      }

      return next;
    });

  return updated;
}

function deterministicOdds(seed: number, min: number, max: number): number {
  const n = (Math.abs(seed) % 1000) / 1000.0;
  return round2(min + (max - min) * n);
}

async function resolveLeagueId(
  season: number,
  db: FirebaseFirestore.Firestore
): Promise<number> {
  // Check Firestore cache
  const configRef = db.doc("config/apiFootball");
  const configSnap = await configRef.get();
  if (configSnap.exists) {
    const data = configSnap.data();
    if (data?.leagueId && data?.season === season) {
      return data.leagueId as number;
    }
  }

  // Resolve from API
  const json = await apiGet("leagues", {
    name: "Serie A",
    country: "Italy",
    season: season.toString(),
    type: "league",
  });

  const response = json["response"];
  if (!Array.isArray(response) || response.length === 0) {
    throw new Error(`Serie A league not found for season ${season}`);
  }

  const first = response[0] as Record<string, unknown>;
  const league = first["league"] as Record<string, unknown>;
  const id = league["id"] as number;

  // Cache in Firestore
  await configRef.set({ leagueId: id, season, updatedAt: FieldValue.serverTimestamp() });

  return id;
}

async function fetchOddsForFixture(fixtureId: number): Promise<FixtureOdds | null> {
  try {
    const json = await apiGet("odds", { fixture: fixtureId.toString() });
    const response = json["response"];
    if (!Array.isArray(response) || response.length === 0) return null;

    const entry = response[0] as Record<string, unknown>;
    const bookmakers = entry["bookmakers"];
    if (!Array.isArray(bookmakers) || bookmakers.length === 0) return null;

    // Find preferred bookmaker
    let chosen: Record<string, unknown> | null = null;
    for (const prefId of PREFERRED_BOOKMAKER_IDS) {
      chosen =
        (bookmakers.find(
          (b: unknown) => (b as Record<string, unknown>)["id"] === prefId
        ) as Record<string, unknown>) ?? null;
      if (chosen) break;
    }
    if (!chosen) chosen = bookmakers[0] as Record<string, unknown>;

    const bets = chosen["bets"];
    if (!Array.isArray(bets)) return null;

    const odds: FixtureOdds = {
      home: null,
      draw: null,
      away: null,
      homeDraw: null,
      drawAway: null,
      homeAway: null,
    };

    for (const bet of bets) {
      const b = bet as Record<string, unknown>;
      const betId = b["id"];
      const values = b["values"];
      if (!Array.isArray(values)) continue;

      if (betId === 1) {
        // Match Winner
        for (const v of values) {
          const val = v as Record<string, unknown>;
          const label = String(val["value"] ?? "");
          const odd = parseFloat(String(val["odd"] ?? ""));
          if (isNaN(odd)) continue;
          if (label === "Home") odds.home = odd;
          else if (label === "Draw") odds.draw = odd;
          else if (label === "Away") odds.away = odd;
        }
      } else if (betId === 12) {
        // Double Chance
        for (const v of values) {
          const val = v as Record<string, unknown>;
          const label = String(val["value"] ?? "");
          const odd = parseFloat(String(val["odd"] ?? ""));
          if (isNaN(odd)) continue;
          if (label === "Home/Draw") odds.homeDraw = odd;
          else if (label === "Home/Away") odds.homeAway = odd;
          else if (label === "Draw/Away") odds.drawAway = odd;
        }
      }
    }

    return odds;
  } catch (e) {
    console.warn(`Failed to fetch odds for fixture ${fixtureId}:`, e);
    return null;
  }
}

async function fetchEventsForFixture(
  fixtureId: number
): Promise<MatchEventDoc[] | null> {
  try {
    const json = await apiGet("fixtures/events", { fixture: fixtureId.toString() });
    const response = json["response"];
    if (!Array.isArray(response)) return null;

    const events = response
      .filter((e): e is Record<string, unknown> => typeof e === "object" && e !== null)
      .map((e) => {
        const time = (e["time"] as Record<string, unknown> | undefined) ?? {};
        const team = (e["team"] as Record<string, unknown> | undefined) ?? {};
        const player = (e["player"] as Record<string, unknown> | undefined) ?? {};
        const assist = (e["assist"] as Record<string, unknown> | undefined) ?? {};

        const typeRaw = String(e["type"] ?? "");
        const detailRaw = String(e["detail"] ?? "");
        const commentsRaw = String(e["comments"] ?? "");
        const normalizedType = normalizeEventType(typeRaw, detailRaw, commentsRaw);
        if (normalizedType == null || !isRelevantEventType(normalizedType)) {
          return null;
        }

        const elapsed = Number(time["elapsed"] ?? 0);
        const extraRaw = time["extra"];
        const extra = extraRaw == null ? null : Number(extraRaw);

        const out: MatchEventDoc = {
          minute: Number.isFinite(elapsed) ? Math.trunc(elapsed) : 0,
          type: normalizedType,
        };

        if (extra != null && Number.isFinite(extra)) {
          out.extraMinute = Math.trunc(extra);
        }
        if (detailRaw.trim()) out.detail = detailRaw.trim();
        const teamName = team["name"] ? String(team["name"]).trim() : "";
        const playerName = player["name"] ? String(player["name"]).trim() : "";
        const assistName = assist["name"] ? String(assist["name"]).trim() : "";
        if (teamName) out.teamName = normalizeSerieATeamName(teamName);
        if (playerName) out.playerName = playerName;
        if (assistName) out.assistName = assistName;
        return out;
      })
      .filter((e): e is MatchEventDoc => e !== null)
      .sort((a, b) => {
        if (a.minute != b.minute) return a.minute - b.minute;
        const aExtra = a.extraMinute ?? 0;
        const bExtra = b.extraMinute ?? 0;
        return aExtra - bExtra;
      });

    return events;
  } catch (e) {
    console.warn(`Failed to fetch events for fixture ${fixtureId}:`, e);
    return null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function chunkArray<T>(values: T[], chunkSize: number): T[][] {
  if (chunkSize <= 0) return [values];
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += chunkSize) {
    out.push(values.slice(i, i + chunkSize));
  }
  return out;
}

function extractFcmTokensFromUserDoc(
  data: FirebaseFirestore.DocumentData | undefined
): string[] {
  if (!data) return [];
  const raw = data["fcmTokens"];
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((t): t is string => typeof t === "string")
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

async function collectFcmTokensForUids(
  db: FirebaseFirestore.Firestore,
  uids: string[]
): Promise<string[]> {
  if (uids.length === 0) return [];
  const cleanUids = Array.from(
    new Set(
      uids.map((uid) => uid.trim()).filter((uid) => uid.length > 0)
    )
  );
  if (cleanUids.length === 0) return [];

  const refs = cleanUids.map((uid) => db.collection("users").doc(uid));
  const tokens = new Set<string>();

  for (const refChunk of chunkArray(refs, 250)) {
    const snapshots = await db.getAll(...refChunk);
    for (const snap of snapshots) {
      if (!snap.exists) continue;
      for (const token of extractFcmTokensFromUserDoc(snap.data())) {
        tokens.add(token);
      }
    }
  }

  return [...tokens];
}

async function collectAllFcmTokens(
  db: FirebaseFirestore.Firestore
): Promise<string[]> {
  const usersSnap = await db.collection("users").get();
  const tokens = new Set<string>();
  for (const doc of usersSnap.docs) {
    for (const token of extractFcmTokensFromUserDoc(doc.data())) {
      tokens.add(token);
    }
  }
  return [...tokens];
}

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

async function sendPushToTokens(
  tokens: string[],
  payload: PushPayload
): Promise<void> {
  if (tokens.length === 0) return;

  const messaging = getMessaging();
  for (const tokenChunk of chunkArray(tokens, 400)) {
    await messaging.sendEachForMulticast({
      tokens: tokenChunk,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data,
      android: {
        priority: "high",
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });
  }
}

// ─── Cloud Function ──────────────────────────────────────────────────────────

interface RefreshOptions {
  includeOdds: boolean;
  lastFixtures: number;
  nextFixtures: number;
  logPrefix: string;
}

async function refreshMatchdayDataCore(options: RefreshOptions): Promise<void> {
  const db = getFirestore();
  const season = seasonStartYear();
  const seasonKey = season.toString();
  const pendingGoalNotifications: PushPayload[] = [];

  console.log(`[${options.logPrefix}] Starting for season ${seasonKey}`);

  const leagueId = await resolveLeagueId(season, db);
  console.log(`[${options.logPrefix}] League ID: ${leagueId}`);

  const [pastJson, nextJson, standingsJson] = await Promise.all([
    apiGet("fixtures", {
      league: leagueId.toString(),
      season: season.toString(),
      last: options.lastFixtures.toString(),
      timezone: "Europe/Rome",
    }),
    apiGet("fixtures", {
      league: leagueId.toString(),
      season: season.toString(),
      next: options.nextFixtures.toString(),
      timezone: "Europe/Rome",
    }),
    apiGet("standings", {
      league: leagueId.toString(),
      season: season.toString(),
    }),
  ]);

  const pastFixtures = parseFixtures(pastJson);
  const nextFixtures = parseFixtures(nextJson);
  const standings = parseStandings(standingsJson);

  if (standings.length > 0) {
    await db
      .collection("seasons")
      .doc(seasonKey)
      .collection("standings")
      .doc("current")
      .set(
        {
          rows: standings,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    console.log(
      `[${options.logPrefix}] Wrote standings rows=${standings.length}`
    );
  }

  const seen = new Set<number>();
  const allFixtures: ApiFixture[] = [];
  for (const f of [...pastFixtures, ...nextFixtures]) {
    if (!seen.has(f.fixtureId)) {
      seen.add(f.fixtureId);
      allFixtures.push(f);
    }
  }

  console.log(
    `[${options.logPrefix}] Got ${allFixtures.length} unique fixtures ` +
      `(past=${pastFixtures.length}, next=${nextFixtures.length})`
  );

  const byMatchday = new Map<number, ApiFixture[]>();
  for (const f of allFixtures) {
    const md = matchdayFromRound(f.round);
    if (md == null) continue;
    if (!byMatchday.has(md)) byMatchday.set(md, []);
    byMatchday.get(md)!.push(f);
  }

  const now = new Date();
  const activeMatchdays: number[] = [];
  for (const [md, fixtures] of byMatchday) {
    const allFinished = fixtures.every((f) => {
      const s = f.statusShort.trim().toUpperCase();
      return ["FT", "AET", "PEN", "WO", "AWD", "CANC"].includes(s);
    });

    if (!allFinished) {
      activeMatchdays.push(md);
      continue;
    }

    const latestKickoff = fixtures.reduce(
      (max, f) => {
        const d = new Date(f.kickoffUtc);
        return d > max ? d : max;
      },
      new Date(0)
    );
    const daysSince =
      (now.getTime() - latestKickoff.getTime()) / (1000 * 60 * 60 * 24);
    if (daysSince <= 7) {
      activeMatchdays.push(md);
    }
  }

  activeMatchdays.sort((a, b) => a - b);
  console.log(
    `[${options.logPrefix}] Active matchdays: [${activeMatchdays.join(", ")}]`
  );

  for (const md of activeMatchdays) {
    const fixtures = byMatchday.get(md)!;
    const docRef = db
      .collection("seasons")
      .doc(seasonKey)
      .collection("matchdays")
      .doc(md.toString());
    const existing = await docRef.get();
    const existingData = existing.data();

    const outcomesByMatchId: Record<string, Outcome> = {};
    for (const f of fixtures) {
      outcomesByMatchId[f.fixtureId.toString()] = computeOutcome(f);
    }

    const existingOutcomesRaw = existingData?.outcomesByMatchId;
    if (
      existingOutcomesRaw != null &&
      typeof existingOutcomesRaw === "object" &&
      !Array.isArray(existingOutcomesRaw)
    ) {
      for (const [matchId, rawOutcome] of Object.entries(existingOutcomesRaw)) {
        if (matchId in outcomesByMatchId) continue;
        const parsed = parseOutcomeValue(rawOutcome);
        if (parsed != null) {
          outcomesByMatchId[matchId] = parsed;
        }
      }
    }

    const kickoffs = fixtures.map((f) => new Date(f.kickoffUtc));
    const lockTime = kickoffs.reduce((min, d) => (d < min ? d : min));
    let finalized = Object.values(outcomesByMatchId).every(
      (o) => o !== "pending"
    );

    const existingMatches = existingData?.matches;
    const existingKickoffs = existingData
      ? parseMatchKickoffsFromDoc(existingData as Record<string, unknown>)
      : [];
    const knownKickoffs = [...kickoffs, ...existingKickoffs];
    const latestKnownKickoff = knownKickoffs.reduce(
      (max, d) => (d > max ? d : max),
      new Date(0)
    );
    const withinLiveWindowAfterLatestKickoff =
      now.getTime() < latestKnownKickoff.getTime() + 4 * 60 * 60 * 1000;

    if (Array.isArray(existingMatches) && fixtures.length < existingMatches.length) {
      finalized = false;
      console.log(
        `[${options.logPrefix}] Matchday ${md}: fixture list shrank ` +
          `(${fixtures.length}/${existingMatches.length}), keep finalized=false`
      );
    }

    if (
      existing.exists &&
      existingData?.finalized === true &&
      finalized &&
      !withinLiveWindowAfterLatestKickoff
    ) {
      await recomputePicksScoresForMatchday(
        db,
        seasonKey,
        md,
        options.logPrefix
      );
      console.log(`[${options.logPrefix}] Matchday ${md} finalized, skip`);
      continue;
    }

    const existingById = new Map<string, Record<string, unknown>>();
    if (Array.isArray(existingMatches)) {
      for (const raw of existingMatches) {
        if (typeof raw !== "object" || raw == null) continue;
        const m = raw as Record<string, unknown>;
        const id = String(m["id"] ?? "");
        if (!id) continue;
        existingById.set(id, m);
      }
    }

    if (!options.includeOdds && existingById.size > 0) {
      for (const fixture of fixtures) {
        const matchId = fixture.fixtureId.toString();
        const prev = existingById.get(matchId);
        if (!prev) continue;

        const prevHomeRaw = prev["homeGoals"];
        const prevAwayRaw = prev["awayGoals"];
        const prevHome = typeof prevHomeRaw === "number" ? prevHomeRaw : 0;
        const prevAway = typeof prevAwayRaw === "number" ? prevAwayRaw : 0;

        const nextHome = fixture.homeGoals;
        const nextAway = fixture.awayGoals;
        if (nextHome == null || nextAway == null) continue;

        const prevTotal = Math.max(0, prevHome) + Math.max(0, prevAway);
        const nextTotal = Math.max(0, nextHome) + Math.max(0, nextAway);
        if (nextTotal <= prevTotal) continue;

        const status = (fixture.statusShort ?? "").trim().toUpperCase();
        const inPlayOrFinal = isInProgressStatus(status) || isFinalStatus(status);
        if (!inPlayOrFinal) continue;

        pendingGoalNotifications.push({
          title: "Nuovo gol live",
          body: `${fixture.homeName} ${nextHome}-${nextAway} ${fixture.awayName}`,
          data: {
            type: "live_goal",
            seasonKey,
            dayNumber: md.toString(),
            matchId,
          },
        });
      }
    }

    const eventsByFixture = new Map<string, MatchEventDoc[]>();
    for (const f of fixtures) {
      const fixtureId = f.fixtureId.toString();
      const status = (f.statusShort ?? "").trim().toUpperCase();
      const existingMatch = existingById.get(fixtureId);
      const existingEvents = Array.isArray(existingMatch?.events) ? existingMatch?.events : null;
      const hasExistingEvents = existingEvents != null && existingEvents.length > 0;

      let shouldFetchEvents = false;
      if (isInProgressStatus(status)) {
        shouldFetchEvents = true;
      } else if (isFinalStatus(status) && !hasExistingEvents) {
        shouldFetchEvents = true;
      }

      if (!shouldFetchEvents) {
        if (Array.isArray(existingEvents)) {
          eventsByFixture.set(
            fixtureId,
            existingEvents as MatchEventDoc[]
          );
        }
        continue;
      }

      const events = await fetchEventsForFixture(f.fixtureId);
      if (events != null) {
        eventsByFixture.set(fixtureId, events);
      } else if (Array.isArray(existingEvents)) {
        eventsByFixture.set(
          fixtureId,
          existingEvents as MatchEventDoc[]
        );
      }
      await sleep(120);
    }

    if (!options.includeOdds) {
      if (!existing.exists) {
        console.log(
          `[${options.logPrefix}] Matchday ${md} missing doc, skip write`
        );
        continue;
      }
      const mergedMatches = mergeLiveFieldsIntoExistingMatches(
        existingMatches,
        fixtures,
        eventsByFixture
      );
      const livePayload: Record<string, unknown> = {
        outcomesByMatchId,
        lockTime: Timestamp.fromDate(lockTime),
        updatedAt: FieldValue.serverTimestamp(),
        finalized,
      };
      if (mergedMatches != null) {
        livePayload.matches = mergedMatches;
      }

      await docRef.set(
        livePayload,
        { merge: true }
      );
      await recomputePicksScoresForMatchday(
        db,
        seasonKey,
        md,
        options.logPrefix
      );
      console.log(
        `[${options.logPrefix}] Wrote live outcomes ${md}: finalized=${finalized}`
      );
      continue;
    }

    // Odds freeze: once a matchday has stored matches, we only update live fields.
    // This keeps the first available odds snapshot stable for the whole matchday.
    if (Array.isArray(existingMatches) && existingMatches.length > 0) {
      const mergedMatches = mergeLiveFieldsIntoExistingMatches(
        existingMatches,
        fixtures,
        eventsByFixture
      );
      const frozenPayload: Record<string, unknown> = {
        outcomesByMatchId,
        lockTime: Timestamp.fromDate(lockTime),
        updatedAt: FieldValue.serverTimestamp(),
        finalized,
        oddsFrozen: true,
      };
      if (existingData?.oddsFrozenAt == null) {
        frozenPayload.oddsFrozenAt = FieldValue.serverTimestamp();
      }
      if (mergedMatches != null) {
        frozenPayload.matches = mergedMatches;
      }

      await docRef.set(frozenPayload, { merge: true });
      await recomputePicksScoresForMatchday(
        db,
        seasonKey,
        md,
        options.logPrefix
      );
      console.log(
        `[${options.logPrefix}] Kept frozen odds for matchday ${md}: finalized=${finalized}`
      );
      continue;
    }

    const oddsByFixture = new Map<number, FixtureOdds>();
    for (const f of fixtures) {
      const odds = await fetchOddsForFixture(f.fixtureId);
      if (odds) oddsByFixture.set(f.fixtureId, odds);
      await sleep(200);
    }

    const matches: MatchDoc[] = fixtures
      .sort((a, b) => a.kickoffUtc.localeCompare(b.kickoffUtc))
      .map((f) =>
        buildMatchDoc(
          f,
          oddsByFixture.get(f.fixtureId) ?? null,
          eventsByFixture.get(f.fixtureId.toString()) ?? null
        )
      );

    await docRef.set(
      {
        matches,
        outcomesByMatchId,
        lockTime: Timestamp.fromDate(lockTime),
        updatedAt: FieldValue.serverTimestamp(),
        finalized,
        oddsFrozen: true,
        oddsFrozenAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await recomputePicksScoresForMatchday(
      db,
      seasonKey,
      md,
      options.logPrefix
    );

    console.log(
      `[${options.logPrefix}] Wrote matchday ${md}: finalized=${finalized}`
    );
  }

  if (pendingGoalNotifications.length > 0) {
    const tokens = await collectAllFcmTokens(db);
    if (tokens.length > 0) {
      for (const payload of pendingGoalNotifications) {
        await sendPushToTokens(tokens, payload);
      }
    }
    console.log(
      `[${options.logPrefix}] goal notifications sent=${pendingGoalNotifications.length}`
    );
  }

  console.log(`[${options.logPrefix}] Done`);
}

export const refreshMatchdayData = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 60 minutes",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    await refreshMatchdayDataCore({
      includeOdds: true,
      lastFixtures: 40,
      nextFixtures: 80,
      logPrefix: "refresh-hourly",
    });
  }
);

export const refreshLiveMatchdayData = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 1 minutes",
    timeoutSeconds: 180,
    memory: "256MiB",
  },
  async () => {
    await refreshMatchdayDataCore({
      includeOdds: false,
      lastFixtures: 20,
      nextFixtures: 40,
      logPrefix: "refresh-live",
    });
  }
);

function parseMatchKickoffsFromDoc(data: Record<string, unknown>): Date[] {
  const rawMatches = data["matches"];
  if (!Array.isArray(rawMatches)) return [];

  return rawMatches
    .filter(
      (m): m is Record<string, unknown> => typeof m === "object" && m != null
    )
    .map((m) => {
      const kickoffRaw = m["kickoff"];
      if (typeof kickoffRaw !== "string") return null;
      const parsed = new Date(kickoffRaw);
      if (Number.isNaN(parsed.getTime())) return null;
      return parsed;
    })
    .filter((d): d is Date => d != null)
    .sort((a, b) => a.getTime() - b.getTime());
}

export const notifyGroupChatMessage = onDocumentCreated(
  {
    region: "europe-west1",
    document: "groups/{groupId}/chatMessages/{messageId}",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const db = getFirestore();

    const groupId = event.params.groupId as string;
    const messageId = event.params.messageId as string;
    const data = snap.data() as Record<string, unknown>;
    const senderUid = String(data["senderUid"] ?? "").trim();
    if (!senderUid) return;

    const senderTeamName = String(data["senderTeamName"] ?? "").trim();
    const senderDisplayName = String(data["senderDisplayName"] ?? "").trim();
    const senderLabel = senderTeamName || senderDisplayName || "Un membro";

    const type = String(data["type"] ?? "text").trim().toLowerCase();
    const text = String(data["text"] ?? "").trim();
    let body = `${senderLabel} ha inviato un messaggio`;
    if (type === "image") body = `${senderLabel} ha inviato una foto`;
    if (type === "sticker") body = `${senderLabel} ha inviato uno sticker`;
    if (type === "text" && text.length > 0) {
      body = `${senderLabel}: ${text.slice(0, 120)}`;
    }

    const membersSnap = await db
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();
    const targetUids = membersSnap.docs
      .map((doc) => doc.id)
      .filter((uid) => uid !== senderUid);
    if (targetUids.length === 0) return;

    const tokens = await collectFcmTokensForUids(db, targetUids);
    if (tokens.length === 0) return;

    await sendPushToTokens(tokens, {
      title: "Nuovo messaggio in chat",
      body,
      data: {
        type: "chat_message",
        groupId,
        messageId,
      },
    });
  }
);

export const cleanupGroupChatMessages = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 15 minutes",
    timeoutSeconds: 180,
    memory: "256MiB",
  },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000)
    );

    let deleted = 0;
    while (true) {
      const snap = await db
        .collectionGroup("chatMessages")
        .where("createdAt", "<=", cutoff)
        .orderBy("createdAt")
        .limit(400)
        .get();

      if (snap.empty) break;

      const batch = db.batch();
      for (const doc of snap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      deleted += snap.docs.length;

      if (snap.docs.length < 400) break;
    }

    console.log(`[chat-cleanup] deleted=${deleted}`);
  }
);
