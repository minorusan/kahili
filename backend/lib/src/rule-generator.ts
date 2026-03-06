import { type ChildProcess } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  readdirSync,
  unlinkSync,
  watch,
  type FSWatcher,
} from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { broadcast } from "./websocket.js";
import { log } from "./logger.js";
import { spawnAgent, pipeAgentLogs, killProcessTree } from "./agent-spawn.js";
import { registerDefaultPrompt, getPromptTemplate } from "./prompt-store.js";
import { restartKahu } from "./kahu-manager.js";
import { readBuild } from "./build.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = resolve(__dirname, "../..");
const KAHU_DIR = resolve(BACKEND_DIR, "kahu");
const RULES_DIR = resolve(KAHU_DIR, "src", "rules");
const GENERATION_DIR = resolve(BACKEND_DIR, "docs", "rule-generation");

interface RuleGeneration {
  prompt: string;
  pid: number;
  statusPath: string;
  status: "running" | "completed" | "failed" | "rejected";
  startedAt: string;
  completedAt?: string;
  lastStatus: string;
}

let current: RuleGeneration | null = null;
let agentProcess: ChildProcess | null = null;
let statusWatcher: FSWatcher | null = null;

export function getCurrentRuleGeneration(): RuleGeneration | null {
  if (current && current.status === "running") {
    try {
      current.lastStatus = readFileSync(current.statusPath, "utf-8");
    } catch {
      // file may not exist yet
    }
  }
  return current;
}

const RULE_GEN_DEFAULT_PROMPT = `You are a rule generator for a Sentry error grouping system.

USER REQUEST:
{{USER_PROMPT}}

STATUS FILE AT {{STATUS_PATH}}
You MUST write to this file throughout your work:
1. IMMEDIATELY write: "Generating: Analyzing request..."
2. As you progress, UPDATE with brief status
3. When DONE, write: "COMPLETED: <rule-name> created"
4. If the request is impossible, nonsensical, or too vague to implement, write EXACTLY:
   "REJECTED BY AGENT: <reason>"
   and stop. Do NOT create any files in that case.

YOUR WORKING DIRECTORY: {{RULES_DIR}}

REFERENCE FILES (read these first to understand the patterns):
- {{RULES_DIR}}/rule.ts — the abstract Rule base class and MotherIssue interface
- {{RULES_DIR}}/nre-rule.ts — example rule implementation (NullReferenceException grouping)
- {{RULES_DIR}}/index.ts — rule runner that imports and registers all rules
- {{KAHU_DIR}}/src/types.ts — SavedIssue, SentryFullEvent, and all Sentry types

WHAT YOU MUST DO:
1. Read all reference files above to understand the architecture
2. Create ONE new rule file as a sibling of nre-rule.ts (e.g., my-new-rule.ts)
3. The rule must extend the abstract Rule class from "./rule.js"
4. Implement these required properties:
   - name (string) — short identifier
   - description (string) — one-line summary for the user
   - logic (string) — step-by-step summary of the implementation logic, displayed readonly in the UI.
     Use numbered steps joined with "\\n", e.g.:
     readonly logic = "1. Check if title contains X\\n2. Extract Y from Z\\n3. Grouping key: RuleName::field::value";
   - groupingKey(issue: SavedIssue): string | null
5. Update index.ts to import your new rule and add it to the RULES array
6. Write completion status to the status file

IMPORTANT — VERIFY AGAINST REAL DATA:
- The user request may contain typos or approximate names. Do NOT blindly copy them into string matching.
- Before writing the rule, read a few actual issue JSON files from {{KAHU_DIR}}/data/issues/ to confirm the exact spelling of tokens, class names, and field values you plan to match against.
- Use the correct spelling found in real data, not the user's request.

CONSTRAINTS:
- You may ONLY create/modify files inside {{RULES_DIR}}
- You may ONLY create one new .ts rule file and update index.ts
- Do NOT touch any other files
- Do NOT install packages
- Do NOT run build commands
- Follow the exact same patterns as nre-rule.ts
- The groupingKey must return a deterministic string for grouping, or null to skip`;

registerDefaultPrompt("rule-generation", RULE_GEN_DEFAULT_PROMPT);

function buildRuleGenPrompt(userPrompt: string, statusPath: string): string {
  const template = getPromptTemplate("rule-generation");
  return template
    .replace(/\{\{USER_PROMPT\}\}/g, userPrompt)
    .replace(/\{\{STATUS_PATH\}\}/g, statusPath)
    .replace(/\{\{RULES_DIR\}\}/g, RULES_DIR)
    .replace(/\{\{KAHU_DIR\}\}/g, KAHU_DIR);
}

/**
 * Delete a rule by name: remove its .ts file, its import/registration from index.ts,
 * and all mother issues created by it.
 */
export function deleteRule(ruleName: string): { deleted: boolean; filesRemoved: number } {
  let filesRemoved = 0;

  // 1. Find and delete the rule .ts file
  const ruleFiles = readdirSync(RULES_DIR).filter((f) => f.endsWith(".ts") && f !== "rule.ts" && f !== "index.ts" && f !== "storage.ts");
  for (const file of ruleFiles) {
    const filePath = resolve(RULES_DIR, file);
    const content = readFileSync(filePath, "utf-8");
    // Match by the rule's `name` property
    if (content.includes(`name = "${ruleName}"`) || content.includes(`name = '${ruleName}'`)) {
      unlinkSync(filePath);
      log.info(`[kahili:rulegen] Deleted rule file: ${file}`);

      // 2. Remove import and RULES array entry from index.ts
      const indexPath = resolve(RULES_DIR, "index.ts");
      let indexContent = readFileSync(indexPath, "utf-8");

      // Remove the import line for this file
      const importBase = file.replace(/\.ts$/, ".js");
      const importRegex = new RegExp(`^import\\s+\\{[^}]+\\}\\s+from\\s+['"]\\.\\/${importBase.replace(/\./g, "\\.")}['"];?\\s*\\n`, "m");
      indexContent = indexContent.replace(importRegex, "");

      // Remove from RULES array — match "new ClassName()," or "new ClassName()"
      // First find the class name from the deleted file
      const classMatch = content.match(/export\s+class\s+(\w+)/);
      if (classMatch) {
        const className = classMatch[1];
        // Remove "new ClassName(), " or ", new ClassName()"
        indexContent = indexContent.replace(new RegExp(`,?\\s*new\\s+${className}\\(\\)\\s*,?`), (match) => {
          // If it matched both leading and trailing comma, keep one
          if (match.startsWith(",") && match.endsWith(",")) return ",";
          return "";
        });
        // Clean up any resulting ", ]" or "[, " patterns
        indexContent = indexContent.replace(/\[\s*,\s*/, "[");
        indexContent = indexContent.replace(/,\s*\]/, "]");
      }

      writeFileSync(indexPath, indexContent);
      log.info(`[kahili:rulegen] Updated index.ts to remove ${ruleName}`);
      break;
    }
  }

  // 3. Delete mother issues for this rule
  const motherIssuesDir = resolve(KAHU_DIR, "data", "mother-issues");
  if (existsSync(motherIssuesDir)) {
    const miFiles = readdirSync(motherIssuesDir).filter((f) => f.endsWith(".json"));
    for (const file of miFiles) {
      const filePath = resolve(motherIssuesDir, file);
      try {
        const content = readFileSync(filePath, "utf-8");
        const mi = JSON.parse(content);
        if (mi.ruleName === ruleName) {
          unlinkSync(filePath);
          filesRemoved++;
        }
      } catch {
        // skip corrupt files
      }
    }
    log.info(`[kahili:rulegen] Deleted ${filesRemoved} mother issues for rule ${ruleName}`);
  }

  return { deleted: true, filesRemoved };
}

export async function startRuleGeneration(
  userPrompt: string
): Promise<RuleGeneration> {
  if (current?.status === "running") {
    throw new Error(
      `Rule generation already running (PID ${current.pid})`
    );
  }

  mkdirSync(GENERATION_DIR, { recursive: true });

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const statusPath = resolve(GENERATION_DIR, `${stamp}.status`);

  writeFileSync(statusPath, "Generating: Analyzing request...\n");

  const prompt = buildRuleGenPrompt(userPrompt, statusPath);
  const child = spawnAgent(prompt, RULES_DIR);
  agentProcess = child;

  if (!child.pid) throw new Error("Failed to spawn rule generation agent");
  const pid = child.pid;

  current = {
    prompt: userPrompt,
    pid,
    statusPath,
    status: "running",
    startedAt: new Date().toISOString(),
    lastStatus: "Generating: Analyzing request...",
  };

  log.info(`[kahili:rulegen] Spawned agent PID ${pid} for rule generation`);

  broadcast("rulegen:started", { pid, status: "running" });

  pipeAgentLogs(child, "rulegen");

  // Watch status file for changes
  let lastContent = "";
  const onFileChange = () => {
    try {
      const content = readFileSync(statusPath, "utf-8");
      if (content !== lastContent) {
        lastContent = content;
        if (current) current.lastStatus = content;
        broadcast("rulegen:progress", {
          status: "running",
          statusText: content,
        });
      }
    } catch {
      // file may be mid-write
    }
  };

  statusWatcher = watch(statusPath, onFileChange);

  child.on("exit", async (code, signal) => {
    agentProcess = null;
    if (statusWatcher) {
      statusWatcher.close();
      statusWatcher = null;
    }

    // Read final status
    let finalStatus = "";
    try {
      finalStatus = readFileSync(statusPath, "utf-8");
    } catch {
      finalStatus = `Rule generation ended without status (code=${code}, signal=${signal})`;
    }

    const rejected = finalStatus.includes("REJECTED BY AGENT");

    if (current) {
      if (rejected) {
        current.status = "rejected";
      } else {
        current.status = code === 0 ? "completed" : "failed";
      }
      current.completedAt = new Date().toISOString();
      current.lastStatus = finalStatus;
    }

    log.info(
      `[kahili:rulegen] Agent PID ${pid} exited (code=${code}, signal=${signal}, rejected=${rejected})`
    );

    if (!rejected && code === 0) {
      // Agent created the rule — rebuild and restart kahu
      log.info("[kahili:rulegen] Rule created — rebuilding and restarting kahu...");
      try {
        const buildInfo = readBuild();
        await restartKahu(buildInfo.build);
        log.info("[kahili:rulegen] Kahu restarted with new rule.");
      } catch (err) {
        log.error("[kahili:rulegen] Failed to restart kahu:", err);
      }
    }

    broadcast("rulegen:completed", {
      status: current?.status ?? "completed",
      statusText: finalStatus,
      rejected,
    });
  });

  return current;
}

export function cancelRuleGeneration(): boolean {
  if (!current || current.status !== "running") {
    return false;
  }

  const pid = current.pid;

  if (agentProcess) {
    // SIGTERM first for graceful shutdown
    agentProcess.kill("SIGTERM");
  }

  // Escalate with killProcessTree after delay
  setTimeout(() => {
    killProcessTree(pid);
  }, 2000);

  current.status = "failed";
  current.completedAt = new Date().toISOString();
  current.lastStatus += "\n\n---\n*Rule generation cancelled by user.*";
  agentProcess = null;

  broadcast("rulegen:completed", {
    status: "failed",
    statusText: current.lastStatus,
    rejected: false,
  });

  return true;
}
