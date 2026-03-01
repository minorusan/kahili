import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { execFile } from "node:child_process";
import { readFile, stat, readdir, unlink } from "node:fs/promises";
import path from "node:path";
const { join, extname, resolve } = path;
import { readBuild } from "./build.js";
import { readPidFile } from "./kahu-manager.js";
import { applyKahuSettings, readKahuSettings, type KahuSettings } from "./settings.js";
import { startInvestigation, getCurrentInvestigation, cancelInvestigation } from "./investigator.js";
import { startRuleGeneration, getCurrentRuleGeneration, cancelRuleGeneration, deleteRule } from "./rule-generator.js";
import { attachWebSocket } from "./websocket.js";
import { log } from "./logger.js";

// Flutter web build directory (two levels up from dist/ to repo root, then client/build/web)
const WEB_ROOT = join(import.meta.dirname!, "..", "..", "..", "client", "build", "web");

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wasm": "application/wasm",
};

const startTime = Date.now();

function json(res: ServerResponse, data: unknown, status = 200): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data, null, 2));
}

const MAX_BODY = 1024 * 1024; // 1MB

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolveBody, reject) => {
    const chunks: Buffer[] = [];
    let totalSize = 0;
    req.on("data", (chunk: Buffer) => {
      totalSize += chunk.length;
      if (totalSize > MAX_BODY) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolveBody(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

function statusPayload() {
  const buildInfo = readBuild();
  const pidInfo = readPidFile();

  return {
    name: "kahili",
    build: buildInfo.build,
    kahuPid: pidInfo?.pid ?? null,
    kahuBuild: pidInfo?.build ?? null,
    uptime: Math.floor((Date.now() - startTime) / 1000),
  };
}

function gitExec(args: string[], cwd: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("git", args, { cwd, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      // git fetch writes progress to stderr even on success
      if (err && args[0] !== "fetch") {
        reject(new Error(`git ${args[0]} failed: ${stderr || err.message}`));
        return;
      }
      resolve(stdout);
    });
  });
}

async function serveStatic(res: ServerResponse, urlPath: string): Promise<boolean> {
  // Strip query parameters before resolving file path
  const pathOnly = urlPath.split("?")[0];

  // Block service-worker and manifest requests — never serve these
  const blocked = ["/flutter_service_worker.js", "/manifest.json"];
  if (blocked.includes(pathOnly)) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
    return true;
  }

  // Prevent path traversal with proper resolution
  const resolved = resolve(WEB_ROOT, "." + pathOnly);
  if (!resolved.startsWith(WEB_ROOT)) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
    return true;
  }

  let filePath = pathOnly === "/" ? join(WEB_ROOT, "index.html") : resolved;

  try {
    const s = await stat(filePath);
    if (s.isDirectory()) filePath = join(filePath, "index.html");
  } catch {
    // File doesn't exist — serve index.html for SPA routing
    filePath = join(WEB_ROOT, "index.html");
  }

  try {
    const data = await readFile(filePath);
    const ext = extname(filePath);
    const contentType = MIME_TYPES[ext] || "application/octet-stream";
    const headers: Record<string, string> = {
      "Content-Type": contentType,
      "Cache-Control": "no-cache, no-store, must-revalidate",
    };
    // Wipe browser HTTP cache on every page load so stale JS is never served
    if (filePath.endsWith("index.html")) {
      headers["Clear-Site-Data"] = "\"cache\", \"storage\"";
    }
    res.writeHead(200, headers);
    res.end(data);
    return true;
  } catch {
    return false;
  }
}

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = req.url || "/";

  // API routes
  if (url === "/api/status") {
    return json(res, statusPayload());
  }

  // POST /api/client-log — receive client-side error logs
  if (req.method === "POST" && url === "/api/client-log") {
    try {
      const raw = await readBody(req);
      const body = JSON.parse(raw);
      const level = body.level || "error";
      const msg = body.message || "";
      const stack = body.stackTrace || "";
      if (level === "error") {
        log.error(`[CLIENT] ${msg}`);
        if (stack) log.error(`[CLIENT:STACK] ${stack}`);
      } else {
        log.info(`[CLIENT:${level}] ${msg}`);
      }
    } catch {
      // don't fail on malformed logs
    }
    return json(res, { ok: true });
  }

  // GET /api/kahu-settings — read current settings
  if (req.method === "GET" && url === "/api/kahu-settings") {
    return json(res, readKahuSettings());
  }

  // POST /api/kahu-settings — apply new settings
  if (req.method === "POST" && url === "/api/kahu-settings") {
    let body: KahuSettings;
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw) as KahuSettings;
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    try {
      const result = await applyKahuSettings(body);
      return json(res, {
        ok: true,
        envWritten: result.env,
        motherIssuesBackfilled: result.backfilled,
        kahuPid: result.kahuPid,
      });
    } catch (err) {
      log.error("[kahili] Failed to apply settings:", err);
      return json(
        res,
        { error: "failed to apply settings", detail: String(err) },
        500
      );
    }
  }

  // GET /api/investigate — current investigation status
  if (req.method === "GET" && url === "/api/investigate") {
    const inv = getCurrentInvestigation();
    if (!inv) {
      return json(res, { active: false });
    }
    return json(res, { active: inv.status === "running", investigation: inv });
  }

  // POST /api/investigate — start investigation
  if (req.method === "POST" && url === "/api/investigate") {
    let body: { motherIssueId?: string; branch?: string; additionalPrompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.motherIssueId) {
      return json(res, { error: "motherIssueId is required" }, 400);
    }

    try {
      const inv = await startInvestigation(
        body.motherIssueId,
        body.branch,
        body.additionalPrompt
      );
      return json(res, { ok: true, investigation: inv });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // GET /api/repo-info — fetch and return release branches/tags
  if (req.method === "GET" && url === "/api/repo-info") {
    const settings = readKahuSettings();
    const repoPath = settings.REPO_PATH;
    if (!repoPath) {
      return json(res, { error: "REPO_PATH not configured" }, 400);
    }

    try {
      await gitExec(["fetch", "--all", "--tags"], repoPath);

      const [branchOut, tagOut] = await Promise.all([
        gitExec(["branch", "-r", "--list", "*release*", "--sort=-committerdate"], repoPath),
        gitExec(["tag", "--sort=-creatordate"], repoPath),
      ]);

      const branches = branchOut.split("\n").map((b) => b.trim()).filter(Boolean).slice(0, 20);
      const tags = tagOut.split("\n").map((t) => t.trim()).filter(Boolean).slice(0, 20);

      return json(res, { branches, tags });
    } catch (err) {
      log.error("[kahili] repo-info failed:", err);
      return json(res, { error: "git operation failed", detail: String(err) }, 500);
    }
  }

  // DELETE /api/investigate — cancel current investigation
  if (req.method === "DELETE" && url === "/api/investigate") {
    const cancelled = cancelInvestigation();
    return json(res, { ok: cancelled });
  }

  // GET /api/reports/status — list which mother issues have reports
  if (req.method === "GET" && url === "/api/reports/status") {
    const investigationsDir = join(import.meta.dirname!, "..", "..", "docs", "investigations");
    try {
      const files = await readdir(investigationsDir);
      const ids = files
        .filter((f) => f.endsWith(".md"))
        .map((f) => f.replace(/\.md$/, ""));
      return json(res, { investigated: ids });
    } catch {
      return json(res, { investigated: [] });
    }
  }

  // GET /api/report/:motherIssueId — get investigation report
  const reportMatch = url.match(/^\/api\/report\/([a-f0-9]+)$/);
  if (req.method === "GET" && reportMatch) {
    const issueId = reportMatch[1];
    const reportPath = join(import.meta.dirname!, "..", "..", "docs", "investigations", `${issueId}.md`);
    try {
      const content = await readFile(reportPath, "utf-8");
      return json(res, { exists: true, motherIssueId: issueId, report: content });
    } catch {
      return json(res, { exists: false, motherIssueId: issueId });
    }
  }

  // GET /api/generate-rule — current rule generation status
  if (req.method === "GET" && url === "/api/generate-rule") {
    const gen = getCurrentRuleGeneration();
    if (!gen) {
      return json(res, { active: false });
    }
    return json(res, { active: gen.status === "running", generation: gen });
  }

  // POST /api/generate-rule — start rule generation
  if (req.method === "POST" && url === "/api/generate-rule") {
    let body: { prompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.prompt) {
      return json(res, { error: "prompt is required" }, 400);
    }

    try {
      const gen = await startRuleGeneration(body.prompt);
      return json(res, { ok: true, generation: gen });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // DELETE /api/generate-rule — cancel rule generation
  if (req.method === "DELETE" && url === "/api/generate-rule") {
    const cancelled = cancelRuleGeneration();
    return json(res, { ok: cancelled });
  }

  // POST /api/regenerate-rule — delete old rule + mother issues, then generate new rule
  if (req.method === "POST" && url === "/api/regenerate-rule") {
    let body: { ruleName?: string; prompt?: string };
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch {
      return json(res, { error: "invalid JSON body" }, 400);
    }

    if (!body.ruleName || !body.prompt) {
      return json(res, { error: "ruleName and prompt are required" }, 400);
    }

    try {
      // 1. Delete old rule and its mother issues
      const deleteResult = deleteRule(body.ruleName);
      log.info(`[kahili] Deleted rule ${body.ruleName}: ${deleteResult.filesRemoved} mother issues removed`);

      // 2. Start new rule generation
      const gen = await startRuleGeneration(body.prompt);
      return json(res, { ok: true, deleted: deleteResult, generation: gen });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      const status = msg.includes("already running") ? 409 : 500;
      return json(res, { error: msg }, status);
    }
  }

  // GET /api/daily-reports — list available daily report dates
  if (req.method === "GET" && url === "/api/daily-reports") {
    const reportsDir = join(import.meta.dirname!, "..", "..", "kahu", "data", "reports");
    try {
      const files = await readdir(reportsDir);
      const dates = files
        .filter((f) => f.endsWith(".md"))
        .map((f) => f.replace(/\.md$/, ""))
        .sort()
        .reverse();
      return json(res, { dates });
    } catch {
      return json(res, { dates: [] });
    }
  }

  // GET /api/daily-reports/:date — get a specific day's report
  const dailyMatch = url.match(/^\/api\/daily-reports\/(\d{4}-\d{2}-\d{2})$/);
  if (req.method === "GET" && dailyMatch) {
    const date = dailyMatch[1];
    const reportPath = join(import.meta.dirname!, "..", "..", "kahu", "data", "reports", `${date}.md`);
    try {
      const content = await readFile(reportPath, "utf-8");
      return json(res, { exists: true, date, report: content });
    } catch {
      return json(res, { exists: false, date });
    }
  }

  // Proxy kahu API — /api/kahu/* → kahu:3456/api/*
  if (url.startsWith("/api/kahu/")) {
    const kahuPath = url.replace("/api/kahu/", "/api/");
    try {
      const kahuRes = await fetch(`http://localhost:3456${kahuPath}`);
      const body = await kahuRes.text();
      res.writeHead(kahuRes.status, { "Content-Type": kahuRes.headers.get("content-type") || "application/json" });
      res.end(body);
      return;
    } catch (err) {
      return json(res, { error: "kahu unavailable", detail: String(err) }, 502);
    }
  }

  // GET /clear — standalone cache-nuking page (bypasses service worker)
  if (req.method === "GET" && (url === "/clear" || url.startsWith("/clear?"))) {
    const clearHtml = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Clearing cache...</title></head>
<body style="font-family:sans-serif;text-align:center;padding:40px">
<h2>Clearing cache &amp; service workers...</h2>
<p id="status">Working...</p>
<script>
(async function() {
  const s = document.getElementById('status');
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      for (const r of regs) await r.unregister();
      s.textContent = 'Unregistered ' + regs.length + ' service worker(s). ';
    }
    if ('caches' in window) {
      const names = await caches.keys();
      for (const n of names) await caches.delete(n);
      s.textContent += 'Deleted ' + names.length + ' cache(s). ';
    }
    s.textContent += 'Redirecting...';
    setTimeout(function() { window.location.href = '/?t=' + Date.now(); }, 1000);
  } catch(e) {
    s.textContent = 'Error: ' + e.message;
  }
})();
</script></body></html>`;
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache, no-store, must-revalidate",
      "Clear-Site-Data": "\"cache\", \"storage\"",
    });
    res.end(clearHtml);
    return;
  }

  // Non-API routes: serve Flutter web app
  if (req.method === "GET" && !url.startsWith("/api/")) {
    const served = await serveStatic(res, url);
    if (served) return;
  }

  json(res, { error: "not found" }, 404);
}

export function startServer(port: number): void {
  const server = createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      log.error("[kahili] HTTP handler error:", err);
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "internal server error" }));
      }
    });
  });

  attachWebSocket(server);

  server.listen(port, () => {
    log.info(`[kahili] HTTP server listening on http://localhost:${port}`);
  });
}
