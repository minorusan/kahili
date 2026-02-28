import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BUILD_FILE = resolve(__dirname, "../..", "build.json");

interface BuildInfo {
  build: number;
  updatedAt: string;
}

export function readBuild(): BuildInfo {
  try {
    const raw = readFileSync(BUILD_FILE, "utf-8");
    return JSON.parse(raw) as BuildInfo;
  } catch {
    return { build: 0, updatedAt: "" };
  }
}

export function incrementBuild(): BuildInfo {
  const current = readBuild();
  const next: BuildInfo = {
    build: current.build + 1,
    updatedAt: new Date().toISOString(),
  };
  writeFileSync(BUILD_FILE, JSON.stringify(next, null, 2) + "\n");
  return next;
}
