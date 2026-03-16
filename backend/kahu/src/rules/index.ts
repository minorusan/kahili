import { createHash } from "node:crypto";
import { Rule, type MotherIssue } from "./rule.js";
import { MilestoneErrorRule } from "./milestone-error-rule.js";
import { UnityWebRequestRule } from "./unity-webrequest-rule.js";
import { SkullIconRule } from "./skull-icon-rule.js";
import { HttpClientErrorStartRule } from "./http-client-error-start-rule.js";
import { HttpClientErrorStatusCodeRule } from "./http-client-error-status-code-rule.js";
import { SkuIconRule } from "./sku-icon-rule.js";
import { SkuProviderNotFoundRule } from "./sku-provider-not-found-rule.js";
import { CouponsServiceRule } from "./coupons-service-rule.js";
import { AlbumLiveOpInitRule } from "./album-liveop-init-rule.js";
import { AlbumMessagePrefixRule } from "./album-message-prefix-rule.js";
import { ManagedStacktraceRule } from "./managed-stacktrace-rule.js";
import { NreManagedStacktraceRule } from "./nre-managed-stacktrace-rule.js";
import { ContinuousOperationStampItStacktraceRule } from "./continuous-operation-stampit-stacktrace-rule.js";
import { ContinuousOperationStampItTitleRule } from "./continuous-operation-stampit-title-rule.js";
import { BigDataFailedToSendRule } from "./big-data-failed-to-send-rule.js";
import { UpdatingMilestonesFailedRule } from "./updating-milestones-failed-rule.js";
import { MissingOfferSlotViewRule } from "./missing-offer-slot-view-rule.js";
import {
  saveMotherIssue,
  loadAllMotherIssues,
  ensureMotherIssuesDir,
} from "./storage.js";
import { loadAllIssues, backfillFirstSeenRelease } from "../storage.js";
import { log } from "../logger.js";
import type { SavedIssue } from "../types.js";

export const RULES: Rule[] = [ new MilestoneErrorRule(), new UnityWebRequestRule(), new SkullIconRule(), new HttpClientErrorStartRule(), new HttpClientErrorStatusCodeRule(), new SkuIconRule(), new SkuProviderNotFoundRule(), new CouponsServiceRule(), new ContinuousOperationStampItStacktraceRule(), new ContinuousOperationStampItTitleRule(), new AlbumLiveOpInitRule(), new AlbumMessagePrefixRule(), new ManagedStacktraceRule(), new NreManagedStacktraceRule(), new BigDataFailedToSendRule(), new UpdatingMilestonesFailedRule(), new MissingOfferSlotViewRule()];

/**
 * Parse Unity/C# stack frames from a message string.
 * Formats:
 *   ClassName.Method () (at file.cs:123)
 *   ClassName+<Lambda>d__1:MoveNext()
 *   Namespace.Class.<Method>d__5:MoveNext()
 */
export function parseStackFromMessage(
  msg: string
): Array<{ filename: string; function: string; lineno: number; inApp: boolean }> {
  // Split on literal \n (from JSON) or actual newlines
  const lines = msg.replace(/\\n/g, "\n").split("\n");
  if (lines.length < 2) return [];

  const frames: Array<{
    filename: string;
    function: string;
    lineno: number;
    inApp: boolean;
  }> = [];

  // Skip first line (error message), parse the rest as frames
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // Try to extract "(at file:line)" part
    const atMatch = line.match(/\(at\s+(.+?):(\d+)\)/);
    const filename = atMatch?.[1] ?? "";
    const lineno = atMatch ? parseInt(atMatch[2], 10) : 0;

    // Function name is everything before "(at ...)" or the whole line
    let fn = atMatch
      ? line.slice(0, line.indexOf("(at")).trim()
      : line;

    // Clean up trailing parens/spaces
    fn = fn.replace(/\s*\(.*$/, "").trim();
    if (!fn) continue;

    // inApp heuristic: starts with "ninja." or "PlayPerfect." or doesn't contain "System." / "Cysharp."
    const isFramework =
      fn.startsWith("System.") ||
      fn.startsWith("Cysharp.") ||
      fn.startsWith("UnityEngine.") ||
      fn.startsWith("TMPro.");
    const inApp = !isFramework;

    frames.push({ filename, function: fn, lineno, inApp });
  }

  return frames;
}

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
    let firstSeenRelease: string | undefined;

    for (const si of groupIssues) {
      totalOccurrences += parseInt(si.issue.count, 10) || 0;
      affectedUsers += si.issue.userCount || 0;

      if (si.issue.firstSeen < firstSeen) {
        firstSeen = si.issue.firstSeen;
        if (si.firstSeenRelease) firstSeenRelease = si.firstSeenRelease;
      }
      if (si.issue.lastSeen > lastSeen) lastSeen = si.issue.lastSeen;

      level = highestLevel(level, si.issue.level);

      // Track earliest release across all children
      if (!firstSeenRelease && si.firstSeenRelease) {
        firstSeenRelease = si.firstSeenRelease;
      }
    }

    // Extract stack trace from first issue's first event
    let stackTrace: MotherIssue["stackTrace"];
    const structuredFrames =
      groupIssues[0].events[0]?.exception?.values?.[0]?.stacktrace?.frames;
    if (structuredFrames?.length) {
      stackTrace = {
        frames: structuredFrames.map((f) => ({
          filename: f.filename,
          function: f.function,
          lineno: f.lineno,
          inApp: f.inApp,
        })),
      };
    } else {
      // Parse stack trace from message text (common for Unity/C# issues)
      const msg = groupIssues[0].events[0]?.message || groupIssues[0].issue.title || "";
      const parsed = parseStackFromMessage(msg);
      if (parsed.length > 0) {
        stackTrace = { frames: parsed };
      }
    }

    // Collect sentry permalinks and smartlook URLs
    const sentryLinks: string[] = [];
    const smartlookSet = new Set<string>();
    for (const si of groupIssues) {
      if (si.issue.permalink) sentryLinks.push(si.issue.permalink);
      for (const evt of si.events) {
        // Check contexts.smartlook.url
        const sl = evt.contexts?.smartlook as
          | { url?: string; [key: string]: unknown }
          | undefined;
        if (sl?.url) smartlookSet.add(sl.url);
        // Check tags for SmartlookUrl
        for (const tag of evt.tags ?? []) {
          if (tag.key === "SmartlookUrl" && tag.value) {
            smartlookSet.add(tag.value);
          }
        }
      }
    }

    // Check if every child issue has been archived/resolved (i.e. not unresolved)
    const allChildrenArchived =
      groupIssues.length > 0 &&
      groupIssues.every((si) => si.issue.status !== "unresolved");

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
      childStatuses: groupIssues.map((si) => si.issue.status ?? "unresolved"),
      sentryLinks,
      smartlookUrls: [...smartlookSet],
      stackTrace,
      firstSeenRelease,
      allChildrenArchived,
      createdAt: now,
      updatedAt: now,
    };

    motherIssues.push(mi);
  }

  return motherIssues;
}

export async function processRules(): Promise<void> {
  await ensureMotherIssuesDir();

  // One-time backfill: populate firstSeenRelease from stored events
  const backfilled = await backfillFirstSeenRelease();
  if (backfilled > 0) {
    log.info(`[Rules] Backfilled firstSeenRelease for ${backfilled} issues`);
  }

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
      // Preserve first seen release if not freshly computed
      if (!mi.firstSeenRelease && prev.firstSeenRelease) {
        mi.firstSeenRelease = prev.firstSeenRelease;
      }
    }
    await saveMotherIssue(mi);
  }

  log.info(
    `[Rules] Processed ${issues.length} issues → ${motherIssues.length} mother issues`
  );
}
