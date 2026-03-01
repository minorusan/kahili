import { writeFileSync, readFileSync, readdirSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readBuild } from "./build.js";
import { restartKahu } from "./kahu-manager.js";
import { log } from "./logger.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = resolve(__dirname, "../..");
const KAHU_DIR = resolve(BACKEND_DIR, "kahu");
const KAHU_ENV_FILE = resolve(KAHU_DIR, ".env");
const MOTHER_ISSUES_DIR = resolve(KAHU_DIR, "data", "mother-issues");

export interface KahuSettings {
  SENTRY_TOKEN?: string;
  SENTRY_ORG?: string;
  SENTRY_PROJECT?: string;
  POLL_INTERVAL?: string;
  ALERT_RULE_NAME?: string;
  WEB_PORT?: string;
  REPO_PATH?: string;
  [key: string]: string | undefined;
}

export function readKahuSettings(): KahuSettings {
  try {
    const raw = readFileSync(KAHU_ENV_FILE, "utf-8");
    const settings: KahuSettings = {};
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eqIdx = trimmed.indexOf("=");
      if (eqIdx === -1) continue;
      settings[trimmed.slice(0, eqIdx)] = trimmed.slice(eqIdx + 1);
    }
    return settings;
  } catch {
    return {};
  }
}

function writeEnvFile(settings: KahuSettings): void {
  const lines = Object.entries(settings)
    .filter(([, v]) => v !== undefined && v !== "")
    .map(([k, v]) => `${k}=${v}`);
  writeFileSync(KAHU_ENV_FILE, lines.join("\n") + "\n");
}

function backfillRepoPath(repoPath: string): number {
  let count = 0;
  let files: string[];
  try {
    files = readdirSync(MOTHER_ISSUES_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return 0;
  }

  for (const file of files) {
    const filePath = join(MOTHER_ISSUES_DIR, file);
    try {
      const raw = readFileSync(filePath, "utf-8");
      const mi = JSON.parse(raw);
      mi.repoPath = repoPath;
      writeFileSync(filePath, JSON.stringify(mi, null, 2));
      count++;
    } catch {
      // skip corrupt files
    }
  }
  return count;
}

export async function applyKahuSettings(
  settings: KahuSettings
): Promise<{ env: boolean; backfilled: number; kahuPid: number }> {
  // Merge with existing settings — provided keys overwrite, missing keys preserved
  const current = readKahuSettings();
  const merged = { ...current, ...settings };

  writeEnvFile(merged);
  log.info("[kahili] Wrote kahu .env");

  // Backfill repo path into mother issues
  let backfilled = 0;
  if (merged.REPO_PATH) {
    backfilled = backfillRepoPath(merged.REPO_PATH);
    log.info(
      `[kahili] Backfilled repoPath into ${backfilled} mother issue(s).`
    );
  }

  // Restart kahu with current build so it picks up new settings
  const buildInfo = readBuild();
  const kahuPid = await restartKahu(buildInfo.build);

  return { env: true, backfilled, kahuPid };
}
