import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Rule, type MotherIssue } from "./rule.js";
import { NreRule } from "./nre-rule.js";
import {
  saveMotherIssue,
  loadAllMotherIssues,
  ensureMotherIssuesDir,
} from "./storage.js";
import { log } from "../logger.js";
import type { SavedIssue } from "../types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ISSUES_DIR = join(__dirname, "..", "..", "data", "issues");

const RULES: Rule[] = [new NreRule()];

const SEVERITY_ORDER: Record<string, number> = {
  debug: 0,
  info: 1,
  warning: 2,
  error: 3,
  fatal: 4,
};

function highestLevel(a: string, b: string): string {
  return (SEVERITY_ORDER[a] ?? 0) >= (SEVERITY_ORDER[b] ?? 0) ? a : b;
}

async function loadAllIssues(): Promise<SavedIssue[]> {
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

export function runRules(issues: SavedIssue[]): MotherIssue[] {
  // Group: ruleKey → list of matching issues
  const groups = new Map<string, { rule: Rule; issues: SavedIssue[] }>();

  for (const issue of issues) {
    for (const rule of RULES) {
      const key = rule.groupingKey(issue);
      if (key === null) continue;

      let group = groups.get(key);
      if (!group) {
        group = { rule, issues: [] };
        groups.set(key, group);
      }
      group.issues.push(issue);
    }
  }

  const motherIssues: MotherIssue[] = [];
  const now = new Date().toISOString();

  for (const [groupingKey, { rule, issues: groupIssues }] of groups) {
    const id = createHash("sha256")
      .update(groupingKey)
      .digest("hex")
      .slice(0, 16);

    // Compute aggregate metrics
    let totalOccurrences = 0;
    let affectedUsers = 0;
    let firstSeen = groupIssues[0].issue.firstSeen;
    let lastSeen = groupIssues[0].issue.lastSeen;
    let level: string = groupIssues[0].issue.level;

    for (const si of groupIssues) {
      totalOccurrences += parseInt(si.issue.count, 10) || 0;
      affectedUsers += si.issue.userCount || 0;

      if (si.issue.firstSeen < firstSeen) firstSeen = si.issue.firstSeen;
      if (si.issue.lastSeen > lastSeen) lastSeen = si.issue.lastSeen;

      level = highestLevel(level, si.issue.level);
    }

    // Extract stack trace from first issue's first event
    let stackTrace: MotherIssue["stackTrace"];
    const frames =
      groupIssues[0].events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    if (frames?.length) {
      stackTrace = {
        frames: frames.map((f) => ({
          filename: f.filename,
          function: f.function,
          lineno: f.lineno,
          inApp: f.inApp,
        })),
      };
    }

    const mi: MotherIssue = {
      id,
      groupingKey,
      ruleName: rule.name,
      title: groupIssues[0].issue.title,
      errorType: groupIssues[0].issue.metadata.type || "Error",
      level,
      metrics: {
        totalOccurrences,
        affectedUsers,
        firstSeen,
        lastSeen,
      },
      childIssueIds: groupIssues.map((si) => si.issue.id),
      stackTrace,
      createdAt: now,
      updatedAt: now,
    };

    motherIssues.push(mi);
  }

  return motherIssues;
}

export async function processRules(): Promise<void> {
  await ensureMotherIssuesDir();

  const issues = await loadAllIssues();
  if (issues.length === 0) {
    log.info("[Rules] No issues to process");
    return;
  }

  // Load existing mother issues to preserve createdAt
  const existing = await loadAllMotherIssues();
  const existingMap = new Map(existing.map((mi) => [mi.id, mi]));

  const motherIssues = runRules(issues);

  for (const mi of motherIssues) {
    const prev = existingMap.get(mi.id);
    if (prev) {
      mi.createdAt = prev.createdAt;
    }
    await saveMotherIssue(mi);
  }

  log.info(
    `[Rules] Processed ${issues.length} issues → ${motherIssues.length} mother issues`
  );
}
