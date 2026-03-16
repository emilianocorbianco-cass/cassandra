import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
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
  elapsed: number | null;
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
  elapsed?: number | null;
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
  winningOddsSum: number;
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
        elapsed: status["elapsed"] != null ? Number(status["elapsed"]) : null,
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

function bonusForWinningOddsSum(winningOddsSum: number): number {
  if (winningOddsSum < 3) return -10;
  if (winningOddsSum < 5) return -4;
  if (winningOddsSum < 7) return -1;
  if (winningOddsSum < 10) return 0;
  if (winningOddsSum < 12) return 1;
  if (winningOddsSum < 14) return 4;
  if (winningOddsSum < 20) return 10;
  return 20;
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
  const winningOddsSumRaw = raw["winningOddsSum"];
  const winningOddsSum = winningOddsSumRaw == null ? 0 : Number(winningOddsSumRaw);
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
    winningOddsSum,
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
    almostEqual(a.winningOddsSum, b.winningOddsSum) &&
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
  let winningOddsSum = 0;
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
      if (correct) {
        correctCount += 1;
        winningOddsSum += singlePlayed;
      }
      playedOdds.push(singlePlayed);
      continue;
    }

    const doublePlayed = played ?? 0;
    const correct = isCorrectDouble(pick, outcome);
    if (correct) {
      baseTotal += doublePlayed;
      correctCount += 1;
      winningOddsSum += doublePlayed;
    } else {
      baseTotal -= wrongDoublePenaltySumSingles(match, pick);
    }
    playedOdds.push(doublePlayed);
  }

  const allGraded = matches.every((m) => {
    const outcome = outcomesByMatchId[m.id];
    return outcome != null && outcome !== "pending";
  });
  const bonusPoints = allGraded ? bonusForWinningOddsSum(winningOddsSum) : 0;
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
    winningOddsSum,
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

function parseGroupIds(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((v): v is string => typeof v === "string")
    .map((v) => v.trim())
    .filter((v) => v.length > 0);
}

async function resolveGroupIdsForUid(
  db: FirebaseFirestore.Firestore,
  uid: string
): Promise<string[]> {
  const groupIds = new Set<string>();

  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.exists) {
    const fromUserDoc = parseGroupIds(userSnap.data()?.["groupIds"]);
    for (const groupId of fromUserDoc) groupIds.add(groupId);
  }

  // Legacy fallback: derive membership from groups/{groupId}/members/{uid}.
  // This avoids collectionGroup indexes and remains deterministic for maintenance jobs.
  const groupsSnap = await db.collection("groups").select().get();
  if (!groupsSnap.empty) {
    const memberRefs = groupsSnap.docs.map((groupDoc) =>
      groupDoc.ref.collection("members").doc(uid)
    );
    const memberSnaps = await db.getAll(...memberRefs);
    for (const memberSnap of memberSnaps) {
      if (!memberSnap.exists) continue;
      const groupId = memberSnap.ref.parent.parent?.id;
      if (groupId && groupId.trim().length > 0) {
        groupIds.add(groupId.trim());
      }
    }
  }

  return Array.from(groupIds);
}

async function backfillLegacyPicksGroupIds(
  db: FirebaseFirestore.Firestore,
  seasonKey: string,
  logPrefix: string
): Promise<void> {
  const picksSnap = await db
    .collection("picks")
    .where("seasonKey", "==", seasonKey)
    .get();
  if (picksSnap.empty) return;

  let scanned = 0;
  let updated = 0;
  let skippedNoGroup = 0;
  let skippedAmbiguous = 0;
  const uidToGroupIds = new Map<string, string[]>();
  let batch = db.batch();
  let pendingWrites = 0;

  for (const doc of picksSnap.docs) {
    scanned += 1;
    const data = doc.data();
    const existingGroupId =
      typeof data["groupId"] === "string" ? data["groupId"].trim() : "";
    if (existingGroupId.length > 0) continue;

    const uid = typeof data["uid"] === "string" ? data["uid"].trim() : "";
    if (!uid) continue;

    let groupIds = uidToGroupIds.get(uid);
    if (groupIds == null) {
      groupIds = await resolveGroupIdsForUid(db, uid);
      uidToGroupIds.set(uid, groupIds);
    }

    if (groupIds.length === 0) {
      skippedNoGroup += 1;
      continue;
    }
    if (groupIds.length > 1) {
      skippedAmbiguous += 1;
      continue;
    }

    batch.set(
      doc.ref,
      {
        groupId: groupIds[0],
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    pendingWrites += 1;
    updated += 1;

    if (pendingWrites >= 400) {
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
    }
  }

  if (pendingWrites > 0) {
    await batch.commit();
  }

  console.log(
    `[${logPrefix}] Backfill picks.groupId season=${seasonKey} scanned=${scanned} updated=${updated} skippedNoGroup=${skippedNoGroup} skippedAmbiguous=${skippedAmbiguous}`
  );
}

async function backfillGroupInviteIndex(
  db: FirebaseFirestore.Firestore,
  logPrefix: string
): Promise<void> {
  const groupsSnap = await db.collection("groups").get();
  if (groupsSnap.empty) return;

  let scanned = 0;
  let upserted = 0;
  let conflicts = 0;
  let skippedInvalid = 0;
  let skippedDeleting = 0;
  let batch = db.batch();
  let pendingWrites = 0;

  for (const groupDoc of groupsSnap.docs) {
    scanned += 1;
    const data = groupDoc.data();
    const deleting = data["deleting"] === true;
    if (deleting) {
      skippedDeleting += 1;
      continue;
    }
    const inviteCodeRaw =
      typeof data["inviteCode"] === "string" ? data["inviteCode"] : "";
    const inviteCode = inviteCodeRaw.trim().toUpperCase();
    const adminUid =
      typeof data["adminUid"] === "string" ? data["adminUid"].trim() : "";
    const groupName =
      typeof data["name"] === "string" ? data["name"].trim() : "";

    if (!inviteCode || !adminUid || !groupName) {
      skippedInvalid += 1;
      continue;
    }

    const inviteRef = db.collection("group_invites").doc(inviteCode);
    const inviteSnap = await inviteRef.get();
    if (inviteSnap.exists) {
      const existing = inviteSnap.data();
      const existingGroupId =
        typeof existing?.["groupId"] === "string"
          ? existing["groupId"].trim()
          : "";
      if (existingGroupId && existingGroupId !== groupDoc.id) {
        conflicts += 1;
        continue;
      }
    }

    batch.set(
      inviteRef,
      {
        groupId: groupDoc.id,
        groupName,
        inviteCode,
        adminUid,
        updatedAt: FieldValue.serverTimestamp(),
        ...(inviteSnap.exists
          ? {}
          : { createdAt: FieldValue.serverTimestamp() }),
      },
      { merge: true }
    );
    pendingWrites += 1;
    upserted += 1;

    if (pendingWrites >= 400) {
      await batch.commit();
      batch = db.batch();
      pendingWrites = 0;
    }
  }

  if (pendingWrites > 0) {
    await batch.commit();
  }

  console.log(
    `[${logPrefix}] Backfill group_invites scanned=${scanned} upserted=${upserted} conflicts=${conflicts} skippedInvalid=${skippedInvalid} skippedDeleting=${skippedDeleting}`
  );
}

async function recomputeAllPicksScoresForSeason(
  db: FirebaseFirestore.Firestore,
  seasonKey: string,
  logPrefix: string
): Promise<void> {
  const picksSnap = await db
    .collection("picks")
    .where("seasonKey", "==", seasonKey)
    .get();
  if (picksSnap.empty) return;

  const dayNumberSet = new Set<number>();
  for (const doc of picksSnap.docs) {
    const dayNumber = Number(doc.data()["dayNumber"]);
    if (!Number.isFinite(dayNumber) || dayNumber < 1 || dayNumber > 60) {
      continue;
    }
    dayNumberSet.add(Math.trunc(dayNumber));
  }
  const dayNumbers = Array.from(dayNumberSet).sort((a, b) => a - b);
  if (dayNumbers.length === 0) return;

  for (const dayNumber of dayNumbers) {
    await recomputePicksScoresForMatchday(db, seasonKey, dayNumber, logPrefix);
  }
  console.log(
    `[${logPrefix}] Recompute all scores by picks season=${seasonKey} days=${dayNumbers.length}`
  );
}

async function cleanupInvalidMatchdayDocsOnce(
  db: FirebaseFirestore.Firestore,
  seasonKey: string,
  logPrefix: string
): Promise<void> {
  const stateRef = db.collection("_maintenance").doc(`season-${seasonKey}`);
  const stateSnap = await stateRef.get();
  const alreadyCleaned =
    stateSnap.exists &&
    stateSnap.data()?.["invalidMatchdaysCleanupDone"] === true;
  if (alreadyCleaned) return;

  const matchdaysSnap = await db
    .collection("seasons")
    .doc(seasonKey)
    .collection("matchdays")
    .get();
  if (matchdaysSnap.empty) {
    await stateRef.set(
      {
        invalidMatchdaysCleanupDone: true,
        invalidMatchdaysCleanupAt: FieldValue.serverTimestamp(),
        invalidMatchdaysDeleted: 0,
      },
      { merge: true }
    );
    return;
  }

  let deleted = 0;
  let batch = db.batch();
  let pendingDeletes = 0;
  for (const doc of matchdaysSnap.docs) {
    const dayNumber = Number.parseInt(doc.id, 10);
    if (!Number.isFinite(dayNumber) || dayNumber < 1 || dayNumber > 60) {
      batch.delete(doc.ref);
      pendingDeletes += 1;
      deleted += 1;
      if (pendingDeletes >= 400) {
        await batch.commit();
        batch = db.batch();
        pendingDeletes = 0;
      }
    }
  }
  if (pendingDeletes > 0) {
    await batch.commit();
  }

  await stateRef.set(
    {
      invalidMatchdaysCleanupDone: true,
      invalidMatchdaysCleanupAt: FieldValue.serverTimestamp(),
      invalidMatchdaysDeleted: deleted,
    },
    { merge: true }
  );
  console.log(
    `[${logPrefix}] Cleanup invalid matchday docs season=${seasonKey} deleted=${deleted}`
  );
}

async function cleanupDeletingGroups(
  db: FirebaseFirestore.Firestore,
  logPrefix: string
): Promise<void> {
  const deletingSnap = await db
    .collection("groups")
    .where("deleting", "==", true)
    .limit(40)
    .get();
  if (deletingSnap.empty) return;

  let processed = 0;
  let completed = 0;
  let failed = 0;

  for (const groupDoc of deletingSnap.docs) {
    processed += 1;
    const groupId = groupDoc.id;
    try {
      await cleanupSingleDeletingGroup(db, groupDoc);
      completed += 1;
    } catch (e) {
      failed += 1;
      console.warn(`[${logPrefix}] Cleanup deleting group failed id=${groupId}`, e);
    }
  }

  console.log(
    `[${logPrefix}] Cleanup deleting groups scanned=${processed} completed=${completed} failed=${failed}`
  );
}

async function cleanupSingleDeletingGroup(
  db: FirebaseFirestore.Firestore,
  groupDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
  const groupRef = groupDoc.ref;
  const groupId = groupRef.id;
  const data = groupDoc.data();
  const inviteCode =
    typeof data["inviteCode"] === "string"
      ? data["inviteCode"].trim().toUpperCase()
      : "";

  const chunkSize = 200;
  while (true) {
    const membersSnap = await groupRef.collection("members").limit(chunkSize).get();
    if (membersSnap.empty) break;

    const batch = db.batch();
    for (const memberDoc of membersSnap.docs) {
      const uid = memberDoc.id.trim();
      if (uid) {
        batch.set(
          db.collection("users").doc(uid),
          {
            groupIds: FieldValue.arrayRemove([groupId]),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      batch.delete(memberDoc.ref);
    }
    await batch.commit();

    if (membersSnap.docs.length < chunkSize) break;
  }

  if (inviteCode) {
    await db.collection("group_invites").doc(inviteCode).delete();
  }

  while (true) {
    const staleInvites = await db
      .collection("group_invites")
      .where("groupId", "==", groupId)
      .limit(200)
      .get();
    if (staleInvites.empty) break;
    const batch = db.batch();
    for (const inviteDoc of staleInvites.docs) {
      batch.delete(inviteDoc.ref);
    }
    await batch.commit();
    if (staleInvites.docs.length < 200) break;
  }

  await groupRef.delete();
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
  if (type === "var") {
    // Only store VAR decisions that cancel a goal; ignore reviews and other decisions.
    if (detail.includes("goal disallowed") || detail.includes("goal cancelled")) {
      return "var_goal";
    }
    return null;
  }
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
    "var_goal",
  ].includes(normalizedType);
}

function round2(v: number): number {
  return Math.round(v * 100) / 100;
}

/**
 * Detects whether the odds in a list of match docs were produced by the
 * deterministic fallback rather than fetched from a real bookmaker.
 *
 * Heuristic: the deterministic generator seeds from fixture ID, producing
 * nearly identical odds across fixtures whose IDs are numerically close.
 * We check if ALL "homeAway" (12) double-chance odds are identical — this
 * is virtually impossible with real bookmaker data but very likely with
 * the seed-based formula.
 */
function looksLikeDeterministicOdds(matches: MatchDoc[]): boolean {
  if (matches.length < 3) return false;
  const haVals = new Set(matches.map((m) => m.odds.homeAway));
  if (haVals.size === 1) return true;
  // Also check if home odds have < 3 distinct values across 10 matches
  const homeVals = new Set(matches.map((m) => m.odds.home));
  if (matches.length >= 8 && homeVals.size <= 2) return true;
  return false;
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
  if (f.elapsed != null) doc.elapsed = f.elapsed;
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
        kickoff: fixture.kickoffUtc,
        statusShort: fixture.statusShort,
        elapsed: fixture.elapsed,
        homeGoals: fixture.homeGoals,
        awayGoals: fixture.awayGoals,
      };
      if (fixture.homeLogo) next.homeLogo = fixture.homeLogo;
      if (fixture.awayLogo) next.awayLogo = fixture.awayLogo;
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
    const response = await messaging.sendEachForMulticast({
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
    console.log(
      `[push] title="${payload.title}" tokens=${tokenChunk.length} success=${response.successCount} failure=${response.failureCount}`
    );
    if (response.failureCount > 0) {
      const sampleErrors = response.responses
        .map((r, idx) => ({ r, idx }))
        .filter(({ r }) => !r.success && r.error)
        .slice(0, 6)
        .map(({ r, idx }) => `${tokenChunk[idx]}:${r.error?.code ?? "unknown"}`);
      if (sampleErrors.length > 0) {
        console.warn(`[push] sample failures ${sampleErrors.join(" | ")}`);
      }
    }
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
  const pendingVarGoalNotifications: PushPayload[] = [];

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

    // var_goal detection: send a push notification when a VAR decision cancels
    // a goal that wasn't already in the stored events.
    // Guards mirror the goal-notification guards: live refresh only (includeOdds=false)
    // and only when prior data exists to diff against.
    if (!options.includeOdds && existingById.size > 0) {
      for (const f of fixtures) {
        const fixtureId = f.fixtureId.toString();
        const newEvents = eventsByFixture.get(fixtureId) ?? [];
        const existingMatch = existingById.get(fixtureId);
        const existingEvents = Array.isArray(existingMatch?.["events"])
          ? (existingMatch["events"] as MatchEventDoc[])
          : [];

        const existingVarCount = existingEvents.filter(
          (e) => e.type === "var_goal"
        ).length;
        const newVarCount = newEvents.filter(
          (e) => e.type === "var_goal"
        ).length;
        if (newVarCount <= existingVarCount) continue;

        const status = (f.statusShort ?? "").trim().toUpperCase();
        if (!isInProgressStatus(status) && !isFinalStatus(status)) continue;

        pendingVarGoalNotifications.push({
          title: "Gol annullato (VAR) \uD83D\uDEAB",
          body: `${f.homeName} ${f.homeGoals ?? 0}-${f.awayGoals ?? 0} ${f.awayName}`,
          data: {
            type: "var_goal",
            seasonKey,
            dayNumber: md.toString(),
            matchId: fixtureId,
          },
        });
      }
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

    // Odds freeze: once a matchday has stored matches with real bookmaker odds,
    // we only update live fields. This keeps the first available odds snapshot
    // stable for the whole matchday.
    //
    // GUARD: if the stored odds are clearly deterministic (fallback), we do NOT
    // freeze them — instead we fall through and re-fetch from the API so real
    // bookmaker odds replace the placeholders.
    const existingMatchDocs: MatchDoc[] = Array.isArray(existingMatches)
      ? existingMatches
          .filter((m): m is Record<string, unknown> => typeof m === "object" && m != null)
          .map((m) => m as unknown as MatchDoc)
      : [];
    const hasDeterministicOdds =
      existingMatchDocs.length > 0 && looksLikeDeterministicOdds(existingMatchDocs);

    if (Array.isArray(existingMatches) && existingMatches.length > 0 && !hasDeterministicOdds) {
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

    if (hasDeterministicOdds) {
      console.log(
        `[${options.logPrefix}] Matchday ${md}: detected deterministic odds, re-fetching from API`
      );
    }

    const oddsByFixture = new Map<number, FixtureOdds>();
    for (const f of fixtures) {
      const odds = await fetchOddsForFixture(f.fixtureId);
      if (odds) oddsByFixture.set(f.fixtureId, odds);
      await sleep(200);
    }

    console.log(
      `[${options.logPrefix}] Matchday ${md}: fetched real odds for ${oddsByFixture.size}/${fixtures.length} fixtures`
    );

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

  if (pendingVarGoalNotifications.length > 0) {
    const tokens = await collectAllFcmTokens(db);
    if (tokens.length > 0) {
      for (const payload of pendingVarGoalNotifications) {
        await sendPushToTokens(tokens, payload);
      }
    }
    console.log(
      `[${options.logPrefix}] var_goal notifications sent=${pendingVarGoalNotifications.length}`
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
    console.log(
      `[notify-chat] group=${groupId} message=${messageId} recipients=${targetUids.length}`
    );

    const tokens = await collectFcmTokensForUids(db, targetUids);
    if (tokens.length === 0) return;
    console.log(
      `[notify-chat] group=${groupId} message=${messageId} tokens=${tokens.length}`
    );

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

export const maintenanceBackfillPicksAndScores = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 3 hours",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = getFirestore();
    const seasonKey = seasonStartYear().toString();
    const logPrefix = "maintenance-picks";

    await cleanupDeletingGroups(db, logPrefix);
    await backfillGroupInviteIndex(db, logPrefix);
    await cleanupInvalidMatchdayDocsOnce(db, seasonKey, logPrefix);
    await backfillLegacyPicksGroupIds(db, seasonKey, logPrefix);
    await recomputeAllPicksScoresForSeason(db, seasonKey, logPrefix);
  }
);

export const cleanupDeletingGroupsMaintenance = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 30 minutes",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    const db = getFirestore();
    await cleanupDeletingGroups(db, "maintenance-groups");
  }
);

// ─── Member count reconciliation ─────────────────────────────────────────────
// Auto-corrects memberCount on the group document whenever a member is
// created or deleted. This replaces the fragile client-side increment/decrement
// with a definitive count query.

export const reconcileMemberCount = onDocumentWritten(
  {
    region: "europe-west1",
    document: "groups/{groupId}/members/{memberUid}",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const groupId = event.params.groupId;
    const db = getFirestore();
    const groupRef = db.collection("groups").doc(groupId);

    // Only reconcile on create or delete (not profile updates).
    const beforeExists = event.data?.before?.exists ?? false;
    const afterExists = event.data?.after?.exists ?? false;
    if (beforeExists === afterExists) return; // update, nothing to do

    const membersSnap = await groupRef.collection("members").select().get();
    const actualCount = membersSnap.size;
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) return;

    const storedCount =
      (groupSnap.data()?.["memberCount"] as number | undefined) ?? 0;
    if (storedCount === actualCount) return;

    await groupRef.update({
      memberCount: actualCount,
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.log(
      `[reconcile-members] group=${groupId} stored=${storedCount} actual=${actualCount}`
    );
  }
);

// ─── Group integrity repair (scheduled) ──────────────────────────────────────
// Runs alongside the existing maintenance job to fix:
//   1. Admin role: ensure adminUid has role='admin' in members subcollection
//   2. memberCount drift: reconcile with actual member count
//   3. Orphan detection: log members without a /users/{uid} doc

async function repairGroupIntegrity(
  db: FirebaseFirestore.Firestore,
  logPrefix: string
): Promise<void> {
  const groupsSnap = await db.collection("groups").get();
  if (groupsSnap.empty) return;

  let scanned = 0;
  let adminFixed = 0;
  let countFixed = 0;
  let orphansFound = 0;

  for (const groupDoc of groupsSnap.docs) {
    scanned += 1;
    const data = groupDoc.data();
    const adminUid =
      typeof data["adminUid"] === "string" ? data["adminUid"].trim() : "";
    const storedCount =
      typeof data["memberCount"] === "number" ? data["memberCount"] : 0;

    const membersSnap = await groupDoc.ref.collection("members").get();
    const actualCount = membersSnap.size;

    // Fix memberCount if needed
    if (storedCount !== actualCount) {
      await groupDoc.ref.update({
        memberCount: actualCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
      countFixed += 1;
    }

    // Fix admin role
    if (adminUid) {
      const adminMemberRef = groupDoc.ref.collection("members").doc(adminUid);
      const adminMemberSnap = await adminMemberRef.get();
      if (adminMemberSnap.exists) {
        const currentRole = adminMemberSnap.data()?.["role"];
        if (currentRole !== "admin") {
          await adminMemberRef.update({
            role: "admin",
            updatedAt: FieldValue.serverTimestamp(),
          });
          adminFixed += 1;
        }
      }
    }

    // Detect orphan members (no user doc)
    if (membersSnap.docs.length > 0) {
      const memberUids = membersSnap.docs.map((d) => d.id);
      const userRefs = memberUids.map((uid) =>
        db.collection("users").doc(uid)
      );
      const userSnaps = await db.getAll(...userRefs);
      for (let i = 0; i < userSnaps.length; i++) {
        if (!userSnaps[i].exists) {
          orphansFound += 1;
          console.log(
            `[${logPrefix}] orphan member uid=${memberUids[i]} ` +
              `group=${groupDoc.id}`
          );
        }
      }
    }
  }

  console.log(
    `[${logPrefix}] Group integrity repair scanned=${scanned} ` +
      `adminFixed=${adminFixed} countFixed=${countFixed} ` +
      `orphansFound=${orphansFound}`
  );
}

export const maintenanceGroupIntegrity = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 6 hours",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    const db = getFirestore();
    await repairGroupIntegrity(db, "maintenance-integrity");
  }
);

// ─── One-off migration: recompute all picks scores with new bonus rules ──────

export const migratePicksScores = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    // Only authenticated users can trigger this.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const db = getFirestore();
    const logPrefix = "migrate-picks-scores";

    // Collect all season/matchday combos from matchdays collection.
    const seasonsSnap = await db.collection("seasons").get();
    let totalUpdated = 0;

    for (const seasonDoc of seasonsSnap.docs) {
      const seasonKey = seasonDoc.id;
      const matchdaysSnap = await seasonDoc.ref.collection("matchdays").get();

      for (const mdDoc of matchdaysSnap.docs) {
        const dayNumber = parseInt(mdDoc.id, 10);
        if (isNaN(dayNumber)) continue;

        await recomputePicksScoresForMatchday(
          db,
          seasonKey,
          dayNumber,
          logPrefix
        );
        totalUpdated += 1;
      }
    }

    console.log(
      `[${logPrefix}] Migration complete. Processed ${totalUpdated} matchdays.`
    );
    return { success: true, matchdaysProcessed: totalUpdated };
  }
);

// ─── Cold Test System ────────────────────────────────────────────────────────
// Callable functions for end-to-end cold testing with real users.
// These allow wiping user data, seeding matchdays with accelerated timelines,
// and progressively revealing real match results.

async function deleteCollection(
  db: FirebaseFirestore.Firestore,
  collectionPath: string,
  batchSize = 400
): Promise<number> {
  let totalDeleted = 0;
  while (true) {
    const snap = await db.collection(collectionPath).limit(batchSize).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    totalDeleted += snap.docs.length;

    if (snap.docs.length < batchSize) break;
  }
  return totalDeleted;
}

async function deleteSubcollections(
  db: FirebaseFirestore.Firestore,
  parentCollection: string,
  subcollectionNames: string[],
  batchSize = 400
): Promise<number> {
  let totalDeleted = 0;
  const parentSnap = await db.collection(parentCollection).get();
  for (const parentDoc of parentSnap.docs) {
    for (const sub of subcollectionNames) {
      totalDeleted += await deleteCollection(
        db,
        `${parentCollection}/${parentDoc.id}/${sub}`,
        batchSize
      );
    }
  }
  return totalDeleted;
}

export const coldTestWipeData = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const db = getFirestore();
    const logPrefix = "cold-test-wipe";
    const deleted: Record<string, number> = {};

    // Delete subcollections first (members, chatMessages under groups)
    deleted.groupSubs = await deleteSubcollections(
      db,
      "groups",
      ["members", "chatMessages"]
    );
    console.log(`[${logPrefix}] Deleted ${deleted.groupSubs} group subcollection docs`);

    // Delete top-level collections (not seasons)
    for (const col of ["users", "groups", "group_invites", "picks"]) {
      deleted[col] = await deleteCollection(db, col);
      console.log(`[${logPrefix}] Deleted ${deleted[col]} docs from ${col}`);
    }

    // Clear Firebase Storage
    try {
      const bucket = getStorage().bucket();
      const [files] = await bucket.getFiles();
      let storageDeleted = 0;
      for (const file of files) {
        await file.delete();
        storageDeleted++;
      }
      deleted.storageFiles = storageDeleted;
      console.log(`[${logPrefix}] Deleted ${storageDeleted} storage files`);
    } catch (e) {
      console.warn(`[${logPrefix}] Storage cleanup error:`, e);
      deleted.storageFiles = 0;
    }

    console.log(`[${logPrefix}] Wipe complete`);
    return { success: true, deleted };
  }
);

interface ColdTestRealResult {
  outcome: Outcome;
  homeGoals: number | null;
  awayGoals: number | null;
}

export const coldTestSeedMatchday = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as Record<string, unknown>;
    const dayNumber = Number(data.dayNumber);
    if (!Number.isFinite(dayNumber) || dayNumber < 1 || dayNumber > 38) {
      throw new HttpsError(
        "invalid-argument",
        "dayNumber must be between 1 and 38."
      );
    }

    const kickoffIntervalMin = Math.max(
      3,
      Number(data.kickoffIntervalMin) || 10
    );
    const matchDurationMin = Math.max(5, Number(data.matchDurationMin) || 12);

    const db = getFirestore();
    const season = seasonStartYear();
    const seasonKey = season.toString();
    const logPrefix = "cold-test-seed";

    const docRef = db
      .collection("seasons")
      .doc(seasonKey)
      .collection("matchdays")
      .doc(dayNumber.toString());

    // Try to read existing matchday data first
    const existingSnap = await docRef.get();
    let matches: MatchDoc[];
    let realOutcomes: Record<string, ColdTestRealResult> = {};

    if (existingSnap.exists) {
      const existingData = existingSnap.data()!;
      const rawMatches = existingData.matches;
      if (!Array.isArray(rawMatches) || rawMatches.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          `Matchday ${dayNumber} exists but has no matches.`
        );
      }

      // Extract matches and compute real outcomes from existing data
      matches = rawMatches
        .filter(
          (m: unknown): m is Record<string, unknown> =>
            typeof m === "object" && m != null
        )
        .map((m: Record<string, unknown>) => m as unknown as MatchDoc);

      // Compute real outcomes from existing outcome data or match scores
      const existingOutcomes = parseOutcomesByMatchIdFromMatchdayData(
        existingData as Record<string, unknown>
      );
      for (const match of matches) {
        const existingOutcome = existingOutcomes[match.id];
        const hg =
          match.homeGoals != null ? Number(match.homeGoals) : null;
        const ag =
          match.awayGoals != null ? Number(match.awayGoals) : null;

        let outcome: Outcome;
        if (existingOutcome && existingOutcome !== "pending") {
          outcome = existingOutcome;
        } else if (hg != null && ag != null) {
          outcome = hg > ag ? "home" : hg < ag ? "away" : "draw";
        } else {
          outcome = "draw"; // fallback
        }

        realOutcomes[match.id] = {
          outcome,
          homeGoals: hg,
          awayGoals: ag,
        };
      }

      console.log(
        `[${logPrefix}] Using existing matchday ${dayNumber} data (${matches.length} matches)`
      );
    } else {
      // Fetch from API-Football
      console.log(
        `[${logPrefix}] No existing data, fetching from API-Football`
      );

      const leagueId = await resolveLeagueId(season, db);
      const json = await apiGet("fixtures", {
        league: leagueId.toString(),
        season: season.toString(),
        round: `Regular Season - ${dayNumber}`,
        timezone: "Europe/Rome",
      });

      const fixtures = parseFixtures(json);
      if (fixtures.length === 0) {
        throw new HttpsError(
          "not-found",
          `No fixtures found for matchday ${dayNumber}.`
        );
      }

      // Fetch odds for each fixture
      const oddsByFixture = new Map<number, FixtureOdds>();
      for (const f of fixtures) {
        const odds = await fetchOddsForFixture(f.fixtureId);
        if (odds) oddsByFixture.set(f.fixtureId, odds);
        await sleep(200);
      }

      // Build match docs and extract real outcomes
      matches = fixtures
        .sort((a, b) => a.kickoffUtc.localeCompare(b.kickoffUtc))
        .map((f) =>
          buildMatchDoc(
            f,
            oddsByFixture.get(f.fixtureId) ?? null,
            null
          )
        );

      for (const f of fixtures) {
        realOutcomes[f.fixtureId.toString()] = {
          outcome: computeOutcome(f),
          homeGoals: f.homeGoals,
          awayGoals: f.awayGoals,
        };
      }

      console.log(
        `[${logPrefix}] Fetched ${matches.length} fixtures with ${oddsByFixture.size} odds`
      );
    }

    // Rewrite kickoff times: staggered every kickoffIntervalMin from now + 20min
    const now = new Date();
    const firstKickoff = new Date(now.getTime() + 20 * 60 * 1000);

    for (let i = 0; i < matches.length; i++) {
      const newKickoff = new Date(
        firstKickoff.getTime() + i * kickoffIntervalMin * 60 * 1000
      );
      matches[i] = {
        ...matches[i],
        kickoff: newKickoff.toISOString(),
        // Reset live fields
        statusShort: "NS",
        homeGoals: undefined,
        awayGoals: undefined,
        elapsed: undefined,
        events: undefined,
      };
    }

    const lockTime = firstKickoff;
    const lastKickoff = new Date(
      firstKickoff.getTime() +
        (matches.length - 1) * kickoffIntervalMin * 60 * 1000
    );

    // Write to Firestore
    await docRef.set({
      matches,
      outcomesByMatchId: Object.fromEntries(
        matches.map((m) => [m.id, "pending"])
      ),
      lockTime: Timestamp.fromDate(lockTime),
      updatedAt: FieldValue.serverTimestamp(),
      finalized: false,
      _coldTestRealOutcomes: realOutcomes,
      _coldTestMatchDurationMin: matchDurationMin,
    });

    console.log(
      `[${logPrefix}] Seeded matchday ${dayNumber}: ${matches.length} matches, ` +
        `lockTime=${lockTime.toISOString()}, interval=${kickoffIntervalMin}min, ` +
        `duration=${matchDurationMin}min`
    );

    return {
      success: true,
      matchCount: matches.length,
      lockTime: lockTime.toISOString(),
      firstKickoff: firstKickoff.toISOString(),
      lastKickoff: lastKickoff.toISOString(),
    };
  }
);

export const coldTestResolveMatches = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as Record<string, unknown>;
    const dayNumber = Number(data.dayNumber);
    if (!Number.isFinite(dayNumber) || dayNumber < 1 || dayNumber > 38) {
      throw new HttpsError(
        "invalid-argument",
        "dayNumber must be between 1 and 38."
      );
    }

    const db = getFirestore();
    const season = seasonStartYear();
    const seasonKey = season.toString();
    const logPrefix = "cold-test-resolve";

    const docRef = db
      .collection("seasons")
      .doc(seasonKey)
      .collection("matchdays")
      .doc(dayNumber.toString());

    const snap = await docRef.get();
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        `Matchday ${dayNumber} not found.`
      );
    }

    const matchdayData = snap.data()!;
    const rawRealOutcomes = matchdayData._coldTestRealOutcomes;
    if (!rawRealOutcomes || typeof rawRealOutcomes !== "object") {
      throw new HttpsError(
        "failed-precondition",
        "This matchday was not seeded by cold test."
      );
    }

    const realOutcomes = rawRealOutcomes as Record<
      string,
      ColdTestRealResult
    >;
    const matchDurationMin = Number(matchdayData._coldTestMatchDurationMin) || 12;

    const rawMatches = matchdayData.matches;
    if (!Array.isArray(rawMatches)) {
      throw new HttpsError(
        "failed-precondition",
        "No matches in matchday document."
      );
    }

    const existingOutcomes = parseOutcomesByMatchIdFromMatchdayData(
      matchdayData as Record<string, unknown>
    );

    const now = new Date();
    let revealed = 0;
    let pending = 0;
    const updatedOutcomes = { ...existingOutcomes };
    const updatedMatches = [...rawMatches];

    for (let i = 0; i < updatedMatches.length; i++) {
      const match = updatedMatches[i] as Record<string, unknown>;
      const matchId = String(match.id ?? "");
      if (!matchId) continue;

      // Already resolved
      if (updatedOutcomes[matchId] && updatedOutcomes[matchId] !== "pending") {
        revealed++;
        continue;
      }

      const kickoffStr = String(match.kickoff ?? "");
      const kickoff = new Date(kickoffStr);
      if (Number.isNaN(kickoff.getTime())) {
        pending++;
        continue;
      }

      const endTime = new Date(
        kickoff.getTime() + matchDurationMin * 60 * 1000
      );

      if (now >= endTime) {
        // Reveal this match
        const real = realOutcomes[matchId];
        if (real) {
          updatedOutcomes[matchId] = real.outcome;
          updatedMatches[i] = {
            ...match,
            statusShort: "FT",
            homeGoals: real.homeGoals ?? 0,
            awayGoals: real.awayGoals ?? 0,
            elapsed: 90,
          };
          revealed++;
        } else {
          pending++;
        }
      } else if (now >= kickoff) {
        // Match is "in progress" — update status
        const elapsedMs = now.getTime() - kickoff.getTime();
        const simulatedMinute = Math.min(
          90,
          Math.round((elapsedMs / (matchDurationMin * 60 * 1000)) * 90)
        );
        updatedMatches[i] = {
          ...match,
          statusShort: simulatedMinute >= 45 ? "2H" : "1H",
          elapsed: simulatedMinute,
          homeGoals: 0,
          awayGoals: 0,
        };
        pending++;
      } else {
        pending++;
      }
    }

    const finalized =
      pending === 0 &&
      revealed > 0 &&
      Object.values(updatedOutcomes).every((o) => o !== "pending");

    await docRef.update({
      matches: updatedMatches,
      outcomesByMatchId: updatedOutcomes,
      finalized,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Recompute scores for all picks
    await recomputePicksScoresForMatchday(
      db,
      seasonKey,
      dayNumber,
      logPrefix
    );

    console.log(
      `[${logPrefix}] Matchday ${dayNumber}: revealed=${revealed} pending=${pending} finalized=${finalized}`
    );

    return { revealed, pending, finalized };
  }
);
