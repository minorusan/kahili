import { readFile, writeFile, mkdir } from "node:fs/promises";
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
  if (existsSync(filePath)) {
    try {
      const existing = JSON.parse(
        await readFile(filePath, "utf-8")
      ) as SavedIssue;
      savedAt = existing.savedAt;
    } catch {
      // Corrupted file, reset savedAt
    }
  }

  const saved: SavedIssue = {
    issue,
    events,
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
