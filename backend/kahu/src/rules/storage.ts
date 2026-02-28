import { readFile, writeFile, readdir, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { MotherIssue } from "./rule.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MOTHER_ISSUES_DIR = join(__dirname, "..", "..", "data", "mother-issues");

export async function ensureMotherIssuesDir(): Promise<void> {
  await mkdir(MOTHER_ISSUES_DIR, { recursive: true });
}

export async function saveMotherIssue(mi: MotherIssue): Promise<void> {
  await ensureMotherIssuesDir();
  const filePath = join(MOTHER_ISSUES_DIR, `${mi.id}.json`);
  await writeFile(filePath, JSON.stringify(mi, null, 2));
}

export async function loadAllMotherIssues(): Promise<MotherIssue[]> {
  await ensureMotherIssuesDir();
  let files: string[];
  try {
    files = await readdir(MOTHER_ISSUES_DIR);
  } catch {
    return [];
  }

  const jsonFiles = files.filter((f) => f.endsWith(".json"));
  const issues: MotherIssue[] = [];
  for (const file of jsonFiles) {
    try {
      const raw = await readFile(join(MOTHER_ISSUES_DIR, file), "utf-8");
      issues.push(JSON.parse(raw) as MotherIssue);
    } catch {
      // skip corrupt files
    }
  }
  return issues;
}

export async function loadMotherIssue(
  id: string
): Promise<MotherIssue | null> {
  const filePath = join(MOTHER_ISSUES_DIR, `${id}.json`);
  if (!existsSync(filePath)) return null;
  try {
    const raw = await readFile(filePath, "utf-8");
    return JSON.parse(raw) as MotherIssue;
  } catch {
    return null;
  }
}
