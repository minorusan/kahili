import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  PollState,
  SentryIssue,
  SentryFullEvent,
  SavedIssue,
} from "./types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..");

const DATA_DIR = join(PROJECT_ROOT, "data");
const ISSUES_DIR = join(DATA_DIR, "issues");
const STATE_FILE = join(DATA_DIR, "state.json");

export async function ensureDataDirs(): Promise<void> {
  await mkdir(ISSUES_DIR, { recursive: true });
}

export async function loadState(): Promise<PollState> {
  if (!existsSync(STATE_FILE)) {
    return {
      lastPollTime: null,
      alertRuleId: null,
      alertRuleName: null,
      processedIssues: {},
    };
  }

  const raw = await readFile(STATE_FILE, "utf-8");
  return JSON.parse(raw) as PollState;
}

export async function saveState(state: PollState): Promise<void> {
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

export async function saveIssue(
  issue: SentryIssue,
  events: SentryFullEvent[]
): Promise<void> {
  const filePath = join(ISSUES_DIR, `${issue.id}.json`);
  const now = new Date().toISOString();

  let savedAt = now;
  let firstSeenRelease: string | undefined;
  if (existsSync(filePath)) {
    try {
      const existing = JSON.parse(
        await readFile(filePath, "utf-8")
      ) as SavedIssue;
      savedAt = existing.savedAt;
      firstSeenRelease = existing.firstSeenRelease;
    } catch {
      // Corrupted file, reset savedAt
    }
  }

  // Set firstSeenRelease from events if not already set
  if (!firstSeenRelease && events.length > 0) {
    // Use the oldest event's release (events are newest-first)
    const oldest = events[events.length - 1];
    firstSeenRelease = oldest.release ?? undefined;
  }

  const saved: SavedIssue = {
    issue,
    events,
    firstSeenRelease,
    savedAt,
    updatedAt: now,
  };

  await writeFile(filePath, JSON.stringify(saved, null, 2));
}

export async function loadIssue(issueId: string): Promise<SavedIssue | null> {
  const filePath = join(ISSUES_DIR, `${issueId}.json`);

  if (!existsSync(filePath)) {
    return null;
  }

  const raw = await readFile(filePath, "utf-8");
  return JSON.parse(raw) as SavedIssue;
}

export async function backfillFirstSeenRelease(): Promise<number> {
  let backfilled = 0;
  let files: string[];
  try {
    files = await readdir(ISSUES_DIR);
  } catch {
    return 0;
  }
  const jsonFiles = files.filter((f) => f.endsWith(".json"));
  for (const file of jsonFiles) {
    const filePath = join(ISSUES_DIR, file);
    try {
      const raw = await readFile(filePath, "utf-8");
      const saved = JSON.parse(raw) as SavedIssue;
      if (saved.firstSeenRelease) continue;

      // Compute from events (oldest event = last in array)
      if (saved.events.length > 0) {
        const oldest = saved.events[saved.events.length - 1];
        if (oldest.release) {
          saved.firstSeenRelease = oldest.release;
          await writeFile(filePath, JSON.stringify(saved, null, 2));
          backfilled++;
        }
      }
    } catch {
      // skip corrupt files
    }
  }
  return backfilled;
}

export async function loadAllIssues(): Promise<SavedIssue[]> {
  let files: string[];
  try {
    files = await readdir(ISSUES_DIR);
  } catch {
    return [];
  }
  const jsonFiles = files.filter((f) => f.endsWith(".json"));
  const issues: SavedIssue[] = [];
  for (const file of jsonFiles) {
    try {
      const raw = await readFile(join(ISSUES_DIR, file), "utf-8");
      issues.push(JSON.parse(raw) as SavedIssue);
    } catch {
      // skip corrupt files
    }
  }
  return issues;
}
