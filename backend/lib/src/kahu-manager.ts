import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync, spawn, type ChildProcess } from "node:child_process";
import { log } from "./logger.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = resolve(__dirname, "../..");
const PID_FILE = resolve(BACKEND_DIR, "kahu.pid");
const KAHU_DIR = resolve(BACKEND_DIR, "kahu");

interface PidInfo {
  pid: number;
  build: number;
}

export function readPidFile(): PidInfo | null {
  try {
    const raw = readFileSync(PID_FILE, "utf-8");
    return JSON.parse(raw) as PidInfo;
  } catch {
    return null;
  }
}

export function writePidFile(pid: number, build: number): void {
  writeFileSync(PID_FILE, JSON.stringify({ pid, build }, null, 2) + "\n");
}

export function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function killProcess(pid: number): Promise<void> {
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    return; // already dead
  }

  // Wait up to 3 seconds for graceful shutdown
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    if (!isProcessAlive(pid)) return;
    await new Promise((r) => setTimeout(r, 200));
  }

  // Force kill if still alive
  try {
    process.kill(pid, "SIGKILL");
  } catch {
    // already dead
  }
}

/** Kill anything occupying the kahu port, regardless of PID file. */
function killPortOccupants(port: number): void {
  try {
    execSync(`fuser -k ${port}/tcp 2>/dev/null`, { stdio: "ignore" });
  } catch {
    // nothing on that port — fine
  }
}

export function buildKahu(): void {
  log.info("[kahili] Building kahu...");
  execSync("npm run build", { cwd: KAHU_DIR, stdio: "inherit" });
  log.info("[kahili] Kahu build complete.");
}

export function spawnKahu(): ChildProcess {
  const child = spawn("node", ["dist/index.js"], {
    cwd: KAHU_DIR,
    stdio: "pipe",
    env: { ...process.env },
  });

  child.stdout?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      log.info(`[kahu] ${line}`);
    }
  });

  child.stderr?.on("data", (data: Buffer) => {
    for (const line of data.toString().split("\n").filter(Boolean)) {
      log.error(`[kahu:err] ${line}`);
    }
  });

  child.on("exit", (code, signal) => {
    log.info(`[kahili] Kahu exited (code=${code}, signal=${signal})`);
  });

  return child;
}

export async function restartKahu(currentBuild: number): Promise<number> {
  const pidInfo = readPidFile();

  if (pidInfo && isProcessAlive(pidInfo.pid)) {
    log.info(`[kahili] Restarting kahu (killing PID ${pidInfo.pid})...`);
    await killProcess(pidInfo.pid);
  }

  // Kill anything still holding kahu's port
  const kahuPort = parseInt(process.env.WEB_PORT || "3456", 10);
  killPortOccupants(kahuPort);

  try {
    unlinkSync(PID_FILE);
  } catch {
    // already gone
  }

  buildKahu();

  const child = spawnKahu();
  const pid = child.pid!;

  writePidFile(pid, currentBuild);
  log.info(`[kahili] Kahu restarted (PID ${pid}, build ${currentBuild}).`);

  return pid;
}

export async function ensureKahu(currentBuild: number): Promise<number> {
  const pidInfo = readPidFile();

  if (pidInfo) {
    const alive = isProcessAlive(pidInfo.pid);

    if (alive && pidInfo.build >= currentBuild) {
      log.info(
        `[kahili] Kahu (PID ${pidInfo.pid}, build ${pidInfo.build}) is up to date — skipping rebuild.`
      );
      return pidInfo.pid;
    }

    if (alive) {
      log.info(
        `[kahili] Kahu (PID ${pidInfo.pid}, build ${pidInfo.build}) is stale (current: ${currentBuild}) — killing...`
      );
      await killProcess(pidInfo.pid);
    } else {
      log.info(
        `[kahili] Stale PID file (PID ${pidInfo.pid} is dead) — cleaning up.`
      );
    }

    try {
      unlinkSync(PID_FILE);
    } catch {
      // already gone
    }
  }

  // Kill anything still holding kahu's port
  const kahuPort = parseInt(process.env.WEB_PORT || "3456", 10);
  killPortOccupants(kahuPort);

  buildKahu();

  const child = spawnKahu();
  const pid = child.pid!;

  writePidFile(pid, currentBuild);
  log.info(
    `[kahili] Kahu spawned (PID ${pid}, build ${currentBuild}).`
  );

  return pid;
}
