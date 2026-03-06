import { type ChildProcess, execSync, spawn as cpSpawn } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  readdirSync,
  watch,
  type FSWatcher,
} from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { broadcast } from "./websocket.js";
import { log } from "./logger.js";
import { spawnAgent, pipeAgentLogs, killProcessTree } from "./agent-spawn.js";
import { registerDefaultPrompt, getPromptTemplate } from "./prompt-store.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = resolve(__dirname, "../..");
const PROJECT_ROOT = resolve(BACKEND_DIR, "..");
const DEVELOP_DIR = resolve(BACKEND_DIR, "data", "develop-requests");

function scheduleRestart(): void {
  log.info("[kahili:develop] Scheduling kahili restart in 3s...");
  setTimeout(() => {
    log.info("[kahili:develop] Spawning detached 'kahili restart'...");
    const child = cpSpawn("kahili", ["restart"], {
      detached: true,
      stdio: "ignore",
      env: { ...process.env },
    });
    child.unref();
  }, 3000);
}

interface DevelopRequest {
  id: string;
  request: string;
  pid: number;
  reportPath: string;
  status: "running" | "completed" | "failed" | "rejected";
  statusText: string;
  rejectionReason?: string;
  commitHash?: string;
  startedAt: string;
  completedAt?: string;
}

let current: DevelopRequest | null = null;
let agentProcess: ChildProcess | null = null;
let reportWatcher: FSWatcher | null = null;

function ensureDir(): void {
  mkdirSync(DEVELOP_DIR, { recursive: true });
}

function metaPath(id: string): string {
  return resolve(DEVELOP_DIR, `${id}.json`);
}

function mdPath(id: string): string {
  return resolve(DEVELOP_DIR, `${id}.md`);
}

export function listDevelopRequests(): Array<{
  id: string;
  request: string;
  status: string;
  rejectionReason?: string;
  commitHash?: string;
  startedAt: string;
  completedAt?: string;
}> {
  ensureDir();
  try {
    const files = readdirSync(DEVELOP_DIR).filter((f) => f.endsWith(".json"));
    return files
      .map((f) => {
        try {
          const data = JSON.parse(readFileSync(resolve(DEVELOP_DIR, f), "utf-8"));
          return {
            id: data.id as string,
            request: data.request as string,
            status: data.status as string,
            rejectionReason: data.rejectionReason as string | undefined,
            commitHash: data.commitHash as string | undefined,
            startedAt: data.startedAt as string,
            completedAt: data.completedAt as string | undefined,
          };
        } catch {
          return null;
        }
      })
      .filter((q): q is NonNullable<typeof q> => q !== null)
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt));
  } catch {
    return [];
  }
}

export function getDevelopDetail(id: string): {
  request: string;
  report: string;
  status: string;
  rejectionReason?: string;
  commitHash?: string;
  startedAt: string;
  completedAt?: string;
} | null {
  try {
    const meta = JSON.parse(readFileSync(metaPath(id), "utf-8"));
    let report = "";
    try {
      report = readFileSync(mdPath(id), "utf-8");
    } catch {
      // .md may not exist yet
    }
    return {
      request: meta.request,
      report,
      status: meta.status,
      rejectionReason: meta.rejectionReason,
      commitHash: meta.commitHash,
      startedAt: meta.startedAt,
      completedAt: meta.completedAt,
    };
  } catch {
    return null;
  }
}

export function getCurrentDevelopAgent(): DevelopRequest | null {
  if (current && current.status === "running") {
    try {
      current.statusText = readFileSync(current.reportPath, "utf-8");
    } catch {
      // file may not exist yet
    }
  }
  return current;
}

function saveMeta(d: DevelopRequest): void {
  ensureDir();
  writeFileSync(
    metaPath(d.id),
    JSON.stringify(
      {
        id: d.id,
        request: d.request,
        status: d.status,
        rejectionReason: d.rejectionReason,
        commitHash: d.commitHash,
        startedAt: d.startedAt,
        completedAt: d.completedAt,
      },
      null,
      2
    )
  );
}

const DEVELOP_DEFAULT_PROMPT = `You are the Kahili Development Agent. You implement feature requests for the Kahili project.

SCOPE RESTRICTION:
You may ONLY operate within the Kahili repository at {{PROJECT_ROOT}}.
You may NOT access, modify, or reference any files outside this directory.

DECISION STEP (do this FIRST):
Evaluate if the feature request is clear and specific enough to implement.
If the request is ambiguous, unclear, or too vague to implement correctly:
1. Write a report to {{REPORT_PATH}} explaining why the request is rejected
2. Start the report with exactly: "REJECTED: " followed by a clear explanation of what's ambiguous and what information is needed
3. Exit immediately after writing the rejection

If the request is clear, proceed with implementation.

CRITICAL: Read AGENTS.md at the repo root FIRST. It contains the full architecture, directory layout, API routes, code patterns, theme colors, and build commands. You MUST read it before making any changes.

MANDATORY: REPORT FILE AT {{REPORT_PATH}}
1. IMMEDIATELY write: "Evaluating feature request..."
2. If rejecting: write "REJECTED: <reason>" and exit
3. If implementing: update with progress as you work
4. When DONE: replace with full implementation report

IMPLEMENTATION RULES:
- Read existing code before modifying — understand patterns and conventions
- Follow existing code style and patterns in the Kahili codebase
- Make changes that are minimal and focused on the request
- Build ALL affected packages after making changes (backend/lib, backend/kahu, client as needed)
- Run builds to verify your changes compile: npm run build / flutter build web --no-pub
- If a build fails, fix the errors and rebuild
- After successful build, commit all changes with a descriptive message
- Use: git add <specific files> && git commit -m "feat: <description>"
- Do NOT push to remote
- Do NOT run kahili restart or kahili stop — the system restarts automatically after you exit

POST-IMPLEMENTATION:
After committing, write the final report with these sections:

# Feature: <short title>
## Status
Implemented and committed.
## Commit
<commit hash from git log -1>
## Summary
What was implemented and why.
## Changes
List of files modified/created with brief descriptions.
## Build Status
Confirmation that all affected packages built successfully.
## Testing Notes
How to verify the feature works.

FEATURE REQUEST:
{{REQUEST}}`;

registerDefaultPrompt("develop", DEVELOP_DEFAULT_PROMPT);

function buildDevelopPrompt(request: string, reportPath: string): string {
  const template = getPromptTemplate("develop");
  return template
    .replace(/\{\{PROJECT_ROOT\}\}/g, PROJECT_ROOT)
    .replace(/\{\{REPORT_PATH\}\}/g, reportPath)
    .replace(/\{\{REQUEST\}\}/g, request);
}

export async function startDevelopAgent(
  request: string
): Promise<DevelopRequest> {
  if (current?.status === "running") {
    throw new Error("A development request is already being processed");
  }

  const id =
    Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const reportPath = mdPath(id);

  ensureDir();
  writeFileSync(reportPath, "Evaluating feature request...\n");

  const prompt = buildDevelopPrompt(request, reportPath);

  const child = spawnAgent(prompt, PROJECT_ROOT);
  agentProcess = child;

  if (!child.pid) throw new Error("Failed to spawn develop agent");
  const pid = child.pid;

  current = {
    id,
    request,
    pid,
    reportPath,
    status: "running",
    statusText: "Evaluating feature request...",
    startedAt: new Date().toISOString(),
  };

  saveMeta(current);

  log.info(
    `[kahili:develop] Spawned agent PID ${pid} for request "${request.slice(0, 80)}"`
  );

  broadcast("develop:started", { id, status: "running" });

  pipeAgentLogs(child, `develop:${id}`);

  // Watch report file for changes and broadcast
  let lastContent = "";
  const onFileChange = () => {
    try {
      const content = readFileSync(reportPath, "utf-8");
      if (content !== lastContent) {
        lastContent = content;
        if (current) current.statusText = content;
        broadcast("develop:progress", {
          id,
          status: "running",
          statusText: content,
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

    let finalReport = "";
    try {
      finalReport = readFileSync(reportPath, "utf-8");
    } catch {
      finalReport = `Develop agent ended without response (code=${code}, signal=${signal})`;
    }

    // Check if the agent rejected the request
    const isRejected = finalReport.trimStart().startsWith("REJECTED:");

    if (current) {
      if (isRejected) {
        current.status = "rejected";
        current.rejectionReason = finalReport.replace(/^REJECTED:\s*/i, "").trim();
      } else if (code === 0) {
        current.status = "completed";
        // Try to extract commit hash from the report
        const commitMatch = finalReport.match(/## Commit\s*\n([a-f0-9]{7,40})/);
        if (commitMatch) {
          current.commitHash = commitMatch[1];
        } else {
          // Try getting it from git
          try {
            const hash = execSync("git log -1 --format=%H", {
              cwd: PROJECT_ROOT,
              encoding: "utf-8",
            }).trim();
            current.commitHash = hash;
          } catch {
            // no commit found
          }
        }

      } else {
        current.status = "failed";
      }
      current.completedAt = new Date().toISOString();
      current.statusText = finalReport;
      saveMeta(current);
    }

    log.info(
      `[kahili:develop] Agent PID ${pid} exited (code=${code}, signal=${signal}, status=${current?.status})`
    );

    broadcast("develop:completed", {
      id,
      status: current?.status ?? "completed",
      report: finalReport,
    });

    // Auto-restart kahili after successful implementation so new code takes effect
    if (current?.status === "completed") {
      scheduleRestart();
    }
  });

  return current;
}

export function cancelDevelopAgent(): boolean {
  if (!current || current.status !== "running") {
    return false;
  }

  if (agentProcess) {
    agentProcess.kill("SIGTERM");
    const pid = current.pid;
    setTimeout(() => {
      killProcessTree(pid);
    }, 2000);
  } else if (current.pid) {
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

