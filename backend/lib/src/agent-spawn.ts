import { spawn, execSync, type ChildProcess } from "node:child_process";
import { log } from "./logger.js";

/** All currently-running agent child processes. */
const trackedChildren = new Set<ChildProcess>();

/** Kill all tracked agent processes (SIGTERM, then SIGKILL after 2s). */
export function killAllAgents(): void {
  for (const child of trackedChildren) {
    try {
      child.kill("SIGTERM");
    } catch {
      // already dead
    }
  }
  if (trackedChildren.size > 0) {
    setTimeout(() => {
      for (const child of trackedChildren) {
        try {
          child.kill("SIGKILL");
        } catch {
          // already dead
        }
      }
    }, 2000);
  }
}

/**
 * Kill a process and all its children (the whole process group tree).
 * Used to clean up codex agent after completion.
 */
export function killProcessTree(pid: number): void {
  try {
    // Kill entire process group — script + claude + any children
    execSync(`kill -9 -$(ps -o pgid= -p ${pid} | tr -d ' ') 2>/dev/null`, {
      stdio: "ignore",
    });
  } catch {
    // Fallback: kill just the PID
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      // already dead
    }
  }
}

/**
 * Spawn an OpenAI Codex agent in non-interactive exec mode.
 * Returns the codex ChildProcess.
 */
export function spawnAgent(prompt: string, cwd: string): ChildProcess {
  const agentEnv: Record<string, string | undefined> = {
    ...process.env,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY ?? "",
  };
  delete agentEnv.CLAUDECODE;

  const child = spawn(
    "codex",
    [
      "exec",
      "--dangerously-bypass-approvals-and-sandbox",
      "--skip-git-repo-check",
      "-C", cwd,
      prompt,
    ],
    {
      cwd,
      stdio: "pipe",
      env: agentEnv,
    }
  );

  trackedChildren.add(child);
  child.on("exit", () => {
    trackedChildren.delete(child);
  });

  return child;
}

/**
 * Pipe agent stdout/stderr to the logger with a tag prefix.
 */
export function pipeAgentLogs(child: ChildProcess, tag: string): void {
  child.stdout?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      log.info(`[${tag}] ${line}`);
    }
  });

  child.stderr?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      log.error(`[${tag}:err] ${line}`);
    }
  });
}
