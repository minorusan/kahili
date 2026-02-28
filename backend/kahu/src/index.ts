import "dotenv/config";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./logger.js";
import { SentryClient } from "./sentry-client.js";
import { startPolling } from "./poller.js";
import { startServer } from "./server.js";
import { processRules } from "./rules/index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

let buildNumber = "?";
try {
  const buildFile = resolve(__dirname, "../..", "build.json");
  const buildInfo = JSON.parse(readFileSync(buildFile, "utf-8"));
  buildNumber = String(buildInfo.build);
} catch {
  // build.json not available — running standalone
}

export { buildNumber };

const token = process.env.SENTRY_TOKEN;
const org = process.env.SENTRY_ORG;
const project = process.env.SENTRY_PROJECT;
const pollInterval = parseInt(process.env.POLL_INTERVAL || "300", 10);
const alertRuleName = process.env.ALERT_RULE_NAME || "Client Errors";
const webPort = parseInt(process.env.WEB_PORT || "3456", 10);

if (!token) {
  log.error("Missing SENTRY_TOKEN in environment");
  process.exit(1);
}
if (!org) {
  log.error("Missing SENTRY_ORG in environment");
  process.exit(1);
}
if (!project) {
  log.error("Missing SENTRY_PROJECT in environment");
  process.exit(1);
}

log.info("╔═══════════════════════════════════════╗");
log.info("║           kahu — Sentry Worker        ║");
log.info("╠═══════════════════════════════════════╣");
log.info(`║  Build:    ${buildNumber.padEnd(26)}║`);
log.info(`║  Org:      ${org.padEnd(26)}║`);
log.info(`║  Project:  ${project.padEnd(26)}║`);
log.info(`║  Rule:     ${alertRuleName.padEnd(26)}║`);
log.info(`║  Interval: ${String(pollInterval + "s").padEnd(26)}║`);
log.info(`║  Web UI:   ${"http://localhost:" + webPort}${" ".repeat(Math.max(0, 26 - ("http://localhost:" + webPort).length))}║`);
log.info("╚═══════════════════════════════════════╝");
log.info(`Log file: ${log.getSessionFile()}`);

const client = new SentryClient({ token, org, project });

startServer(webPort);

// Run rules engine on startup against existing issues
await processRules();

startPolling(client, { pollInterval, alertRuleName });
