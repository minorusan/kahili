import { type ChildProcess } from "node:child_process";
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
const HELP_DIR = resolve(BACKEND_DIR, "data", "help-questions");

interface HelpQuestion {
  id: string;
  question: string;
  pid: number;
  answerPath: string;
  status: "running" | "completed" | "failed";
  statusText: string;
  startedAt: string;
  completedAt?: string;
}

let current: HelpQuestion | null = null;
let agentProcess: ChildProcess | null = null;
let answerWatcher: FSWatcher | null = null;

function ensureDir(): void {
  mkdirSync(HELP_DIR, { recursive: true });
}

function metaPath(id: string): string {
  return resolve(HELP_DIR, `${id}.json`);
}

function mdPath(id: string): string {
  return resolve(HELP_DIR, `${id}.md`);
}

export function listHelpQuestions(): Array<{
  id: string;
  question: string;
  status: string;
  startedAt: string;
  completedAt?: string;
}> {
  ensureDir();
  try {
    const files = readdirSync(HELP_DIR).filter((f) => f.endsWith(".json"));
    return files
      .map((f) => {
        try {
          const data = JSON.parse(readFileSync(resolve(HELP_DIR, f), "utf-8"));
          return {
            id: data.id as string,
            question: data.question as string,
            status: data.status as string,
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

export function getHelpAnswer(id: string): {
  question: string;
  answer: string;
  status: string;
  startedAt: string;
  completedAt?: string;
} | null {
  try {
    const meta = JSON.parse(readFileSync(metaPath(id), "utf-8"));
    let answer = "";
    try {
      answer = readFileSync(mdPath(id), "utf-8");
    } catch {
      // .md may not exist yet
    }
    return {
      question: meta.question,
      answer,
      status: meta.status,
      startedAt: meta.startedAt,
      completedAt: meta.completedAt,
    };
  } catch {
    return null;
  }
}

export function getCurrentHelpAgent(): HelpQuestion | null {
  if (current && current.status === "running") {
    try {
      current.statusText = readFileSync(current.answerPath, "utf-8");
    } catch {
      // file may not exist yet
    }
  }
  return current;
}

function saveMeta(q: HelpQuestion): void {
  ensureDir();
  writeFileSync(
    metaPath(q.id),
    JSON.stringify(
      {
        id: q.id,
        question: q.question,
        status: q.status,
        startedAt: q.startedAt,
        completedAt: q.completedAt,
      },
      null,
      2
    )
  );
}

const HELP_FAQ_DEFAULT_PROMPT = `You are the Kahili Help Agent. You ONLY answer questions about Kahili — the Sentry issue tracker and monitoring system.

SCOPE RESTRICTION:
If the user's question is NOT related to Kahili (its features, usage, configuration, architecture, troubleshooting, or the Sentry/monitoring domain it operates in), you MUST write ONLY this to the answer file and exit:
"I can only answer questions about Kahili. Please ask about Kahili's features, configuration, architecture, troubleshooting, or usage."

CRITICAL: Read AGENTS.md at the repo root FIRST. It contains the full architecture, directory layout, API routes, code patterns, and all details about Kahili.

You have access to the full Kahili source code at {{PROJECT_ROOT}}. Read files as needed to provide accurate answers.

MANDATORY: ANSWER FILE AT {{ANSWER_PATH}}
1. IMMEDIATELY write: "Analyzing your question..."
2. As you research, UPDATE the file with brief status lines (e.g., "Reading server configuration...", "Checking API endpoints...")
3. When DONE, REPLACE the entire file with your final answer in well-formatted Markdown

USER'S QUESTION:
{{QUESTION}}

RULES:
- ONLY answer Kahili-related questions
- Read source files to give accurate, specific answers
- Format your final answer in clear Markdown with headings and code blocks where appropriate
- Be concise but thorough
- ONLY read files — do NOT modify any source code or configuration
- Write ONLY to the answer file at {{ANSWER_PATH}}`;

registerDefaultPrompt("help-faq", HELP_FAQ_DEFAULT_PROMPT);

function buildHelpPrompt(question: string, answerPath: string): string {
  const template = getPromptTemplate("help-faq");
  return template
    .replace(/\{\{PROJECT_ROOT\}\}/g, PROJECT_ROOT)
    .replace(/\{\{ANSWER_PATH\}\}/g, answerPath)
    .replace(/\{\{QUESTION\}\}/g, question);
}

export async function startHelpAgent(
  question: string
): Promise<HelpQuestion> {
  if (current?.status === "running") {
    throw new Error("A help question is already being processed");
  }

  const id =
    Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const reportPath = mdPath(id);

  ensureDir();
  writeFileSync(reportPath, "Analyzing your question...\n");

  const prompt = buildHelpPrompt(question, reportPath);

  const child = spawnAgent(prompt, PROJECT_ROOT);
  agentProcess = child;

  if (!child.pid) throw new Error("Failed to spawn help agent");
  const pid = child.pid;

  current = {
    id,
    question,
    pid,
    answerPath: reportPath,
    status: "running",
    statusText: "Analyzing your question...",
    startedAt: new Date().toISOString(),
  };

  saveMeta(current);

  log.info(
    `[kahili:help] Spawned agent PID ${pid} for question "${question.slice(0, 80)}"`
  );

  broadcast("help:started", { id, status: "running" });

  pipeAgentLogs(child, `help:${id}`);

  // Watch answer file for changes and broadcast
  let lastContent = "";
  const onFileChange = () => {
    try {
      const content = readFileSync(reportPath, "utf-8");
      if (content !== lastContent) {
        lastContent = content;
        if (current) current.statusText = content;
        broadcast("help:progress", {
          id,
          status: "running",
          statusText: content,
        });
      }
    } catch {
      // file may be mid-write
    }
  };

  answerWatcher = watch(reportPath, onFileChange);

  child.on("exit", (code, signal) => {
    agentProcess = null;
    if (answerWatcher) {
      answerWatcher.close();
      answerWatcher = null;
    }

    let finalAnswer = "";
    try {
      finalAnswer = readFileSync(reportPath, "utf-8");
    } catch {
      finalAnswer = `Help agent ended without response (code=${code}, signal=${signal})`;
    }

    if (current) {
      current.status = code === 0 ? "completed" : "failed";
      current.completedAt = new Date().toISOString();
      current.statusText = finalAnswer;
      saveMeta(current);
    }

    log.info(
      `[kahili:help] Agent PID ${pid} exited (code=${code}, signal=${signal})`
    );

    broadcast("help:completed", {
      id,
      status: current?.status ?? "completed",
      answer: finalAnswer,
    });
  });

  return current;
}

export function cancelHelpAgent(): boolean {
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
