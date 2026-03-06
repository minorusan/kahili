import { readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROMPTS_DIR = resolve(__dirname, "..", "..", "data", "prompts");

/** All known prompt names and their hardcoded defaults. */
const DEFAULTS: Record<string, string> = {};

function ensureDir(): void {
  mkdirSync(PROMPTS_DIR, { recursive: true });
}

/**
 * Register a default prompt template. Called by each agent module at import time.
 * This way the defaults live alongside the code that uses them.
 */
export function registerDefaultPrompt(name: string, template: string): void {
  DEFAULTS[name] = template;
}

/**
 * Get the current prompt template for a given name.
 * Returns the user-customized version if it exists, otherwise the default.
 */
export function getPromptTemplate(name: string): string {
  ensureDir();
  const filePath = resolve(PROMPTS_DIR, `${name}.txt`);
  try {
    return readFileSync(filePath, "utf-8");
  } catch {
    return DEFAULTS[name] ?? "";
  }
}

/**
 * Save a customized prompt template.
 */
export function savePromptTemplate(name: string, content: string): void {
  ensureDir();
  const filePath = resolve(PROMPTS_DIR, `${name}.txt`);
  writeFileSync(filePath, content);
}

/**
 * Reset a prompt to its default by deleting the custom file.
 */
export function resetPromptTemplate(name: string): void {
  ensureDir();
  const filePath = resolve(PROMPTS_DIR, `${name}.txt`);
  try {
    unlinkSync(filePath);
  } catch {
    // file doesn't exist, that's fine
  }
}

/**
 * List all prompt names with their current content and whether they're customized.
 */
export function listPrompts(): Array<{
  name: string;
  template: string;
  isCustomized: boolean;
  description: string;
}> {
  ensureDir();

  const customFiles = new Set<string>();
  try {
    for (const f of readdirSync(PROMPTS_DIR)) {
      if (f.endsWith(".txt")) customFiles.add(f.replace(/\.txt$/, ""));
    }
  } catch {
    // dir may not exist
  }

  const descriptions: Record<string, string> = {
    investigation: "Prompt for the investigation agent that analyzes Sentry errors and suggests fixes",
    "rule-generation": "Prompt for the rule generation agent that creates issue grouping rules",
    "help-faq": "Prompt for the FAQ agent that answers questions about Kahili",
    develop: "Prompt for the develop agent that implements feature requests",
  };

  return Object.keys(DEFAULTS).map((name) => ({
    name,
    template: getPromptTemplate(name),
    isCustomized: customFiles.has(name),
    description: descriptions[name] ?? "",
  }));
}
