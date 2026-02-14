import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineString } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
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
  odds: {
    home: number;
    draw: number;
    away: number;
    homeDraw: number;
    drawAway: number;
    homeAway: number;
  };
}

type Outcome = "home" | "draw" | "away" | "pending" | "voided";

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
        homeName: String(home["name"] ?? "Home"),
        awayName: String(away["name"] ?? "Away"),
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
        teamName: String(team["name"] ?? "?"),
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

function round2(v: number): number {
  return Math.round(v * 100) / 100;
}

function clamp(v: number, min: number, max: number): number {
  if (max < min) return min;
  return Math.max(min, Math.min(max, v));
}

function buildMatchDoc(
  f: ApiFixture,
  odds: FixtureOdds | null
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
  return doc;
}

function mergeLiveFieldsIntoExistingMatches(
  existingMatches: unknown,
  fixtures: ApiFixture[]
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

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

    if (existing.exists && existing.data()?.finalized === true) {
      console.log(`[${options.logPrefix}] Matchday ${md} finalized, skip`);
      continue;
    }

    const outcomesByMatchId: Record<string, Outcome> = {};
    for (const f of fixtures) {
      outcomesByMatchId[f.fixtureId.toString()] = computeOutcome(f);
    }

    const kickoffs = fixtures.map((f) => new Date(f.kickoffUtc));
    const lockTime = kickoffs.reduce((min, d) => (d < min ? d : min));
    const finalized = Object.values(outcomesByMatchId).every(
      (o) => o !== "pending"
    );

    if (!options.includeOdds) {
      if (!existing.exists) {
        console.log(
          `[${options.logPrefix}] Matchday ${md} missing doc, skip write`
        );
        continue;
      }
      const existingMatches = existing.data()?.matches;
      const mergedMatches = mergeLiveFieldsIntoExistingMatches(
        existingMatches,
        fixtures
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
      console.log(
        `[${options.logPrefix}] Wrote live outcomes ${md}: finalized=${finalized}`
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
      .map((f) => buildMatchDoc(f, oddsByFixture.get(f.fixtureId) ?? null));

    await docRef.set(
      {
        matches,
        outcomesByMatchId,
        lockTime: Timestamp.fromDate(lockTime),
        updatedAt: FieldValue.serverTimestamp(),
        finalized,
      },
      { merge: true }
    );

    console.log(
      `[${options.logPrefix}] Wrote matchday ${md}: finalized=${finalized}`
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
