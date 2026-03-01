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
 * Used to clean up script + claude agent after completion.
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
 * Spawn a claude agent wrapped in `script -qc` for PTY allocation.
 * Returns the script ChildProcess (whose child is claude).
 */
export function spawnAgent(prompt: string, cwd: string): ChildProcess {
  const agentEnv = { ...process.env };
  delete agentEnv.CLAUDECODE;

  const child = spawn(
    "script",
    ["-qc", `claude --dangerously-skip-permissions -p ${JSON.stringify(prompt)}`, "/dev/null"],
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
