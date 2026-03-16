import type { SentryClient } from "./sentry-client.js";
import type { ProcessedIssueState } from "./types.js";
import { loadState, saveState, saveIssue, loadAllIssues, ensureDataDirs } from "./storage.js";
import { log } from "./logger.js";
import { processRules } from "./rules/index.js";
import { stopReporter } from "./reporter.js";

const DEFAULT_SEARCH_QUERY = "LogSource:client";

export interface PollerConfig {
  pollInterval: number; // seconds
  searchQuery?: string;
  // Legacy — kept for backwards compat but no longer used
  alertRuleName?: string;
}

let running = true;

export function stopPolling(): void {
  running = false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Re-fetch current status for all tracked issues from Sentry.
 * Updates the local saved issue files so processRules() sees current statuses.
 */
export async function refreshIssueStatuses(client: SentryClient): Promise<void> {
  const saved = await loadAllIssues();
  if (saved.length === 0) return;

  log.info(`[Poll] Refreshing statuses for ${saved.length} tracked issues...`);
  let updated = 0;

  for (const si of saved) {
    if (!running) break;
    try {
      const fresh = await client.getIssue(si.issue.id);
      if (fresh.status !== si.issue.status) {
        log.info(
          `[Poll] Issue ${si.issue.shortId} status: ${si.issue.status} → ${fresh.status}`
        );
        si.issue.status = fresh.status;
        si.issue.statusDetails = fresh.statusDetails ?? {};
        await saveIssue(si.issue, si.events);
        updated++;
      }
    } catch (err) {
      log.warn(`[Poll] Failed to refresh status for ${si.issue.id}: ${err}`);
    }
  }

  if (updated > 0) {
    log.info(`[Poll] Updated ${updated} issue statuses`);
  }
}

export async function startPolling(
  client: SentryClient,
  config: PollerConfig
): Promise<void> {
  await ensureDataDirs();

  process.on("SIGINT", () => {
    log.info("[Poll] SIGINT received, finishing current cycle...");
    running = false;
    stopReporter();
  });
  process.on("SIGTERM", () => {
    log.info("[Poll] SIGTERM received, finishing current cycle...");
    running = false;
    stopReporter();
  });

  const searchQuery = config.searchQuery || DEFAULT_SEARCH_QUERY;
  log.info(
    `[Poll] Starting poller (interval: ${config.pollInterval}s, query: "${searchQuery}")`
  );

  // Refresh issue statuses from Sentry on startup before first poll
  await refreshIssueStatuses(client);
  await processRules();

  while (running) {
    try {
      await pollCycle(client, searchQuery);
      await refreshIssueStatuses(client);
      await processRules();
    } catch (err) {
      log.error("[Poll] Error during poll cycle:", err);
    }

    if (!running) break;

    log.info(`[Poll] Sleeping ${config.pollInterval}s until next cycle...`);
    const sleepMs = config.pollInterval * 1000;
    const sleepStep = 1000;
    for (let elapsed = 0; elapsed < sleepMs && running; elapsed += sleepStep) {
      await sleep(Math.min(sleepStep, sleepMs - elapsed));
    }
  }

  log.info("[Poll] Poller stopped.");
}

async function pollCycle(
  client: SentryClient,
  searchQuery: string
): Promise<void> {
  const state = await loadState();
  const now = new Date().toISOString();

  log.info(`[Poll] Searching Sentry issues: "${searchQuery}"`);

  const issues = await client.searchIssuesPaginated(searchQuery);

  log.info(`[Poll] Got ${issues.length} issues from search`);

  if (issues.length === 0) {
    state.lastPollTime = now;
    await saveState(state);
    log.info("[Poll] No issues found");
    return;
  }

  let newCount = 0;
  let updatedCount = 0;
  let skippedCount = 0;

  for (const issue of issues) {
    if (!running) break;

    const existing = state.processedIssues[issue.id];

    // Skip if already processed with same lastSeen and count
    if (existing && existing.lastTriggered === issue.lastSeen && existing.count === parseInt(issue.count, 10)) {
      skippedCount++;
      continue;
    }

    const isNew = !existing;

    try {
      log.info(
        `[Poll] ${isNew ? "New" : "Updated"} issue ${issue.shortId}: ${issue.title}`
      );
      const events = await client.getIssueFullEvents(issue.id, 5);

      await saveIssue(issue, events);

      const lastEventId =
        events.length > 0
          ? events[0].eventID
          : existing?.lastEventId ?? "";

      const issueState: ProcessedIssueState = {
        lastTriggered: issue.lastSeen,
        lastEventId,
        count: parseInt(issue.count, 10) || 0,
      };
      state.processedIssues[issue.id] = issueState;

      if (isNew) newCount++;
      else updatedCount++;
    } catch (err) {
      log.error(`[Poll] Failed to process issue ${issue.shortId}:`, err);
    }
  }

  state.lastPollTime = now;
  await saveState(state);

  const totalProcessed = Object.keys(state.processedIssues).length;
  log.info(
    `[Poll] ${newCount} new, ${updatedCount} updated, ${skippedCount} skipped, ${totalProcessed} total tracked issues`
  );
}
