import { writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { SentryClient } from "./sentry-client.js";
import type { SentryResolvedIssue } from "./types.js";
import { log } from "./logger.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPORTS_DIR = join(__dirname, "..", "data", "reports");

function todayDateStr(): string {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

function formatMinutes(mins: number): string {
  if (mins < 60) return `${mins}m`;
  if (mins < 1440) return `${Math.round(mins / 60)}h`;
  return `${Math.round(mins / 1440)}d`;
}

function formatConditions(issue: SentryResolvedIssue): string {
  const sd = issue.statusDetails || {};

  // Archived issues
  if (issue.status === "ignored") {
    switch (issue.substatus) {
      case "archived_forever":
        return "archived forever";

      case "archived_until_escalating":
        return "archived until escalating";

      case "archived_until_condition_met": {
        const parts: string[] = [];

        if (sd.ignoreCount != null) {
          let s = `${sd.ignoreCount.toLocaleString()} more events`;
          if (sd.ignoreWindow != null) s += ` in ${formatMinutes(sd.ignoreWindow)}`;
          parts.push(s);
        }

        if (sd.ignoreUserCount != null) {
          let s = `${sd.ignoreUserCount.toLocaleString()} more users`;
          if (sd.ignoreUserWindow != null) s += ` in ${formatMinutes(sd.ignoreUserWindow)}`;
          parts.push(s);
        }

        if (sd.ignoreUntil != null) {
          const until = new Date(sd.ignoreUntil);
          parts.push(`${until.toISOString().slice(0, 10)}`);
        }

        return parts.length > 0
          ? `archived until ${parts.join(" or ")}`
          : "archived (condition)";
      }

      default:
        return `archived (${issue.substatus || "unknown"})`;
    }
  }

  // Resolved issues
  if (sd.inRelease) {
    return `in release ${sd.inRelease}`;
  } else if (sd.inNextRelease) {
    return "in next release";
  } else if (sd.inCommit) {
    return `in commit ${sd.inCommit.id.slice(0, 8)}`;
  }

  return "manually";
}

interface ReportRow {
  issue: SentryResolvedIssue;
  action: "Resolved" | "Archived";
  actor: string;
  latestComment: string;
}

function buildReport(date: string, rows: ReportRow[]): string {
  const lines: string[] = [];
  const resolvedCount = rows.filter((r) => r.action === "Resolved").length;
  const archivedCount = rows.filter((r) => r.action === "Archived").length;
  const total = rows.length;

  lines.push(`# Daily Issues Report — ${date}`);
  lines.push("");
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Resolved: ${resolvedCount} | Archived: ${archivedCount} | Total: ${total}`);
  lines.push("");

  if (total === 0) {
    lines.push("No resolved or archived issues today.");
    return lines.join("\n");
  }

  lines.push("| # | Issue | Action | By | Conditions | Jira | Comment |");
  lines.push("|---|-------|--------|----|------------|------|---------|");

  let idx = 1;
  for (const row of rows) {
    const title = row.issue.title.replace(/\|/g, "\\|").slice(0, 100);
    const sentryLink = `[${row.issue.shortId}](${row.issue.permalink})`;
    const jira = getJiraLink(row.issue);
    const comment = row.latestComment.replace(/\|/g, "\\|").replace(/\n/g, " ");
    lines.push(
      `| ${idx++} | ${sentryLink}: ${title} | ${row.action} | ${row.actor} | ${formatConditions(row.issue)} | ${jira} | ${comment} |`
    );
  }

  return lines.join("\n");
}

function getJiraLink(issue: SentryResolvedIssue): string {
  const jiraAnnotation = (issue.annotations || []).find(
    (a) => a.url && a.url.includes("atlassian")
  );
  return jiraAnnotation
    ? `[${jiraAnnotation.displayName}](${jiraAnnotation.url})`
    : "—";
}

/**
 * Check each issue's per-issue activity feed for a status change today.
 * Returns only issues whose status was actually changed on the given date.
 */
async function findChangedToday(
  client: SentryClient,
  issues: SentryResolvedIssue[],
  actionType: "set_ignored" | "set_resolved",
  date: string
): Promise<ReportRow[]> {
  const rows: ReportRow[] = [];
  const action: "Resolved" | "Archived" =
    actionType === "set_resolved" ? "Resolved" : "Archived";

  for (const issue of issues) {
    try {
      const activities = await client.getIssueActivities(issue.id, 10);

      const match = activities.find((a) => {
        if (a.type !== actionType) return false;
        const created = String(a.dateCreated ?? "");
        return created.startsWith(date);
      });

      if (!match) continue;

      // Extract latest note/comment from activity feed
      const latestNote = activities.find((a) => a.type === "note");
      const latestComment = (latestNote?.data as { text?: string })?.text || "";

      const actor = match.user?.name || match.user?.email || "—";
      rows.push({ issue, action, actor, latestComment });
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      log.warn(
        `[Reporter] Failed to fetch activities for issue ${issue.shortId}: ${errMsg}`
      );
    }
  }

  return rows;
}

async function generateReport(client: SentryClient): Promise<void> {
  const date = todayDateStr();
  const reportPath = join(REPORTS_DIR, `${date}.md`);

  log.info(`[Reporter] Fetching issues for ${date}...`);

  // Fetch candidates sequentially (safe for Pi — one request at a time)
  const archivedIssues = await client.searchIssuesPaginated("is:ignored", 3);
  const resolvedIssues = await client.searchIssuesPaginated("is:resolved", 3);

  log.info(
    `[Reporter] Found ${archivedIssues.length} archived + ${resolvedIssues.length} resolved candidates`
  );

  // Check each issue's activity sequentially to avoid overwhelming Sentry/Pi
  const archivedRows = await findChangedToday(client, archivedIssues, "set_ignored", date);
  const resolvedRows = await findChangedToday(client, resolvedIssues, "set_resolved", date);

  log.info(
    `[Reporter] Confirmed ${archivedRows.length} archived + ${resolvedRows.length} resolved today`
  );

  const allRows = [...archivedRows, ...resolvedRows];
  const report = buildReport(date, allRows);
  await writeFile(reportPath, report + "\n");

  log.info(`[Reporter] Report written to ${reportPath}`);
}

let reporterInterval: ReturnType<typeof setInterval> | null = null;

export async function startReporter(
  client: SentryClient,
  intervalSeconds: number
): Promise<void> {
  await mkdir(REPORTS_DIR, { recursive: true });

  log.info(
    `[Reporter] Starting reporter (interval: ${intervalSeconds}s)`
  );

  let running = false;

  const runCycle = async () => {
    if (running) {
      log.info("[Reporter] Previous cycle still running, skipping...");
      return;
    }
    running = true;
    try {
      await generateReport(client);
    } catch (err) {
      log.error("[Reporter] Report update failed:", err);
    } finally {
      running = false;
    }
  };

  // Run immediately on start
  await runCycle();

  // Then on interval (overlap-safe)
  reporterInterval = setInterval(runCycle, intervalSeconds * 1000);
}

export function stopReporter(): void {
  if (reporterInterval) {
    clearInterval(reporterInterval);
    reporterInterval = null;
    log.info("[Reporter] Stopped.");
  }
}
