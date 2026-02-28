import type { SentryClient } from "./sentry-client.js";
import type { ProcessedIssueState } from "./types.js";
import { loadState, saveState, saveIssue, ensureDataDirs } from "./storage.js";
import { log } from "./logger.js";
import { processRules } from "./rules/index.js";

const DEFAULT_ALERT_RULE_NAME = "Client Errors";

export interface PollerConfig {
  pollInterval: number; // seconds
  alertRuleName?: string;
}

let running = true;

export function stopPolling(): void {
  running = false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function startPolling(
  client: SentryClient,
  config: PollerConfig
): Promise<void> {
  await ensureDataDirs();

  process.on("SIGINT", () => {
    log.info("[Poll] SIGINT received, finishing current cycle...");
    running = false;
  });
  process.on("SIGTERM", () => {
    log.info("[Poll] SIGTERM received, finishing current cycle...");
    running = false;
  });

  const alertRuleName = config.alertRuleName || DEFAULT_ALERT_RULE_NAME;
  log.info(
    `[Poll] Starting poller (interval: ${config.pollInterval}s, alert rule: "${alertRuleName}")`
  );

  // Resolve alert rule ID once at startup
  log.info(`[Poll] Resolving alert rule "${alertRuleName}"...`);
  const rule = await client.findAlertRuleByName(alertRuleName);
  if (!rule) {
    log.error(
      `[Poll] Alert rule "${alertRuleName}" not found. Available rules listed above.`
    );
    const allRules = await client.getAlertRules();
    log.info(
      `[Poll] Available alert rules: ${allRules.map((r) => `"${r.name}" (id: ${r.id})`).join(", ")}`
    );
    process.exit(1);
  }

  const alertRuleId = rule.id;
  log.info(
    `[Poll] Resolved alert rule "${rule.name}" → id: ${alertRuleId}`
  );

  // Cache rule info in state
  const state = await loadState();
  state.alertRuleId = alertRuleId;
  state.alertRuleName = rule.name;
  await saveState(state);

  while (running) {
    try {
      await pollCycle(client, alertRuleId);
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
  alertRuleId: string
): Promise<void> {
  const state = await loadState();
  const now = new Date().toISOString();

  // Use last poll time as start, or 24h ago for first run
  const start =
    state.lastPollTime ||
    new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const end = now;

  log.info(`[Poll] Querying alert rule group-history (${start} → ${end})`);

  const historyItems = await client.getAlertRuleGroupHistory(
    alertRuleId,
    start,
    end
  );

  log.info(
    `[Poll] Got ${historyItems.length} triggered issues from alert rule`
  );

  if (historyItems.length === 0) {
    state.lastPollTime = now;
    await saveState(state);
    log.info("[Poll] No new triggered issues");
    return;
  }

  let newCount = 0;
  let updatedCount = 0;
  let skippedCount = 0;

  for (const item of historyItems) {
    if (!running) break;

    const issue = item.group;
    const existing = state.processedIssues[issue.id];

    // Skip if already processed with same lastTriggered
    if (existing && existing.lastTriggered === item.lastTriggered) {
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
        lastTriggered: item.lastTriggered,
        lastEventId,
        count: item.count,
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
