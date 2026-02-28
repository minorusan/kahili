import { spawn, type ChildProcess } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  watchFile,
  unwatchFile,
} from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { broadcast } from "./websocket.js";
import { readKahuSettings } from "./settings.js";

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
  errorDetails: string,
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

  return `You are investigating a Sentry error. Your task is to investigate, identify root cause, and suggest a concrete fix.

MANDATORY: STATUS FILE AT ${reportPath}
You MUST write to this file throughout your investigation:
1. IMMEDIATELY write: "Investigating: Starting analysis..."
2. As you progress, UPDATE the file with brief status
3. When DONE, REPLACE entire file content with your final report

ERROR DETAILS:
${errorDetails}

INVESTIGATION STEPS:
1. Write initial status to report file
2. BRANCH SELECTION — ${branchInstruction}
3. Use git show <branch>:<filepath> to read files (DO NOT checkout)
4. Trace the error — understand WHY, not just WHERE
5. git log --format='%aN' -5 on affected files to find suggested assignee
6. Write final report

FINAL REPORT FORMAT (markdown):
# Investigation: <short title>
## Release Branch
## Release Version
## Error Summary
## Root Cause
## Affected Code
## Suggested Fix
## Risk Assessment
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

  // Load child issues for full context
  const childIds = (mi.childIssueIds as string[]) || [];
  const childIssues: Record<string, unknown>[] = [];
  for (const cid of childIds) {
    const child = loadChildIssue(cid);
    if (child) childIssues.push(child);
  }

  // Set up report path inside the repo
  mkdirSync(INVESTIGATIONS_DIR, { recursive: true });
  const reportPath = resolve(INVESTIGATIONS_DIR, `${motherIssueId}.md`);

  // Clear previous report
  writeFileSync(reportPath, "Investigating: Starting analysis...\n");

  const errorDetails = buildErrorDetails(mi, childIssues);
  const prompt = buildAgentPrompt(
    errorDetails,
    reportPath,
    branch,
    additionalPrompt
  );

  // Spawn claude agent
  const child = spawn("claude", ["--dangerously-skip-permissions", "-p", prompt], {
    cwd: repoPath,
    stdio: "pipe",
    env: { ...process.env },
  });
  agentProcess = child;

  const pid = child.pid!;

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

  console.log(
    `[kahili:investigate] Spawned claude agent PID ${pid} for mother issue ${motherIssueId}`
  );

  broadcast("investigation:started", {
    motherIssueId,
    pid,
    status: "running",
  });

  // Pipe agent stdout/stderr for logging
  child.stdout?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      console.log(`[investigate:${motherIssueId}] ${line}`);
    }
  });

  child.stderr?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      console.error(`[investigate:${motherIssueId}:err] ${line}`);
    }
  });

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

  watchFile(reportPath, { interval: 1000 }, onFileChange);

  child.on("exit", (code, signal) => {
    agentProcess = null;
    unwatchFile(reportPath);

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

    console.log(
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
  if (!current || current.status !== "running" || !agentProcess) {
    // Try killing by PID even if agentProcess ref is lost
    if (current?.status === "running" && current.pid) {
      try {
        process.kill(current.pid, "SIGTERM");
        current.status = "failed";
        current.completedAt = new Date().toISOString();
        broadcast("investigation:completed", {
          motherIssueId: current.motherIssueId,
          status: "failed",
          report: current.lastReport + "\n\n---\n*Investigation cancelled by user.*",
        });
        return true;
      } catch {
        return false;
      }
    }
    return false;
  }

  agentProcess.kill("SIGTERM");
  return true;
}
