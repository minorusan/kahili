import { type ChildProcess } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  watch,
  type FSWatcher,
} from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { broadcast } from "./websocket.js";
import { readKahuSettings } from "./settings.js";
import { log } from "./logger.js";
import { spawnAgent, pipeAgentLogs, killProcessTree } from "./agent-spawn.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = resolve(__dirname, "../..");
const KAHU_DIR = resolve(BACKEND_DIR, "kahu");
const MOTHER_ISSUES_DIR = resolve(KAHU_DIR, "data", "mother-issues");
const ISSUES_DIR = resolve(KAHU_DIR, "data", "issues");
const INVESTIGATIONS_DIR = resolve(BACKEND_DIR, "docs", "investigations");

interface Investigation {
  motherIssueId: string;
  branch?: string;
  additionalPrompt?: string;
  pid: number;
  reportPath: string;
  status: "running" | "completed" | "failed";
  startedAt: string;
  completedAt?: string;
  lastReport: string;
}

let current: Investigation | null = null;
let agentProcess: ChildProcess | null = null;
let reportWatcher: FSWatcher | null = null;

export function getCurrentInvestigation(): Investigation | null {
  // Re-read report file for freshest status
  if (current && current.status === "running") {
    try {
      current.lastReport = readFileSync(current.reportPath, "utf-8");
    } catch {
      // file may not exist yet
    }
  }
  return current;
}

function loadMotherIssue(id: string): Record<string, unknown> | null {
  const filePath = resolve(MOTHER_ISSUES_DIR, `${id}.json`);
  try {
    return JSON.parse(readFileSync(filePath, "utf-8"));
  } catch {
    return null;
  }
}

function loadChildIssue(id: string): Record<string, unknown> | null {
  const filePath = resolve(ISSUES_DIR, `${id}.json`);
  try {
    return JSON.parse(readFileSync(filePath, "utf-8"));
  } catch {
    return null;
  }
}

function buildErrorDetails(
  mi: Record<string, unknown>,
  childIssues: Record<string, unknown>[]
): string {
  const lines: string[] = [];

  lines.push(`Mother Issue ID: ${mi.id}`);
  lines.push(`Title: ${mi.title}`);
  lines.push(`Error Type: ${mi.errorType}`);
  lines.push(`Rule: ${mi.ruleName}`);
  lines.push(`Level: ${mi.level}`);

  const metrics = mi.metrics as Record<string, unknown>;
  if (metrics) {
    lines.push(`Total Occurrences: ${metrics.totalOccurrences}`);
    lines.push(`Affected Users: ${metrics.affectedUsers}`);
    lines.push(`First Seen: ${metrics.firstSeen}`);
    lines.push(`Last Seen: ${metrics.lastSeen}`);
  }

  const stackTrace = mi.stackTrace as {
    frames: Array<{
      filename: string;
      function: string;
      lineno: number;
      inApp: boolean;
    }>;
  } | undefined;
  if (stackTrace?.frames?.length) {
    lines.push("\nStack Trace (most recent first):");
    for (const f of [...stackTrace.frames].reverse()) {
      const marker = f.inApp ? " [APP]" : "";
      lines.push(`  ${f.filename}:${f.lineno} in ${f.function}${marker}`);
    }
  }

  // Include first child issue's event message for full trace context
  for (const child of childIssues.slice(0, 2)) {
    const saved = child as {
      issue: { id: string; title: string; permalink: string; count: string };
      events: Array<{ message: string; release: string; datetime: string }>;
    };
    lines.push(`\nChild Issue: ${saved.issue.id} (${saved.issue.count} events)`);
    lines.push(`Sentry: ${saved.issue.permalink}`);
    if (saved.events?.[0]) {
      const evt = saved.events[0];
      lines.push(`Release: ${evt.release || "unknown"}`);
      lines.push(`Latest Event: ${evt.datetime}`);
      if (evt.message) {
        // Truncate very long messages
        const msg =
          evt.message.length > 3000
            ? evt.message.slice(0, 3000) + "\n... (truncated)"
            : evt.message;
        lines.push(`\nFull Stack Trace:\n${msg}`);
      }
    }
  }

  return lines.join("\n");
}

function buildAgentPrompt(
  motherIssuePath: string,
  childIssuePaths: string[],
  reportPath: string,
  branch?: string,
  additionalPrompt?: string
): string {
  let branchInstruction: string;
  if (branch) {
    branchInstruction = `Use branch/tag: ${branch}`;
  } else {
    branchInstruction = `No branch specified — use git branch -a to find the closest match to the release version in the error details, or use the default branch.`;
  }

  let extra = "";
  if (additionalPrompt) {
    extra = `\n\nADDITIONAL CONTEXT FROM USER:\n${additionalPrompt}`;
  }

  const childFiles = childIssuePaths.length
    ? childIssuePaths.map((p) => `  - ${p}`).join("\n")
    : "  (none)";

  return `You are investigating a Sentry error. Your task is to investigate, identify root cause, and suggest a concrete fix.

MANDATORY: STATUS FILE AT ${reportPath}
You MUST write to this file throughout your investigation:
1. IMMEDIATELY write: "Investigating: Starting analysis..."
2. As you progress, UPDATE the file with brief status
3. When DONE, REPLACE entire file content with your final report

ERROR DATA FILES (read these first):
Mother issue: ${motherIssuePath}
Child issues:
${childFiles}

INVESTIGATION STEPS:
1. Write initial status to report file
2. Read the mother issue JSON file to understand the error (title, errorType, stackTrace, metrics)
3. Read child issue JSON files for full event details and stack traces
4. BRANCH SELECTION — ${branchInstruction}
5. Use git show <branch>:<filepath> to read source files (DO NOT checkout)
6. Trace the error — understand WHY, not just WHERE
7. git log --format='%aN' -5 on affected files to find suggested assignee
8. Write final report

FINAL REPORT FORMAT (markdown):
# Investigation: <short title>
## TLDR
A 2-3 sentence summary: how severe this likely is, and what's going wrong. Be direct.
## Risk Assessment
## Release Branch
## Release Version
## Error Summary
## Root Cause
## Affected Code
## Suggested Fix
## Suggested Assignee

RULES:
- ONLY git readonly commands (show, log, grep, blame)
- Do NOT checkout, pull, or modify source files
- ONLY write to the report file at ${reportPath}${extra}`;
}

export async function startInvestigation(
  motherIssueId: string,
  branch?: string,
  additionalPrompt?: string
): Promise<Investigation> {
  if (current?.status === "running") {
    throw new Error(
      `Investigation already running for ${current.motherIssueId} (PID ${current.pid})`
    );
  }

  const settings = readKahuSettings();
  const repoPath = settings.REPO_PATH;
  if (!repoPath) {
    throw new Error("REPO_PATH not configured in kahu settings");
  }

  if (!existsSync(repoPath)) {
    throw new Error(`REPO_PATH does not exist: ${repoPath}`);
  }

  const mi = loadMotherIssue(motherIssueId);
  if (!mi) {
    throw new Error(`Mother issue not found: ${motherIssueId}`);
  }

  // Build file paths for child issues
  const childIds = (mi.childIssueIds as string[]) || [];
  const childIssuePaths: string[] = [];
  for (const cid of childIds) {
    const p = resolve(ISSUES_DIR, `${cid}.json`);
    if (existsSync(p)) childIssuePaths.push(p);
  }

  // Set up report path inside the repo
  mkdirSync(INVESTIGATIONS_DIR, { recursive: true });
  const reportPath = resolve(INVESTIGATIONS_DIR, `${motherIssueId}.md`);

  // Clear previous report
  writeFileSync(reportPath, "Investigating: Starting analysis...\n");

  const motherIssuePath = resolve(MOTHER_ISSUES_DIR, `${motherIssueId}.json`);
  const prompt = buildAgentPrompt(
    motherIssuePath,
    childIssuePaths,
    reportPath,
    branch,
    additionalPrompt
  );

  const child = spawnAgent(prompt, repoPath);
  agentProcess = child;

  if (!child.pid) throw new Error("Failed to spawn investigation agent");
  const pid = child.pid;

  current = {
    motherIssueId,
    branch,
    additionalPrompt,
    pid,
    reportPath,
    status: "running",
    startedAt: new Date().toISOString(),
    lastReport: "Investigating: Starting analysis...",
  };

  log.info(
    `[kahili:investigate] Spawned agent PID ${pid} for mother issue ${motherIssueId}`
  );

  broadcast("investigation:started", {
    motherIssueId,
    pid,
    status: "running",
  });

  pipeAgentLogs(child, `investigate:${motherIssueId}`);

  // Watch the report file for changes and broadcast
  let lastContent = "";
  const onFileChange = () => {
    try {
      const content = readFileSync(reportPath, "utf-8");
      if (content !== lastContent) {
        lastContent = content;
        if (current) current.lastReport = content;
        broadcast("investigation:progress", {
          motherIssueId,
          status: "running",
          report: content,
        });
      }
    } catch {
      // file may be mid-write
    }
  };

  reportWatcher = watch(reportPath, onFileChange);

  child.on("exit", (code, signal) => {
    agentProcess = null;
    if (reportWatcher) {
      reportWatcher.close();
      reportWatcher = null;
    }

    // Read final report
    let finalReport = "";
    try {
      finalReport = readFileSync(reportPath, "utf-8");
    } catch {
      finalReport = `Investigation ended without report (code=${code}, signal=${signal})`;
    }

    if (current) {
      current.status = code === 0 ? "completed" : "failed";
      current.completedAt = new Date().toISOString();
      current.lastReport = finalReport;
    }

    log.info(
      `[kahili:investigate] Agent PID ${pid} exited (code=${code}, signal=${signal})`
    );

    broadcast("investigation:completed", {
      motherIssueId,
      status: current?.status ?? "completed",
      report: finalReport,
    });
  });

  return current;
}

export function cancelInvestigation(): boolean {
  if (!current || current.status !== "running") {
    return false;
  }

  if (agentProcess) {
    // SIGTERM first for graceful shutdown
    agentProcess.kill("SIGTERM");
    // Escalate with killProcessTree after delay
    const pid = current.pid;
    setTimeout(() => {
      killProcessTree(pid);
    }, 2000);
  } else if (current.pid) {
    // agentProcess ref lost — try killing by PID
    try {
      process.kill(current.pid, "SIGTERM");
      setTimeout(() => {
        killProcessTree(current!.pid);
      }, 2000);
    } catch {
      return false;
    }
  }

  return true;
}
